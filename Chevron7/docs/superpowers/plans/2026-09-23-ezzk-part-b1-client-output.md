# EZZK Part B1: Correct Client Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The container a ZaKo conversion delivers to the client holds the official conversion clause 1.3 in an `XMLDataContainer` beside the PDF/A, both signed as two data objects of one ASiC-E, with a fingerprint that matches the delivered PDF.

**Architecture:** Chevron7Kit gains the official form files (embedded as base64), a `ConversionFormModel` built from `AttestationData`, a clause 1.3 renderer, an XDC 1.1 builder and a schema validator that runs `/usr/bin/xmllint`. The engine gains an optional `attachments` list on a machine protocol v1 sign file, signed with the main file as separate data objects of one new ASiC-E. `ZakoSessionStore.authorizeAndSign` stops embedding XML into the PDF/A, hashes the delivered bytes, and signs PDF plus clause through the new route. The record path (`AttestationClauseGenerator`, register, EZZK submission) is untouched until B2.

**Tech Stack:** Swift 6 / SwiftPM (macOS 27), XCTest, Java 25 engine with DSS (Maven wrapper), libxml2 `xmllint`.

**Spec:** `Chevron7/docs/superpowers/specs/2026-09-23-ezzk-part-b-design.md` (revision 4). Read it first, especially "Reference: a record EZZK accepted", "Facts about today's code" and "Official forms".

## Global Constraints

- Toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never a beta Xcode.
- Swift tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter <Name>` from `Chevron7/`.
- Engine tests on the Mac Studio: `JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q -Dtest=<Class> test` from `engine/` (elsewhere use the arm64 Zulu FX 25 under `~/Library/Java`).
- Tests never touch `~/Library/Application Support/Chevron7` or `~/Library/Caches/Chevron7` (`RealStorageGuard`); App tests use `makeSettingsStore()`.
- English for code, comments and docs; Slovak for user-facing strings. Never an em dash anywhere.
- Commit types on this branch: `feat`, `fix`, `test`, `docs`, `chore`. Nothing is pushed to `main` from this plan (every `feat`/`fix` on `main` publishes a release).
- Clause 1.3 identifiers, verbatim: namespace `http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3`, identifier `http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3`, version `1.3`, presentation `Content/form.2.html2.xslt` with `MediaDestinationTypeDescription="HTML"`.
- Record 1.0 identifiers, verbatim: namespace `https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`, identifier `http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0`, version `1.0`, presentation `Content/form103.sb.xslt`, `TXT`, digests `V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=` (schema) and `TYaNJLG/51TOIF8aFEcTQw72vudBAtYZUOkOfRG87as=` (presentation).
- XDC digest rule: SHA-256 over Canonical XML 1.0 without comments of the file, base64.
- The ZaKo conversion time is written with the Europe/Bratislava offset (`+01:00` CET, `+02:00` CEST), never the Mac's own time zone.

## Review Focus

1. A security element checked on the physical original with an old free-text location (for example "vpravo dole pri podpise"): authorization must stop with a clear Slovak message asking for a location from the list, never write free text into the clause. Test: Task 4, `testPhysicalElementWithFreeTextLocationIsRefused`.
2. An advocate whose IČO field holds spaces or a non-numeric value: the clause must omit `ID` rather than fail the schema. Test: Task 3, `testLegalSubjectURIRejectsNonDigits`, and Task 5, `testClauseWithoutValidICOValidates`.
3. A scan whose pages are US Letter or an unrecognised size: the clause must carry `Iny` with `PaperSizeOther`, and still validate. Test: Task 5, `testLetterAndUnknownPaperValidate`.
4. A document or person name containing `&`, `<` or quotes: the clause must stay well formed and schema valid. Test: Task 5, `testSpecialCharactersAreEscaped`.
5. A conversion at 23:30 UTC in winter or summer: the clause time must carry the Bratislava offset of that instant. Test: Task 4, `testConversionTimeUsesBratislavaOffset`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Chevron7/docs/reference/forms/` (new) | Verbatim copies of the four official files, `provenance.json`, `README.md` |
| `Chevron7/scripts/embed-official-forms.sh` (new) | Regenerates `OfficialFormFiles.swift` from `docs/reference/forms` |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift` (generated) | Base64 contents and digests of the four files |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialForm.swift` (new) | `OfficialForm` values `record_1_0` and `clause_1_3` |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/FormSchemaValidator.swift` (new) | Validates XML against an `OfficialForm` schema with `xmllint` |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ConversionFormModel.swift` (new) | Every value clause and record need, derived once from ZaKo state |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ConversionCertificateRenderer.swift` (new) | Clause 1.3 XML |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/XMLDataContainerBuilder.swift` (new) | XDC 1.1 envelope |
| `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ZakoClauseDeliveryBuilder.swift` (new) | Final PDF in, validated clause XDC out |
| `Chevron7/Sources/Chevron7Kit/Attestation/ZakoCodelists.swift` (modify) | Location list, `legalSubjectURI`, clause paper size |
| `Chevron7/Sources/Chevron7Kit/Models/DomainModels.swift` (modify) | Location codes `Mid`, official names |
| `Chevron7/Sources/Chevron7Kit/Attestation/AttestationClauseGenerator.swift` (modify) | Two new error cases; `securityElementPages` and `nameParts` made internal for reuse |
| `engine/.../ui/machine/MachineFile.java`, `MachineCliApp.java`, `MachineRequestValidator.java`, `MachineSigningService.java`, `engine/.../core/SigningJob.java` (modify) | Optional `attachments` signed into one ASiC-E |
| `Chevron7/Sources/Chevron7Kit/EngineBridge/Models/SigningModels.swift`, `.../EngineBridge/CLI/AutogramCLIEngine.swift`, `.../Signing/SigningProvider.swift`, `.../Signing/JavaEngine/EngineBridgeSigningProvider.swift` (modify) | Carry attachments to the engine |
| `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift` (modify) | New clause route, no embedding, fingerprint of delivered bytes, mobile Demo only |
| `Chevron7/Sources/Chevron7App/Views/PhysicalSecurityElementView.swift` (modify) | Location picker from codelist 11 |

---

### Task 1: Official form files

**Files:**
- Create: `Chevron7/docs/reference/forms/record-1.0/schema.xsd`, `Chevron7/docs/reference/forms/record-1.0/form103.sb.xslt`, `Chevron7/docs/reference/forms/clause-1.3/schema.xsd`, `Chevron7/docs/reference/forms/clause-1.3/form.2.html2.xslt`, `Chevron7/docs/reference/forms/provenance.json`, `Chevron7/docs/reference/forms/README.md`
- Create: `Chevron7/scripts/embed-official-forms.sh`
- Create (generated): `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift`
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/OfficialForm.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/OfficialFormTests.swift`

**Interfaces:**
- Produces: `public struct OfficialForm: Sendable, Equatable` with `identifier`, `namespace`, `version`, `schema: Data`, `presentation: Data`, `presentationMediaDestination: String`, `schemaDigestBase64`, `presentationDigestBase64`, computed `schemaURI` (`namespace + "/form.xsd"`) and `presentationURI` (`namespace + "/form.xslt"`); statics `OfficialForm.record_1_0`, `OfficialForm.clause_1_3`.

- [ ] **Step 1: Download and verify the official packages**

```bash
cd Chevron7
tmp=$(mktemp -d)
curl -sSfL -o "$tmp/record.zip" "https://www.slovensko.sk/static/eform/dataset/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0.zip"
curl -sSfL -o "$tmp/clause.zip" "https://www.slovensko.sk/static/eform/dataset/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3.zip"
shasum -a 256 "$tmp/record.zip" "$tmp/clause.zip"
```
Expected: `55fbf20ccb3d7d20c03bc0b2f1d42812144234bce9f9115b714f6fae4783e3dc` and `5bc8c120c1970c623ddaf6d7e289a192879664586cf7a445d0d6f2a5257eb6ab`. Stop if either differs.

- [ ] **Step 2: Copy the four files verbatim**

```bash
unzip -q "$tmp/record.zip" -d "$tmp/record" && unzip -q "$tmp/clause.zip" -d "$tmp/clause"
mkdir -p docs/reference/forms/record-1.0 docs/reference/forms/clause-1.3
cp "$tmp/record/schema.xsd" docs/reference/forms/record-1.0/schema.xsd
cp "$tmp/record/Content/form103.sb.xslt" docs/reference/forms/record-1.0/form103.sb.xslt
cp "$tmp/clause/schema.xsd" docs/reference/forms/clause-1.3/schema.xsd
cp "$tmp/clause/Content/form.2.html2.xslt" docs/reference/forms/clause-1.3/form.2.html2.xslt
shasum -a 256 docs/reference/forms/*/*
```
Expected: `record-1.0/schema.xsd` `7b00f00c0e910dccc61f447681ba5b3e6a719650c49f400ba2b7cc8ace582e0e` and `clause-1.3/schema.xsd` `5c4de06e0a115943cc3ef3a01cbd1388e495acfb2c66c7e7fe4c5769f383be8e`. Note the other two hashes for Step 3.

- [ ] **Step 3: Write `docs/reference/forms/provenance.json`**

Fill the two XSLT hashes from Step 2 output (the schema and zip hashes are given):

```json
{
  "retrieved_at": "2026-09-23",
  "digest_rule": "SHA-256 over Canonical XML 1.0 without comments, base64 (XMLDataContainer 1.1 UsedXSDReference / UsedPresentationSchemaReference)",
  "packages": {
    "record-1.0": {
      "url": "https://www.slovensko.sk/static/eform/dataset/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0.zip",
      "sha256": "55fbf20ccb3d7d20c03bc0b2f1d42812144234bce9f9115b714f6fae4783e3dc"
    },
    "clause-1.3": {
      "url": "https://www.slovensko.sk/static/eform/dataset/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3.zip",
      "sha256": "5bc8c120c1970c623ddaf6d7e289a192879664586cf7a445d0d6f2a5257eb6ab"
    }
  },
  "files": {
    "record-1.0/schema.xsd": { "package_path": "schema.xsd", "sha256": "7b00f00c0e910dccc61f447681ba5b3e6a719650c49f400ba2b7cc8ace582e0e" },
    "record-1.0/form103.sb.xslt": { "package_path": "Content/form103.sb.xslt", "sha256": "<from Step 2>" },
    "clause-1.3/schema.xsd": { "package_path": "schema.xsd", "sha256": "5c4de06e0a115943cc3ef3a01cbd1388e495acfb2c66c7e7fe4c5769f383be8e" },
    "clause-1.3/form.2.html2.xslt": { "package_path": "Content/form.2.html2.xslt", "sha256": "<from Step 2>" }
  }
}
```

Replace both `<from Step 2>` with the printed hashes before saving; the test in Step 6 fails on anything else.

And `docs/reference/forms/README.md`:

```markdown
# Official conversion forms

Verbatim files from the slovensko.sk form packages that Chevron7 references in every
XMLDataContainer it builds: record 1.0 (`ConversionRecordOfPaperToElectronicDocument`) and
clause 1.3 (`ConversionCertificateOfPaperToElectronicDocument`). Sources, hashes and the digest
rule are in `provenance.json`. The presentation file is the package manifest's
`media-destination="sign"` entry (record: TXT; clause: the HTML one).

After changing any file here, run `scripts/embed-official-forms.sh` and commit the regenerated
`Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift`. `OfficialFormTests` fails when
the two drift apart. The record digests must stay equal to those of the record EZZK accepted on
2026-08-24 (spec: `docs/superpowers/specs/2026-09-23-ezzk-part-b-design.md`).
```

- [ ] **Step 4: Write the generator script `scripts/embed-official-forms.sh`**

```bash
#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Marián Čuprík
# SPDX-License-Identifier: EUPL-1.2
# Regenerates Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift from
# docs/reference/forms. Digests: SHA-256 over Canonical XML 1.0 without comments.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import base64, hashlib, pathlib, re, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
forms = root / "docs/reference/forms"
files = [
    ("recordSchema", forms / "record-1.0/schema.xsd"),
    ("recordPresentation", forms / "record-1.0/form103.sb.xslt"),
    ("clauseSchema", forms / "clause-1.3/schema.xsd"),
    ("clausePresentation", forms / "clause-1.3/form.2.html2.xslt"),
]
def digest(path):
    stripped = re.sub(rb"<!--.*?-->", b"", path.read_bytes(), flags=re.S)
    with tempfile.NamedTemporaryFile(suffix=".xml") as tmp:
        tmp.write(stripped)
        tmp.flush()
        canonical = subprocess.run(["xmllint", "--c14n", tmp.name], check=True, capture_output=True).stdout
    return base64.b64encode(hashlib.sha256(canonical).digest()).decode()
out = [
    "// SPDX-FileCopyrightText: 2026 Marián Čuprík",
    "// SPDX-License-Identifier: EUPL-1.2",
    "// Generated by scripts/embed-official-forms.sh from docs/reference/forms. Do not edit.",
    "",
    "import Foundation",
    "",
    "enum OfficialFormFiles {",
]
for name, path in files:
    out.append(f'    static let {name} = Data(base64Encoded: "{base64.b64encode(path.read_bytes()).decode()}")!')
    out.append(f'    static let {name}Digest = "{digest(path)}"')
out.append("}")
target = root / "Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("\n".join(out) + "\n")
print(f"wrote {target}")
PY
```

Run: `chmod +x scripts/embed-official-forms.sh && scripts/embed-official-forms.sh && grep -o 'recordSchemaDigest = "[^"]*"\|recordPresentationDigest = "[^"]*"' Sources/Chevron7Kit/Attestation/Forms/OfficialFormFiles.swift`
Expected: `V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=` and `TYaNJLG/51TOIF8aFEcTQw72vudBAtYZUOkOfRG87as=`.

- [ ] **Step 5: Write the failing test `Tests/Chevron7KitTests/OfficialFormTests.swift`**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import CryptoKit
@testable import Chevron7Kit

final class OfficialFormTests: XCTestCase {
    private let formsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/reference/forms")

    func testRecordDigestsMatchTheRecordEZZKAccepted() {
        XCTAssertEqual(OfficialForm.record_1_0.schemaDigestBase64, "V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=")
        XCTAssertEqual(OfficialForm.record_1_0.presentationDigestBase64, "TYaNJLG/51TOIF8aFEcTQw72vudBAtYZUOkOfRG87as=")
        XCTAssertEqual(OfficialForm.record_1_0.schemaURI,
                       "https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0/form.xsd")
        XCTAssertEqual(OfficialForm.record_1_0.presentationMediaDestination, "TXT")
    }

    func testClauseIdentifiers() {
        let clause = OfficialForm.clause_1_3
        XCTAssertEqual(clause.identifier, "http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3")
        XCTAssertEqual(clause.namespace, "http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3")
        XCTAssertEqual(clause.version, "1.3")
        XCTAssertEqual(clause.presentationURI, clause.namespace + "/form.xslt")
        XCTAssertEqual(clause.presentationMediaDestination, "HTML")
    }

    func testEmbeddedFilesEqualTheReferenceCopiesAndProvenance() throws {
        let provenance = try JSONSerialization.jsonObject(
            with: Data(contentsOf: formsDirectory.appendingPathComponent("provenance.json"))) as? [String: Any]
        let files = try XCTUnwrap(provenance?["files"] as? [String: [String: String]])
        let embedded: [(String, Data)] = [
            ("record-1.0/schema.xsd", OfficialForm.record_1_0.schema),
            ("record-1.0/form103.sb.xslt", OfficialForm.record_1_0.presentation),
            ("clause-1.3/schema.xsd", OfficialForm.clause_1_3.schema),
            ("clause-1.3/form.2.html2.xslt", OfficialForm.clause_1_3.presentation),
        ]
        for (path, data) in embedded {
            let reference = try Data(contentsOf: formsDirectory.appendingPathComponent(path))
            XCTAssertEqual(data, reference, "\(path) differs from the embedded copy; run scripts/embed-official-forms.sh")
            let hex = SHA256.hash(data: reference).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hex, files[path]?["sha256"], "\(path) differs from provenance.json")
        }
    }

    func testStoredDigestsRecomputeFromTheEmbeddedFiles() throws {
        for form in [OfficialForm.record_1_0, .clause_1_3] {
            XCTAssertEqual(try Self.canonicalDigest(form.schema), form.schemaDigestBase64, form.identifier)
            XCTAssertEqual(try Self.canonicalDigest(form.presentation), form.presentationDigestBase64, form.identifier)
        }
    }

    /// SHA-256 over Canonical XML 1.0 without comments, the XDC 1.1 digest rule.
    static func canonicalDigest(_ data: Data) throws -> String {
        let xmllint = URL(fileURLWithPath: "/usr/bin/xmllint")
        guard FileManager.default.isExecutableFile(atPath: xmllint.path) else {
            throw XCTSkip("xmllint is needed to canonicalise the form files.")
        }
        let text = String(decoding: data, as: UTF8.self)
        let stripped = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("form-\(UUID().uuidString).xml")
        try Data(stripped.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = xmllint
        process.arguments = ["--c14n", file.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let canonical = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return Data(SHA256.hash(data: canonical)).base64EncodedString()
    }
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OfficialFormTests`
Expected: compile error, `cannot find 'OfficialForm' in scope`.

- [ ] **Step 7: Write `Sources/Chevron7Kit/Attestation/Forms/OfficialForm.swift`**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// An official slovensko.sk form as an XMLDataContainer references it. The files and their
/// digests come from `docs/reference/forms` through `scripts/embed-official-forms.sh`.
public struct OfficialForm: Sendable, Equatable {
    public let identifier: String
    public let namespace: String
    public let version: String
    public let schema: Data
    public let presentation: Data
    /// `MediaDestinationTypeDescription` of the signer presentation (`TXT` or `HTML`).
    public let presentationMediaDestination: String
    public let schemaDigestBase64: String
    public let presentationDigestBase64: String

    public var schemaURI: String { namespace + "/form.xsd" }
    public var presentationURI: String { namespace + "/form.xslt" }

    /// Záznam o vykonanej zaručenej konverzii 1.0, the form EZZK receives.
    public static let record_1_0 = OfficialForm(
        identifier: "http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0",
        namespace: "https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0",
        version: "1.0",
        schema: OfficialFormFiles.recordSchema,
        presentation: OfficialFormFiles.recordPresentation,
        presentationMediaDestination: "TXT",
        schemaDigestBase64: OfficialFormFiles.recordSchemaDigest,
        presentationDigestBase64: OfficialFormFiles.recordPresentationDigest)

    /// Osvedčovacia doložka 1.3, attached to the converted document.
    public static let clause_1_3 = OfficialForm(
        identifier: "http://data.gov.sk/doc/eform/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3",
        namespace: "http://schemas.gov.sk/form/50349287.ConversionCertificateOfPaperToElectronicDocument.sk/1.3",
        version: "1.3",
        schema: OfficialFormFiles.clauseSchema,
        presentation: OfficialFormFiles.clausePresentation,
        presentationMediaDestination: "HTML",
        schemaDigestBase64: OfficialFormFiles.clauseSchemaDigest,
        presentationDigestBase64: OfficialFormFiles.clausePresentationDigest)
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OfficialFormTests`
Expected: 4 tests, PASS.

- [ ] **Step 9: Commit**

```bash
git add docs/reference/forms scripts/embed-official-forms.sh Sources/Chevron7Kit/Attestation/Forms Tests/Chevron7KitTests/OfficialFormTests.swift
git commit -m "feat(zako): embed the official record 1.0 and clause 1.3 form files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Schema validator

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/FormSchemaValidator.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/FormSchemaValidatorTests.swift`

**Interfaces:**
- Consumes: `OfficialForm` (Task 1).
- Produces: `public struct FormSchemaValidator: Sendable` with `init(xmllintURL: URL = URL(fileURLWithPath: "/usr/bin/xmllint"))` and `func validate(_ xml: Data, against form: OfficialForm) throws`; errors `FormSchemaValidator.Failure.validatorUnavailable` and `.invalid(details: String)`.

- [ ] **Step 1: Write the failing test**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class FormSchemaValidatorTests: XCTestCase {
    private let validator = FormSchemaValidator()

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    func testWrongRootIsReportedAsInvalid() {
        let xml = Data("<Nothing xmlns=\"\(OfficialForm.clause_1_3.namespace)\"/>".utf8)
        XCTAssertThrowsError(try validator.validate(xml, against: .clause_1_3)) { error in
            guard case FormSchemaValidator.Failure.invalid(let details) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(details.contains("Nothing"), details)
        }
    }

    func testMissingValidatorIsReported() {
        let missing = FormSchemaValidator(xmllintURL: URL(fileURLWithPath: "/nonexistent/xmllint"))
        XCTAssertThrowsError(try missing.validate(Data("<a/>".utf8), against: .clause_1_3)) { error in
            XCTAssertEqual(error as? FormSchemaValidator.Failure, .validatorUnavailable)
        }
    }
}
```

A passing document is exercised in Task 5, where a real clause exists.

- [ ] **Step 2: Run it to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FormSchemaValidatorTests`
Expected: compile error, `cannot find 'FormSchemaValidator' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Validates a form document against its official XML schema with libxml2's `xmllint`,
/// which ships with macOS. Runs before anything is signed.
public struct FormSchemaValidator: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case validatorUnavailable
        case invalid(details: String)

        public var errorDescription: String? {
            switch self {
            case .validatorUnavailable:
                return "Kontrola podľa oficiálnej schémy nie je dostupná (chýba /usr/bin/xmllint)."
            case .invalid(let details):
                return "Dokument nezodpovedá oficiálnej schéme formulára:\n\(details)"
            }
        }
    }

    private let xmllintURL: URL

    public init(xmllintURL: URL = URL(fileURLWithPath: "/usr/bin/xmllint")) {
        self.xmllintURL = xmllintURL
    }

    public func validate(_ xml: Data, against form: OfficialForm) throws {
        guard FileManager.default.isExecutableFile(atPath: xmllintURL.path) else {
            throw Failure.validatorUnavailable
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chevron7-form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schemaURL = directory.appendingPathComponent("schema.xsd")
        let documentURL = directory.appendingPathComponent("document.xml")
        try form.schema.write(to: schemaURL)
        try xml.write(to: documentURL)

        let process = Process()
        process.executableURL = xmllintURL
        process.arguments = ["--nonet", "--noout", "--schema", schemaURL.path, documentURL.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Read before waiting so a long error report cannot fill the pipe and block xmllint.
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = output.split(separator: "\n")
                .filter { !$0.hasSuffix("fails to validate") }
                .prefix(5)
                .map { $0.replacingOccurrences(of: documentURL.path + ":", with: "riadok ") }
                .joined(separator: "\n")
            throw Failure.invalid(details: details)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FormSchemaValidatorTests`
Expected: 2 tests, PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Chevron7Kit/Attestation/Forms/FormSchemaValidator.swift Tests/Chevron7KitTests/FormSchemaValidatorTests.swift
git commit -m "feat(zako): validate form documents against the official schema

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Codelist corrections

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/Models/DomainModels.swift:194-218` (`locationCodelist11Item`)
- Modify: `Chevron7/Sources/Chevron7Kit/Attestation/ZakoCodelists.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/ZakoCodelistsTests.swift` (create; if the file exists, add the methods)

**Interfaces:**
- Produces: `ZakoCodelists.locationItems: [ZakoCodelistItem]` (13 items, list order), `ZakoCodelists.locationItem(code: String) -> ZakoCodelistItem?`, `ZakoCodelists.legalSubjectURI(ico: String) -> String?`, `ZakoCodelists.clausePaperSize(for: PaperClassification) -> (item: ZakoCodelistItem, other: String?)`, `ZakoCodelists.otherPaperSizeItem`, `ZakoCodelists.descriptionCodesNeedingOtherText: Set<String>`. `SecurityElement.locationCodelist11Item` returns official codes and names (`Mid` / `Uprostred` for the centre).

- [ ] **Step 1: Write the failing tests**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ZakoCodelistsTests: XCTestCase {
    func testCentreUsesOfficialMidCodeAndNamesFollowTheCodelist() {
        func element(x: Double, y: Double) -> SecurityElement {
            SecurityElement(kind: .handwrittenSignature, pageIndex: 0,
                            boundingBox: NormalizedRect(x: x - 0.05, y: y - 0.05, width: 0.1, height: 0.1),
                            confidence: 1, detectedByAI: false)
        }
        XCTAssertEqual(element(x: 0.5, y: 0.5).locationCodelist11Item, ZakoCodelistItem(code: "Mid", skName: "Uprostred"))
        XCTAssertEqual(element(x: 0.1, y: 0.1).locationCodelist11Item, ZakoCodelistItem(code: "Left down", skName: "Vľavo dole"))
        XCTAssertEqual(element(x: 0.9, y: 0.9).locationCodelist11Item, ZakoCodelistItem(code: "Right up", skName: "Vpravo hore"))
        for item in [element(x: 0.5, y: 0.5), element(x: 0.1, y: 0.1), element(x: 0.9, y: 0.1)].map(\.locationCodelist11Item) {
            XCTAssertEqual(ZakoCodelists.locationItem(code: item.code), item)
        }
    }

    func testLocationListIsTheOfficialCodelist() {
        XCTAssertEqual(ZakoCodelists.locationItems.map(\.code),
                       ["Down", "Up", "Down edge", "Up edge", "Left edge", "Right edge", "Mid",
                        "Left", "Left down", "Left up", "Right", "Right down", "Right up"])
        XCTAssertNil(ZakoCodelists.locationItem(code: "vpravo dole pri podpise"))
    }

    func testLegalSubjectURI() {
        XCTAssertEqual(ZakoCodelists.legalSubjectURI(ico: " 42249180 "), "https://data.gov.sk/id/legal-subject/42249180")
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: ""))
    }

    func testLegalSubjectURIRejectsNonDigits() {
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: "42 249 180"))
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: "SK42249180"))
        XCTAssertNil(ZakoCodelists.legalSubjectURI(ico: "1234567"))
    }

    func testClausePaperSize() {
        XCTAssertEqual(ZakoCodelists.clausePaperSize(for: .a4Landscape).item.code, "A4")
        XCTAssertNil(ZakoCodelists.clausePaperSize(for: .a3Portrait).other)
        let letter = ZakoCodelists.clausePaperSize(for: .letterPortrait)
        XCTAssertEqual(letter.item, ZakoCodelistItem(code: "Iny", skName: "Iný"))
        XCTAssertEqual(letter.other, "Letter")
        XCTAssertEqual(ZakoCodelists.clausePaperSize(for: .unknown).other, "neurčený")
    }
}
```

Check `NormalizedRect`'s initializer labels in `DomainModels.swift` before running; if they differ, use the actual ones.

- [ ] **Step 2: Run it to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoCodelistsTests`
Expected: compile errors for `locationItems`, `locationItem(code:)`, `legalSubjectURI`, `clausePaperSize`.

- [ ] **Step 3: Replace the switch at the end of `locationCodelist11Item` in `DomainModels.swift`**

```swift
        let code: String
        switch (vertical, horizontal) {
        case ("down", "left"): code = "Left down"
        case ("down", "center"): code = "Down"
        case ("down", "right"): code = "Right down"
        case ("middle", "left"): code = "Left"
        case ("middle", "center"): code = "Mid"
        case ("middle", "right"): code = "Right"
        case ("up", "left"): code = "Left up"
        case ("up", "center"): code = "Up"
        default: code = "Right up"
        }
        return ZakoCodelists.locationItem(code: code)!
```

- [ ] **Step 4: Add to `ZakoCodelists`**

```swift
    /// Codelist 11 (security element location) in the order of the official form.
    public static let locationItems: [ZakoCodelistItem] = [
        ZakoCodelistItem(code: "Down", skName: "Dole"),
        ZakoCodelistItem(code: "Up", skName: "Hore"),
        ZakoCodelistItem(code: "Down edge", skName: "Dolný okraj"),
        ZakoCodelistItem(code: "Up edge", skName: "Horný okraj"),
        ZakoCodelistItem(code: "Left edge", skName: "Ľavý okraj"),
        ZakoCodelistItem(code: "Right edge", skName: "Pravý okraj"),
        ZakoCodelistItem(code: "Mid", skName: "Uprostred"),
        ZakoCodelistItem(code: "Left", skName: "Vľavo"),
        ZakoCodelistItem(code: "Left down", skName: "Vľavo dole"),
        ZakoCodelistItem(code: "Left up", skName: "Vľavo hore"),
        ZakoCodelistItem(code: "Right", skName: "Vpravo"),
        ZakoCodelistItem(code: "Right down", skName: "Vpravo dole"),
        ZakoCodelistItem(code: "Right up", skName: "Vpravo hore"),
    ]

    public static func locationItem(code: String) -> ZakoCodelistItem? {
        locationItems.first { $0.code == code }
    }

    /// Codelist 12 item for sizes outside A1 to C7; `PaperSizeOther` names the size.
    public static let otherPaperSizeItem = ZakoCodelistItem(code: "Iny", skName: "Iný")

    public static func clausePaperSize(for classification: PaperClassification) -> (item: ZakoCodelistItem, other: String?) {
        switch classification {
        case .letterPortrait, .letterLandscape: return (otherPaperSizeItem, "Letter")
        case .unknown: return (otherPaperSizeItem, "neurčený")
        default: return (paperSizeItem(for: classification)!, nil)
        }
    }

    /// Codelist 15 items whose meaning is carried by `OriginalDocumentSecurityElementsDescriptionOther`.
    public static let descriptionCodesNeedingOtherText: Set<String> = [
        "iný manuálny vstup", "trvale spojenie dokumentu - iné"
    ]

    /// Person identifier the clause schema accepts (`https://data.gov.sk/id/legal-subject/\d{8,12}`).
    public static func legalSubjectURI(ico: String) -> String? {
        let cleaned = ico.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...12).contains(cleaned.count), cleaned.allSatisfy(\.isASCII), cleaned.allSatisfy(\.isNumber) else {
            return nil
        }
        return "https://data.gov.sk/id/legal-subject/\(cleaned)"
    }
```

- [ ] **Step 5: Run the tests, then the whole Kit suite for the renamed location names**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoCodelistsTests`
Expected: PASS.
Run: `grep -rn '"Center"\|"Dole vľavo"\|"Dole vpravo"\|"Hore vľavo"\|"Hore vpravo"\|"V strede"' Sources Tests`
Expected: no matches. If a test asserts an old name, update it to the official name and note it in the commit message.
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter Chevron7KitTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Chevron7Kit/Models/DomainModels.swift Sources/Chevron7Kit/Attestation/ZakoCodelists.swift Tests
git commit -m "fix(zako): use the official location codes and the legal-subject identifier

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `ConversionFormModel`

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ConversionFormModel.swift`
- Modify: `Chevron7/Sources/Chevron7Kit/Attestation/AttestationClauseGenerator.swift` (error cases; `securityElementPages` from `private static` to `static`)
- Test: `Chevron7/Tests/Chevron7KitTests/ConversionFormModelTests.swift`

**Interfaces:**
- Consumes: Task 3 codelists; `AttestationClauseGenerator.securityElementPages(_:originalNonEmptyPageIndices:)`, `AttestationClauseGenerator.fingerprintBase64(hex:)`.
- Produces:

```swift
public struct ConversionFormModel: Sendable, Equatable {
    public struct PaperSize: Sendable, Equatable { public var item: ZakoCodelistItem; public var other: String?; public var sheets: Int }
    public struct SecurityElementEntry: Sendable, Equatable {
        public var description: ZakoCodelistItem; public var descriptionOther: String?
        public var originalPage: Int; public var originalSheet: Int
        public var location: ZakoCodelistItem; public var newPage: Int
    }
    public struct Person: Sendable, Equatable {
        public var givenName: String; public var familyName: String; public var position: String
        public var legalSubjectName: String; public var legalSubjectURI: String?
    }
    public var originalDocumentName: String
    public var originalDocumentOrder: Int
    public var originalDocumentType: String
    public var numberOfSheets: Int
    public var nonEmptyPageCount: Int
    public var paperSizes: [PaperSize]
    public var securityElements: [SecurityElementEntry]
    public var newDocumentName: String
    public var newDocumentFormat: ZakoCodelistItem
    public var fingerprintBase64: String
    public var fingerprintMethod: ZakoCodelistItem
    public var evidenceNumber: String
    public var usedDevice: String
    public var conversionTime: Date
    public var person: Person
    public var conversionTimeText: String
    public var evidenceNumberURI: String
    public static func make(attestation: AttestationData, securityElements: [SecurityElement],
                            newDocumentSHA256Hex: String, originalNonEmptyPageIndices: [Int]?,
                            usedDevice: String) throws -> ConversionFormModel
    public static func bratislavaDateTime(_ date: Date) -> String
}
```

- New `AttestationGenerationError` cases: `.missingEvidenceNumber`, `.invalidOriginalLocation`.

- [ ] **Step 1: Write the failing tests**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ConversionFormModelTests: XCTestCase {
    static let fingerprintHex = String(repeating: "ab", count: 32)

    static func attestation(at time: Date = Date(timeIntervalSince1970: 1_787_589_344)) -> AttestationData {
        AttestationData(
            originalDocumentName: "Brezinová_diplom",
            numberOfSheets: 1,
            nonEmptyPageCount: 1,
            paperSizeBreakdown: [.init(sizeClass: .a4Portrait, sheets: 1)],
            newDocumentName: "Brezinová_diplom.pdf",
            conversionExecutionDateTime: time,
            evidenceNumber: " 1563-260824-1 ",
            performingPerson: AdvocateProfile(fullName: "Mgr. Marián Čuprík", position: "Partner",
                                              registrationNumber: "1042", ico: "42249180",
                                              officeName: "Advokátska kancelária CHZ"))
    }

    static func scanElement(_ kind: SecurityElement.Kind = .handwrittenSignature) -> SecurityElement {
        SecurityElement(kind: kind, pageIndex: 0,
                        boundingBox: NormalizedRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1),
                        confidence: 1, detectedByAI: false)
    }

    func testBuildsEveryValueFromTheZakoState() throws {
        let model = try ConversionFormModel.make(attestation: Self.attestation(),
                                                 securityElements: [Self.scanElement()],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0],
                                                 usedDevice: "Chevron7 v0.5.0")
        XCTAssertEqual(model.evidenceNumber, "1563-260824-1")
        XCTAssertEqual(model.evidenceNumberURI, "https://data.gov.sk/id/egov/conversion-record/1563-260824-1")
        XCTAssertEqual(model.originalDocumentType, "Brezinová_diplom")
        XCTAssertEqual(model.person, .init(givenName: "Marián", familyName: "Čuprík", position: "Partner",
                                           legalSubjectName: "Advokátska kancelária CHZ",
                                           legalSubjectURI: "https://data.gov.sk/id/legal-subject/42249180"))
        XCTAssertEqual(model.paperSizes, [.init(item: ZakoCodelistItem(code: "A4", skName: "Formát papiera A4"), other: nil, sheets: 1)])
        XCTAssertEqual(model.securityElements.first?.description.code, "vlastnoručný podpis")
        XCTAssertNil(model.securityElements.first?.descriptionOther)
        XCTAssertEqual(model.securityElements.first?.location.code, "Left down")
        XCTAssertEqual(model.newDocumentFormat, ZakoCodelists.pdfa2FormatItem)
        XCTAssertEqual(model.fingerprintBase64, AttestationClauseGenerator.fingerprintBase64(hex: Self.fingerprintHex))
    }

    func testConversionTimeUsesBratislavaOffset() {
        // 2026-08-24T16:35:44Z is summer time, 2026-01-15T23:30:00Z is winter time.
        XCTAssertEqual(ConversionFormModel.bratislavaDateTime(Date(timeIntervalSince1970: 1_787_589_344)),
                       "2026-08-24T18:35:44+02:00")
        XCTAssertEqual(ConversionFormModel.bratislavaDateTime(Date(timeIntervalSince1970: 1_768_519_800)),
                       "2026-01-16T00:30:00+01:00")
    }

    func testOtherKindsCarryTheirDescriptionAsOtherText() throws {
        var element = Self.scanElement(.bindingCord)
        element.verbalDescription = "trikolóra cez ľavý okraj"
        let model = try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [element],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")
        XCTAssertEqual(model.securityElements.first?.description.code, "iný manuálny vstup")
        XCTAssertEqual(model.securityElements.first?.descriptionOther, element.descriptionForRecord)
    }

    func testPhysicalElementUsesItsCodelistLocation() throws {
        var element = Self.scanElement()
        element.observation = .physicalOriginal
        element.originalLocation = "Right down"
        element.newDocumentPageIndex = 0
        let model = try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [element],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")
        XCTAssertEqual(model.securityElements.first?.location, ZakoCodelistItem(code: "Right down", skName: "Vpravo dole"))
    }

    func testPhysicalElementWithFreeTextLocationIsRefused() {
        var element = Self.scanElement()
        element.observation = .physicalOriginal
        element.originalLocation = "vpravo dole pri podpise"
        element.newDocumentPageIndex = 0
        XCTAssertThrowsError(try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [element],
                                                          newDocumentSHA256Hex: Self.fingerprintHex,
                                                          originalNonEmptyPageIndices: [0], usedDevice: "Chevron7")) {
            XCTAssertEqual($0 as? AttestationGenerationError, .invalidOriginalLocation)
        }
    }

    func testMissingEvidenceNumberAndBadFingerprintAreRefused() {
        var data = Self.attestation()
        data.evidenceNumber = "  "
        XCTAssertThrowsError(try ConversionFormModel.make(attestation: data, securityElements: [],
                                                          newDocumentSHA256Hex: Self.fingerprintHex,
                                                          originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")) {
            XCTAssertEqual($0 as? AttestationGenerationError, .missingEvidenceNumber)
        }
        XCTAssertThrowsError(try ConversionFormModel.make(attestation: Self.attestation(), securityElements: [],
                                                          newDocumentSHA256Hex: "xyz",
                                                          originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")) {
            XCTAssertEqual($0 as? AttestationGenerationError, .invalidFingerprint)
        }
    }

    func testMissingPaperBreakdownFallsBackToA4() throws {
        var data = Self.attestation()
        data.paperSizeBreakdown = []
        data.numberOfSheets = 3
        let model = try ConversionFormModel.make(attestation: data, securityElements: [],
                                                 newDocumentSHA256Hex: Self.fingerprintHex,
                                                 originalNonEmptyPageIndices: nil, usedDevice: "Chevron7")
        XCTAssertEqual(model.paperSizes.map(\.sheets), [3])
        XCTAssertEqual(model.paperSizes.first?.item.code, "A4")
    }
}
```

Check the `SecurityElement.Kind` case names (`handwrittenSignature`, `bindingCord`) in `SecurityElementCatalogue.swift` and the `AttestationData` init labels before running.

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionFormModelTests`
Expected: compile error, `cannot find 'ConversionFormModel' in scope`.

- [ ] **Step 3: Extend `AttestationGenerationError` and expose `securityElementPages`**

In `AttestationClauseGenerator.swift` add two cases and their descriptions:

```swift
    case missingEvidenceNumber
    case invalidOriginalLocation
```
```swift
        case .missingEvidenceNumber:
            return "Chýba evidenčné číslo záznamu z EZZK."
        case .invalidOriginalLocation:
            return "Pri prvku skontrolovanom na origináli vyberte umiestnenie zo zoznamu."
```
Change `private static func securityElementPages(` to `static func securityElementPages(`.

- [ ] **Step 4: Implement `ConversionFormModel.swift`**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Every value the conversion clause and the conversion record carry, derived once from the
/// ZaKo state so the two documents cannot disagree.
public struct ConversionFormModel: Sendable, Equatable {
    public struct PaperSize: Sendable, Equatable {
        public var item: ZakoCodelistItem
        public var other: String?
        public var sheets: Int
    }

    public struct SecurityElementEntry: Sendable, Equatable {
        public var description: ZakoCodelistItem
        public var descriptionOther: String?
        public var originalPage: Int
        public var originalSheet: Int
        public var location: ZakoCodelistItem
        public var newPage: Int
    }

    public struct Person: Sendable, Equatable {
        public var givenName: String
        public var familyName: String
        public var position: String
        public var legalSubjectName: String
        public var legalSubjectURI: String?
    }

    public var originalDocumentName: String
    public var originalDocumentOrder: Int
    public var originalDocumentType: String
    public var numberOfSheets: Int
    public var nonEmptyPageCount: Int
    public var paperSizes: [PaperSize]
    public var securityElements: [SecurityElementEntry]
    public var newDocumentName: String
    public var newDocumentFormat: ZakoCodelistItem
    public var fingerprintBase64: String
    public var fingerprintMethod: ZakoCodelistItem
    public var evidenceNumber: String
    public var usedDevice: String
    public var conversionTime: Date
    public var person: Person

    public var conversionTimeText: String { Self.bratislavaDateTime(conversionTime) }
    public var evidenceNumberURI: String { ZakoCodelists.conversionRecordURI(evidenceNumber: evidenceNumber) }

    public static func make(attestation d: AttestationData,
                            securityElements: [SecurityElement],
                            newDocumentSHA256Hex: String,
                            originalNonEmptyPageIndices: [Int]?,
                            usedDevice: String) throws -> ConversionFormModel {
        guard newDocumentSHA256Hex.count == 64, newDocumentSHA256Hex.allSatisfy(\.isHexDigit) else {
            throw AttestationGenerationError.invalidFingerprint
        }
        let evidenceNumber = (d.evidenceNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidenceNumber.isEmpty else { throw AttestationGenerationError.missingEvidenceNumber }

        var paperSizes = d.paperSizeBreakdown.map { group -> PaperSize in
            let size = ZakoCodelists.clausePaperSize(for: group.sizeClass)
            return PaperSize(item: size.item, other: size.other, sheets: group.sheets)
        }
        if paperSizes.isEmpty {
            paperSizes = [PaperSize(item: ZakoCodelists.clausePaperSize(for: .a4Portrait).item,
                                    other: nil, sheets: max(d.numberOfSheets, 1))]
        }

        let entries = try securityElements.map { element -> SecurityElementEntry in
            let pages = try AttestationClauseGenerator.securityElementPages(
                element, originalNonEmptyPageIndices: originalNonEmptyPageIndices)
            let location: ZakoCodelistItem
            if element.observation == .physicalOriginal {
                guard let item = ZakoCodelists.locationItem(
                    code: element.originalLocation.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw AttestationGenerationError.invalidOriginalLocation
                }
                location = item
            } else {
                location = element.locationCodelist11Item
            }
            let description = element.kind.codelist15Item
            let other = ZakoCodelists.descriptionCodesNeedingOtherText.contains(description.code)
                ? String(element.descriptionForRecord.prefix(255)) : nil
            return SecurityElementEntry(description: description, descriptionOther: other,
                                        originalPage: pages.original,
                                        originalSheet: element.sheetNumber(sheetMethod: d.sheetCountingMethod),
                                        location: location, newPage: pages.new)
        }

        let names = nameParts(d.performingPerson.fullName)
        let office = d.performingPerson.officeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeLabel = d.originalDocumentTypeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConversionFormModel(
            originalDocumentName: d.originalDocumentName,
            originalDocumentOrder: d.originalDocumentOrder,
            originalDocumentType: typeLabel.isEmpty ? d.originalDocumentName : typeLabel,
            numberOfSheets: d.numberOfSheets,
            nonEmptyPageCount: d.nonEmptyPageCount,
            paperSizes: paperSizes,
            securityElements: entries,
            newDocumentName: d.newDocumentName,
            newDocumentFormat: ZakoCodelists.pdfa2FormatItem,
            fingerprintBase64: AttestationClauseGenerator.fingerprintBase64(hex: newDocumentSHA256Hex),
            fingerprintMethod: ZakoCodelists.sha256Item,
            evidenceNumber: evidenceNumber,
            usedDevice: usedDevice,
            conversionTime: d.conversionExecutionDateTime,
            person: Person(givenName: names.given, familyName: names.family,
                           position: d.performingPerson.position.trimmingCharacters(in: .whitespacesAndNewlines),
                           legalSubjectName: office.isEmpty ? d.performingPerson.fullName : office,
                           legalSubjectURI: ZakoCodelists.legalSubjectURI(ico: d.performingPerson.ico)))
    }

    /// ISO 8601 with the Europe/Bratislava offset of that instant, as both forms require.
    public static func bratislavaDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        return formatter.string(from: date)
    }

    /// Given and family name without academic titles (tokens ending with a dot).
    static func nameParts(_ fullName: String) -> (given: String, family: String) {
        let tokens = fullName.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.hasSuffix(".") }
        return (tokens.dropLast().joined(separator: " "), tokens.last ?? "")
    }
}
```

Check: `ISO8601DateFormatter` with `.withInternetDateTime` and a non-UTC zone prints `+02:00`, not `Z`. The test in Step 1 pins it.

- [ ] **Step 5: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionFormModelTests`
Expected: 7 tests, PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Chevron7Kit/Attestation Tests/Chevron7KitTests/ConversionFormModelTests.swift
git commit -m "feat(zako): derive clause and record values from one form model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Clause 1.3 renderer

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ConversionCertificateRenderer.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/ConversionCertificateRendererTests.swift`

**Interfaces:**
- Consumes: `ConversionFormModel` (Task 4), `OfficialForm.clause_1_3` (Task 1), `FormSchemaValidator` (Task 2).
- Produces: `public struct ConversionCertificateRenderer: Sendable { public init(); public func render(_ model: ConversionFormModel) -> String }`, returning the clause element without an XML declaration.

- [ ] **Step 1: Write the failing tests**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ConversionCertificateRendererTests: XCTestCase {
    private let renderer = ConversionCertificateRenderer()

    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    private func model(_ attestation: AttestationData = ConversionFormModelTests.attestation(),
                       elements: [SecurityElement] = [ConversionFormModelTests.scanElement()]) throws -> ConversionFormModel {
        try ConversionFormModel.make(attestation: attestation, securityElements: elements,
                                     newDocumentSHA256Hex: ConversionFormModelTests.fingerprintHex,
                                     originalNonEmptyPageIndices: [0], usedDevice: "Chevron7 v0.5.0")
    }

    private func assertValid(_ xml: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try FormSchemaValidator().validate(Data(xml.utf8), against: .clause_1_3), file: file, line: line)
    }

    func testClauseValidatesAgainstTheOfficialSchema() throws {
        let xml = renderer.render(try model())
        assertValid(xml)
        XCTAssertTrue(xml.hasPrefix("<ConversionCertificateOfPaperToElectronicDocument xmlns=\"\(OfficialForm.clause_1_3.namespace)\">"))
        XCTAssertTrue(xml.contains("<ConversionRecordEvidenceNumber>https://data.gov.sk/id/egov/conversion-record/1563-260824-1</ConversionRecordEvidenceNumber>"))
        XCTAssertTrue(xml.contains("<ConversionExecutionDateTime>2026-08-24T18:35:44+02:00</ConversionExecutionDateTime>"))
        XCTAssertTrue(xml.contains("<CodelistCode>53</CodelistCode><CodelistItem><ItemCode>PDFA2</ItemCode>"))
        XCTAssertTrue(xml.contains("<IdentifierValue>https://data.gov.sk/id/legal-subject/42249180</IdentifierValue>"))
        XCTAssertFalse(xml.contains("UsedDevice"), "the clause has no UsedDevice element")
    }

    func testClauseWithoutValidICOValidates() throws {
        var data = ConversionFormModelTests.attestation()
        data.performingPerson.ico = "SK 4224"
        data.performingPerson.officeName = ""
        let xml = renderer.render(try model(data))
        assertValid(xml)
        XCTAssertFalse(xml.contains("<ID>"))
        XCTAssertTrue(xml.contains("<LegalSubject><Name>Mgr. Marián Čuprík</Name></LegalSubject>"))
    }

    func testLetterAndUnknownPaperValidate() throws {
        var data = ConversionFormModelTests.attestation()
        data.paperSizeBreakdown = [.init(sizeClass: .letterPortrait, sheets: 1), .init(sizeClass: .unknown, sheets: 2)]
        let xml = renderer.render(try model(data))
        assertValid(xml)
        XCTAssertTrue(xml.contains("<PaperSizeOther>Letter</PaperSizeOther>"))
    }

    func testOtherElementAndPhysicalElementValidate() throws {
        var other = ConversionFormModelTests.scanElement(.bindingCord)
        other.verbalDescription = "trikolóra"
        var physical = ConversionFormModelTests.scanElement(.embossedSeal)
        physical.observation = .physicalOriginal
        physical.originalLocation = "Down edge"
        physical.newDocumentPageIndex = 0
        let xml = renderer.render(try model(elements: [other, physical]))
        assertValid(xml)
        XCTAssertTrue(xml.contains("<OriginalDocumentSecurityElementsDescriptionOther>"))
        XCTAssertTrue(xml.contains("<ItemCode>Down edge</ItemCode>"))
    }

    func testSpecialCharactersAreEscaped() throws {
        var data = ConversionFormModelTests.attestation()
        data.originalDocumentName = "Zmluva \"A\" & <B>"
        data.performingPerson.officeName = "Čuprík & partneri"
        let xml = renderer.render(try model(data))
        assertValid(xml)
        XCTAssertTrue(xml.contains("Zmluva &quot;A&quot; &amp; &lt;B&gt;"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionCertificateRendererTests`
Expected: compile error, `cannot find 'ConversionCertificateRenderer' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Renders the conversion clause (osvedčovacia doložka) 1.3 in the element order of its
/// official schema. Codelist values carry code and Slovak name; the evidence number is a URI.
public struct ConversionCertificateRenderer: Sendable {
    public init() {}

    public func render(_ m: ConversionFormModel) -> String {
        var x = "<ConversionCertificateOfPaperToElectronicDocument xmlns=\"\(OfficialForm.clause_1_3.namespace)\">"
        x += "<OriginalDocumentInfo>"
        x += element("OriginalDocumentName", m.originalDocumentName)
        x += element("OriginalDocumentNumberOfSheets", String(m.numberOfSheets))
        x += element("OriginalDocumentNonEmptyPageCount", String(m.nonEmptyPageCount))
        for size in m.paperSizes {
            x += "<OriginalDocumentPaperSize>"
            x += "<PaperSize>\(codelist(ZakoCodelists.paperSize, size.item))</PaperSize>"
            if let other = size.other { x += element("PaperSizeOther", other) }
            x += element("PaperSizeNumberOfSheets", String(size.sheets))
            x += "</OriginalDocumentPaperSize>"
        }
        for entry in m.securityElements {
            x += "<DocumentSecurityElementsDetails>"
            x += "<OriginalDocumentSecurityElementsDescription>\(codelist(ZakoCodelists.securityElementDescription, entry.description))</OriginalDocumentSecurityElementsDescription>"
            if let other = entry.descriptionOther { x += element("OriginalDocumentSecurityElementsDescriptionOther", other) }
            x += element("OriginalDocumentSecurityElementsPage", String(entry.originalPage))
            x += element("OriginalDocumentSecurityElementsSheet", String(entry.originalSheet))
            x += "<OriginalDocumentSecurityElementsLocation>\(codelist(ZakoCodelists.securityElementLocation, entry.location))</OriginalDocumentSecurityElementsLocation>"
            x += element("NewDocumentSecurityElementsPage", String(entry.newPage))
            x += "</DocumentSecurityElementsDetails>"
        }
        x += "</OriginalDocumentInfo>"
        x += "<NewDocumentInfo>"
        x += element("NewDocumentName", m.newDocumentName)
        x += "<NewDocumentFormat>\(codelist(ZakoCodelists.newDocumentFormat, m.newDocumentFormat))</NewDocumentFormat>"
        x += element("ElectronicFingerprintValue", m.fingerprintBase64)
        x += "<ElectronicFingerprintCalculationMethod>\(codelist(ZakoCodelists.fingerprintMethod, m.fingerprintMethod))</ElectronicFingerprintCalculationMethod>"
        x += "</NewDocumentInfo>"
        x += element("ConversionRecordEvidenceNumber", m.evidenceNumberURI)
        x += element("ConversionExecutionDateTime", m.conversionTimeText)
        x += "<PersonPerformingConversion><PersonData><PhysicalPerson><PersonName>"
        if !m.person.givenName.isEmpty { x += element("GivenName", m.person.givenName) }
        if !m.person.familyName.isEmpty { x += element("FamilyName", m.person.familyName) }
        x += "</PersonName>"
        if !m.person.position.isEmpty { x += element("Position", m.person.position) }
        x += "</PhysicalPerson>"
        x += "<LegalSubject>\(element("Name", m.person.legalSubjectName))</LegalSubject>"
        if let uri = m.person.legalSubjectURI {
            x += "<ID><IdentifierType>\(codelist(ZakoCodelists.identifierType, ZakoCodelists.icoIdentifierItem))</IdentifierType>"
            x += element("IdentifierValue", uri) + "</ID>"
        }
        x += "</PersonData></PersonPerformingConversion>"
        x += "</ConversionCertificateOfPaperToElectronicDocument>"
        return x
    }

    private func element(_ name: String, _ value: String) -> String {
        "<\(name)>\(AttestationClauseGenerator.escape(value))</\(name)>"
    }

    private func codelist(_ code: Int, _ item: ZakoCodelistItem) -> String {
        "<Codelist><CodelistCode>\(code)</CodelistCode><CodelistItem><ItemCode>\(AttestationClauseGenerator.escape(item.code))</ItemCode><ItemName Language=\"sk\">\(AttestationClauseGenerator.escape(item.skName))</ItemName></CodelistItem></Codelist>"
    }
}
```

`AttestationClauseGenerator.escape` is `static` (internal) and reachable from the same module.

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConversionCertificateRendererTests`
Expected: 5 tests, PASS. If the schema rejects an element, the failure prints the `xmllint` line; fix the order or type in the renderer to match `docs/reference/forms/clause-1.3/schema.xsd`, never the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/Chevron7Kit/Attestation/Forms/ConversionCertificateRenderer.swift Tests/Chevron7KitTests/ConversionCertificateRendererTests.swift
git commit -m "feat(zako): render the conversion clause 1.3

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: XMLDataContainer builder

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/XMLDataContainerBuilder.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/XMLDataContainerBuilderTests.swift`

**Interfaces:**
- Consumes: `OfficialForm` (Task 1).
- Produces: `public enum XMLDataContainerBuilder { public static let namespace: String; public static func build(formXML: String, form: OfficialForm) -> Data }`.

- [ ] **Step 1: Write the failing tests**

The expected reference block below is copied from the record EZZK accepted (`EXAMPLES/ezzk-records/1563-260824-1.record.asice`); it holds no personal data.

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class XMLDataContainerBuilderTests: XCTestCase {
    func testRecordEnvelopeMatchesTheRecordEZZKAccepted() {
        let text = String(decoding: XMLDataContainerBuilder.build(formXML: "<ConversionRecord/>", form: .record_1_0), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?><XMLDataContainer xmlns=\"http://data.gov.sk/def/container/xmldatacontainer+xml/1.1\"><XMLData ContentType=\"application/xml; charset=UTF-8\" Identifier=\"http://data.gov.sk/doc/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0\" Version=\"1.0\"><ConversionRecord/></XMLData>"), text)
        XCTAssertTrue(text.hasSuffix("<UsedSchemasReferenced><UsedXSDReference DigestMethod=\"urn:oid:2.16.840.1.101.3.4.2.1\" DigestValue=\"V8kKaM40HWD1QVmPG3ANlZWAylZk0wmzvg0ghiXptA8=\" TransformAlgorithm=\"http://www.w3.org/TR/2001/REC-xml-c14n-20010315\">https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0/form.xsd</UsedXSDReference><UsedPresentationSchemaReference ContentType=\"application/xslt+xml\" DigestMethod=\"urn:oid:2.16.840.1.101.3.4.2.1\" DigestValue=\"TYaNJLG/51TOIF8aFEcTQw72vudBAtYZUOkOfRG87as=\" MediaDestinationTypeDescription=\"TXT\" TransformAlgorithm=\"http://www.w3.org/TR/2001/REC-xml-c14n-20010315\">https://data.gov.sk/id/egov/eform/50349287.ConversionRecordOfPaperToElectronicDocument.sk/1.0/form.xslt</UsedPresentationSchemaReference></UsedSchemasReferenced></XMLDataContainer>"), text)
    }

    func testClauseEnvelopeIsWellFormedAndNamesTheClauseForm() throws {
        let data = XMLDataContainerBuilder.build(formXML: "<ConversionCertificateOfPaperToElectronicDocument xmlns=\"\(OfficialForm.clause_1_3.namespace)\"/>", form: .clause_1_3)
        let document = try XMLDocument(data: data)
        let xmlData = try XCTUnwrap(document.rootElement()?.elements(forName: "XMLData").first)
        XCTAssertEqual(xmlData.attribute(forName: "Identifier")?.stringValue, OfficialForm.clause_1_3.identifier)
        XCTAssertEqual(xmlData.attribute(forName: "Version")?.stringValue, "1.3")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("MediaDestinationTypeDescription=\"HTML\""))
        XCTAssertTrue(text.contains(">\(OfficialForm.clause_1_3.namespace)/form.xsd</UsedXSDReference>"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter XMLDataContainerBuilderTests`
Expected: compile error, `cannot find 'XMLDataContainerBuilder' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Wraps a form document into an XMLDataContainer 1.1 exactly as the record EZZK accepted
/// on 2026-08-24: schema and presentation referenced by URI with C14N SHA-256 digests.
public enum XMLDataContainerBuilder {
    public static let namespace = "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1"
    private static let sha256 = "urn:oid:2.16.840.1.101.3.4.2.1"
    private static let c14n = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"

    /// `formXML` is the form's root element without an XML declaration.
    public static func build(formXML: String, form: OfficialForm) -> Data {
        precondition(!formXML.hasPrefix("<?xml"), "pass the form element without an XML declaration")
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        x += "<XMLDataContainer xmlns=\"\(namespace)\">"
        x += "<XMLData ContentType=\"application/xml; charset=UTF-8\" Identifier=\"\(form.identifier)\" Version=\"\(form.version)\">"
        x += formXML
        x += "</XMLData><UsedSchemasReferenced>"
        x += "<UsedXSDReference DigestMethod=\"\(sha256)\" DigestValue=\"\(form.schemaDigestBase64)\" TransformAlgorithm=\"\(c14n)\">\(form.schemaURI)</UsedXSDReference>"
        x += "<UsedPresentationSchemaReference ContentType=\"application/xslt+xml\" DigestMethod=\"\(sha256)\" DigestValue=\"\(form.presentationDigestBase64)\" MediaDestinationTypeDescription=\"\(form.presentationMediaDestination)\" TransformAlgorithm=\"\(c14n)\">\(form.presentationURI)</UsedPresentationSchemaReference>"
        x += "</UsedSchemasReferenced></XMLDataContainer>"
        return Data(x.utf8)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter XMLDataContainerBuilderTests`
Expected: 2 tests, PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Chevron7Kit/Attestation/Forms/XMLDataContainerBuilder.swift Tests/Chevron7KitTests/XMLDataContainerBuilderTests.swift
git commit -m "feat(zako): build XMLDataContainer 1.1 as EZZK accepts it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Engine signs attachments into one ASiC-E

**Files (all under `engine/src/main/java/digital/slovensko/autogram/`):**
- Modify: `ui/machine/MachineFile.java`
- Modify: `ui/machine/MachineCliApp.java:195-217` (sign request parsing)
- Modify: `ui/machine/MachineRequestValidator.java:48-68, 80-96, 176`
- Modify: `ui/machine/MachineSigningService.java` (`PreparedFile`, `SigningInput`, `DefaultSigningSession.sign`, `signingJob`)
- Modify: `core/SigningJob.java`
- Test: `engine/src/test/java/digital/slovensko/autogram/ui/machine/MachineSigningServiceTest.java`, `MachineRequestValidatorTest.java`, `MachineCliAppTest.java`

**Interfaces:**
- Produces: machine protocol v1 SIGN file object `{"id","source","target","attachments":[<absolute path>, ...]}` (1 to 8 paths; only with `XAdES_BASELINE_T` or `XAdES_BASELINE_B`, never with an eForm). The result is one ASiC-E whose signature references the source and every attachment; `.xdcf` attachments carry MIME `application/vnd.gov.sk.xmldatacontainer+xml`. INSPECT keeps rejecting `attachments`.

- [ ] **Step 1: Write the failing signing test in `MachineSigningServiceTest`**

Add these imports if missing: `java.util.zip.ZipInputStream`, `java.io.ByteArrayInputStream`, `digital.slovensko.autogram.core.SigningKey`, `digital.slovensko.autogram.AutogramTests`, `java.util.Objects`, `java.util.ArrayList`.

```java
    /// ZaKo hands the PDF/A and the clause XDC as two documents. They must become two data
    /// objects of one ASiC-E, never a container nested inside another.
    @Test
    void attachmentsAreSignedAsDataObjectsOfOneContainer() throws Exception {
        var pdf = Files.readAllBytes(Path.of(MachineSigningServiceTest.class
                .getResource("/digital/slovensko/autogram/sample.pdf").getFile()));
        var xdcf = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><XMLDataContainer xmlns=\"http://data.gov.sk/def/container/xmldatacontainer+xml/1.1\"/>"
                .getBytes(java.nio.charset.StandardCharsets.UTF_8);
        var retained = new MemoryRetainedFile();
        var responder = new MachineFileResponder(retained, () -> { });
        var settings = new MachineSettings(true);
        settings.setSignatureLevel(SignatureLevel.XAdES_BASELINE_B);

        var job = MachineSigningService.DefaultSigningSession.signingJob(pdf, "/tmp/dokument.pdf", responder, settings,
                null, List.of(new MachineSigningService.AttachmentContent("dokument.xml.xdcf", xdcf)));
        var token = new Pkcs12SignatureToken(
                Objects.requireNonNull(AutogramTests.class.getResource("test.keystore")).getFile(),
                new KeyStore.PasswordProtection("".toCharArray()));
        job.signWithKeyAndRespond(new SigningKey(token, token.getKeys().get(0)));

        var names = new ArrayList<String>();
        String manifest = null;
        String signature = null;
        try (var zip = new ZipInputStream(new ByteArrayInputStream(retained.readAll()))) {
            for (var entry = zip.getNextEntry(); entry != null; entry = zip.getNextEntry()) {
                names.add(entry.getName());
                var content = new String(zip.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
                if (entry.getName().equals("META-INF/manifest.xml")) manifest = content;
                if (entry.getName().startsWith("META-INF/signatures")) signature = content;
            }
        }
        assertTrue(names.contains("dokument.pdf"), names.toString());
        assertTrue(names.contains("dokument.xml.xdcf"), names.toString());
        assertTrue(names.stream().noneMatch(name -> name.endsWith(".asice")), names.toString());
        assertTrue(manifest.contains("manifest:full-path=\"dokument.xml.xdcf\" manifest:media-type=\"application/vnd.gov.sk.xmldatacontainer+xml\""), manifest);
        assertTrue(signature.contains("URI=\"dokument.pdf\""), signature);
        assertTrue(signature.contains("URI=\"dokument.xml.xdcf\""), signature);
    }

    @Test
    void attachmentsNeedAnAsicESignature() {
        var settings = new MachineSettings(true);
        settings.setSignatureLevel(SignatureLevel.PAdES_BASELINE_T);
        settings.setTsaServer("https://tsa.example.test");
        settings.setTsaEnabled(true);
        assertThrows(java.io.IOException.class, () -> MachineSigningService.DefaultSigningSession.signingJob(
                Files.readAllBytes(Path.of(MachineSigningServiceTest.class
                        .getResource("/digital/slovensko/autogram/sample.pdf").getFile())),
                "/tmp/dokument.pdf", new MachineFileResponder(new MemoryRetainedFile(), () -> { }), settings, null,
                List.of(new MachineSigningService.AttachmentContent("a.xml.xdcf", new byte[] { '<', 'a', '/', '>' }))));
    }
```

Check `MemoryRetainedFile.readAll()` returns what `MachineFileResponder` wrote (it is the class used by the other `signingJob` tests). If `manifest:full-path` and `manifest:media-type` appear in another attribute order in DSS output, assert the two attributes separately.

- [ ] **Step 2: Write the failing parser and validator tests**

In `MachineCliAppTest` add a test that feeds a v1 SIGN request whose file carries `"attachments": ["/abs/a.xml.xdcf"]` through the same entry point the existing SIGN parsing tests use, and asserts the parsed `MachineFile.attachments()` equals `List.of("/abs/a.xml.xdcf")`; and one asserting that an INSPECT file with `attachments` is `PROTOCOL_INVALID_REQUEST`. Follow the request-building helper that the existing SIGN tests in that class use (search the class for `"certificateSerial"`).

In `MachineRequestValidatorTest` add:

```java
    @Test
    void attachmentsAreRefusedOutsideAsicE() {
        var request = new SignRequest("drv", "1", "1234".toCharArray(), "PAdES_BASELINE_T",
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")),
                List.of(new MachineFile("doc", "/abs/doc.pdf", "/abs/out.pdf", null, List.of("/abs/a.xml.xdcf"))));
        var error = assertThrows(MachineProtocolException.class, () -> MachineRequestValidator.validateSign(request));
        assertEquals("PROTOCOL_INVALID_REQUEST", error.getMessage());
    }

    @Test
    void anAttachmentMayNotRepeatTheSource() throws Exception {
        var dir = Files.createTempDirectory("attachments");
        var source = Files.writeString(dir.resolve("doc.pdf"), "%PDF-1.7");
        var request = new SignRequest("drv", "1", "1234".toCharArray(), "XAdES_BASELINE_T",
                new QualifiedTimestampRequest(true, List.of("https://tsa.example.test")),
                List.of(new MachineFile("doc", source.toRealPath().toString(), dir.toRealPath().resolve("out.asice").toString(),
                        null, List.of(source.toRealPath().toString()))));
        assertThrows(MachineProtocolException.class, () -> MachineRequestValidator.validateSign(request));
    }
```

If `MachineProtocolException.getMessage()` is not the code in this codebase, compare with the accessor the other tests in the class use.

- [ ] **Step 3: Run the engine tests to verify they fail**

Run: `cd engine && JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q -Dtest='MachineSigningServiceTest,MachineRequestValidatorTest,MachineCliAppTest' test`
Expected: compilation failure (`AttachmentContent`, the 5-argument `MachineFile`, the 6-argument `signingJob`).

- [ ] **Step 4: `MachineFile.java`**

```java
package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.ui.machine.v2.VisibleSignatureAppearance;

import java.util.List;

/// One machine protocol file. `attachments` are further documents signed together with the
/// source as separate data objects of one ASiC-E (ZaKo: the PDF/A and its clause XDC).
public record MachineFile(String id, String source, String target, VisibleSignatureAppearance.Snapshot visibleAppearance,
        List<String> attachments) {
    public MachineFile {
        attachments = attachments == null ? List.of() : List.copyOf(attachments);
    }

    public MachineFile(String id, String source, String target, VisibleSignatureAppearance.Snapshot visibleAppearance) {
        this(id, source, target, visibleAppearance, List.of());
    }

    public MachineFile(String id, String source, String target) {
        this(id, source, target, null, List.of());
    }
}
```

- [ ] **Step 5: `MachineCliApp.java`: parse attachments on SIGN only**

Replace, in `requiredSignRequest`, `var files = requiredInspectionRequest(filesPayload(payload.get("files"))).files();` with `var files = requiredSignFiles(payload.get("files"));` and add:

```java
    private static List<MachineFile> requiredSignFiles(JsonElement filesElement) {
        if (filesElement == null || !filesElement.isJsonArray() || filesElement.getAsJsonArray().isEmpty()) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
        }
        var files = new ArrayList<MachineFile>();
        for (var element : filesElement.getAsJsonArray()) {
            if (!element.isJsonObject()) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            var file = element.getAsJsonObject();
            var hasAttachments = file.has("attachments");
            if (file.size() != (hasAttachments ? 4 : 3) || !file.has("id") || !file.has("source") || !file.has("target")
                    || !isNonBlankString(file.get("id")) || !isNonBlankString(file.get("source"))
                    || !isNonBlankString(file.get("target"))) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            var attachments = new ArrayList<String>();
            if (hasAttachments) {
                var value = file.get("attachments");
                if (!value.isJsonArray() || value.getAsJsonArray().isEmpty() || value.getAsJsonArray().size() > 8) {
                    throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
                }
                for (var attachment : value.getAsJsonArray()) {
                    if (!isNonBlankString(attachment)) {
                        throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
                    }
                    attachments.add(attachment.getAsString());
                }
            }
            var source = file.get("source").getAsString();
            var target = file.get("target").getAsString();
            try {
                java.nio.file.Path.of(source);
                java.nio.file.Path.of(target);
                for (var attachment : attachments) {
                    java.nio.file.Path.of(attachment);
                }
            } catch (java.nio.file.InvalidPathException exception) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST", exception);
            }
            files.add(new MachineFile(file.get("id").getAsString(), source, target, null, attachments));
        }
        return List.copyOf(files);
    }
```

Remove `filesPayload` if nothing else uses it.

- [ ] **Step 6: `MachineRequestValidator.java`**

Change the record at the end of the file:

```java
record ValidatedMachineFile(MachineFile file, Path source, Path target, List<Path> attachments) {
    ValidatedMachineFile(MachineFile file, Path source, Path target) {
        this(file, source, target, List.of());
    }
}
```

In `validateSign`, before the final `return`:

```java
        var hasAttachments = request.files().stream().anyMatch(file -> file != null && !file.attachments().isEmpty());
        if (hasAttachments && (request.eform() != null || !request.signatureLevel().startsWith("XAdES_"))) {
            throw invalidRequest();
        }
```

In `validateFiles`, replace `validated.add(new ValidatedMachineFile(file, source, target));` with:

```java
            var seen = new HashSet<Path>();
            seen.add(source);
            var attachments = new ArrayList<Path>();
            for (var attachment : file.attachments()) {
                var path = canonicalSource(attachment);
                if (!seen.add(path)) {
                    throw invalidRequest();
                }
                attachments.add(path);
            }
            validated.add(new ValidatedMachineFile(file, source, target, List.copyOf(attachments)));
```

- [ ] **Step 7: `MachineSigningService.java`**

Add a nested record next to `SigningInput`:

```java
    public record AttachmentContent(String name, byte[] content) {
        public AttachmentContent {
            content = content.clone();
        }
    }
```

Change `SigningInput`:

```java
    record SigningInput(MachineFile file, byte[] sourceContent, MachineSigningFileSystem.RetainedFile source,
            MachineSigningFileSystem.RetainedFile staging, List<AttachmentContent> attachments) {
        SigningInput {
            sourceContent = sourceContent.clone();
            attachments = List.copyOf(attachments);
        }

        SigningInput(MachineFile file, byte[] sourceContent, MachineSigningFileSystem.RetainedFile source,
                MachineSigningFileSystem.RetainedFile staging) {
            this(file, sourceContent, source, staging, List.of());
        }
```
(keep the existing methods of the record below the constructors).

In `PreparedFile`: add a field `private final List<AttachmentContent> attachments;`, a constructor parameter for it, and in `prepare(...)` after `sourceContent` is read:

```java
                var attachments = new ArrayList<AttachmentContent>();
                for (var path : validated.attachments()) {
                    attachments.add(new AttachmentContent(path.getFileName().toString(), Files.readAllBytes(path)));
                }
```
pass `List.copyOf(attachments)` to the constructor, and change `signingInput()` to `return new SigningInput(file, sourceContent.clone(), source, staging, attachments);`.

In `DefaultSigningSession.sign`:

```java
            var job = signingJob(input.sourceContent(), input.file().source(), responder, settings,
                    input.file().visibleAppearance(), input.attachments());
```

Keep the existing 4- and 5-argument `signingJob` overloads delegating with `List.of()`, and add:

```java
        static SigningJob signingJob(byte[] source, String name, MachineFileResponder responder, MachineSettings settings,
                VisibleSignatureAppearance.Snapshot appearance, List<AttachmentContent> attachments) throws Exception {
            var filename = Path.of(name).getFileName().toString();
            var document = new InMemoryDocument(source, filename, detectMimeType(filename, source));
            var parameters = signingParameters(document, settings);
            if (appearance != null) {
                var field = appearance.appearance();
                parameters.setVisiblePadesAppearance(appearance.pngBytes(), field.page(), field.originX(), field.originY(),
                        field.width(), field.height(), field.signingTime());
            }
            if (attachments.isEmpty()) {
                return SigningJob.buildFromRequest(document, parameters, responder);
            }
            if (parameters.getContainer() != ASiCContainerType.ASiC_E || parameters.getSignatureType() != SignatureForm.XAdES) {
                throw new IOException("Attachments need an ASiC-E XAdES signature");
            }
            var extra = new ArrayList<DSSDocument>();
            for (var attachment : attachments) {
                var mime = attachment.name().toLowerCase(java.util.Locale.ROOT).endsWith(".xdcf")
                        ? AutogramMimeType.XML_DATACONTAINER
                        : detectMimeType(attachment.name(), attachment.content());
                extra.add(new InMemoryDocument(attachment.content(), attachment.name(), mime));
            }
            return SigningJob.buildFromRequest(document, parameters, responder, extra);
        }
```

Make the previous 5-argument `signingJob(..., appearance)` delegate to this one with `List.of()`. Add the imports this needs (`eu.europa.esig.dss.model.DSSDocument`, `java.util.ArrayList`, `java.nio.file.Files` if missing). For a PAdES level `signingParameters` returns PAdES parameters, so the guard throws before anything is signed.

- [ ] **Step 8: `SigningJob.java`**

```java
    private final List<DSSDocument> extraDocuments;

    private SigningJob(DSSDocument document, SigningParameters parameters, Responder responder,
            List<DSSDocument> extraDocuments) {
        this.document = document;
        this.parameters = parameters;
        this.responder = responder;
        this.extraDocuments = List.copyOf(extraDocuments);
    }
```

Update `build(...)` to take `List<DSSDocument> extraDocuments` and pass it on; `buildFromRequest(document, params, responder)` and `buildFromFile(...)` call it with `List.of()`; add

```java
    public static SigningJob buildFromRequest(DSSDocument document, SigningParameters params, Responder responder,
            List<DSSDocument> extraDocuments) {
        return build(document, params, responder, extraDocuments);
    }
```

In `signDocumentAsAsiCWithXAdeS`, replace the last three lines with:

```java
        if (extraDocuments.isEmpty()) {
            var dataToSign = service.getDataToSign(getDocument(), signatureParameters);
            var signatureValue = key.sign(dataToSign, getParameters().getDigestAlgorithm());
            return service.signDocument(getDocument(), signatureParameters, signatureValue);
        }
        var documents = new ArrayList<DSSDocument>();
        documents.add(getDocument());
        documents.addAll(extraDocuments);
        var dataToSign = service.getDataToSign(documents, signatureParameters);
        var signatureValue = key.sign(dataToSign, getParameters().getDigestAlgorithm());
        return service.signDocument(documents, signatureParameters, signatureValue);
```

Add `import java.util.ArrayList;` and `import java.util.List;` if missing.

- [ ] **Step 9: Run the engine tests**

Run: `cd engine && JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q -Dtest='MachineSigningServiceTest,MachineRequestValidatorTest,MachineCliAppTest' test`
Expected: PASS.
Run: `cd engine && JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca ./mvnw -q test`
Expected: PASS (whole engine suite).

- [ ] **Step 10: Rebuild the engine and commit**

Run: `cd Chevron7 && AUTOGRAM_JAVA_HOME=$HOME/.sdkman/candidates/java/25.0.4.fx-librca scripts/build-engine.sh`
Expected: ends with `✔ Engine:` (a `Killed: 9` line after the smoke test is normal).

```bash
git add engine
git commit -m "feat(engine): sign attachments as data objects of one ASiC-E

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Swift bridge carries attachments

**Files:**
- Modify: `Chevron7/Sources/Chevron7Kit/EngineBridge/Models/SigningModels.swift:34-48`
- Modify: `Chevron7/Sources/Chevron7Kit/EngineBridge/CLI/AutogramCLIEngine.swift` (v1 `machineFile`, its call site near line 227)
- Modify: `Chevron7/Sources/Chevron7Kit/Signing/SigningProvider.swift:241-280` (`SigningRequest`)
- Modify: `Chevron7/Sources/Chevron7Kit/Signing/JavaEngine/EngineBridgeSigningProvider.swift:362-392`
- Test: `Chevron7/Tests/Chevron7KitTests/EngineBridgeTests.swift`

**Interfaces:**
- Consumes: engine protocol from Task 7.
- Produces: `SigningFile(id:sourceURL:visibleAppearance:attachmentURLs:)` (default `[]`); `SigningRequest.signsExtraFilesAsDataObjects: Bool` (default `false`). When `true` and the output is ASiC-E, the provider writes `pdfData` under `filename` and every `extraFiles` entry that is not `mimetype`, not under `META-INF/` and not named `filename` as an attachment, instead of packaging `kontajner.asice`. The v1 file JSON gains `"attachments"` only when non-empty.

- [ ] **Step 1: Write the failing tests**

Find the existing test in `EngineBridgeTests.swift` that inspects the v1 SIGN payload the engine receives (search for `"certificateSerial"` or `payload`), copy its setup, and add a case with `SigningFile(id: "document", sourceURL: pdfURL, attachmentURLs: [xdcfURL])` asserting the encoded file object is `{"id","source","target","attachments":[canonical xdcf path]}`, plus a case without attachments asserting the key is absent.

For the provider, add to the test class that exercises `EngineBridgeSigningProvider.sign` with a fake engine (search for `EngineBridgeSigningProvider(` in the tests): a request with `extraFiles: ASiCEPackager().zakoContainer(pdfData: pdf, pdfFileName: "dokument.pdf", dolozkaXML: xdcf, dolozkaFileName: "dokument.xml.xdcf")`, `filename: "dokument.pdf"`, `signsExtraFilesAsDataObjects: true`, and assert the captured `EngineSigningRequest.files` has one file whose `sourceURL.lastPathComponent == "dokument.pdf"` and whose `attachmentURLs.map(\.lastPathComponent) == ["dokument.xml.xdcf"]`, and that no `kontajner.asice` was written. Keep the existing `extraFiles` case (flag false) asserting `kontajner.asice` as today.

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter EngineBridge`
Expected: compile errors for `attachmentURLs` and `signsExtraFilesAsDataObjects`.

- [ ] **Step 3: `SigningFile`**

```swift
struct SigningFile: Sendable, Equatable, Identifiable {
    let id: String
    let sourceURL: URL
    let visibleAppearance: VisibleSignatureRequest?
    /// Further documents signed with `sourceURL` as data objects of one ASiC-E.
    let attachmentURLs: [URL]

    var redactedDisplayName: String {
        sourceURL.lastPathComponent
    }

    init(id: String, sourceURL: URL, visibleAppearance: VisibleSignatureRequest? = nil, attachmentURLs: [URL] = []) {
        self.id = id
        self.sourceURL = sourceURL
        self.visibleAppearance = visibleAppearance
        self.attachmentURLs = attachmentURLs
    }
}
```

- [ ] **Step 4: `AutogramCLIEngine` v1 encoding**

```swift
    private func machineFile(id: String, sourceURL: URL, targetURL: URL, attachmentURLs: [URL] = []) -> JSONValue {
        // Java validátor vyžaduje reálny canonical path (realpath, /var → /private/var)
        let source = EnginePaths.canonical(sourceURL).path
        let target = EnginePaths.canonical(targetURL).path
        var fields: [String: JSONValue] = [
            "id": .string(id),
            "source": .string(source),
            "target": .string(target)
        ]
        if !attachmentURLs.isEmpty {
            fields["attachments"] = .array(attachmentURLs.map { .string(EnginePaths.canonical($0).path) })
        }
        return .object(fields)
    }
```

At the v1 SIGN call site (near line 227) pass `attachmentURLs: file.attachmentURLs`. Leave INSPECT and v2 call sites as they are.

- [ ] **Step 5: `SigningRequest`**

Add the stored property with a doc comment, an `init` parameter `signsExtraFilesAsDataObjects: Bool = false` at the end of the parameter list, and its assignment:

```swift
    /// ZaKo: sign `pdfData` and the data entries of `extraFiles` as separate data objects of
    /// one ASiC-E the engine builds, instead of wrapping a packaged container.
    public var signsExtraFilesAsDataObjects: Bool
```

- [ ] **Step 6: `EngineBridgeSigningProvider`**

Before the `else if !wantsPAdES, !request.extraFiles.isEmpty` branch, add a branch and collect attachment URLs used later when building `SigningFile`:

```swift
        var attachmentURLs: [URL] = []
        if request.eform != nil {
            // unchanged
        } else if !wantsPAdES, request.signsExtraFilesAsDataObjects {
            let name = request.filename.map { ($0 as NSString).lastPathComponent } ?? Self.pdfSourceName(for: request)
            sourceURL = workDirectory.appendingPathComponent(name)
            try request.pdfData.write(to: sourceURL, options: [.atomic])
            for entry in request.extraFiles
            where entry.path != "mimetype" && !entry.path.hasPrefix("META-INF/") && entry.path != name {
                let url = workDirectory.appendingPathComponent(ASiCEPackager.sanitizedFileName(entry.path))
                try entry.data.write(to: url, options: [.atomic])
                attachmentURLs.append(EnginePaths.canonical(url))
            }
        } else if !wantsPAdES, !request.extraFiles.isEmpty {
```

Keep the existing `eform` branch body where it is (the snippet only shows the order). Then build the file as `SigningFile(id: "document", sourceURL: EnginePaths.canonical(sourceURL), visibleAppearance: appearanceRequest, attachmentURLs: attachmentURLs)`. Check `ASiCEPackager.sanitizedFileName` keeps a plain name like `dokument.xml.xdcf` unchanged; if it changes it, use `(entry.path as NSString).lastPathComponent`.

- [ ] **Step 7: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter EngineBridge`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/Chevron7Kit Tests/Chevron7KitTests/EngineBridgeTests.swift
git commit -m "feat(signing): pass ZaKo attachments to the engine as data objects

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Clause delivery builder

**Files:**
- Create: `Chevron7/Sources/Chevron7Kit/Attestation/Forms/ZakoClauseDeliveryBuilder.swift`
- Test: `Chevron7/Tests/Chevron7KitTests/ZakoClauseDeliveryBuilderTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 6.
- Produces:

```swift
public struct ZakoClauseDelivery: Sendable {
    public let model: ConversionFormModel
    public let clauseXML: String
    public let clauseXDCF: Data
}
public struct ZakoClauseDeliveryBuilder: Sendable {
    public init(validator: FormSchemaValidator = FormSchemaValidator())
    public func build(finalPDF: Data, attestation: AttestationData, securityElements: [SecurityElement],
                      originalNonEmptyPageIndices: [Int]?, usedDevice: String) throws -> ZakoClauseDelivery
}
```

- [ ] **Step 1: Write the failing test**

The fake `signatures001.xml` below gives `ASiCEContainerVerifier` real digests, a SignedProperties reference and a `SignatureTimeStamp`, so `P2EConformanceValidator` judges only the clause and the container layout.

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import CryptoKit
@testable import Chevron7Kit

final class ZakoClauseDeliveryBuilderTests: XCTestCase {
    override func setUpWithError() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint") else {
            throw XCTSkip("xmllint is needed for schema validation.")
        }
    }

    func testDeliveredContainerPassesTheConformanceValidator() throws {
        let pdf = Data("%PDF-1.7 synthetic delivered bytes".utf8)
        let attestation = ConversionFormModelTests.attestation()
        let delivery = try ZakoClauseDeliveryBuilder().build(
            finalPDF: pdf, attestation: attestation,
            securityElements: [ConversionFormModelTests.scanElement()],
            originalNonEmptyPageIndices: [0], usedDevice: "Chevron7 v0.5.0")

        XCTAssertEqual(delivery.model.fingerprintBase64, Data(SHA256.hash(data: pdf)).base64EncodedString())

        var entries = ASiCEPackager().zakoContainer(pdfData: pdf, pdfFileName: "dokument.pdf",
                                                     dolozkaXML: delivery.clauseXDCF,
                                                     dolozkaFileName: "1563-260824-1.xml.xdcf")
        entries.append(ASiCEPackager.Entry(path: "META-INF/signatures001.xml",
                                           data: Self.fakeSignature(for: [("dokument.pdf", pdf),
                                                                          ("1563-260824-1.xml.xdcf", delivery.clauseXDCF)])))
        let asic = try ASiCEPackager().package(files: entries)
        let result = P2EConformanceValidator().validate(
            clauseASiC: asic,
            context: .init(expectedPDFData: pdf, expectedEvidenceNumber: "1563-260824-1",
                           expectedConversionTime: attestation.conversionExecutionDateTime))
        XCTAssertTrue(result.isValid, result.issues.joined(separator: "\n"))
    }

    func testInvalidModelNeverReachesTheContainer() {
        var attestation = ConversionFormModelTests.attestation()
        attestation.originalDocumentName = ""
        XCTAssertThrowsError(try ZakoClauseDeliveryBuilder().build(
            finalPDF: Data("%PDF".utf8), attestation: attestation, securityElements: [],
            originalNonEmptyPageIndices: nil, usedDevice: "Chevron7"))
    }

    static func fakeSignature(for objects: [(String, Data)]) -> Data {
        let references = objects.map { name, data in
            "<ds:Reference URI=\"\(name)\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/><ds:DigestValue>\(Data(SHA256.hash(data: data)).base64EncodedString())</ds:DigestValue></ds:Reference>"
        }.joined()
        let xml = "<asic:XAdESSignatures xmlns:asic=\"http://uri.etsi.org/02918/v1.2.1#\" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\" xmlns:xades=\"http://uri.etsi.org/01903/v1.3.2#\"><ds:Signature Id=\"s\"><ds:SignedInfo>\(references)<ds:Reference Type=\"http://uri.etsi.org/01903#SignedProperties\" URI=\"#xades-s\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/><ds:DigestValue>AA==</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:Object><xades:QualifyingProperties><xades:UnsignedProperties><xades:UnsignedSignatureProperties><xades:SignatureTimeStamp/></xades:UnsignedSignatureProperties></xades:UnsignedProperties></xades:QualifyingProperties></ds:Object></ds:Signature></asic:XAdESSignatures>"
        return Data(xml.utf8)
    }
}
```

An empty `originalDocumentName` violates `StringMax255ReqType` (`minLength 1`), so the schema check refuses it.

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoClauseDeliveryBuilderTests`
Expected: compile error, `cannot find 'ZakoClauseDeliveryBuilder' in scope`.

- [ ] **Step 3: Implement**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public struct ZakoClauseDelivery: Sendable {
    public let model: ConversionFormModel
    public let clauseXML: String
    public let clauseXDCF: Data
}

/// Turns the delivered PDF/A bytes and the ZaKo state into the validated clause XDC that is
/// signed beside the PDF. The fingerprint is taken over exactly the bytes the client receives.
public struct ZakoClauseDeliveryBuilder: Sendable {
    private let validator: FormSchemaValidator

    public init(validator: FormSchemaValidator = FormSchemaValidator()) {
        self.validator = validator
    }

    public func build(finalPDF: Data, attestation: AttestationData, securityElements: [SecurityElement],
                      originalNonEmptyPageIndices: [Int]?, usedDevice: String) throws -> ZakoClauseDelivery {
        let model = try ConversionFormModel.make(
            attestation: attestation,
            securityElements: securityElements,
            newDocumentSHA256Hex: AttestationClauseGenerator.sha256Hex(of: finalPDF),
            originalNonEmptyPageIndices: originalNonEmptyPageIndices,
            usedDevice: usedDevice)
        let xml = ConversionCertificateRenderer().render(model)
        try validator.validate(Data(xml.utf8), against: .clause_1_3)
        return ZakoClauseDelivery(model: model, clauseXML: xml,
                                  clauseXDCF: XMLDataContainerBuilder.build(formXML: xml, form: .clause_1_3))
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoClauseDeliveryBuilderTests`
Expected: PASS. If `P2EConformanceValidator` reports a clause-field issue, the renderer or the model is wrong: fix them there. If it reports a structural issue of the fake signature, adjust `fakeSignature` to what `ASiCEContainerVerifier.verify` reads (`ASiCEPackager.swift` neighbourhood, `ASiCEContainerVerifier`), never the validator.

- [ ] **Step 5: Commit**

```bash
git add Sources/Chevron7Kit/Attestation/Forms/ZakoClauseDeliveryBuilder.swift Tests/Chevron7KitTests/ZakoClauseDeliveryBuilderTests.swift
git commit -m "feat(zako): build the validated clause XDC from the delivered PDF

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Wire the clause route into `ZakoSessionStore`

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift:1123-1260` (`authorizeAndSign`)
- Test: `Chevron7/Tests/Chevron7AppTests/ZakoClauseRouteTests.swift`

**Interfaces:**
- Consumes: `ZakoClauseDeliveryBuilder` (Task 9), `SigningRequest.signsExtraFilesAsDataObjects` (Task 8).
- Produces: the ZaKo output folder holds the signed ASiC-E (PDF/A plus clause XDC), the PDF/A without embedded XML, and the clause `.xml.xdcf` (XDC, not bare XML). The register row keeps `attestationXML` from `AttestationClauseGenerator` (record path, replaced in B2).

- [ ] **Step 1: Change `authorizeAndSign`**

Replace the block from `let fingerprint = AttestationClauseGenerator.sha256Hex(of: pdfaData)` through the `PDFAValidator` check with:

```swift
            // The clause fingerprints the exact bytes the client receives, so nothing may be
            // embedded or rewritten after this point (spec: Facts, fingerprint and embedding).
            let finalPDF = try pdfaConverter.normalizeForDelivery(pdfaData, title: attestation.newDocumentName)
            let pdfaCheck = PDFAValidator().validate(finalPDF, profile: selectedFormPack.outputProfile)
            guard pdfaCheck.isValid else {
                throw ComplianceValidationError(domain: "PDF/A-2b", issues: pdfaCheck.issues)
            }
            let fingerprint = AttestationClauseGenerator.sha256Hex(of: finalPDF)
            let nonEmptyPageIndices = analysis.pageAnalyses.filter { !$0.isEmpty }.map(\.pageIndex)

            analysisProgressText = "Vytváram osvedčovaciu doložku…"
            let clause = try ZakoClauseDeliveryBuilder().build(
                finalPDF: finalPDF,
                attestation: attestation,
                securityElements: confirmedElementsSnapshot,
                originalNonEmptyPageIndices: nonEmptyPageIndices,
                usedDevice: attestation.usedDeviceDescription)

            // Record XML for the register only; part B2 replaces it with the record renderer.
            let xmlInput = AttestationClauseGenerator.Input(
                attestation: attestation,
                securityElements: confirmedElementsSnapshot,
                newDocumentFingerprintSHA256Hex: fingerprint,
                originalNonEmptyPageIndices: nonEmptyPageIndices)
            let xml = try clauseGenerator.generateXML(input: xmlInput, formPack: selectedFormPack)
```

Delete the `AttestationXMLValidator` block, the `embeddedFileService.embed` call and the second `normalizeForDelivery` that followed it (the old record XML is no longer embedded or packed). Keep `let xml` for `EvidenceRecord.attestationXML` and `ConversionRecordEnvelope.attestationXML` as they are.

Then change the container and signing lines:

```swift
            let containerFiles = packager.zakoContainer(pdfData: finalPDF,
                                                        pdfFileName: docFileName,
                                                        dolozkaXML: clause.clauseXDCF,
                                                        dolozkaFileName: xdcfFileName)
```

```swift
                signed = try await signingProvider.sign(SigningRequest(
                    pdfData: finalPDF,
                    identityID: identityID,
                    includeTimestamp: includeQualifiedTimestamp,
                    tsaURL: includeQualifiedTimestamp ? settings.selectedTSAURL : nil,
                    pin: signingPIN.isEmpty ? nil : signingPIN,
                    extraFiles: containerFiles,
                    filename: docFileName,
                    signsExtraFilesAsDataObjects: true))
```

(check the actual `SigningRequest.init` parameter order and name `filename` in `SigningProvider.swift`), and write the XDC instead of the bare XML:

```swift
            try clause.clauseXDCF.write(to: xdcfTarget, options: [.atomic])
```

If `embeddedFileService` has no other use in the file, leave the property (removing it is out of scope).

- [ ] **Step 2: Write a regression test for the source contract**

The full authorization needs a card; the route is pinned by tests in Tasks 7 to 9. This test pins what `ZakoSessionStore` must no longer do, so the old route cannot return unnoticed:

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest

final class ZakoClauseRouteTests: XCTestCase {
    private var source: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Chevron7App/ZakoSessionStore.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testAuthorizationSignsTheClauseAsADataObjectAndEmbedsNothing() throws {
        let text = try source
        XCTAssertTrue(text.contains("ZakoClauseDeliveryBuilder()"))
        XCTAssertTrue(text.contains("signsExtraFilesAsDataObjects: true"))
        XCTAssertFalse(text.contains("osvedcovacia-dolozka.xml"), "the PDF/A must not embed XML after its fingerprint")
        XCTAssertFalse(text.contains("dolozkaXML: Data(xml.utf8)"), "the clause slot must hold the clause XDC, not the record")
    }
}
```

- [ ] **Step 3: Run the app tests and the whole suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoClauseRouteTests`
Expected: PASS.
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS. Tests that asserted the embedded `osvedcovacia-dolozka.xml` or bare XML in the `.xml.xdcf` must be updated to the new contract (XDC with the clause); name each one in the commit message.

- [ ] **Step 4: Commit**

```bash
git add Sources/Chevron7App/ZakoSessionStore.swift Tests
git commit -m "fix(zako): deliver the clause 1.3 beside an unmodified PDF/A

The container carried the conversion record where the clause belongs and
the PDF/A changed after its fingerprint was taken.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Location picker for elements checked on the original

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/Views/PhysicalSecurityElementView.swift:70-92`
- Modify: `Chevron7/Sources/Chevron7Kit/Models/AttestationData.swift` (`AttestationValidator.validate`, physical location check)
- Test: `Chevron7/Tests/Chevron7KitTests/AttestationValidatorLocationTests.swift`

**Interfaces:**
- Consumes: `ZakoCodelists.locationItems`, `locationItem(code:)` (Task 3).
- Produces: `SecurityElement.originalLocation` of a physical-original element holds a codelist 11 code; `AttestationValidator` reports `.physicalElementLocationRequired` unless it does.

- [ ] **Step 1: Write the failing test**

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class AttestationValidatorLocationTests: XCTestCase {
    private func errors(location: String) -> [AttestationValidationError] {
        var element = ConversionFormModelTests.scanElement()
        element.observation = .physicalOriginal
        element.originalLocation = location
        element.newDocumentPageIndex = 0
        return AttestationValidator.validate(ConversionFormModelTests.attestation(),
                                             securityElements: [element], qualifiedTimestampTime: nil)
    }

    func testFreeTextLocationNeedsACodelistChoice() {
        XCTAssertTrue(errors(location: "vpravo dole pri podpise").contains(.physicalElementLocationRequired))
    }

    func testCodelistLocationIsAccepted() {
        XCTAssertFalse(errors(location: "Right down").contains(.physicalElementLocationRequired))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AttestationValidatorLocationTests`
Expected: `testFreeTextLocationNeedsACodelistChoice` FAILS.

- [ ] **Step 3: Validator**

In `AttestationValidator.validate`, replace the physical location check with:

```swift
                if ZakoCodelists.locationItem(code: element.originalLocation.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                    errors.append(.physicalElementLocationRequired)
                }
```

and change the Slovak text of `.physicalElementLocationRequired` to `"Vyberte umiestnenie prvku skontrolovaného na origináli zo zoznamu."`.

- [ ] **Step 4: View**

Replace the `TextField("Umiestnenie na origináli", ...)` in `PhysicalSecurityElementInspector` with:

```swift
            Picker("Umiestnenie na origináli", selection: Binding(
                get: { ZakoCodelists.locationItem(code: element.originalLocation)?.code ?? "" },
                set: { store.updatePhysicalElement(id: element.id, location: $0,
                                                   newDocumentPageIndex: element.newDocumentPageIndex) })) {
                Text("Vyberte umiestnenie").tag("")
                ForEach(ZakoCodelists.locationItems, id: \.code) { item in
                    Text(item.skName).tag(item.code)
                }
            }
```

- [ ] **Step 5: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AttestationValidator`
Expected: PASS. Update any older test that set a free-text `originalLocation` on a valid physical element to a code such as `"Right down"`.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "fix(zako): pick the location of original-only elements from codelist 11

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Mobile ZaKo only in Demo

**Files:**
- Modify: `Chevron7/Sources/Chevron7App/ZakoSessionStore.swift:100-102` (`isMobileSigningAvailable`) and `authorizeAndSign`
- Test: `Chevron7/Tests/Chevron7AppTests/ZakoMobileAvailabilityTests.swift`

**Interfaces:**
- Produces: `isMobileSigningAvailable` is true only in EZZK Demo mode; `authorizeAndSign(viaMobile: true)` outside Demo sets `lastError` to `Self.mobileOutsideDemoMessage` and signs nothing.

- [ ] **Step 1: Write the failing test**

Model it on `ZakoEvidenceNumberTests.testNumberFetchedInDemoIsRefusedAfterSwitchingToTest` (same file folder), which already switches the EZZK mode on a `makeSettingsStore(ezzkAccountController:)`:

```swift
// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7App
@testable import Chevron7Kit

@MainActor
final class ZakoMobileAvailabilityTests: XCTestCase {
    func testMobileZakoIsRefusedOutsideDemo() async {
        // Build the controller and switch it to Test exactly as
        // ZakoEvidenceNumberTests.testNumberFetchedInDemoIsRefusedAfterSwitchingToTest does.
        let (settingsStore, _) = makeTestModeSettingsStore()
        settingsStore.settings.mobileSigningEnabled = true
        let store = ZakoSessionStore(settingsStore: settingsStore)
        XCTAssertFalse(store.isMobileSigningAvailable)
        await store.authorizeAndSign(viaMobile: true)
        XCTAssertEqual(store.lastError, ZakoSessionStore.mobileOutsideDemoMessage)
    }
}
```

Implement `makeTestModeSettingsStore()` as a private helper in this file by copying the controller setup lines from `testNumberFetchedInDemoIsRefusedAfterSwitchingToTest` (they create a controller in Test mode and pass it to `makeSettingsStore(ezzkAccountController:)`). Check how `settings.mobileSigningEnabled` is set in other tests (`settingsStore.settings` may be a value you assign back).

- [ ] **Step 2: Run to verify failure**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ZakoMobileAvailabilityTests`
Expected: compile error for `mobileOutsideDemoMessage`, then a failing assertion.

- [ ] **Step 3: Implement**

```swift
    static let mobileOutsideDemoMessage = "Zaručenú konverziu s EZZK podpisujte kartou SAK. Podpis z mobilu je zatiaľ dostupný iba v režime Demo."

    var isMobileSigningAvailable: Bool {
        settings.mobileSigningEnabled && !signingProviderIsDemo && settingsStore.ezzkAccountController.isDemoMode
    }
```

At the start of `authorizeAndSign`, right after `preparePreflight()`:

```swift
        if viaMobile, !settingsStore.ezzkAccountController.isDemoMode {
            lastError = Self.mobileOutsideDemoMessage
            return
        }
```

Note: `!signingProviderIsDemo` and Demo EZZK mode are independent settings (Demo EZZK with a real card is the combination this allows).

- [ ] **Step 4: Run the tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter Zako`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Chevron7App/ZakoSessionStore.swift Tests/Chevron7AppTests/ZakoMobileAvailabilityTests.swift
git commit -m "fix(zako): offer the phone for conversion only in Demo

The phone path uploads only the PDF, so it produces no clause XDC.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Documentation and live check

**Files:**
- Modify: `CLAUDE.md` and `AGENTS.md` at the repository root (identical edits)
- Modify: `Chevron7/docs/P2E-EZZK-FINDINGS.md` (new dated section)

- [ ] **Step 1: Document**

In both `CLAUDE.md` and `AGENTS.md`, in the ZaKo/Security elements bullets, add one line:

```markdown
  - Client output (EZZK part B1): `ZakoClauseDeliveryBuilder` renders clause 1.3 from `ConversionFormModel`, validates it with `FormSchemaValidator` (`/usr/bin/xmllint`, official schema from `docs/reference/forms`, embedded by `scripts/embed-official-forms.sh`) and wraps it with `XMLDataContainerBuilder`; the engine signs PDF/A and clause XDC as two data objects of one ASiC-E (`SigningRequest.signsExtraFilesAsDataObjects`, machine protocol v1 `attachments`); the PDF/A embeds nothing and its SHA-256 is the clause fingerprint. Spec: `Chevron7/docs/superpowers/specs/2026-09-23-ezzk-part-b-design.md`
```

Run: `diff CLAUDE.md AGENTS.md`
Expected: no output.

In `P2E-EZZK-FINDINGS.md` add a section `## Part B1 (2026-09-23)` summarising, one line each: the clause slot defect and its fix, the fingerprint/embedding defect and its fix, the location codelist change, the phone limited to Demo, and that the record path is unchanged until B2.

- [ ] **Step 2: Full verification**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS.
Run: `cd Chevron7 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./build_app.sh`
Expected: `✔ Hotovo`.

- [ ] **Step 3: Live check with the owner (SAK card, EZZK Demo mode)**

The owner runs one ZaKo conversion of a synthetic document in Demo mode with the SAK card, then:

```bash
cd <output folder>
unzip -l *.asice
```
Expected: `mimetype`, `<name>.pdf`, `<number>.xml.xdcf`, `META-INF/manifest.xml`, `META-INF/signatures001.xml`, and no `.asice` inside.

```bash
unzip -p *.asice '*.pdf' | openssl dgst -sha256 -binary | base64
unzip -p *.asice '*.xdcf' | grep -o '<ElectronicFingerprintValue>[^<]*'
```
Expected: the two values are equal.

Record the result (pass or the exact failure) in the `## Part B1` section of `P2E-EZZK-FINDINGS.md`.

- [ ] **Step 4: Commit**

```bash
git add ../CLAUDE.md ../AGENTS.md docs/P2E-EZZK-FINDINGS.md
git commit -m "docs(zako): describe the clause output of EZZK part B1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
