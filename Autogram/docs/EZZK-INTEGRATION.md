# EZZK integration

How Chevron7 talks to EZZK (the central register of records about guaranteed
conversion, CEZZK) and what an operator has to know to run, test and maintain it.

Companion documents:

- `docs/superpowers/specs/2026-09-17-ezzk-soap-design.md`: the approved design of part A.
- `docs/superpowers/plans/2026-09-17-ezzk-soap.md`: the implementation plan it was built from.
- `docs/P2E-EZZK-FINDINGS.md`: the research register, the deviations from the MIRRI manual, and the gaps left open.
- `docs/reference/ezzk-soap/2026-09-17/`: the WSDL and XSD snapshot the request tests validate against.

## Scope

Part A, which is what ships today:

- The advocate signs in with their own EZZK name and password and Chevron7 verifies it against EZZK.
- Chevron7 reads the EZZK server time, allocates and consumes evidence numbers (test environment only), and looks records up.
- Production is read only: sign in, server time and public record lookup. Nothing allocates, consumes or submits there.
- `ezzk-probe` exercises the same service from the command line.

Part B, which is not built yet: the signed conversion record (form
`50349287.ConversionRecordOfPaperToElectronicDocument.sk`) in an `XMLDataContainer`,
signed with the mandate certificate and a qualified timestamp into its own ASiC,
sent with `ReceiveConversionRecord`. Part B also unlocks allocation on production
and brings record form version 1.2, which takes effect on 2027-01-01.

## Why SOAP and not the portal API

The portal REST API behind Keycloak needs MIRRI to register a native redirect URI
for Chevron7, and on the 2026-09-17 call the podpisuj.sk team confirmed that will
not happen: EZZK is not maintained, MIRRI has no administrative access to it, and
even creating a user requires a paid change request to Ditec. The SOAP service is
what every integrator has used since 2019 and it authenticates the advocate's own
account. The OAuth code (`EZZKSessionController`, `EZZKClient`, `EZZKTokenStore`,
`EZZKAuthenticationSession`) stays in the repository, compiled but unwired, for a
future login through slovensko.sk.

## Modes

`AppSettings.ezzkMode` has three values and drives everything else. Old settings
without the field decode to `demo`.

| Mode | Service | What works |
| --- | --- | --- |
| `demo` | none, `MockEZZKService` | Local numbers and local clock. No network, no Keychain. |
| `test` | `https://ezzk-test.iomo.sk` | Sign in, server time, lookup, allocate and consume numbers. |
| `production` | `https://ezzk.iomo.sk` | Sign in, server time, public lookup. Allocation, consumption and submission are refused. |

The production lock is enforced in four independent places, so removing any one of
them does not open it: `EZZKSOAPClient.perform` (before any network use),
`EZZKSOAPServiceAdapter.requestEvidenceNumbers`, `EZZKAccountController.requestTestNumbers`
and `ezzk-probe` itself. `EZZKSOAPServiceAdapter.submit` always throws
`submissionUnavailable` until part B.

## Setting it up

1. Nastavenia, tab EZZK, card Prostredie: pick Demo, Test or Produkcia. The SOAP addresses of the chosen environment are shown read only.
2. Card Účet: enter Prihlasovacie meno and Heslo (the credentials EZZK sent by email after registration), Názov osoby exactly as it appears in the conversion clause, and IČO.
3. Press Prihlásiť a overiť. Chevron7 calls `LogIn` and only saves the credentials in the Keychain after EZZK accepts them. The card then shows the account name EZZK returned and the time of the check. Odhlásiť deletes the Keychain item and drops the token.
4. Card Overenie záznamu works without signing in, on test and on production.
5. Card Evidenčné čísla is test only. On production it shows a locked label instead of a button.

Every advocate needs their own EZZK account. There is no shared integrator account.

## Transport contract

The contract below was verified against the live service on 2026-09-17. Where the
MIRRI manual and the live service disagree, the live service wins.

- SOAP 1.2, `Content-Type: application/soap+xml; charset=utf-8; action="<action>"`.
- WS-Addressing headers are mandatory: `a:Action` (`mustUnderstand`), `a:MessageID` (`urn:uuid:`) and `a:To` (`mustUnderstand`). An empty header, as in the manual's examples, fails with `a:ActionMismatch`.
- Service actions are `http://www.ditec.sk/IEZZKService/IEZZKService/<Operation>`; login is `http://ditec/2017/06/iam/core/ILogInService/LogIn`.
- WCF data contract serialization: every element declared in the XSD must be present, in XSD order, with `i:nil="true"` for empty nillable values.
- Fields inherited from a base type, and the shared object elements (`Class`, `Encoding`, `Id`, `IsSigned`, `Mimetype`, `Data`), live in `http://schemas.datacontract.org/2004/07/Ditec.IOM.EZZK.Dol`. `Container` fields live in the operation namespace. The manual puts the `ZiadostVypis` fields in the operation namespace and the service rejects that with `DeserializationFailed`. The element is `Mimetype`, not `MimeType`.
- `LogIn` uses `ApplicationId` `EZZK`. Success returns a `TokenDescriptor` and the account name; failure returns an `ErrorCode` such as `CORE-003` (wrong name or password) or `CORE-018` (locked account).
- Every authenticated call sends `Cookie: IamTokenDescriptor=<token>`. The same token in an HTTP header is ignored. Without the cookie the service answers HTTP 500 with the fault "The service implementation object was not initialized or is not available."; with an invalid token it answers HTTP 200 with `Result/Code` 101.
- The load balancer sets a `SERVERID` cookie and alternates nodes. A token works on any node, so Chevron7 never sends that cookie back.
- The manual states no token lifetime. Chevron7 keeps the token in memory only, logs in lazily, and on 101 or the uninitialized-service fault logs in once more and repeats the call once. A second failure is `authenticationFailed`.

### Operations used

| Operation | Auth | Used for |
| --- | --- | --- |
| `GetOptions` | no | Server time, read from the HTTP `Date` header. |
| `GetConversionRecordEvidenceNumber` | yes | Allocating evidence numbers. Test only. |
| `ConsumeConversionRecordEvidenceNumber` | yes | Consuming a number. Test only. |
| `GetConversionRecordInformationPurpose` | no | Public record lookup in Settings and in the probe. |
| `GetConversionRecord` | yes | The advocate's own record with the stored object. |
| `ReceiveConversionRecord` | yes | Submitting a record. Built and callable, but the app refuses it until part B. |

Result codes: 0 OK; 1 recorded but not processed yet; 101 not authorized; 104 and
105 number not recorded; 106 the number is used by several records, so the
execution time has to be sent; 110 and 113 empty batch; 112 the number belongs to
another person.

## Evidence numbers

- EZZK returns every unconsumed number of the person and allocates new ones only when fewer than the configured amount remain. The test sample account returned ten in one call.
- Test numbers look like `260917-dD9DbFE4f7`, production numbers like `1563-260824-1`. Chevron7 treats a number as an opaque string.
- EZZK consumes an unused number automatically at midnight of the day it was allocated. `AttestationData.evidenceNumberAllocatedAt` records the server time of the allocation and `EZZKEvidenceNumberPolicy.isUsable` refuses to sign with a number from another calendar day in `Europe/Bratislava`.
- `AttestationData.evidenceNumberMode` records the mode the number came from, and signing is refused if the current mode differs, so a demo or test number cannot end up in a clause signed on production. Both checks run before anything is signed or written.
- The adapter drops numbers that a local record in `LocalEvidenceStore` already uses before handing one to ZaKo.
- A number without an allocation time or without a mode (typed by hand or from older data) is not blocked.
- `ReceiveConversionRecord` answering 0 means the batch was accepted for processing, not that it was accepted. Validation runs later and rejections arrive in the sender's eDesk. Podpisuj reports that EZZK flags many valid advocate records as invalid for a missing timestamp, so part B has to add a qualified timestamp to the record signature.

## Error mapping

| Situation | `EZZKError` | What the user sees |
| --- | --- | --- |
| Wrong name or password (`CORE-003`) | `credentialsRejected(code:)` | Nesprávne prihlasovacie meno alebo heslo. |
| Locked account (`CORE-018`) | `accountLocked` | Účet v EZZK je zablokovaný. |
| Token rejected after one fresh login | `authenticationFailed` | Prompt to sign in again. |
| Unknown result code | `serviceRejected(code:message:)` | The code and the server's own text. |
| `DeserializationFailed` or `ActionMismatch` | `invalidRequest` | An application defect. Logged with the fault subcode public and the reason private. |
| Test certificate is not the pinned one | `untrustedCertificate` | Update the pin in the app. |
| Network error or HTTP 5xx on allocate, consume or submit | `outcomeUnknown` | The outcome is unknown and the call is never repeated. |
| Allocation attempted on production | `productionAllocationDisabled` | Opens together with record submission. |
| `submit` in part A | `submissionUnavailable` | Rows stay queued in the register. |
| Number from another day or another mode | `evidenceNumberExpired`, `evidenceNumberFromOtherMode` | Get a new number. |

Errors that fail before anything was sent (no connection, host not found, DNS
failure) stay a plain `networkFailure` even on a consequential call, because in
that case the outcome is known.

## Security

- The password lives only in the Keychain, in a generic password item with service `app.slovensko.chevron7.ezzk.soap` and account `test` or `production`. It is never written to `AppSettings`, logs, probe output or the repository.
- The token lives only in memory, inside the client actor. Nothing can read it out, and the probe never prints it.
- The session uses an ephemeral configuration with no cookie storage and no cache, and refuses every redirect, so the password body and the token cookie cannot leave the EZZK host.
- The test environment trusts exactly one pinned certificate; production uses system trust. There is no global TLS bypass.
- No credentials are stored in the repository, including the sample test account from the MIRRI manual.

## Code map

| File | Responsibility |
| --- | --- |
| `Sources/Chevron7Kit/EZZK/EZZKEnvironment.swift` | Environments, SOAP URLs, the certificate pin. |
| `Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPEnvelope.swift` | Namespaces, XML escaping, the SOAP 1.2 envelope with WS-Addressing, date formatting. |
| `Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPRequest.swift` | `EZZKPerson`, request values and one builder per operation. |
| `Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPResponse.swift` | Fault and result parsing with `XMLDocument`, matched by local name. |
| `Sources/Chevron7Kit/EZZK/SOAP/URLSessionEZZKSOAPTransport.swift` | The pinned, redirect-refusing transport. |
| `Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPCredentialStore.swift` | The Keychain item. |
| `Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPClient.swift` | The actor: lazy login, token cookie, one safe re-login, no repeat of consequential calls. |
| `Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPServiceAdapter.swift` | `EZZKServicing` for the app: filters used numbers, refuses production allocation and submission. |
| `Sources/Chevron7Kit/EZZK/EZZKEvidenceNumberPolicy.swift` | The day rule, the mode rule and the clause identity check. |
| `Sources/Chevron7App/EZZK/EZZKAccountController.swift` | Account state for Settings and ZaKo, one transport and one client per environment. |
| `Sources/Chevron7App/Views/SettingsView.swift` | The EZZK tab. |
| `Sources/ezzk-probe/main.swift` | The command line probe. |

## Probe

```
swift run ezzk-probe <login|time|numbers|consume|lookup> [number] [--env test|production] [--name N] [--ico I] [--at ISO]
```

Credentials come from `EZZK_LOGIN` and `EZZK_PASSWORD`, otherwise from the Keychain
item Settings saved for that environment. `numbers` and `consume` refuse
`--env production` before building a client. The token is never printed; `login`
prints only the account name.

## Testing

- `swift test --filter EZZK` runs the unit tests. They never reach the network and never touch the real Keychain.
- Request bodies are validated with `/usr/bin/xmllint --schema` against the production WSDL and XSD snapshot, including a negative case that must fail.
- Response parsing runs against recorded replies with tokens redacted and personal data anonymized.
- `EZZK_LIVE=1 swift test --filter EZZKSOAPTransportTests` additionally performs the real pinned handshake against the test host with an unauthenticated `GetOptions`, and asserts that a wrong pin is refused.
- Live checks with the probe are manual and are not part of CI.

## Maintenance

- The test certificate is self-signed, `CN=ezzk-test.iomo.sk`, and expires on 2026-10-20. When it is renewed, read the new digest and update `EZZKEnvironment.pinnedCertificateSHA256`:

  ```bash
  echo | openssl s_client -connect ezzk-test.iomo.sk:443 -servername ezzk-test.iomo.sk 2>/dev/null | openssl x509 -outform DER | shasum -a 256
  ```

- Production uses a public RapidSSL certificate for `*.iomo.sk`. The one observed on 2026-09-17 expires on 2026-09-21; if it lapses, EZZK fails for every integrator, which is not a Chevron7 defect.
- The WSDL and XSD snapshot is dated. Refresh it when the service changes and rerun the request tests.
- Gaps deliberately left open in part A are listed at the end of `docs/P2E-EZZK-FINDINGS.md`.
