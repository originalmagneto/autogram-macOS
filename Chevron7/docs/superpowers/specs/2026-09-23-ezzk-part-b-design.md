# EZZK part B: correct clause, signed record, submission, production

Date: 2026-09-23. Revision 2, after an independent review and after reading an accepted record back from EZZK. Status: awaiting review.
Builds on: `2026-09-17-ezzk-soap-design.md` (part A). Background: `Chevron7/docs/EZZK-INTEGRATION.md`, `Chevron7/docs/P2E-EZZK-FINDINGS.md`.

## Goal

An advocate completes a guaranteed conversion (zaručená konverzia, paper to electronic) in Chevron7 including the record in the live EZZK, the way they did it through podpisuj.sk until now. Advocates have been asking for this.

Success means:

- A record Chevron7 sends is processed by EZZK: the public lookup reports "Záznam je spracovaný", as it does for Podpisuj's `1563-260824-1`.
- The evidence number is allocated, used and its record accepted on the same Bratislava day, before midnight.
- The document the client receives carries the correct conversion clause (osvedčovacia doložka) in a correctly built, signed container.

## Reference: a record EZZK accepted

On 2026-09-23 `ezzk-probe record 1563-260824-1 --env production` (`GetConversionRecord`, read only, the owner's own record) returned the record Podpisuj sent on 2026-08-24, reported as processed. It is kept locally in `EXAMPLES/ezzk-records/` (ignored by git: it carries a client's name, and the repository is public). It is the oracle for this design:

- **Container:** ASiC-E (`application/vnd.etsi.asic-e+zip`) holding exactly one data file, `1563-260824-1.record.xml.xdcf`, with manifest MIME `application/vnd.gov.sk.xmldatacontainer+xml`, and `META-INF/signatures001.xml`.
- **Signature:** XAdES, one reference to the `.xdcf` plus SignedProperties, `DataObjectFormat` MIME `application/vnd.gov.sk.xmldatacontainer+xml`, exclusive C14N, RSA-SHA256, `SigningTime` and one `SignatureTimeStamp` (level Baseline T). The timestamp comes from the Belgian qualified TSA (BOSA, policy `2.16.56.13.6.3.1.1000`), the same default the Chevron7 engine uses. The signing certificate is the advocate's I.CA mandate certificate ("OPRÁVNENIE 1042", policy `1.3.158.36061701.1.1.1042`, QC policy `0.4.0.194112`).
- **XDC 1.1:** `XMLData ContentType="application/xml; charset=UTF-8" Identifier="http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0" Version="1.0"`. `UsedXSDReference` URI `https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0/form.xsd`, digest `V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=`. `UsedPresentationSchemaReference` URI `.../1.0/form.xslt`, `ContentType="application/xslt+xml"`, `MediaDestinationTypeDescription="TXT"`, digest `TYaNJLG/51TOIF8aFEcTQw72vudBAtYZUOkOfRG87as=`. Both `DigestMethod="urn:oid:2.16.840.1.101.3.4.2.1"`, `TransformAlgorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"`.
- **Digest rule (verified):** those digests equal SHA-256 over Canonical XML 1.0 **without comments** of the official `schema.xsd` and `Content/form103.sb.xslt` (the package manifest's `media-destination="sign"` file). With comments, or over the raw bytes, or over `form103.html.xslt`, they do not match.
- **Record body:** element order Name, Order, Type, sheets, non-empty pages, paper sizes, security elements inside `OriginalDocumentInfo`; then `NewDocumentInfo`, `ConversionRecordEvidenceNumber` (the plain number, `1563-260824-1`), `UsedDevice` (`Podpisuj v5.7.144`), `ConversionExecutionDateTime` (`2026-08-24T18:35:44+02:00`), `PersonPerformingConversion` last. Plain strings where the record schema has `MandatoryStringType`: `PaperSize` `A4`, security element description as the clause codelist item code (`vlastnoručný podpis`, `okrúhla pečiatka so štátnym znakom`, `lepiaci štítok`), location as the clause location item code (`Left down`, `Down`, `Right down`), `NewDocumentFormat` `PDF/A-2`, `ElectronicFingerprintCalculationMethod` `SHA-256`. `OriginalDocumentType` repeats the document name. The person block is given and family name, `Position`, `LegalSubject/Name`, and `ID` with codelist 4001 item 7 and `IdentifierValue` `https://data.gov.sk/id/legal-subject/<IČO>`.

## Facts about today's code

- **The clause slot holds a record.** `AttestationClauseGenerator` (`Chevron7/Sources/Chevron7Kit/Attestation/AttestationClauseGenerator.swift:8-9, 83-145`) emits the record form. `ZakoSessionStore.authorizeAndSign` embeds it in the PDF/A as `osvedcovacia-dolozka.xml` and puts it beside the document as `.xml.xdcf`. The clause form is never generated. `P2EConformanceValidator` (`:164`) requires the clause root but runs only in `P2EConformanceTests` on fixtures.
- **Today's record would not validate or match EZZK's sample:** codelist elements inside `MandatoryStringType` fields (`:105, :126, :129`); `OriginalDocumentOrder` before `OriginalDocumentName` (`:85-86`); `OriginalDocumentType` omitted when empty (`:88`) although required; the tail order is person, device, time, number instead of number, device, time, person (`:135-145`); the evidence number is written as a URI (`ZakoCodelists.conversionRecordURI`, `ZakoCodelists.swift:49-53`).
- **Today's `.xml.xdcf` is bare form XML,** not an `XMLDataContainer`.
- **The card-signed ZaKo container nests.** `ZakoSessionStore.swift:1196-1241` packs PDF and `.xdcf` into an unsigned `kontajner.asice` (`ASiCEPackager.zakoContainer`) and sends it as one file. DSS treats an ASiC without a signature file as one data object and wraps it again (`WEB-SIGNING-FINDINGS-2026-09-16.md` finding 6, same mechanism, fixed there for web signing only). Podpisuj's client containers in `EXAMPLES/` instead carry one signature with two references, one to the PDF and one to the clause `.xdcf`.
- The engine's single-file route already produces the record's container shape: an `.xdcf` source with `XAdES_BASELINE_T` goes through `buildForASiCWithXAdES` (`engine/.../MachineSigningService.java:645-647`) and yields a one-file ASiC-E with the XDC MIME in `DataObjectFormat`. One machine sign request carries one signature level and one eForm for all its files (`MachineV2RequestValidator.java:28-61`).
- The timestamp switch `includeQualifiedTimestamp` is a mutable property (`ZakoSessionStore.swift:65`). The engine reports `qualifiedTimestampValid` per signature through inspection (`AutogramCLIEngine.swift:631`, `InspectionModels.swift:47`).
- The mobile (AVM) ZaKo path uploads only the PDF (`ZakoSessionStore.swift:1212-1224`), so it produces neither a clause container nor a record.
- The PIN for I.CA cards is typed into Chevron7's own field (`SigningIdentityInfo.requiresPIN`, `SigningProvider.swift:20`), so the app can pass it to two sign requests.
- `ReceiveConversionRecord` is built and validated against the production XSD (`EZZKSOAPRequest.swift:169-195`, `EZZKSOAPRequestTests`): one `ObjectOfstring` per record, `Class=ATTACHMENT`, `Encoding=Base64`, `Id` = evidence number, `IsSigned=true`, MIME, base64 data. Result 0 is acceptance for processing only. Result 106 means a number is used by several records, so EZZK stores duplicates rather than refusing them.
- `ConsumeConversionRecordEvidenceNumber` exists (`EZZKSOAPClient.swift:71`). Whether `ReceiveConversionRecord` consumes the number implicitly is not known.
- `register.json` status raw values are Slovak labels (`LocalEvidenceStore.swift:9-15`); `EvidenceRecord.envelope()` carries only the attestation XML.

## Official forms

Downloaded 2026-09-23 from `https://www.slovensko.sk/static/eform/dataset/`; zip hashes match `docs/reference/security-elements/provenance.json`.

| Form | Package SHA-256 | Schema | Signer presentation (`media-destination="sign"`) |
|---|---|---|---|
| Record 1.0 (in force 2019-11-29) | `55fbf20ccb3d7d20c03bc0b2f1d42812144234bce9f9115b714f6fae4783e3dc` | `schema.xsd` `7b00f00c0e910dccc61f447681ba5b3e6a719650c49f400ba2b7cc8ace582e0e` | `Content/form103.sb.xslt`, TXT |
| Clause 1.3 (in force 2019-12-01) | `5bc8c120c1970c623ddaf6d7e289a192879664586cf7a445d0d6f2a5257eb6ab` | `schema.xsd` `5c4de06e0a115943cc3ef3a01cbd1388e495acfb2c66c7e7fe4c5769f383be8e` | two `sign` entries: `Content/form.2.html2.xslt` (HTML) and `Content/form.2.sb.xslt` (TXT); use the HTML one |

Clause 1.3 identifiers: namespace `http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3`, identifier `http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3` (already in `P2EConformanceProfile.targetV1_3`). Its reference URIs follow the same convention as the accepted record: `<namespace>/form.xsd` and `<namespace>/form.xslt`. The presentation reference is `form.2.html2.xslt` with `MediaDestinationTypeDescription="HTML"`: the engine's `EFormResourceLoader.selectXslt` prefers the `sign` entry of type HTML, and Podpisuj's clause containers in `EXAMPLES/` reference an HTML presentation. The clause uses codelists (12 paper size, 15 security element, 11 location, 53 new document format, as in Podpisuj's clauses) with the item codes listed in `docs/reference/security-elements/select-options.json` (`OriginalDocumentPaperSize`, `Description`, `Location`, `FormatDokumentu`); the record uses the same item codes as plain strings.

## Decisions

1. Part B includes the clause fix. Clause version **1.3**.
2. Clause and record are signed at authorization with one PIN entry, and the record is sent to EZZK immediately. Unsent records stay in Register konverzií with a midnight warning.
3. Live (production) conversion with EZZK is card only. Because the mobile path produces neither a clause container nor a record, ZaKo on the phone stays available in Demo only; Test and Production refuse it with a clear message.
4. Chevron7 builds the form XML and its XDC; **the engine builds and signs every container** (no unsigned container is ever handed to the engine). This replaces "Chevron7 packs, engine signs" from revision 1.

## Components

1. **Official form resources.** Record 1.0 and clause 1.3 `schema.xsd` and the signer XSLT (`form103.sb.xslt`, `form.2.html2.xslt`) become Chevron7Kit resources with a provenance file (URL, date, SHA-256). A copy goes to `Chevron7/docs/reference/forms/`. The XDC digests are stored beside them. Tests check the file hashes against the provenance file and recompute the digests as C14N without comments; for record 1.0 the recomputed digests must equal the accepted record's values above.
2. **`ConversionFormModel` (new).** One value built from `AttestationData` and the confirmed security elements, holding every field both forms need (including document order, document type defaulting to the document name, used device `Chevron7 v<version>`, plain evidence number). Both renderers read only this model, so clause and record cannot disagree.
3. **`ConversionRecordRenderer` (replaces `AttestationClauseGenerator`).** Renders record 1.0 exactly in the accepted record's shape and order, plain strings where the schema says `MandatoryStringType`.
4. **`ConversionCertificateRenderer` (new).** Renders clause 1.3 with codelists (12, 15, 11, 53) and the person identifier codelist 4001.
5. **`XMLDataContainerBuilder` (new).** Wraps a rendered form into XDC 1.1 with the identifier, version, reference URIs and stored digests of its form.
6. **Engine: multi-document ASiC-E (new machine protocol capability).** One sign request whose files are signed as separate data objects of one new ASiC-E (DSS `signDocument(List<DSSDocument>)`), each with its own `DataObjectFormat` MIME (`application/pdf`, `application/vnd.gov.sk.xmldatacontainer+xml`). Used for the client container: PDF/A plus clause `.xdcf`, like Podpisuj's. Covered by engine tests at `XAdES_BASELINE_T`, including a check that the result holds no nested container.
7. **Engine: record container (existing route).** The record `<number>.record.xml.xdcf` is sent as one file with `XAdES_BASELINE_T`; the engine builds the one-file ASiC-E. An engine test pins the manifest and `DataObjectFormat` MIME.
8. **Signing orchestration.** Two sign requests with the same PIN: client container, then record. The qualified timestamp is forced on outside Demo (the switch is not offered there). After signing, both results are inspected and must report `qualifiedTimestampValid`; otherwise nothing is sent.
9. **Submission.** `EZZKSOAPServiceAdapter.submit` sends the signed record container through `ReceiveConversionRecord` (MIME `application/vnd.etsi.asic-e+zip`).
10. **Register konverzií.** `EvidenceRecord` gains: submission state, path of the signed record container, submit time, request `MessageID`, EZZK result code and description, last lookup time and result, and the EZZK mode the conversion was signed in. Existing status raw strings are frozen; new states get new strings.
11. **One production policy.** The refusals at `EZZKSOAPClient.swift:103-107`, `EZZKSOAPServiceAdapter.swift:26,38`, `EZZKAccountController.swift:126`, `ezzk-probe/main.swift:50`, `SettingsView.swift:921-922,977-990`, `AuthorizeDoneViews.swift:431-437` and `EvidenceDashboardView.swift:348-364` read one `EZZKProductionPolicy`. The legacy OAuth client (`EZZKSessionController`) stays closed and untouched.

## Flow at authorization

1. The evidence number is allocated in the attestation form as today; the same-day and same-mode rules still apply.
2. Chevron7 reads the EZZK server time as the conversion time and builds `ConversionFormModel`.
3. Clause and record are rendered, wrapped in XDC and validated against the official schemas. Invalid output is never signed and the number is not used.
4. PDF/A is produced with the clause (not the record) as its embedded associated file.
5. Engine request 1 signs PDF/A plus clause `.xdcf` into the client container; request 2 signs the record into its container. One PIN entry.
6. Both signatures are inspected for a qualified timestamp.
7. Outputs and the register row are saved, and the record is submitted at once.
8. The Done screen shows the submission result and the mode the conversion was signed in.

## Register states

| State | Meaning | Next step |
|---|---|---|
| Podpísaný | clause and record signed, not yet sent | submit automatically |
| Čaká na odoslanie | submission certainly did not happen (failed before any byte was sent) | "Odoslať" button |
| Prijatý na spracovanie | EZZK returned result 0 | automatic status check |
| Spracovaný | public lookup reports the record as processed | done |
| Výsledok neznámy | the request may have reached EZZK (network loss mid-request, HTTP 5xx) | no automatic resend; resolve by lookup first |
| Odmietnutý | EZZK returned a non-zero result | show the code and description |
| Záznam nepodpísaný | client container signed, record signature failed | sign the record again from the register (PIN) |
| Oneskorený | not accepted before Bratislava midnight of the allocation day | send with an explicit warning, record what EZZK answers |

Rules:

- **No double submission.** EZZK stores duplicates (result 106), so "Výsledok neznámy" is resolved by the public lookup of the evidence number before anything else. Found: the row moves to "Prijatý na spracovanie" or "Spracovaný". Not found: back to "Čaká na odoslanie".
- **Status check.** The public lookup (no login) runs about 5 minutes after acceptance, then hourly while the app runs, until processed.
- **Midnight.** A row not yet accepted on its allocation day gets a prominent warning in the register and the sidebar during that day. After midnight it becomes "Oneskorený". The signed clause already carries the number, so the record is never re-signed with a new number; whether EZZK accepts a late record is verified on test (B2) and the warning text states the verified behaviour.
- **Existing rows.** Old status strings keep decoding; nothing on disk is rewritten until a row changes.

## Error handling and part A gaps closed here

- **One login at a time (gap 2).** Authenticated calls share one in-flight login. A rejected password stops further logins until it is changed in Settings (`CORE-018`).
- **Network loss while sending (gap 5).** For `ReceiveConversionRecord`, errors after the request started count as outcome unknown.
- **Register downgrades unknown to failed.** `EvidenceDashboardView` (`:337-365`) stops mapping `outcomeUnknown` to `submissionFailed`.
- **Done screen mode (gap 6).** Reads the stored mode of the conversion.
- **Tests reading the real Keychain (gap 7).** The three older ZaKo tests use `AppSettingsStore(ezzkAccountController:)`.
- Failure before signing: nothing is signed or sent; the number stays unused and lapses at midnight, which is harmless because no clause carries it. Failure signing the record: the client container stays, the row is "Záznam nepodpísaný". Failure sending: see the table.

Left open, not blocking part B: the whole-certificate test pin (gap 1, expires 2026-10-20), the Keychain accessibility attribute (gap 3), demo numbers looking like production numbers (gap 4).

## Delivery in three parts

Each part gets its own implementation plan and merges on its own.

- **B1: correct client output.** Form resources, `ConversionFormModel`, clause renderer, XDC builder, engine multi-document ASiC-E, PDF/A embedding the clause, `P2EConformanceValidator` run on the real ZaKo output in a test, mobile ZaKo limited to Demo. No EZZK behaviour changes. Fixes a defect users have today, so it ships first.
- **B2: record and submission.** Record renderer, record container, signing orchestration and timestamp check, submission, register states and fields, gaps 2, 5, 6, 7 and the dashboard bug, `ezzk-probe record`. Live verification on test EZZK.
- **B3: production.** `EZZKProductionPolicy`, owner switch, first live conversion, then enabling production for everyone.

## Testing

Automated, without network, card or real storage (`RealStorageGuard` applies):

- Clause and record, inside their XDC, validated with `xmllint --nonet --schema` against the official schemas.
- The record renderer's output compared element by element with the accepted record's structure (a sanitised fixture with invented names, same shape).
- XDC digests recomputed as C14N without comments and compared with the stored values and, for the record, with the accepted record.
- Engine: multi-document container has one signature, two references, correct `DataObjectFormat` MIME, no nested ASiC; record container matches the accepted record's layout.
- `P2EConformanceValidator` on the container produced by the ZaKo flow.
- Register transitions: unknown outcome, lookup resolution, resend, late, midnight in Europe/Bratislava; frozen status strings decode.
- Single-flight login and stop after a rejected password; production policy honoured at every former refusal point.

Live, on test EZZK with the owner, before 2026-10-20 (the test certificate pin expires then):

1. Settings in Test mode with the MIRRI manual's sample account (entered by the owner; not stored in the repository).
2. A full conversion of a synthetic document with the SAK card; the lookup must report the record processed.
3. `ezzk-probe numbers` before and after: does `ReceiveConversionRecord` consume the number, or must Chevron7 call `ConsumeConversionRecordEvidenceNumber`? The answer goes into B2 before B3.
4. A record sent after the allocation day's midnight: what EZZK returns (for the "Oneskorený" text).
5. `ezzk-probe record` on the test record: the stored object must match what Chevron7 sent.

## Rollout

Every `feat` or `fix` push to `main` publishes a release, so:

1. B1 and B2 merge to `main` with production allocation and submission off for everyone.
2. A hidden owner switch (`defaults write` key read by `EZZKProductionPolicy`, no UI) enables production on the owner's Mac. The key ships in every build and can be found, but it only unlocks EZZK calls with the account the user has already signed in with, so it gives nobody access they do not have. The owner performs the first live conversion; the lookup must report "Záznam je spracovaný".
3. A `feat` commit enables production for everyone and unlocks "Odosielanie záznamov" in Settings, which publishes the release.

## Out of scope

- Record form 1.2 "from 2027-01-01": slovensko.sk serves only record 1.0. Before any work on it, find the source of that claim.
- Mobile (AVM) ZaKo outside Demo.
- OpenSC, the card status badge in the ZaKo section (separate task), AI detection learning.
- Batch signing of records from the register.
