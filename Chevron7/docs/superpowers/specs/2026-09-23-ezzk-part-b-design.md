# EZZK part B: correct clause, signed record, submission, production

Date: 2026-09-23. Status: design approved in conversation, awaiting review of this written spec.
Builds on: `2026-09-17-ezzk-soap-design.md` (part A). Background: `Chevron7/docs/EZZK-INTEGRATION.md`, `Chevron7/docs/P2E-EZZK-FINDINGS.md`.

## Goal

An advocate completes a guaranteed conversion (zaručená konverzia, paper to electronic) in Chevron7 including the record in the live EZZK, the way they did it through podpisuj.sk until now. Advocates have been asking for this.

Success means:

- A record Chevron7 sends is processed by EZZK: the public lookup reports "Záznam je spracovaný", as it does for Podpisuj's `1563-260824-1`.
- The evidence number is allocated, used and its record accepted on the same Bratislava day, before midnight.
- The document the client receives carries the correct conversion clause (osvedčovacia doložka).

## Facts this design rests on

Verified on 2026-09-23 unless a source says otherwise.

- Production EZZK works for reading: sign-in from the app (Settings, account `MarianCuprik_L`) and from `ezzk-probe login --env production`, and the public lookup of `1563-260824-1`. The production TLS certificate is public (RapidSSL, valid to 2027-04-03). The pinned test certificate expires 2026-10-20.
- **Defect in today's output.** `AttestationClauseGenerator` (`Chevron7/Sources/Chevron7Kit/Attestation/AttestationClauseGenerator.swift:8-9, 83-145`) emits the record form (`ConversionRecord`, record 1.0 namespace). `ZakoSessionStore.authorizeAndSign` embeds it in the PDF/A as `osvedcovacia-dolozka.xml` and packs it as the `.xml.xdcf` beside the document. The clause form (`ConversionCertificateOfPaperToElectronicDocument`) is never generated. `P2EConformanceValidator` (`:164`) requires the clause root, but it only runs in `P2EConformanceTests` on fixtures, never on real output. Podpisuj's containers in `EXAMPLES/` carry the clause (their identifier `.../ConversionCertificateOfPaperToElectronicDocument/1.2`) wrapped in an XDC 1.1.
- Today's `.xml.xdcf` is bare form XML, not an `XMLDataContainer`.
- Official form packages (downloaded 2026-09-23, SHA-256 matches `docs/reference/security-elements/provenance.json`):
  - Record 1.0: `https://www.slovensko.sk/static/eform/dataset/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0.zip` (`55fbf20ccb3d7d20c03bc0b2f1d42812144234bce9f9115b714f6fae4783e3dc`), in force since 2019-11-29, namespace `https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`. `schema.xsd` `7b00f00c0e910dccc61f447681ba5b3e6a719650c49f400ba2b7cc8ace582e0e`, `Content/form103.html.xslt` `7af9e14eac4a5336bd04a604c126673d2be077fc117641f535cbe9e54d5cb4fb`.
  - Clause 1.3: `https://www.slovensko.sk/static/eform/dataset/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3.zip` (`5bc8c120c1970c623ddaf6d7e289a192879664586cf7a445d0d6f2a5257eb6ab`), in force since 2019-12-01, namespace `http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3`. `schema.xsd` `5c4de06e0a115943cc3ef3a01cbd1388e495acfb2c66c7e7fe4c5769f383be8e`, `Content/form.2.xslt` `b350ad4bb239dc3c2e19054e966addd72007be63b7c8a40a6677cf3488fe4817`, `Content/form.2.html.xslt` `86d745d7b4b1cdd1d8cb172270d8efc1cb91e0917a1419c878d783deb2b5078f`.
  - No other version of either form is served at that address (1.1, 1.2, 1.4, 2.0 return 404).
- The clause 1.3 and record 1.0 schemas carry the same data. The record adds `OriginalDocumentOrder`, `OriginalDocumentType` and `UsedDevice`; the clause adds optional `...Other` free-text elements beside codelist values.
- `XMLDataContainer` 1.1 as Podpisuj writes it: `XMLData` with `ContentType`, `Identifier`, `Version`, then `UsedSchemasReferenced` with `UsedXSDReference` and `UsedPresentationSchemaReference` (`ContentType="application/xslt+xml"`, `MediaDestinationTypeDescription="HTML"`), each with `DigestMethod="urn:oid:2.16.840.1.101.3.4.2.1"` (SHA-256), `TransformAlgorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"` and a base64 `DigestValue`.
- `ReceiveConversionRecord` is built and validated against the production XSD (`EZZKSOAPRequest.receive`, `EZZKSOAPRequest.swift:169-195`; `EZZKSOAPRequestTests`). It sends each record as an `ObjectOfstring` attachment (`Class=ATTACHMENT`, `Encoding=Base64`, `Id`=evidence number, `IsSigned=true`, MIME type, base64 data). `Result` 0 means accepted for processing only; rejections arrive later in the sender's eDesk. An empty batch returns 110.
- `GetConversionRecord` and the public lookup return metadata only (`OdpovedVypis`), never the record file, so no accepted record can be fetched as a sample.
- Podpisuj reports that EZZK marks advocate records without a timestamp as invalid.
- One machine protocol sign request carries one signature level and one eForm for all files (`MachineV2RequestValidator.java:28-61`), so clause and record are two requests.
- The mandate certificate lives on the SAK (I.CA) card. For I.CA the PIN is typed into Chevron7's own field (`EngineBridgeSigningProvider.requiresPIN`), so the app can pass it to both requests.

## Decisions

1. Part B includes the clause fix. Clause version **1.3** (official, published, in force).
2. Clause and record are signed together at authorization with one PIN entry, and the record is sent to EZZK immediately. Unsent records stay in Register konverzií with a midnight warning.
3. Live (production) conversion with EZZK is card only. The mobile (AVM) path is refused on production with a clear message; it stays available in Demo and Test.
4. Approach A: Chevron7 builds both containers; the engine signs both through the existing ASiC path. The engine's eForm mode is not used.

## Components

1. **Official form resources.** The record 1.0 and clause 1.3 `schema.xsd` and presentation XSLT files become package resources of Chevron7Kit, with a provenance file (URL, date, SHA-256). A copy goes to `Chevron7/docs/reference/forms/` for tests and review. A test checks the resource hashes against the provenance file.
2. **`ConversionCertificateGenerator` (new).** Builds clause 1.3 XML from `AttestationData` and the confirmed security elements.
3. **`ConversionRecordGenerator` (renamed).** Today's `AttestationClauseGenerator` renamed to what it produces. Existing behaviour kept; completeness checked against the full record 1.0 schema. Both generators share one input model so clause and record cannot disagree.
4. **`XMLDataContainerBuilder` (new).** Wraps a form document into XDC 1.1 exactly as described under Facts. Reference URIs, identifier and version come from the official package metadata. The digests are SHA-256 over the Canonical XML 1.0 form of the XSD and XSLT resources; they are fixed values stored beside the resources, and a test recomputes them with `xmllint --c14n` so a resource change without a digest change fails.
5. **Two containers.**
   - Document for the client: PDF/A plus the clause `.xml.xdcf`. The PDF/A embeds the clause (not the record) as its associated file.
   - Record for EZZK: `<evidence number>.asice` holding only the record `.xml.xdcf`.
   Both are packed by the existing `ASiCEPackager`.
6. **Signing.** The engine signs both containers through the path ZaKo uses today (`buildForExistingASiC(XAdES_BASELINE_T)`, `engine/.../MachineSigningService.java:639-643`), two requests with the same PIN. After signing, Chevron7 checks that both signatures carry a qualified timestamp; if not, the conversion stops before anything is sent. The engine already evaluates timestamp qualification (`engine/.../ui/machine/TimestampQualificationEvaluator.java`); the implementation plan decides how that result reaches the app.
7. **Submission.** `EZZKSOAPServiceAdapter.submit` sends the signed record container through the existing `ReceiveConversionRecord` call (MIME `application/vnd.etsi.asic-e+zip`).
8. **Register konverzií.** `EvidenceRecord` gains the submission state, submit time, request `MessageID`, EZZK result code and description, the last lookup time and the EZZK mode the conversion was signed in.
9. **One production policy.** The production refusals spread over `EZZKSOAPClient.swift:103-107`, `EZZKSOAPServiceAdapter.swift:26,38`, `EZZKAccountController.swift:126`, `ezzk-probe/main.swift:50`, `SettingsView.swift:921-922,977-990`, `AuthorizeDoneViews.swift:431-437` and `EvidenceDashboardView.swift:348-364` read one `EZZKProductionPolicy` instead of deciding separately. The legacy OAuth client (`EZZKSessionController`) stays closed and untouched.

## Flow at authorization

1. The evidence number is allocated in the attestation form as today; the same-day and same-mode rules (`EZZKEvidenceNumberPolicy`, `AttestationData.evidenceNumberMode`) still apply.
2. Chevron7 reads the EZZK server time as the conversion time and builds the clause and the record.
3. Both documents are validated against the official schemas before signing. An invalid document is never signed and the number is not used.
4. PDF/A with the clause, then both containers, then both signatures with one PIN, then the qualified timestamp check.
5. Outputs and the register row are saved, and the record is submitted at once.
6. The Done screen shows the submission result and the mode the conversion was signed in.

## Register states

| State | Meaning | Next step |
|---|---|---|
| Podpísaný | clause and record signed, not yet sent | submit automatically |
| Čaká na odoslanie | submission certainly did not happen (no network before sending) | "Odoslať" button |
| Prijatý na spracovanie | EZZK returned result 0 | automatic status check |
| Spracovaný | public lookup reports the record as processed | done |
| Výsledok neznámy | the request may have reached EZZK (network loss mid-request, HTTP 5xx) | no automatic resend; resolve by lookup first |
| Odmietnutý | EZZK returned a non-zero result | show the description |
| Záznam nepodpísaný | clause signed, record signature failed | sign the record again from the register (PIN) |

Rules:

- **No double submission.** "Výsledok neznámy" is resolved by the public lookup of the evidence number. Found: the row moves to "Prijatý na spracovanie" or "Spracovaný". Not found: the row returns to "Čaká na odoslanie" and may be sent again.
- **Status check.** The public lookup (no login) runs about 5 minutes after acceptance, then hourly until the record is processed, while the app runs.
- **Existing rows.** `register.json` today uses draft, awaitingNumber, readyToSign, signed, queuedForSubmission, submitted and submissionFailed (`LocalEvidenceStore.swift:8-15`). Old values keep decoding: `signed` and `queuedForSubmission` map to "Podpísaný" and "Čaká na odoslanie"; `submitted` and `submissionFailed` rows (Demo only so far, since submission never worked) keep their meaning. Only new fields are added; nothing is rewritten on disk until a row changes.
- **Midnight.** A row not yet accepted on the day its number was allocated gets a prominent warning in the register and the sidebar; after Bratislava midnight it is marked late (oneskorený).

## Error handling and part A gaps closed here

- **One login at a time (gap 2).** Authenticated calls share a single in-flight login. A rejected password stops all further logins until the password is changed in Settings, so automatic submission cannot lock the account (`CORE-018`).
- **Network loss while sending (gap 5).** For `ReceiveConversionRecord`, `notConnectedToInternet` and similar errors after the request started count as outcome unknown; only a failure before any byte left counts as not sent.
- **Register downgrades unknown to failed.** `EvidenceDashboardView` (`:337-365`) stops mapping `outcomeUnknown` to `submissionFailed`.
- **Done screen mode (gap 6).** Reads the stored mode of the conversion, not the current setting.
- **Tests reading the real Keychain (gap 7).** The three older ZaKo tests use `AppSettingsStore(ezzkAccountController:)`.
- Failure before signing (schema, server time, timestamp): nothing is signed or sent; the number stays unused until midnight. Failure signing the record: the clause stays, the row is "Záznam nepodpísaný". Failure sending: see the table.

Left open, not blocking part B: the whole-certificate test pin (gap 1, expires 2026-10-20), the Keychain accessibility attribute (gap 3), demo numbers looking like production numbers (gap 4).

## Testing

Automated, without network, card or real storage:

- Clause and record output validated with `xmllint --nonet --schema` against the official schemas, in the pattern of `EZZKSOAPRequestTests`.
- XDC structure and digests; the XDC envelope compared with the Podpisuj clauses in `EXAMPLES/`.
- `P2EConformanceValidator` run on the real container produced by the ZaKo flow in a test, so the defect found here cannot return.
- Register state transitions: unknown outcome, lookup resolution, resend, midnight in Europe/Bratislava.
- Single-flight login and stop after a rejected password.
- Production policy: every former refusal point honours the one policy.
- Tests never touch the real `~/Library/Application Support/Chevron7`, the real Keychain or live EZZK (`RealStorageGuard` applies).

Live, with the owner, before 2026-10-20:

1. Settings in Test mode with the MIRRI manual's sample account (entered by the owner; not stored in the repository).
2. A full conversion of a synthetic document with the SAK card.
3. The record reaches test EZZK and the lookup shows it processed.
4. Signatures and timestamps of both containers checked with a signature validator.

## Rollout

Every `feat` or `fix` push to `main` publishes a release, so production is switched on in steps:

1. Part B merges to `main` with production allocation and submission off for everyone. Other advocates keep Demo and Test.
2. A hidden owner switch (`defaults write` key read by `EZZKProductionPolicy`, no UI) enables production on the owner's Mac. The owner performs the first live conversion; the lookup must report "Záznam je spracovaný".
3. One small follow-up commit enables production for everyone and unlocks the "Odosielanie záznamov" card in Settings.

## Out of scope

- Record form 1.2 "from 2027-01-01": slovensko.sk serves only record 1.0. Before any work on it, find the source of that claim.
- Mobile (AVM) conversion on production.
- OpenSC, the card status badge in the ZaKo section (separate task), AI detection learning.
- Batch signing of records from the register.
