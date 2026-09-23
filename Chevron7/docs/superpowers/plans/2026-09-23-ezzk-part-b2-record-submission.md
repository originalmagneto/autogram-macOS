# EZZK Part B2: Signed Record and Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At authorization Chevron7 also builds, signs and sends the conversion record to EZZK, tracks each record's EZZK state in Register konverzií, and reuses evidence numbers it already holds; production stays refused until B3.

**Architecture:** Chevron7Kit renders record 1.0 from the B1 `ConversionFormModel`, validates it against a libxml2-compatible copy of the official schema, and wraps it in an XDC. The engine gets a local (no network) route that signs a single `.xdcf` into a one-file ASiC-E. ZaKo sends both signing requests with the same PIN and the qualified built-in timestamp authorities. A Kit `EZZKSubmissionCoordinator` owns every register state transition (submit, unknown-outcome resolution, status check, late marking) so the ZaKo flow, the dashboard and the periodic checker share one rule set.

**Tech Stack:** Swift 6 / SwiftPM (macOS 27), XCTest, Java 25 engine with DSS (Maven wrapper), libxml2 `xmllint`.

**Spec:** `Chevron7/docs/superpowers/specs/2026-09-23-ezzk-part-b-design.md`, revision 5. The section "Revision 5: B2 amendments" wins over earlier sections for B2. Read it first.

## Global Constraints

- Toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never a beta Xcode.
- Swift tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <Name>` from `Chevron7/`; record every `Executed N tests` line of a full run (never pipe it through `tail`).
- Engine tests on the Mac Studio: `JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q -Dtest=<Class> test` from `engine/`.
- Tests never touch `~/Library/Application Support/Chevron7`, `~/Library/Caches/Chevron7`, the real Keychain or live EZZK (`RealStorageGuard`); App tests use `makeSettingsStore(ezzkAccountController:)` with `MemoryCredentialStore` and a scripted transport.
- Production stays refused: `EZZKSOAPClient` must keep refusing consequential calls (`numbers`, `consume`, `receive`) on `.production` before any network use. B3 changes that, not B2.
- English for code, comments and docs; Slovak for user-facing strings; never an em dash.
- `EvidenceRecord.Status` raw values are persisted and frozen; new states get new raw strings; every new stored field is optional.
- Record 1.0 identifiers, verbatim: identifier `http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`, namespace `https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`, XDC digests `V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=` and `TYaNJLG/51TOIF8aFEcTQw72vudBAtYZUOkOfRG87as=` (official files, never the validation copy).
- Record entry name `<number>.record.xml.xdcf`; manifest and `DataObjectFormat` MIME `application/vnd.gov.sk.xmldatacontainer+xml` (no charset); container MIME for `ReceiveConversionRecord` `application/vnd.etsi.asic-e+zip`.
- Bratislava time (`Europe/Bratislava`) decides "the allocation day" and midnight.

## Review Focus

1. The Mac loses Wi-Fi in the middle of `ReceiveConversionRecord`: the row must become "Výsledok neznámy", never "Čaká na odoslanie", and the next action is a lookup, not a resend. Test: Task 7 `testConnectionLostDuringReceiveIsOutcomeUnknown` and Task 9 `testUnknownOutcomeIsResolvedByLookupBeforeAnyResend`.
2. The advocate reopens ZaKo after an abandoned conversion and asks for a number while EZZK already allocated one today: Chevron7 must reuse it rather than hit code 113. Test: Task 10 `testReusesTodaysUnusedNumberBeforeAllocating`.
3. A stored EZZK password that has become wrong (changed in the portal): at most one login attempt until the password is changed in Settings, so the account is never locked. Test: Task 7 `testRejectedPasswordStopsFurtherLoginsUntilCredentialsChange`.
4. A register written by B1 (old statuses, no new fields) opens after the upgrade with every row intact. Test: Task 6 `testDecodesARegisterWrittenBeforeB2`.
5. The record signature fails after the client container was signed (card removed, wrong PIN on the second request): the client output is still saved and the row says "Záznam nepodpísaný". Test: Task 11 source-contract test plus Task 9 `testRecordUnsignedRowIsNeverSubmitted`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Chevron7/docs/reference/forms/record-1.0/schema.validation.xsd` (new) | Official record schema with only the IdentifierValue pattern made libxml2-valid |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialForm.swift`, `OfficialFormFiles.swift`, `scripts/embed-official-forms.sh` (modify) | `validationSchema` next to `schema` |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ConversionRecordRenderer.swift` (new) | Record 1.0 XML in the accepted record's shape |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ZakoRecordDeliveryBuilder.swift` (new) | Model in, validated record XDC and names out |
| `engine/.../ui/machine/MachineSigningService.java`, `engine/.../core/SigningJob.java` (modify) | Local one-file ASiC-E route for a record XDC |
| `Chevron7/Sources/Chevron7Kit/Signing/SigningProvider.swift`, `.../Signing/JavaEngine/EngineBridgeSigningProvider.swift`, `.../EngineBridge/Models/SigningModels.swift`, `.../EngineBridge/CLI/AutogramCLIEngine.swift` (modify) | Record source file, explicit timestamp endpoints |
| `Chevron7/Sources/Chevron7Kit/Evidence/LocalEvidenceStore.swift`, `.../Models/UXLabels.swift` (modify) | New states and fields, record container storage |
| `Chevron7/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPClient.swift` (modify) | Receipt, single-flight login, rejected-password stop, connection-loss rule |
| `Chevron7/Sources/Chevron7Kit/EZZK/EZZKService.swift`, `.../EZZK/SOAP/EZZKSOAPServiceAdapter.swift`, `Chevron7/Sources/Chevron7App/EZZK/EZZKSessionController.swift` (modify) | Submission carries the container and returns a receipt |
| `Chevron7/Sources/Chevron7Kit/EZZK/EZZKSubmissionCoordinator.swift` (new) | Every register state transition |
| `Chevron7/Sources/Chevron7Kit/EZZK/EvidenceNumberPool.swift` (new) | Allocated but unused numbers per mode and Bratislava day |
| `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift`, `.../Views/AuthorizeDoneViews.swift`, `.../Views/EvidenceDashboardView.swift`, `.../AppSettingsStore.swift` (modify) | Wiring, UI, periodic status check |

---

### Task 1: Libxml2-valid record schema

**Files:**
- Create: `Chevron7/docs/reference/forms/record-1.0/schema.validation.xsd`
- Modify: `Chevron7/docs/reference/forms/provenance.json`, `Chevron7/docs/reference/forms/README.md`, `Chevron7/scripts/embed-official-forms.sh`, `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialForm.swift`, `Chevron7/Sources/Chevron7Kit/Attestation/Forms/FormSchemaValidator.swift`
- Regenerate: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/OfficialFormTests.swift`, `Chevron7/Tests/Chevron7KitTests/FormSchemaValidatorTests.swift`

**Interfaces:**
- Produces: `OfficialForm.validationSchema: Data` (equals `schema` for clause 1.3); `FormSchemaValidator.validate(_:against:)` validates against `validationSchema`.

- [ ] **Step 1: Create the validation copy**

```bash
cd Chevron7
sed 's#https:\\/\\/data\\.gov\\.sk\\/id\\/legal-subject\\/#https://data\\.gov\\.sk/id/legal-subject/#' \
  docs/reference/forms/record-1.0/schema.xsd > docs/reference/forms/record-1.0/schema.validation.xsd
diff docs/reference/forms/record-1.0/schema.xsd docs/reference/forms/record-1.0/schema.validation.xsd
```
Expected: exactly one changed line, the `IdentifierValueType` pattern, now `https://data\.gov\.sk/id/legal-subject/([0-9]{8}|[0-9]{12})`.
Run: `echo '<a/>' > /tmp/x.xml; xmllint --nonet --noout --schema docs/reference/forms/record-1.0/schema.validation.xsd /tmp/x.xml`
Expected: the schema compiles (the only error is about element `a`).

- [ ] **Step 2: Provenance and README**

Add to `provenance.json` under `files`:

```json
    "record-1.0/schema.validation.xsd": {
      "derived_from": "record-1.0/schema.xsd",
      "sha256": "<shasum -a 256 of the new file>",
      "derivation": "Only the IdentifierValueType pattern rewritten from https:\\/\\/data\\.gov\\.sk\\/id\\/legal-subject\\/([0-9]{8}|[0-9]{12}) to https://data\\.gov\\.sk/id/legal-subject/([0-9]{8}|[0-9]{12}) because libxml2 rejects the escaped slashes. Used only for local validation; XMLDataContainer references and digests stay on schema.xsd."
    }
```

Replace `<shasum -a 256 of the new file>` with the printed hash before saving. Append one paragraph to `README.md` saying the same in two sentences.

- [ ] **Step 3: Embed it**

In `scripts/embed-official-forms.sh`, add `("recordValidationSchema", forms / "record-1.0/schema.validation.xsd")` to `files` and emit it without a digest (the digest line is only for files an XDC references): change the loop to

```python
for name, path in files:
    out.append(f'    static let {name} = Data(base64Encoded: "{base64.b64encode(path.read_bytes()).decode()}")!')
    if name != "recordValidationSchema":
        out.append(f'    static let {name}Digest = "{digest(path)}"')
```

Run: `scripts/embed-official-forms.sh`

- [ ] **Step 4: Write the failing tests**

In `OfficialFormTests` add:

```swift
    func testRecordValidationSchemaDiffersOnlyInTheIdentifierPattern() throws {
        let official = String(decoding: OfficialForm.record_1_0.schema, as: UTF8.self).components(separatedBy: "\n")
        let validation = String(decoding: OfficialForm.record_1_0.validationSchema, as: UTF8.self).components(separatedBy: "\n")
        XCTAssertEqual(official.count, validation.count)
        let changed = zip(official, validation).filter { $0 != $1 }
        XCTAssertEqual(changed.count, 1)
        XCTAssertTrue(changed.first?.1.contains("https://data\\.gov\\.sk/id/legal-subject/([0-9]{8}|[0-9]{12})") == true)
        XCTAssertEqual(OfficialForm.clause_1_3.validationSchema, OfficialForm.clause_1_3.schema)
    }
```

and extend `testEmbeddedFilesEqualTheReferenceCopiesAndProvenance` with the pair `("record-1.0/schema.validation.xsd", OfficialForm.record_1_0.validationSchema)`.

In `FormSchemaValidatorTests` add:

```swift
    func testRecordSchemaCompilesAndRejectsAWrongRoot() {
        let xml = Data("<Nothing xmlns=\"\(OfficialForm.record_1_0.namespace)\"/>".utf8)
        XCTAssertThrowsError(try validator.validate(xml, against: .record_1_0)) { error in
            guard case FormSchemaValidator.Failure.invalid(let details) = error else { return XCTFail("\(error)") }
            XCTAssertFalse(details.contains("failed to compile"), details)
            XCTAssertTrue(details.contains("Nothing"), details)
        }
    }
```

- [ ] **Step 5: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'OfficialFormTests|FormSchemaValidatorTests'`
Expected: compile error for `validationSchema`.

- [ ] **Step 6: Implement**

In `OfficialForm` add `public let validationSchema: Data` (after `schema`), pass `validationSchema: OfficialFormFiles.recordValidationSchema` for `record_1_0` and `validationSchema: OfficialFormFiles.clauseSchema` for `clause_1_3`. In `FormSchemaValidator.validate`, write `form.validationSchema` instead of `form.schema`.

- [ ] **Step 7: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter 'OfficialFormTests|FormSchemaValidatorTests'`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add docs/reference/forms scripts/embed-official-forms.sh Sources/Chevron7Kit/Attestation/Forms Tests/Chevron7KitTests
git commit -m "feat(zako): validate records against a libxml2-compatible copy of the record schema

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Record renderer

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ConversionRecordRenderer.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/ConversionRecordRendererTests.swift`

**Interfaces:**
- Consumes: `ConversionFormModel` (B1), `OfficialForm.record_1_0`, `FormSchemaValidator`, `ConversionFormModelTests.attestation()` / `.scanElement(_:)`.
- Produces: `public struct ConversionRecordRenderer: Sendable { public init(); public func render(_ model: ConversionFormModel) -> String }` returning the `ConversionRecord` element without an XML declaration.

The element order and the plain-string values follow the accepted record (spec "Reference: a record EZZK accepted" and its per-field table): Name, Order, Type, sheets, non-empty pages, paper sizes, security elements inside `OriginalDocumentInfo`; `NewDocumentInfo`; `ConversionRecordEvidenceNumber` (plain number); `UsedDevice`; `ConversionExecutionDateTime`; `PersonPerformingConversion` last. Values: `PaperSize` = item code (`Iny` rows carry the `other` text instead, because the record has no `PaperSizeOther`); description = item code, or the `descriptionOther` text for "other" kinds; location = item code; `NewDocumentFormat` = item name (`PDF/A-2`); method = item code (`SHA-256`).

- [ ] **Step 1: Write the failing tests**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ConversionRecordRendererTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    private func model(_ attestation: AttestationData = ConversionFormModelTests.attestation(),
                       elements: [SecurityElement] = [ConversionFormModelTests.scanElement()]) throws -> ConversionFormModel {
        try ConversionFormModel.make(attestation: attestation, securityElements: elements,
                                     newDocumentSHA256Hex: ConversionFormModelTests.fingerprintHex,
                                     originalNonEmptyPageIndices: [0], usedDevice: "Chevron7 v0.7.0")
    }

    private func elementOrder(_ xml: String) throws -> [String] {
        let document = try XMLDocument(xmlString: xml)
        return (document.rootElement()?.children ?? []).compactMap { $0.localName }
    }

    func testRecordValidatesAndFollowsTheAcceptedRecordShape() throws {
        let xml = ConversionRecordRenderer().render(try model())
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .record_1_0))
        XCTAssertEqual(try elementOrder(xml), ["OriginalDocumentInfo", "NewDocumentInfo", "ConversionRecordEvidenceNumber",
                                               "UsedDevice", "ConversionExecutionDateTime", "PersonPerformingConversion"])
        XCTAssertTrue(xml.contains("<ConversionRecordEvidenceNumber>1563-260824-1</ConversionRecordEvidenceNumber>"))
        XCTAssertTrue(xml.contains("<OriginalDocumentName>Brezinová_diplom</OriginalDocumentName><OriginalDocumentOrder>1</OriginalDocumentOrder><OriginalDocumentType>Brezinová_diplom</OriginalDocumentType>"))
        XCTAssertTrue(xml.contains("<PaperSize>A4</PaperSize>"))
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsDescription>vlastnoručný podpis</OriginalDocumentSecurityElementsDescription>"))
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsLocation>Left down</OriginalDocumentSecurityElementsLocation>"))
        XCTAssertTrue(xml.contains("<NewDocumentFormat>PDF/A-2</NewDocumentFormat>"))
        XCTAssertTrue(xml.contains("<ElectronicFingerprintCalculationMethod>SHA-256</ElectronicFingerprintCalculationMethod>"))
        XCTAssertTrue(xml.contains("<UsedDevice>Chevron7 v0.7.0</UsedDevice>"))
        XCTAssertTrue(xml.contains("<ConversionExecutionDateTime>2026-08-24T18:35:44+02:00</ConversionExecutionDateTime>"))
        XCTAssertTrue(xml.contains("<IdentifierValue>https://data.gov.sk/id/legal-subject/42249180</IdentifierValue>"))
        XCTAssertFalse(xml.contains("<Codelist><CodelistCode>12"), "record uses plain strings, not codelists")
    }

    func testOtherKindsLetterPaperAndPhysicalElementsValidate() throws {
        var data = ConversionFormModelTests.attestation()
        data.paperSizeBreakdown = [.init(sizeClass: .letterPortrait, sheets: 1)]
        var other = ConversionFormModelTests.scanElement(.bindingCord)
        other.verbalDescription = "trikolóra"
        var physical = ConversionFormModelTests.scanElement(.embossedSeal)
        physical.observation = .physicalOriginal
        physical.originalLocation = "Down edge"
        physical.newDocumentPageIndex = 0
        let xml = ConversionRecordRenderer().render(try model(data, elements: [other, physical]))
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .record_1_0))
        XCTAssertTrue(xml.contains("<PaperSize>Letter</PaperSize>"))
        XCTAssertTrue(xml.contains("trikolóra"))
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsLocation>Down edge</OriginalDocumentSecurityElementsLocation>"))
    }

    func testIcoWithElevenDigitsIsOmittedBecauseTheRecordAllowsOnlyEightOrTwelve() throws {
        var data = ConversionFormModelTests.attestation()
        data.performingPerson.ico = "12345678901"
        let xml = ConversionRecordRenderer().render(try model(data))
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .record_1_0))
        XCTAssertFalse(xml.contains("<ID>"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionRecordRendererTests`
Expected: compile error, `cannot find 'ConversionRecordRenderer' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Renders the conversion record 1.0 exactly in the shape of the record EZZK accepted on
/// 2026-08-24: plain strings where the record schema has `MandatoryStringType`, the plain
/// evidence number, and person data last.
public struct ConversionRecordRenderer: Sendable {
    public init() {}

    public func render(_ m: ConversionFormModel) -> String {
        var x = "<ConversionRecord xmlns=\"\(OfficialForm.record_1_0.namespace)\"><OriginalDocumentInfo>"
        x += element("OriginalDocumentName", m.originalDocumentName)
        x += element("OriginalDocumentOrder", String(m.originalDocumentOrder))
        x += element("OriginalDocumentType", m.originalDocumentType)
        x += element("OriginalDocumentNumberOfSheets", String(m.numberOfSheets))
        x += element("OriginalDocumentNonEmptyPageCount", String(m.nonEmptyPageCount))
        for size in m.paperSizes {
            x += "<OriginalDocumentPaperSize>"
            x += element("PaperSize", size.other ?? size.item.code)
            x += element("PaperSizeNumberOfSheets", String(size.sheets))
            x += "</OriginalDocumentPaperSize>"
        }
        for entry in m.securityElements {
            x += "<DocumentSecurityElementsDetails>"
            x += element("OriginalDocumentSecurityElementsDescription", entry.descriptionOther ?? entry.description.code)
            x += element("OriginalDocumentSecurityElementsPage", String(entry.originalPage))
            x += element("OriginalDocumentSecurityElementsSheet", String(entry.originalSheet))
            x += element("OriginalDocumentSecurityElementsLocation", entry.location.code)
            x += element("NewDocumentSecurityElementsPage", String(entry.newPage))
            x += "</DocumentSecurityElementsDetails>"
        }
        x += "</OriginalDocumentInfo><NewDocumentInfo>"
        x += element("NewDocumentName", m.newDocumentName)
        x += element("NewDocumentFormat", m.newDocumentFormat.skName)
        x += element("ElectronicFingerprintValue", m.fingerprintBase64)
        x += element("ElectronicFingerprintCalculationMethod", m.fingerprintMethod.code)
        x += "</NewDocumentInfo>"
        x += element("ConversionRecordEvidenceNumber", m.evidenceNumber)
        x += element("UsedDevice", m.usedDevice)
        x += element("ConversionExecutionDateTime", m.conversionTimeText)
        x += "<PersonPerformingConversion><PersonData><PhysicalPerson><PersonName>"
        x += element("GivenName", m.person.givenName)
        x += element("FamilyName", m.person.familyName)
        x += "</PersonName>"
        x += element("Position", m.person.position.isEmpty ? "advokát" : m.person.position)
        x += "</PhysicalPerson>"
        x += "<LegalSubject>\(element("Name", m.person.legalSubjectName))</LegalSubject>"
        if let uri = m.person.legalSubjectURI, Self.recordAcceptsIdentifier(uri) {
            x += "<ID><IdentifierType><Codelist><CodelistCode>\(ZakoCodelists.identifierType)</CodelistCode><CodelistItem>"
            x += "<ItemCode>\(ZakoCodelists.icoIdentifierItem.code)</ItemCode>"
            x += "<ItemName Language=\"sk\">\(AttestationClauseGenerator.escape(ZakoCodelists.icoIdentifierItem.skName))</ItemName>"
            x += "</CodelistItem></Codelist></IdentifierType>"
            x += element("IdentifierValue", uri) + "</ID>"
        }
        x += "</PersonData></PersonPerformingConversion></ConversionRecord>"
        return x
    }

    /// Record 1.0 accepts 8 or 12 digits, the clause 8 to 12.
    static func recordAcceptsIdentifier(_ uri: String) -> Bool {
        let digits = uri.split(separator: "/").last.map(String.init) ?? ""
        return digits.count == 8 || digits.count == 12
    }

    private func element(_ name: String, _ value: String) -> String {
        "<\(name)>\(AttestationClauseGenerator.escape(value))</\(name)>"
    }
}
```

Before running, open `docs/reference/forms/record-1.0/schema.validation.xsd` and confirm `GivenName`, `FamilyName` and `Position` are required (`minOccurs="1"`); if the model can give an empty given name (a one-word name), and the schema requires one, the test in Step 1 with "Mgr. Marián Čuprík" still passes, but add a model-level guard only if a test proves a failure.

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionRecordRendererTests`
Expected: 3 tests PASS. Schema failures are fixed in the renderer, never in the expectations of Step 1, which mirror the accepted record.

- [ ] **Step 5: Commit**

```bash
git add Sources/Chevron7Kit/Attestation/Forms/ConversionRecordRenderer.swift Tests/Chevron7KitTests/ConversionRecordRendererTests.swift
git commit -m "feat(zako): render the conversion record 1.0 as EZZK accepts it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Record delivery builder

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ZakoRecordDeliveryBuilder.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/ZakoRecordDeliveryBuilderTests.swift`

**Interfaces:**
- Consumes: Task 2, `XMLDataContainerBuilder`, `FormSchemaValidator`.
- Produces:

```swift
public struct ZakoRecordDelivery: Sendable {
    public let recordXML: String
    public let recordXDCF: Data
    public let entryName: String      // "<number>.record.xml.xdcf"
    public let containerName: String  // "<number>.record.asice"
}
public struct ZakoRecordDeliveryBuilder: Sendable {
    public init(validator: FormSchemaValidator = FormSchemaValidator())
    public func build(model: ConversionFormModel) throws -> ZakoRecordDelivery
}
```

- [ ] **Step 1: Failing test**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ZakoRecordDeliveryBuilderTests: XCTestCase {
    func testBuildsTheValidatedRecordXDCAndItsNames() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else { throw XCTSkip("xmllint") }
        let model = try ConversionFormModel.make(attestation: ConversionFormModelTests.attestation(),
                                                 securityElements: [ConversionFormModelTests.scanElement()],
                                                 newDocumentSHA256Hex: ConversionFormModelTests.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")
        let delivery = try ZakoRecordDeliveryBuilder().build(model: model)
        XCTAssertEqual(delivery.entryName, "1563-260824-1.record.xml.xdcf")
        XCTAssertEqual(delivery.containerName, "1563-260824-1.record.asice")
        let text = String(decoding: delivery.recordXDCF, as: UTF8.self)
        XCTAssertTrue(text.contains("Identifier=\"\(OfficialForm.record_1_0.identifier)\""))
        XCTAssertTrue(text.contains("DigestValue=\"V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=\""))
        XCTAssertTrue(text.contains(delivery.recordXML))
    }

    func testEvidenceNumberWithPathCharactersIsRefused() throws {
        var data = ConversionFormModelTests.attestation()
        data.evidenceNumber = "../1563"
        let model = try ConversionFormModel.make(attestation: data, securityElements: [],
                                                 newDocumentSHA256Hex: ConversionFormModelTests.fingerprintHex,
                                                 originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")
        XCTAssertThrowsError(try ZakoRecordDeliveryBuilder().build(model: model))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoRecordDeliveryBuilderTests`
Expected: compile error.

- [ ] **Step 3: Implement**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public struct ZakoRecordDelivery: Sendable {
    public let recordXML: String
    public let recordXDCF: Data
    public let entryName: String
    public let containerName: String
}

/// Builds the record XDC EZZK receives, validated against the record schema before anything
/// is signed. File names follow the accepted record (`<number>.record.xml.xdcf`).
public struct ZakoRecordDeliveryBuilder: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case unusableEvidenceNumber
        public var errorDescription: String? {
            "Evidenčné číslo obsahuje znaky, ktoré sa nedajú použiť v názve súboru záznamu."
        }
    }

    private let validator: FormSchemaValidator

    public init(validator: FormSchemaValidator = FormSchemaValidator()) {
        self.validator = validator
    }

    public func build(model: ConversionFormModel) throws -> ZakoRecordDelivery {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard !model.evidenceNumber.isEmpty,
              model.evidenceNumber.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else {
            throw Failure.unusableEvidenceNumber
        }
        let xml = ConversionRecordRenderer().render(model)
        try validator.validate(Data(xml.utf8), against: .record_1_0)
        return ZakoRecordDelivery(recordXML: xml,
                                  recordXDCF: XMLDataContainerBuilder.build(formXML: xml, form: .record_1_0),
                                  entryName: "\(model.evidenceNumber).record.xml.xdcf",
                                  containerName: "\(model.evidenceNumber).record.asice")
    }
}
```

- [ ] **Step 4: Run the tests** (expected PASS) and **Step 5: Commit** `feat(zako): build the validated record XDC`.

---

### Task 4: Engine signs a record XDC locally

**Files (under `engine/src/main/java/digital/slovensko/autogram/`):**
- Modify: `ui/machine/MachineSigningService.java` (`isSupportedSource`, `PreparedFile.prepare`, `signingParameters`), `core/SigningJob.java` (`build`)
- Test: `engine/src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java`

**Interfaces:**
- Produces: a v1 SIGN file whose source ends in `.xdcf`, whose content's root element is `XMLDataContainer` in namespace `http://data.gov.sk/def/container/xmldatacontainer+xml/1.1`, with no attachments, no eForm and an `XAdES_*` level, is signed into a new one-file ASiC-E without network access; the data object keeps the source file name and MIME `application/vnd.gov.sk.xmldatacontainer+xml`. Other non-PDF, non-ASiC sources stay refused.

- [ ] **Step 1: Failing tests** in `MachineSigningServiceTest` (copy the keystore pattern of `attachmentsAreSignedAsDataObjectsOfOneContainer`):

```java
    /// The EZZK record is an XMLDataContainer signed alone, as in the record EZZK accepted.
    @Test
    void recordXdcIsSignedAloneWithTheBareXdcMimeAndNoNetwork() throws Exception {
        var xdcf = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><XMLDataContainer xmlns=\"http://data.gov.sk/def/container/xmldatacontainer+xml/1.1\">"
                + "<XMLData ContentType=\"application/xml; charset=UTF-8\" Identifier=\"http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0\" Version=\"1.0\"><ConversionRecord xmlns=\"https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0\"/></XMLData>"
                + "</XMLDataContainer>").getBytes(java.nio.charset.StandardCharsets.UTF_8);
        var retained = new MemoryRetainedFile();
        var settings = new MachineSettings(true);
        settings.setSignatureLevel(SignatureLevel.XAdES_BASELINE_B);
        var job = MachineSigningService.DefaultSigningSession.signingJob(xdcf, "/tmp/260923-TEST.record.xml.xdcf",
                new MachineFileResponder(retained, () -> { }), settings, null, List.of());
        var token = new Pkcs12SignatureToken(Objects.requireNonNull(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/test.keystore")).getFile(), new KeyStore.PasswordProtection("".toCharArray()));
        job.signWithKeyAndRespond(new SigningKey(token, token.getKeys().get(0)));

        var names = new ArrayList<String>();
        String manifest = null;
        String signature = null;
        byte[] data = null;
        try (var zip = new ZipInputStream(new ByteArrayInputStream(retained.readAll()))) {
            for (var entry = zip.getNextEntry(); entry != null; entry = zip.getNextEntry()) {
                names.add(entry.getName());
                var content = zip.readAllBytes();
                if (entry.getName().equals("META-INF/manifest.xml")) manifest = new String(content, java.nio.charset.StandardCharsets.UTF_8);
                if (entry.getName().startsWith("META-INF/signatures")) signature = new String(content, java.nio.charset.StandardCharsets.UTF_8);
                if (entry.getName().equals("260923-TEST.record.xml.xdcf")) data = content;
            }
        }
        assertEquals(List.of("260923-TEST.record.xml.xdcf"), names.stream()
                .filter(name -> !name.equals("mimetype") && !name.startsWith("META-INF/")).toList());
        assertArrayEquals(xdcf, data, "the record XDC must be signed byte for byte");
        assertTrue(manifest.contains("manifest:media-type=\"application/vnd.gov.sk.xmldatacontainer+xml\""), manifest);
        assertTrue(signature.contains("<xades:MimeType>application/vnd.gov.sk.xmldatacontainer+xml</xades:MimeType>"), signature);
    }

    @Test
    void anXdcfThatIsNotAnXmlDataContainerIsRefused() {
        var settings = new MachineSettings(true);
        settings.setSignatureLevel(SignatureLevel.XAdES_BASELINE_B);
        assertThrows(java.io.IOException.class, () -> MachineSigningService.DefaultSigningSession.signingJob(
                "<Other/>".getBytes(java.nio.charset.StandardCharsets.UTF_8), "/tmp/x.record.xml.xdcf",
                new MachineFileResponder(new MemoryRetainedFile(), () -> { }), settings, null, List.of()));
    }
```

Also add a service-level test modelled on `rejectsNonPdfSourceDuringSingleOpenPreparationBeforeTokenWork` that a `.xdcf` source with an `XMLDataContainer` root passes `prepare` (reaches the session factory), while a `.xml` source is still refused with `SIGNING_UNAVAILABLE`. If the DSS `xades:MimeType` prefix differs, assert on the element text regardless of prefix.

- [ ] **Step 2: Run to verify failure**

Run: `cd engine && JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q -Dtest=MachineSigningServiceTest test`
Expected: the new tests fail (refused source or network/eForm exception or wrong MIME).

- [ ] **Step 3: Implement**

In `MachineSigningService`:

```java
    private static final String XDC_NAMESPACE = "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1";

    static boolean isRecordXdc(String source, byte[] content) {
        if (!source.toLowerCase(java.util.Locale.ROOT).endsWith(".xdcf")) {
            return false;
        }
        try {
            var factory = javax.xml.parsers.DocumentBuilderFactory.newInstance();
            factory.setNamespaceAware(true);
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setXIncludeAware(false);
            factory.setExpandEntityReferences(false);
            var root = factory.newDocumentBuilder().parse(new java.io.ByteArrayInputStream(content)).getDocumentElement();
            return "XMLDataContainer".equals(root.getLocalName()) && XDC_NAMESPACE.equals(root.getNamespaceURI());
        } catch (Exception exception) {
            return false;
        }
    }

    private static boolean isSupportedSource(String source, byte[] content) {
        return hasPdfHeader(content) || isAsic(source, content) || isRecordXdc(source, content);
    }
```

In `signingParameters`, before the `level == XAdES_BASELINE_T` branch:

```java
            if (AutogramMimeType.isXDC(document.getMimeType())) {
                if (!isRecordXdc(document.getName(), DSSUtils.toByteArray(document))) {
                    throw new IOException("Only an XMLDataContainer is signed as a record");
                }
                var level = settings.getSignatureLevel();
                if (level != SignatureLevel.XAdES_BASELINE_T && level != SignatureLevel.XAdES_BASELINE_B) {
                    throw new IOException("A record is signed as XAdES in an ASiC-E");
                }
                // Local route: the XDC already references its form; nothing is fetched or re-wrapped.
                return SigningParameters.buildParameters(level, DigestAlgorithm.SHA256, ASiCContainerType.ASiC_E,
                        SignaturePackaging.ENVELOPING, false, null, null, null, null, false, null, false, 640,
                        document, level == SignatureLevel.XAdES_BASELINE_T ? settings.getTspSource() : null, true);
            }
```

(use the DSS `DSSUtils.toByteArray` the file already imports or the `eu.europa.esig.dss.spi.DSSUtils` equivalent; check the exact class name in the imports).

In `signingJob`, when `attachments` is not empty, keep refusing an XDC source (the existing ZIP/PDF-header guards already do). In `SigningJob.build`, keep the bare MIME for a record: replace

```java
        if (isXDC(document.getMimeType())) {
            document.setMimeType(AutogramMimeType.XML_DATACONTAINER_WITH_CHARSET);
```

with

```java
        if (isXDC(document.getMimeType())) {
            // A record signed alone keeps the bare MIME EZZK accepted; eForm XDCs keep the charset form.
            document.setMimeType(params.shouldCreateXdc() || params.getContainer() == null
                    ? AutogramMimeType.XML_DATACONTAINER_WITH_CHARSET
                    : AutogramMimeType.XML_DATACONTAINER);
```

then run the whole engine suite: if any existing eForm test expects the charset MIME, narrow the condition so only the record route (identified by `autoLoadEform == false` and no eForm attributes, exposed as a `SigningParameters.isPlainRecordXdc()` accessor you add) gets the bare MIME. The engine suite must stay green.

- [ ] **Step 4: Run the engine tests**

Run: `cd engine && JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q test`
Expected: PASS (all tests).

- [ ] **Step 5: Rebuild the engine and commit**

Run: `cd Chevron7 && AUTOGRAM_JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca scripts/build-engine.sh` (ends with `✔ Engine:`).

```bash
git add engine
git commit -m "feat(engine): sign an EZZK record XDC alone, locally and with its bare MIME

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Swift bridge for the record and explicit timestamp endpoints

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/Signing/SigningProvider.swift` (`SigningRequest`), `.../Signing/JavaEngine/EngineBridgeSigningProvider.swift` (source branches, engine request), `.../EngineBridge/Models/SigningModels.swift` (`EngineSigningRequest`), `.../EngineBridge/CLI/AutogramCLIEngine.swift` (`sign`, timestamp endpoints)
- Test: the test file that holds `EngineBridgeSignsExtraFilesAsDataObjectsTests` (Task 8 of B1) and `MachineRequestEncodingTests`

**Interfaces:**
- Produces: `SigningRequest.timestampServers: [String]?` (default `nil`: engine preferences as today) and `SigningRequest.signsAsRecordContainer: Bool` (default `false`). With `signsAsRecordContainer`, the provider writes `pdfData` (the record XDC bytes) under `filename` (must end in `.xdcf`, else `SigningError.signingFailed("Záznam musí mať príponu .xdcf.")`) and signs it as `.asiceXAdES`. `EngineSigningRequest.timestampServersOverride: [String]?`; when set and non-empty, `AutogramCLIEngine.sign` uses exactly these endpoints for Baseline T instead of `timestampSourceProvider.load()`.

- [ ] **Step 1: Failing tests**, using the `RecordingSigningEngine` double added in B1 Task 8:
  - `testRecordContainerIsSentUnderItsXdcfName`: request with `pdfData: Data("<XMLDataContainer/>".utf8)`, `filename: "260923-X.record.xml.xdcf"`, `signsAsRecordContainer: true` → captured `files.first?.sourceURL.lastPathComponent == "260923-X.record.xml.xdcf"`, no attachments, `outputFormat == .asiceXAdES`.
  - `testRecordNeedsAnXdcfName`: same with `filename: "x.pdf"` → throws.
  - `testExplicitTimestampServersReachTheEngineRequest`: `timestampServers: ["https://tsa.belgium.be/connect"]` → captured `timestampServersOverride == ["https://tsa.belgium.be/connect"]`.
  - In the AutogramCLIEngine encoding tests: with `timestampServersOverride` set, the v1 SIGN payload's `timestamp.servers` equals the override; without it, it equals the provider's endpoints (existing behaviour).

- [ ] **Step 2: Run to verify failure** (compile errors), **Step 3: Implement** the properties, the provider branch (placed before the `signsExtraFilesAsDataObjects` branch), and in `AutogramCLIEngine.sign`:

```swift
let timestamp: (endpoints: [String], authentication: TimestampAuthenticationSecret?) =
    !wantsTimestamp ? (endpoints: [], authentication: nil)
    : (request.timestampServersOverride.flatMap { $0.isEmpty ? nil : $0 }).map { (endpoints: $0, authentication: nil) }
        ?? (try qualifiedTimestampRequest())
```

- [ ] **Step 4: Run** `swift test --filter 'EngineBridge|MachineRequestEncoding'` (PASS) and **Step 5: Commit** `feat(signing): sign an EZZK record container and pass explicit timestamp servers`.

---

### Task 6: Register states, fields and record storage

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/Evidence/LocalEvidenceStore.swift`, `Chevron7/Sources/Chevron7Kit/Models/UXLabels.swift`, the two `statusTint` switches in `Chevron7/Sources/Chevron7App/Views/EvidenceDashboardView.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/EvidenceRegisterB2Tests.swift`

**Interfaces:**
- Produces, on `EvidenceRecord.Status` (new raw strings, old ones untouched):

```swift
case acceptedForProcessing = "Prijatý na spracovanie v EZZK"
case processed = "Spracovaný v EZZK"
case outcomeUnknown = "Výsledok odoslania neznámy"
case rejected = "Odmietnutý v EZZK"
case recordUnsigned = "Záznam nepodpísaný"
case late = "Oneskorený"
```

- New optional `EvidenceRecord` fields: `ezzkMode: AppSettings.EZZKMode?`, `evidenceNumberAllocatedAt: Date?`, `recordContainerPath: String?` (relative to the register folder), `submittedAt: Date?`, `submissionMessageID: String?`, `ezzkResultCode: Int?`, `ezzkResultDescription: String?`, `lastLookupAt: Date?`.
- `LocalEvidenceStore.storeRecordContainer(_ data: Data, for id: UUID) throws -> String` (writes `records/<id>.asice` under the register folder atomically, returns the relative path) and `recordContainerData(for record: EvidenceRecord) -> Data?`.
- `isSubmissionPending` is true for `.signed`, `.queuedForSubmission`, `.submissionFailed`, `.outcomeUnknown`, `.late`; `progressIndex`: `.acceptedForProcessing` 5, `.processed` 6, `.outcomeUnknown`, `.rejected`, `.late` 4, `.recordUnsigned` 3. Labels in `UXLabels.evidenceStatusLabel`: `.signed` "Podpísaný, čaká na odoslanie", `.queuedForSubmission` "Čaká na odoslanie", `.acceptedForProcessing` "Prijatý na spracovanie", `.processed` "Spracovaný v EZZK", `.outcomeUnknown` "Výsledok neznámy, najprv overte v EZZK", `.rejected` "Odmietnutý v EZZK", `.recordUnsigned` "Záznam nepodpísaný", `.late` "Oneskorený".

- [ ] **Step 1: Failing tests**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class EvidenceRegisterB2Tests: XCTestCase {
    func testDecodesARegisterWrittenBeforeB2() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let evidence = directory.appendingPathComponent("Evidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":"2026-09-20T10:00:00Z","updatedAt":"2026-09-20T10:00:00Z",
          "status":"Vo fronte odoslania","direction":"paperToElectronic","originalName":"a","newDocumentName":"a.pdf",
          "evidenceNumber":"1563-260920-1","fingerprintSHA256Hex":"ab","attestationXML":"<x/>","conversionTime":"2026-09-20T10:00:00Z",
          "performingPersonName":"M","securityElementCount":1,"totalPages":1,"totalSheets":1}]
        """
        try Data(legacy.utf8).write(to: evidence.appendingPathComponent("register.json"))
        let store = LocalEvidenceStore(directory: directory)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.status, .queuedForSubmission)
        XCTAssertNil(store.records.first?.submittedAt)
    }

    func testNewStatesRoundTripAndKeepTheirRawStrings() throws {
        XCTAssertEqual(EvidenceRecord.Status.queuedForSubmission.rawValue, "Vo fronte odoslania")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalEvidenceStore(directory: directory)
        var record = EvidenceRecord(status: .signed, direction: .paperToElectronic, originalName: "a", newDocumentName: "a.pdf",
                                    evidenceNumber: "1563-260923-1", fingerprintSHA256Hex: "ab", attestationXML: "<x/>",
                                    conversionTime: Date(), performingPersonName: "M", securityElementCount: 0,
                                    totalPages: 1, totalSheets: 1)
        record.status = .outcomeUnknown
        record.ezzkMode = .test
        record.submissionMessageID = "m-1"
        record.recordContainerPath = try store.storeRecordContainer(Data("zip".utf8), for: record.id)
        store.upsert(record)
        let reopened = LocalEvidenceStore(directory: directory)
        let loaded = try XCTUnwrap(reopened.record(id: record.id))
        XCTAssertEqual(loaded.status, .outcomeUnknown)
        XCTAssertEqual(loaded.ezzkMode, .test)
        XCTAssertEqual(reopened.recordContainerData(for: loaded), Data("zip".utf8))
        XCTAssertEqual(loaded.recordContainerPath, "records/\(record.id.uuidString).asice")
    }

    func testPendingStatesAndLabels() {
        XCTAssertTrue(EvidenceRecord.Status.outcomeUnknown.isSubmissionPendingState)
        XCTAssertFalse(EvidenceRecord.Status.recordUnsigned.isSubmissionPendingState)
        XCTAssertEqual(UXLabels.evidenceStatusLabel(for: .outcomeUnknown, isOverdue: false), "Výsledok neznámy, najprv overte v EZZK")
    }
}
```

Adapt the `EvidenceRecord.init` call to its exact labels; add `Status.isSubmissionPendingState` and make `isSubmissionPending` use it. Check that `AppSettings.EZZKMode` is `Codable` (it is persisted in settings); if it is not reachable from `LocalEvidenceStore.swift`, it is in the same module (`Chevron7Kit/Support/AppSettings.swift`).

- [ ] **Step 2: Run to verify failure**, **Step 3: Implement** (new cases in every exhaustive switch: `sfSymbol`, `progressIndex`, `UXLabels.evidenceStatusLabel`, both `statusTint`; the store's folder is the existing `Evidence` directory; `storeRecordContainer` creates `records/` and writes atomically), **Step 4: Run** `swift test --filter 'EvidenceRegisterB2Tests|EvidenceAndPackagingTests'` (PASS) and the App build, **Step 5: Commit** `feat(register): EZZK submission states, fields and record container storage`.

---

### Task 7: EZZK client: receipt, one login at a time, connection loss

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/SOAP/EZZKSOAPClient.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/EZZKSOAPClientTests.swift` (reuse `SOAPScriptedTransport`, `EZZKSOAPFixtures`, `makeClient`)

**Interfaces:**
- Produces: `public struct EZZKSubmissionReceipt: Equatable, Sendable { public var messageID: String; public var submittedAt: Date }`; `public func receive(records:person:) async throws -> EZZKSubmissionReceipt` (the `MessageId` sent in the body, lowercased UUID, and `now()` at send time).
- Behaviour:
  1. Concurrent authenticated calls share one in-flight login (an actor-held `Task<String, Error>?`).
  2. After `credentialsRejected` or `accountLocked`, the client remembers the rejected credentials' fingerprint (SHA-256 of `login + "\u{0}" + password`) and throws the same error for every later authenticated call without contacting EZZK, until `credentialsProvider()` returns different credentials.
  3. For consequential requests (`numbers`, `consume`, `receive`) every transport error after the request was handed to the transport, including `notConnectedToInternet` and `networkConnectionLost`, becomes `EZZKError.outcomeUnknown`; only `cannotFindHost`, `dnsLookupFailed` and `cannotConnectToHost` stay `networkFailure` (nothing reached the server). Non-consequential calls keep today's mapping.

- [ ] **Step 1: Failing tests** (names are the contract):
  - `testReceiveReturnsTheMessageIDItSent`: script `loginSucceeded`, `result(code: 0, operation: "ReceiveConversionRecord")`; the receipt's `messageID` equals the `<w:MessageId>` in the captured request body.
  - `testConcurrentAuthenticatedCallsShareOneLogin`: two `async let` `evidenceNumbers` calls → `transport.operations.filter { $0 == "LogIn" }.count == 1`.
  - `testRejectedPasswordStopsFurtherLoginsUntilCredentialsChange`: provider returns fixed credentials; script `loginRejected(code: "CORE-003")`; first call throws `credentialsRejected`; second call throws the same with no new request (`transport.requests.count` unchanged); after switching the provider's password, the next call logs in again.
  - `testConnectionLostDuringReceiveIsOutcomeUnknown`: script `loginSucceeded`, then `.fail(URLError(.networkConnectionLost))` for receive → `outcomeUnknown`; same with `.notConnectedToInternet`; with `.cannotConnectToHost` → `networkFailure`.
  - Keep `testUnreachableHostIsAPlainNetworkFailure` and the production refusal tests green.

- [ ] **Step 2: Run to verify failure**, **Step 3: Implement**, **Step 4: Run** `swift test --filter 'EZZKSOAPClientTests|EZZKSOAPServiceAdapterTests|EZZKAccountControllerTests'` (PASS), **Step 5: Commit** `fix(ezzk): one login at a time, stop after a rejected password, treat a lost connection while sending as unknown`.

---

### Task 8: Submission carries the container and returns a receipt

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKService.swift` (`ConversionRecordEnvelope`, `EZZKSubmissionTransport`, `MockEZZKService`), `.../EZZK/SOAP/EZZKSOAPServiceAdapter.swift`, `Chevron7/Sources/Chevron7App/EZZK/EZZKSessionController.swift` (the two private conformers)
- Test: `Chevron7/Tests/Chevron7KitTests/EZZKSOAPServiceAdapterTests.swift`

**Interfaces:**
- Produces: `ConversionRecordEnvelope.signedRecordContainer: Data?` (not persisted: exclude it from `Codable` with explicit `CodingKeys` if the struct is persisted anywhere, else leave synthesized); `func submit(_ envelope: ConversionRecordEnvelope) async throws -> EZZKSubmissionReceipt`; the SOAP adapter sends `EZZKRecordAttachment(evidenceNumber:mimeType: "application/vnd.etsi.asic-e+zip", data:)` and throws `EZZKError.invalidRequest("chýba podpísaný záznam")` when the container is missing; `MockEZZKService.submit` returns a receipt with a random message ID; the legacy OAuth conformers keep throwing what they throw today.

- [ ] Steps: failing tests (`testSubmitSendsTheSignedContainerAsAsicAttachment` checks the body contains `<d:Mimetype>application/vnd.etsi.asic-e+zip</d:Mimetype>` and the base64 of the container; `testSubmitWithoutContainerIsARequestError`; replace `testSubmitIsUnavailableInPartA` by `testSubmitOnProductionIsStillRefusedWithoutAnyRequest`), run (fail), implement, run `swift test --filter 'EZZKSOAPServiceAdapterTests|EvidenceAndPackagingTests'` (PASS), commit `feat(ezzk): send the signed record container`.

---

### Task 9: Submission coordinator

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/EZZK/EZZKSubmissionCoordinator.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/EZZKSubmissionCoordinatorTests.swift`

**Interfaces:**
- Consumes: Tasks 6 to 8; `EZZKRecordLookup`; `EZZKError`.
- Produces:

```swift
public protocol EZZKRecordLookingUp: Sendable {
    func publicRecord(evidenceNumber: String) async throws -> EZZKRecordLookup
}
public struct EZZKSubmissionCoordinator: Sendable {
    public init(submitter: any EZZKSubmissionTransport, lookup: any EZZKRecordLookingUp,
                now: @escaping @Sendable () -> Date = { Date() })
    /// Sends a pending row and returns it in its new state. Never resends an unknown outcome.
    public func submit(_ record: EvidenceRecord, container: Data?) async -> EvidenceRecord
    /// Resolves `.outcomeUnknown` by lookup: found -> accepted/processed, 105 -> queued, error -> unchanged.
    public func resolveUnknown(_ record: EvidenceRecord) async -> EvidenceRecord
    /// For `.acceptedForProcessing`: lookup code 0 -> `.processed`; code 1 -> unchanged with `lastLookupAt`.
    public func refreshStatus(_ record: EvidenceRecord) async -> EvidenceRecord
    /// `.signed`/`.queuedForSubmission`/`.submissionFailed` rows whose allocation day (Bratislava) has passed become `.late`.
    public func markLateIfNeeded(_ record: EvidenceRecord) -> EvidenceRecord
    /// When the next status check is due: 5 minutes after `submittedAt`, then hourly after `lastLookupAt`.
    public func nextStatusCheck(for record: EvidenceRecord) -> Date?
}
```

Rules: `submit` only runs for `.signed`, `.queuedForSubmission`, `.submissionFailed`, `.late`; `.outcomeUnknown` is returned unchanged (resolve first); `.recordUnsigned` is returned unchanged. Result mapping: receipt → `.acceptedForProcessing` with `submittedAt`, `submissionMessageID`, `ezzkResultCode = 0`; `EZZKError.outcomeUnknown` → `.outcomeUnknown`; `EZZKError.serviceRejected(code, message)` → `.rejected` with code and description; `networkFailure`, `notConfigured`, `authenticationFailed`, `credentialsRejected`, `accountLocked`, `submissionUnavailable` → `.queuedForSubmission` (nothing was sent) with `ezzkResultDescription = error.localizedDescription`; a missing container → `.recordUnsigned`. `updatedAt` is set on every change.

- [ ] Steps: failing tests with a fake submitter and a fake lookup (names are the contract): `testAcceptedSubmissionStoresTheReceipt`, `testLostConnectionBecomesUnknownAndIsNotResent`, `testUnknownOutcomeIsResolvedByLookupBeforeAnyResend` (lookup found → `.acceptedForProcessing`; 105 → `.queuedForSubmission`), `testRejectedSubmissionKeepsCodeAndDescription`, `testRecordUnsignedRowIsNeverSubmitted`, `testProcessedAfterLookupCodeZero`, `testRowBecomesLateAfterBratislavaMidnightOfItsAllocationDay` (allocation 2026-09-23T21:30:00Z is 23:30 in Bratislava; at 22:10Z it is late, at 21:50Z it is not), `testNextStatusCheckIsFiveMinutesThenHourly`; run (fail); implement; run `swift test --filter EZZKSubmissionCoordinatorTests` (PASS); commit `feat(ezzk): one set of rules for record submission states`.

---

### Task 10: Evidence number pool

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/EZZK/EvidenceNumberPool.swift`
- Modify: `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift` (`fetchEvidenceNumber`, around lines 1017-1056), `Chevron7/Sources/Chevron7App/AppSettingsStore.swift` (owns one pool on the register folder)
- Test: `Chevron7/Tests/Chevron7KitTests/EvidenceNumberPoolTests.swift`, `Chevron7/Tests/Chevron7AppTests/ZakoEvidenceNumberTests.swift`

**Interfaces:**
- Produces:

```swift
public final class EvidenceNumberPool: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable { public var number: String; public var mode: AppSettings.EZZKMode; public var allocatedAt: Date }
    public init(directory: URL)                         // file: <directory>/Evidence/allocated-numbers.json
    public func add(_ entry: Entry)
    public func reusable(mode: AppSettings.EZZKMode, at now: Date, excluding used: Set<String>) -> Entry?  // same Bratislava day, not used by any register row
    public func remove(_ number: String)
    public func prune(before now: Date)                 // drops entries from earlier Bratislava days
}
public extension EZZKError { static let numberLimitMessage: String }
```

`numberLimitMessage` = "EZZK vám už pridelilo evidenčné číslo, na ktoré ešte neprišiel záznam. Dokončite rozpracovanú konverziu alebo počkajte do polnoci." `fetchEvidenceNumber` first asks the pool (Demo mode skips the pool); on reuse it sets `attestation.evidenceNumber`, `evidenceNumberAllocatedAt = entry.allocatedAt`, `evidenceNumberMode`; otherwise it allocates as today and adds the entry. `EZZKError.serviceRejected(code: 113, _)` shows `numberLimitMessage` in `evidenceNumberError`. A number is removed from the pool when its record is accepted (Task 11 calls `remove`).

- [ ] Steps: failing tests (`testReusesTodaysUnusedNumberBeforeAllocating` in the App target with a scripted transport whose script has no second allocation reply, asserting the second fetch returns the first number without a request; `testCode113ShowsTheLimitMessage`; Kit: `testEntriesFromAnEarlierBratislavaDayAreNotReused`, `testUsedNumbersAreNotReused`, `testPoolPersists`), run (fail), implement, run `swift test --filter 'EvidenceNumberPool|ZakoEvidenceNumberTests'` (PASS), commit `feat(ezzk): reuse evidence numbers already allocated today`.

---

### Task 11: ZaKo signs and sends the record

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift` (`authorizeAndSign` from the clause route to `step = .done`, `retryQueuedSubmission`, the QTS toggle visibility helper), `Chevron7/Sources/Chevron7App/Views/AuthorizeDoneViews.swift` (QTS toggle shown only in Demo)
- Test: `Chevron7/Tests/Chevron7AppTests/ZakoRecordRouteTests.swift`

**Interfaces:**
- Consumes: Tasks 3, 5, 6, 8, 9, 10; B1 `ZakoClauseDeliveryBuilder` result `clause.model`.
- Produces, after the client container is signed and verified:
  1. `let recordDelivery = try ZakoRecordDeliveryBuilder().build(model: clause.model)` (built before any signing so an invalid record stops the conversion before the client container is signed).
  2. Outside Demo: `timestampServers: TimestampAuthority.qualifiedURLs` on both `SigningRequest`s; if the list is empty, throw `SigningError.timestampFailed` before signing.
  3. Second signing request: `SigningRequest(pdfData: recordDelivery.recordXDCF, identityID: identityID, includeTimestamp: true, pin: signingPIN.isEmpty ? nil : signingPIN, filename: recordDelivery.entryName, timestampServers: qualified, signsAsRecordContainer: true)`. A failure here does not undo the client outputs: they are written, and the row is saved as `.recordUnsigned` with `ezzkResultDescription = error.localizedDescription`; `lastError` explains that the record must be signed again from the register.
  4. On success: store the container with `evidenceStore.storeRecordContainer(_:for:)`, write a copy to the output folder as `recordDelivery.containerName` (`ConversionOutputNaming.uniqueURL`), set `attestationXML = recordDelivery.recordXML`, `ezzkMode = attestation.evidenceNumberMode ?? settingsStore.ezzkAccountController.mode`, `evidenceNumberAllocatedAt = attestation.evidenceNumberAllocatedAt`.
  5. Submit through `EZZKSubmissionCoordinator.submit(_:container:)` (lookup = the account controller's `lookUp`), upsert its result, set `submissionStatus` to the new status, and on `.acceptedForProcessing` remove the number from the pool.
  6. `retryQueuedSubmission` uses the coordinator the same way (`resolveUnknown` first for `.outcomeUnknown`).
  7. The mobile route is unchanged (Demo only since B1).

- [ ] Steps: a source-contract regression test (`ZakoRecordRouteTests`) asserting `ZakoSessionStore.swift` contains `ZakoRecordDeliveryBuilder()`, `signsAsRecordContainer: true`, `timestampServers: `, `EZZKSubmissionCoordinator(` and `.recordUnsigned`, and no longer contains `clauseGenerator.generateXML`; plus a behavioural test of the Demo path if `ZakoSessionStore` can be driven in tests with the Demo signing provider (check `ConversionPipelineIntegrationTests` for how far the pipeline runs without a card; if it can, assert the register row ends `.acceptedForProcessing` with `ezzkMode == .demo` and a stored container). Run the full Swift suite; build the app with `./build_app.sh`; commit `feat(zako): sign and send the conversion record`.

---

### Task 12: Register and Done screen

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/Views/EvidenceDashboardView.swift` (`submitPending`, detail timeline, actions), `Chevron7/Sources/Chevron7App/Views/AuthorizeDoneViews.swift` (Done status block, lines ~401-440), `Chevron7/Sources/Chevron7App/AppSettingsStore.swift` or the app model (periodic status check)
- Test: `Chevron7/Tests/Chevron7AppTests/EvidenceSubmissionFlowTests.swift`

**Interfaces:**
- Produces:
  - `submitPending()` drives every pending row through the coordinator: `.outcomeUnknown` rows are resolved first; nothing maps an error to `.submissionFailed` any more (the part A bug).
  - Detail view: shows state, `submittedAt`, `submissionMessageID`, result code and description, `lastLookupAt`; actions "Odoslať" (pending states), "Overiť v EZZK" (`.outcomeUnknown`, `.acceptedForProcessing`), "Podpísať záznam znova" is out of scope (row stays `.recordUnsigned` with the explanation "Záznam podpíšte znova novou konverziou; opakovaný podpis z Registra príde neskôr.").
  - A `@MainActor final class EZZKStatusChecker` (App target) started by the app model: every 5 minutes it marks late rows, resolves unknown rows, and refreshes accepted rows whose `nextStatusCheck` is due. It stops when the app quits; it only runs outside Demo rows' mode mismatch (a row is checked against its own `ezzkMode`, and skipped when the controller is in another mode).
  - Done screen: reads `record.ezzkMode` (gap 6) and shows the coordinator state with the Slovak labels of Task 6; the "Znova odoslať do CEZZK" button becomes "Odoslať do EZZK" and is shown for pending states in Test (Production still refused).
  - Evidence rows of `.late` show the Revision 5 warning text.
- [ ] Steps: failing tests (`testSubmitPendingNeverMarksUnknownAsFailed`, `testStatusCheckerRefreshesDueAcceptedRows`, `testCheckerSkipsRowsOfAnotherMode`), run (fail), implement, run the full Swift suite, build the app, commit `feat(register): EZZK submission states, status checks and Done screen`.

---

### Task 13: Tests stop reading the real Keychain

**Files:**
- Modify: `Chevron7/Tests/Chevron7AppTests/ZakoEvidenceNumberTests.swift` (the three `makeSettingsStore()` calls at lines ~12, ~51, ~64) and every other App test that calls `makeSettingsStore()` without a controller and then switches the EZZK mode or depends on it (`ZakoMobileAvailabilityTests`, `ZakoCertificateResolutionTests`, `ZakoReviewNavigationTests`, `ZakoBankRecordingTests`, `AppStorageRootTests`, `RecentDocumentStoreTests`, `SigningBatchTests`, `SmartcardBadgeTests`)
- Modify: `Chevron7/Tests/Chevron7AppTests/TestSettingsStore.swift`

**Interfaces:**
- Produces: `makeSettingsStore()` builds its own `EZZKAccountController(mode: .demo, credentialStore: MemoryCredentialStore(), transportFactory: { _ in ScriptedTransport([]) })` when none is passed, so no test can reach the real Keychain or network; `MemoryCredentialStore` and `ScriptedTransport` move to `TestSettingsStore.swift` (or a shared test-support file) so every App test file can use them.
- [ ] Steps: add a test `testDefaultTestSettingsStoreNeverTouchesTheRealKeychain` that builds `makeSettingsStore()`, switches to `.test`, and asserts `storedLogin` is empty and the controller's credential store is a `MemoryCredentialStore`; run (fail: real store); implement; run the full Swift suite; commit `test: keep EZZK tests off the real Keychain`.

---

### Task 14: Documentation and live verification on test EZZK

**Files:**
- Modify: `CLAUDE.md` and `AGENTS.md` (identical), `Chevron7/docs/EZZK-INTEGRATION.md`, `Chevron7/docs/P2E-EZZK-FINDINGS.md` (section `## Part B2 (2026-09-23)`)

- [ ] **Step 1: Docs.** In the EZZK bullet of `CLAUDE.md`/`AGENTS.md`: record signed alone (`ZakoRecordDeliveryBuilder`, engine local XDC route), sent with `ReceiveConversionRecord` (consumes the number), states owned by `EZZKSubmissionCoordinator`, `EvidenceNumberPool`, `EZZKStatusChecker`, qualified TSA endpoints for ZaKo, production still refused until B3. In `P2E-EZZK-FINDINGS.md`: the live answers of Revision 5 and the late-record result (read it from the controller's note in the plan ledger; if still pending, write "pending").
- [ ] **Step 2: Full verification.** `swift test` (record every `Executed` line), engine `./mvnw -q test`, `./build_app.sh`.
- [ ] **Step 3: Live check with the owner (Test mode, SAK card).** One full ZaKo conversion of a synthetic document named "Zmluva o dielo č. 3". Then:

```bash
swift run ezzk-probe lookup <number> --env test
swift run ezzk-probe record <number> --env test --out /tmp/record.asice
unzip -l /tmp/record.asice
```
Expected: the register row is "Prijatý na spracovanie" (later "Spracovaný v EZZK"), the lookup finds the record, and the stored object is our `<number>.record.xml.xdcf` in a one-file ASiC-E with a Baseline T signature. Record the outcome in `P2E-EZZK-FINDINGS.md`.
- [ ] **Step 4: Commit** `docs(ezzk): describe the record submission of part B2`.
