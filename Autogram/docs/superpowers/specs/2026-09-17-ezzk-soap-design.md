# EZZK through the Ditec SOAP service

Date: 2026-09-17. Status: approved in conversation, awaiting written review.

## Problem

Autogram talks to EZZK (the central register of guaranteed conversion records)
through the Keycloak OAuth flow and the portal REST API described in
`2026-08-29-ezzk-oauth-rest-ui-design.md`. That path needs MIRRI to register a
native redirect URI for `login-app`, and it will not happen: on the 2026-09-17 call
the podpisuj.sk team confirmed that EZZK is not maintained, MIRRI has no
administrative access to it, and even creating users requires paid change requests
to Ditec. Login is therefore blocked, and Autogram cannot request evidence numbers
or read server time from EZZK at all.

EZZK also exposes the SOAP service that every integrating system has used since
2019. It authenticates the advocate's own EZZK name and password, the ones sent by
email after registration. Podpisuj uses it the same way.

## Goals

This spec covers part A of two:

1. The advocate enters their EZZK name and password in Settings, Autogram verifies
   them with EZZK and keeps the password in the Keychain.
2. Autogram reads the EZZK server time, requests and consumes evidence numbers, and
   looks up records through SOAP, on the test and production environments.
3. On production, part A is read-only: login check, server time and record lookup.
   Evidence number allocation stays locked until part B can send the record.
4. `ezzk-probe` exercises the service from the command line.

Part B is a separate spec: building the record (form
`50349287.ConversionRecordOfPaperToElectronicDocument.sk` version 1.0 in an
`XMLDataContainer`), signing it with the mandate certificate and a qualified
timestamp into its own ASiC, sending it with `ReceiveConversionRecord`, wiring it to
ZaKo and the Register konverzií, and the record form version 1.2 that takes effect
on 2027-01-01. Part B also unlocks production allocation.

Out of scope: login through slovensko.sk, migration of historical records, eDesk
notifications about asynchronously rejected records.

## Verified contract

Sources: MIRRI "Integračný manuál poskytovaných služieb modulu EZZK" version 1.4
(2019-11-18), the live WSDL and XSD of both environments, and calls made on
2026-09-17. Where the manual and the live service disagree, the live service wins.

### Endpoints

| Environment | Login | Service |
| --- | --- | --- |
| Test | `https://ezzk-test.iomo.sk/Iam.Core3.Svc.Wcf/LogInService.svc` | `https://ezzk-test.iomo.sk/EZZK.Svc.Wcf/EZZKService.svc` |
| Production | `https://ezzk.iomo.sk/Iam.Core3.Svc.Wcf/LogInService.svc` | `https://ezzk.iomo.sk/EZZK.Svc.Wcf/EZZKService.svc` |

- Production uses a public certificate (`CN=*.iomo.sk`, RapidSSL); the one observed
  on 2026-09-17 expires on 2026-09-21.
- Test uses a self-signed certificate, `CN=ezzk-test.iomo.sk`, SHA-256
  `D1:6F:5B:61:72:0A:59:53:08:56:5D:D8:4E:32:93:5E:7A:7D:E8:3A:6C:2F:A8:F0:E6:41:34:51:ED:2B:12:E2`,
  valid until 2026-10-20.

### Envelope

- SOAP 1.2, `Content-Type: application/soap+xml; charset=utf-8; action="<action>"`.
- WS-Addressing headers are mandatory: `a:Action` (`mustUnderstand`), `a:MessageID`
  (`urn:uuid:`) and `a:To` (`mustUnderstand`). An empty header, as in the manual's
  examples, fails with `a:ActionMismatch`.
- Service actions are `http://www.ditec.sk/IEZZKService/IEZZKService/<Operation>`.
  Login is `http://ditec/2017/06/iam/core/ILogInService/LogIn`.
- Data contract serialization: every element listed in the XSD must be present, in
  XSD order, with `i:nil="true"` for empty nillable values.
- The shared object elements (`Class`, `Encoding`, `Id`, `IsSigned`, `Mimetype`,
  `Data`) and every field inherited from a base type live in
  `http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol`. `Container` fields
  live in the operation namespace (for example `...Dol.PoskytnutieEvidencnehoCislaWS`).
  The manual puts the `ZiadostVypis` fields in the operation namespace, and the
  service rejects that with `DeserializationFailed`.
- The element is `Mimetype`, not `MimeType`.

### Login

- `LogIn` with `InputMessageOf_LogInInput`, `Content` of type
  `LogInInputAuthentication`, `InputData` of type `TokenInputData` with
  `ApplicationId` = `EZZK`, `AuthenticationInput` of type `PasswordInput` with
  `Login` and `Password`.
- Success: `ErrorCode` is nil, `TokenDescriptor` holds the token, `Account/Name`
  holds the account name.
- Failure: `ErrorCode` such as `CORE-003` (`ACCOUNT_OR_CREDENTIALS_INVALID`) or
  `CORE-018` (`LOGIN_LOCKED`).
- The response also sets the load balancer cookie `SERVERID`.
- Every authenticated call sends `Cookie: IamTokenDescriptor=<token>`. The token as
  an HTTP header is ignored.
- Without the cookie the service answers HTTP 500 with the fault "The service
  implementation object was not initialized or is not available." With an invalid
  token it answers HTTP 200 with `Result/Code` 101, "Nemáte oprávnenie na volanie
  služby".
- The manual states no token lifetime.

### Operations

| Operation | Auth | Request data | Response |
| --- | --- | --- | --- |
| `GetOptions` | no | empty | empty; the HTTP `Date` header gives server time |
| `GetConversionRecordEvidenceNumber` | yes | `Container`: `EvidenceNumberAmount` (nil), `MessageId`, `Object` with `PersonPerformingConversion` (name, IČO as codelist 4001 item 7) | `ConversionRecordEvidenceNumberList` entries |
| `ConsumeConversionRecordEvidenceNumber` | yes | `Object` also carries `ConversionRecordEvidenceNumber` (nil consumes the oldest) | `Result` only |
| `GetConversionRecord` | yes | `ZiadostVypis`: `ConversionExecutionDateTime` (optional), `ConversionRecordEvidenceNumber`, `Purpose` (1 original, 2 XML), `TimeStamp` | `OdpovedVypis` plus base64 object |
| `GetConversionRecordInformationPurpose` | no | `ZiadostVypis` without `Purpose` | `OdpovedVypis`: execution time, number, document names, formats and sheet counts, person, receipt date |
| `ReceiveConversionRecord` | yes | `Object` with person, `ObjectDataList` of `ObjectOfstring` (`ATTACHMENT`, `Base64`, `Id` = evidence number, `IsSigned` true, ASiC MIME type, base64 data), `SenderId` `ico://sk/<ico>` | `Result` only |

Observed behavior:

- The test sample account received ten numbers in one call. EZZK returns every
  unconsumed number of the person and allocates new ones only when fewer than the
  configured amount remain.
- Test numbers look like `260917-dD9DbFE4f7`; production numbers look like
  `1563-260824-1`. Autogram treats the number as an opaque string.
- On test, a different `PersonPerformingConversion` IČO still received numbers, so
  the test service does not bind the person to the account.
- Consuming the same number twice returns 0 both times.
- `ReceiveConversionRecord` with an empty `ObjectDataList` returns 110, not 113 as
  the manual says.
- EZZK consumes an unused number automatically at midnight of the day it was
  allocated.
- `ReceiveConversionRecord` returning 0 means the batch was accepted for processing.
  Validation runs later, and rejected records are reported to the sender's eDesk.

Result codes: 0 OK; 1 recorded but not processed yet; 101 not authorized; 104 and
105 number not recorded; 106 number used by several records, send the execution
time; 110 and 113 empty batch; 112 number allocated to another person.

## Design

### AutogramKit: `EZZK/SOAP/`

- `EZZKEnvironment` gains `soapLoginURL` and `soapServiceURL` from the table above
  and a `pinnedCertificateSHA256` (test only).
- `EZZKSOAPEnvelope` builds the SOAP 1.2 envelope and WS-Addressing headers. One
  `EZZKXML.escape` helper serves all SOAP builders.
- `EZZKSOAPRequest` is a value holding `action`, `url`, `requiresAuthentication`,
  `isConsequential` and the body. Static builders exist for the six operations:
  - `login(login:password:)`
  - `serverTime()` (`GetOptions`)
  - `evidenceNumbers(person:)`
  - `consume(evidenceNumber:person:)`
  - `record(evidenceNumber:purpose:executionTime:)`
  - `publicRecord(evidenceNumber:executionTime:)`
  - `receive(records:person:)`
- `EZZKPerson` holds `corporateBodyFullName` and `ico`.
- `EZZKSOAPResponseParser` parses with `XMLDocument` (`nodeLoadExternalEntitiesNever`)
  and matches elements by local name, because WCF moves namespace prefixes between
  responses. It returns either a SOAP fault (code, subcode, reason text) or
  `Result` code, description and the operation data:
  - `EZZKLoginResult`
  - `[String]` numbers
  - `EZZKRecordInfo`
  - `Data?` for the base64 object
- `EZZKSOAPTransport` has one method, `send(URLRequest) async throws -> (Data,
  HTTPURLResponse)`. `URLSessionEZZKSOAPTransport`:
  - uses an ephemeral session without cookie storage
  - refuses every redirect
  - uses system trust on production
  - on test, evaluates the server trust challenge and accepts only a leaf
    certificate whose SHA-256 matches the pinned value. Otherwise it fails with
    `untrustedCertificate`.
- `actor EZZKSOAPClient` owns one environment, a transport and a credentials
  provider:
  - Keeps the token and `SERVERID` in memory only.
  - Logs in lazily before the first authenticated call.
  - On code 101 or the "service implementation object was not initialized" fault,
    it logs in once more and repeats the call once. A second failure is
    `authenticationFailed`. Repeating is safe because the service rejected the
    request before processing it.
  - Never repeats a consequential call (numbers, consume, receive) after a network
    error or timeout. The outcome is unknown and is reported as such.
  - `serverTime()` reads the `Date` header of `GetOptions`.
- `EZZKSOAPCredentials` (`login`, `password`) is stored by
  `EZZKSOAPCredentialStore` as a generic password:
  - service `sk.autogram.Autogram.ezzk.soap`, account `test` or `production`
  - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
  - goes through the existing `EZZKKeychainAdapter` protocol so tests can use
    memory
- `EZZKSOAPServiceAdapter: EZZKServicing` adapts the client to the app:
  - `serverTime()` passes through.
  - `requestEvidenceNumbers(count:)` refuses production with
    `productionAllocationDisabled`. Otherwise it asks EZZK for numbers, drops those
    already used by a record in `LocalEvidenceStore`, and returns the first `count`.
    The protocol signature does not change.
  - `submit(_:)` throws `submissionUnavailable` until part B.
  - Also exposes `publicRecord(evidenceNumber:)` and `consume(evidenceNumber:)` for
    Settings and the probe.
- `EZZKError` gains:
  - `authenticationFailed(code: String?)`
  - `accountLocked`
  - `serverRejected(code: Int, message: String)`
  - `invalidRequest(String)` for `DeserializationFailed` and `ActionMismatch`
  - `untrustedCertificate`
  - `productionAllocationDisabled`
  - `submissionUnavailable`
  - `evidenceNumberExpired`
  - `outcomeUnknown`

  Slovak `errorDescription` texts replace "skontrolujte IČO, meno a heslo". Fault
  stack traces from the server are never shown or logged, only the reason text.
- Removed: `HTTPSEZZKService`, `EZZKCredentials`. `ConversionRecordEnvelope`, the
  capability protocols and `MockEZZKService` stay.

### AutogramApp

- `AppSettings` gains `ezzkMode` (`demo`, `test`, `production`, default `demo`) and
  `ezzkPersonName` next to the existing `ezzkICO`. Old settings decode to `demo`.
  The login name is stored with the password in the Keychain; the never-used
  `ezzkUsername` field stays decodable and is ignored. The demo mode is no longer
  derived from missing credentials.
- `@MainActor @Observable EZZKAccountController` replaces `EZZKSessionController`
  as the object that `AppSettingsStore`, Settings and ZaKo use.
  - States: `signedOut`, `verifying`, `signedIn(accountName, checkedAt)`,
    `failed(message)`.
  - `service` returns `MockEZZKService` in demo mode, otherwise an
    `EZZKSOAPServiceAdapter` for the chosen environment.
  - `signIn(login:password:)` calls `LogIn` and saves the credentials only after it
    succeeds.
  - `signOut()` deletes the Keychain item and drops the token.
  - Also `lookUp(evidenceNumber:)` and `requestTestNumbers()`.
  - It never touches `LocalEvidenceStore` rows.
- `EZZKSessionController`, `EZZKAuthenticationSession`, `EZZKClient`,
  `EZZKTokenStore` and their tests stay in the code but are not wired, kept for a
  future slovensko.sk login.

### Settings, EZZK tab

- **Prostredie:** segmented `Demo (lokálne)` / `Test` / `Produkcia`, with the SOAP
  addresses shown read-only.
- **Účet:**
  - Fields `Prihlasovacie meno`, `Heslo` (`SecureField`), `Názov osoby` (exactly
    as in the clause) and `IČO`.
  - `Prihlásiť a overiť` runs `signIn` and shows the account name EZZK returned
    and the time of the check. `Odhlásiť` runs `signOut`.
  - Errors in Slovak: CORE-003 "Nesprávne prihlasovacie meno alebo heslo.",
    CORE-018 "Účet v EZZK je zablokovaný.", others with their code.
- **Overenie záznamu:**
  - Evidence number field and `Vyhľadať`, using `GetConversionRecordInformationPurpose`
    on test and production, with no login needed.
  - Shows execution time, receipt time, person, original and new document name,
    format and sheet count.
  - Code 1 shows "Záznam je evidovaný, ale ešte nespracovaný."
- **Evidenčné čísla:**
  - Test only: `Vyžiadať čísla` with a confirmation dialog, then the returned list.
  - Production: the button is disabled with "Pridelenie čísiel na produkcii sa
    zapne spolu s odosielaním záznamov."
- **Odosielanie záznamov:** informational, pointing to the next part.
- **Migrácia:** unchanged.

### ZaKo

- Conversion time comes from `serverTime()` on test and production, and from the
  local clock in demo, as today.
- `Získať číslo` requests the number and then calls `serverTime()` on the same
  service, storing the result in a new `AttestationData.evidenceNumberAllocatedAt`
  (`Date?`, decoded with `decodeIfPresent`).
  - In demo it uses the mock.
  - On test it uses the adapter.
  - On production it shows the `productionAllocationDisabled` message in
    `evidenceNumberError`.
- Preflight blocks signing with `evidenceNumberExpired` when the calendar day of
  `evidenceNumberAllocatedAt` and of the server time at signing differ in the
  `Europe/Bratislava` time zone, because EZZK consumes unused numbers at midnight.
  A number without `evidenceNumberAllocatedAt` (typed by hand or from older data)
  is not blocked.
- Preflight warns when the clause's performing person name or IČO differs from
  `ezzkPersonName` or `ezzkICO` in test and production.
- After signing, `submit` throws `submissionUnavailable`. The row stays
  `queuedForSubmission` as today. The Register konverzií shows that sending records
  arrives in the next part.

### `ezzk-probe`

- Executable target depending on `AutogramKit`, following the `avm-probe`
  structure.
- Commands:
  - `login`
  - `time`
  - `numbers`
  - `consume <number>`
  - `lookup <number> [--at <ISO time>]`
- Options `--env test|production` (default `test`), `--name`, `--ico`.
- Credentials come from `EZZK_LOGIN` and `EZZK_PASSWORD`, or from the Keychain
  item Settings saved for that environment. They are never printed. Tokens are
  printed redacted.
- `numbers` and `consume` refuse `--env production`.

## Error handling summary

| Situation | Behavior |
| --- | --- |
| Wrong name or password | `authenticationFailed("CORE-003")`, account state `failed`, stored credentials kept for correction |
| Locked account | `accountLocked` |
| Token expired (101 or init fault) | one silent login and one repeat, then `authenticationFailed` |
| Network error on a read | error shown, the user may retry |
| Network error on numbers, consume or receive | `outcomeUnknown`, no automatic repeat |
| Test certificate changed | `untrustedCertificate`: "Certifikát testovacieho prostredia EZZK sa zmenil. Aktualizujte odtlačok v aplikácii." |
| `DeserializationFailed` or `ActionMismatch` | `invalidRequest`, logged as an application defect |
| Unknown result code | `serverRejected(code, message)` with the server text |

## Security

- The password lives only in the Keychain, never in `AppSettings`, logs, probe
  output or the repository. The token and `SERVERID` live only in memory.
- The dead `ezzk.password` read in `AppSettingsStore` and the unused
  `saveEZZKPassword()` are removed.
- No redirects are followed, so the password body and token cookie cannot leave
  the EZZK host.
- The test environment trusts exactly one pinned certificate. There is no global
  TLS bypass.
- The repository holds no credentials, including the sample account from the
  manual.
- Consequential calls on production are impossible in part A by construction.

## Testing

- Snapshot of the WSDL and XSD files from 2026-09-17 in
  `Autogram/docs/reference/ezzk-soap/2026-09-17/`, with `schemaLocation` rewritten
  to local files, plus a README naming the source URLs and the manual.
- Envelope tests:
  - Every request body validates against the snapshot with `/usr/bin/xmllint --schema`.
  - Headers contain `Action`, `MessageID` and `To`.
  - `Content-Type` carries the action.
  - Escaping of names with `&`, `<` and diacritics.
- Parser tests on recorded responses, with tokens redacted and the production
  lookup replaced by a test response or anonymized:
  - login success, CORE-003
  - number list, code 101
  - init fault, `DeserializationFailed`
  - public lookup with codes 0 and 1
  - receive 110
- Client tests with a recording transport:
  - lazy login
  - cookie with token and `SERVERID`
  - one re-login on 101, and no loop on a second 101
  - no repeat after a network error for consequential calls
  - `Date` header parsing
  - the test certificate evaluator with a matching and a different certificate
- Adapter tests:
  - skips numbers already used in `LocalEvidenceStore`
  - refuses production allocation
  - refuses `submit`
- Credential store tests through the in-memory Keychain adapter.
- App tests:
  - `EZZKAccountController` transitions with a fake client
  - `AppSettings` decoding old JSON to `demo`
  - ZaKo preflight blocking an evidence number from a previous server day
- Manual live checks, not run in CI:
  - `swift run ezzk-probe login --env test` and `numbers --env test` with the
    sample account from environment variables
  - `swift run ezzk-probe lookup 1563-260824-1 --env production`

## Documentation

- `Autogram/docs/P2E-EZZK-FINDINGS.md`: a SOAP section with the verified contract,
  the deviations from the manual, both certificate expiry dates, and the note that
  the OAuth path is dormant.
- `CLAUDE.md` and `AGENTS.md`: the EZZK SOAP client in the architecture list and
  the `ezzk-probe` command in the build and test instructions, kept in sync.
