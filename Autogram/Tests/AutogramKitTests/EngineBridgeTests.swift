import Foundation
import XCTest
import PDFKit
import AppKit
@testable import AutogramKit

final class EngineBridgeGeometryTests: XCTestCase {
    func testDSSFieldConvertsCropBoxLocalPlacementForPageRotations() {
        let placement = VisibleSignaturePlacement(
            pageIndex: 1,
            pageRect: CGRect(x: 72, y: 144, width: 216, height: 108),
            rotationDegrees: 31
        )
        let cropBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let converter = PDFCoordinateConverter()
        let cases: [(rotation: Int, originX: CGFloat, originY: CGFloat, width: CGFloat, height: CGFloat)] = [
            (0, 72, 540, 216, 108),
            (90, 540, 324, 108, 216),
            (180, 324, 144, 216, 108),
            (270, 144, 72, 108, 216)
        ]

        for testCase in cases {
            let field = converter.dssField(placement,
                                           cropBox: cropBox,
                                           pageRotation: testCase.rotation)
            XCTAssertEqual(field.page, 2)
            XCTAssertEqual(field.originX, testCase.originX)
            XCTAssertEqual(field.originY, testCase.originY)
            XCTAssertEqual(field.width, testCase.width)
            XCTAssertEqual(field.height, testCase.height)
        }
    }

    func testProviderVisibleAppearanceUsesCropBoxAndTopLeftOrigin() throws {
        let pdfData = TestPDFBuilder.singlePageWhitePDF()
        guard let document = PDFDocument(data: pdfData), let page = document.page(at: 0) else {
            return XCTFail("Testovacie PDF sa nepodarilo otvoriť.")
        }
        let cropBox = page.bounds(for: .cropBox)
        let provider = EngineBridgeSigningProvider()
        let workDirectory = try EngineBridgeSigningProvider.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        // normalized y rastie zhora nadol; y=0.25 → cropBox-lokálne minY = 0.65 * height
        let stamp = VisualStampSpec(fullName: "Test Testovsky",
                                    timestamp: Date(),
                                    pageIndex: 0,
                                    normalizedRect: NormalizedRect(x: 0.1, y: 0.25, width: 0.3, height: 0.1),
                                    imagePNG: Data())
        let appearance = try provider.visibleAppearance(for: stamp,
                                                        certificateDisplayName: "Test",
                                                        qualification: nil,
                                                        pdfData: pdfData,
                                                        directory: workDirectory)

        XCTAssertEqual(appearance.page, 1)
        XCTAssertEqual(appearance.originX, cropBox.width * 0.1, accuracy: 0.5)
        // normalizovaná aj DSS os y rastie zhora nadol → originY = 0.25 * výška
        XCTAssertEqual(appearance.originY, cropBox.height * 0.25, accuracy: 0.5)
        XCTAssertEqual(appearance.width, cropBox.width * 0.3, accuracy: 0.5)
        XCTAssertEqual(appearance.height, cropBox.height * 0.1, accuracy: 0.5)

        let pngData = try Data(contentsOf: appearance.renderedPNGURL)
        XCTAssertEqual(Array(pngData.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "appearance musí byť PNG")
    }

    func testTextArtworkRendersPNG() {
        let png = EngineBridgeSigningProvider.textArtworkPNG(fullName: "Advokát Test", timestamp: Date())
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(png.count, 200)
    }

    func testRenderedCardKeepsTransparentBackground() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("card-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let store = SignatureAssetStore(applicationSupportRoot: work)
        try FileManager.default.createDirectory(at: store.assetsDirectory, withIntermediateDirectories: true)
        let asset = SignatureAsset(id: UUID(), kind: .png, managedFilename: "art.png")
        try EngineBridgeSigningProvider.textArtworkPNG(fullName: "Test", timestamp: Date())
            .write(to: store.fileURL(for: asset))
        let url = try VisibleSignatureRenderer(assetStore: store).render(
            asset: asset,
            content: VisibleSignatureCardContent(signerName: "Mgr. Test",
                                                 certificateQualification: "Kvalifikovaný elektronický podpis"),
            signingTime: Date(),
            rotationDegrees: 0)
        let png = try Data(contentsOf: url)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(png.count, 4000, "Karta musí byť plná grafika, nie prázdne PNG")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        // Sample the empty inner margin, inside the former white card fill.
        let margin = Int(12 * VisibleSignatureRenderer.renderScale)
        let background = try XCTUnwrap(bitmap.colorAt(x: margin, y: bitmap.pixelsHigh / 2))
        XCTAssertLessThan(background.alphaComponent, 0.01, "Pozadie karty nesmie prekryť obsah dokumentu")
    }
}

final class EngineBridgeSelectionTests: XCTestCase {
    private func certificate(serial: String, qualification: String?) -> SigningCertificate {
        SigningCertificate(serialNumber: serial,
                           displayName: "Cert \(serial)",
                           issuer: "eID SR",
                           validFrom: .distantPast,
                           validUntil: .distantFuture,
                           certificateKey: "v1:key-\(serial)",
                           holderKey: "holder-\(serial)",
                           certificateQualification: qualification)
    }

    func testPrefersQualifiedSignatureCertificate() {
        let selected = EngineBridgeSigningProvider.selectCertificate(
            from: [certificate(serial: "111", qualification: nil),
                   certificate(serial: "222", qualification: "QESIG")],
            preferredSerialNumber: nil)
        XCTAssertEqual(selected?.serialNumber, "222")
    }

    func testPreferredSerialWinsOverQualification() {
        let selected = EngineBridgeSigningProvider.selectCertificate(
            from: [certificate(serial: "111", qualification: nil),
                   certificate(serial: "222", qualification: "QESIG")],
            preferredSerialNumber: "111")
        XCTAssertEqual(selected?.serialNumber, "111")
    }

    func testSyntheticIdentityIsQualifiedButNotMandate() {
        let identity = EngineBridgeSigningProvider.syntheticIdentity()
        XCTAssertEqual(identity.id, "engine:eid")
        XCTAssertTrue(identity.isQualified)
        XCTAssertFalse(identity.isMandateCertificate,
                       "eID je QES – mandátny flag patrí len advokátskemu/notárskemu preukazu.")
        XCTAssertTrue(identity.requiresPIN)
        let named = EngineBridgeSigningProvider.syntheticIdentity(driverNames: ["I.CA SecureStore"])
        XCTAssertTrue(named.label.contains("I.CA SecureStore"))
    }

    /// eID tokens report CKF_PROTECTED_AUTHENTICATION_PATH (checked on a real card:
    /// slots Sig_ZEP and Sig_EP), so the BOK is typed in the eID client's own
    /// window. `requiresPIN` stays true because the main window still collects it.
    func testOnlyEIDIdentitiesUseTheProtectedAuthenticationPath() {
        let eid = EngineBridgeSigningProvider.syntheticIdentity(driverNames: ["eID"], driverID: "eid")
        XCTAssertTrue(eid.usesProtectedAuthenticationPath)
        XCTAssertTrue(eid.requiresPIN)
        XCTAssertFalse(EngineBridgeSigningProvider.syntheticIdentity(driverNames: ["I.CA"], driverID: "secure_store")
            .usesProtectedAuthenticationPath)

        let certificate = SigningCertificate(serialNumber: "42", displayName: "Marián Čuprík")
        XCTAssertTrue(EngineBridgeSigningProvider.identityInfo(from: certificate, driverID: "eid").usesProtectedAuthenticationPath)
        XCTAssertTrue(EngineBridgeSigningProvider.identityInfo(from: certificate, driverID: "eid").requiresPIN)
        XCTAssertFalse(EngineBridgeSigningProvider.identityInfo(from: certificate, driverID: "secure_store")
            .usesProtectedAuthenticationPath)
    }

    /// A portal looks for the original PDF by name inside the ASiC-E it gets back.
    func testAsicSourceKeepsThePortalFilename() {
        func request(_ format: SigningOutputFormat, _ filename: String?) -> SigningRequest {
            SigningRequest(pdfData: Data(), identityID: "x", includeTimestamp: false,
                           outputFormat: format, filename: filename)
        }
        XCTAssertEqual(EngineBridgeSigningProvider.pdfSourceName(for: request(.attachedASIC, "122085-Navrhasuhlas.pdf")),
                       "122085-Navrhasuhlas.pdf")
        XCTAssertEqual(EngineBridgeSigningProvider.pdfSourceName(for: request(.attachedASIC, "../../etc/zmluva.pdf")),
                       "zmluva.pdf")
        XCTAssertEqual(EngineBridgeSigningProvider.pdfSourceName(for: request(.attachedASIC, "formular.xml")), "document.pdf")
        XCTAssertEqual(EngineBridgeSigningProvider.pdfSourceName(for: request(.attachedASIC, nil)), "document.pdf")
        XCTAssertEqual(EngineBridgeSigningProvider.pdfSourceName(for: request(.embeddedPAdES, "zmluva.pdf")), "document.pdf")
    }

    func testCardKindNamesTheEIDAndICACards() {
        XCTAssertEqual(EngineBridgeSigningProvider.syntheticIdentity(driverNames: ["Občiansky preukaz (eID klient)"],
                                                                    driverID: "eid").cardKindLabel,
                       "Občiansky preukaz (eID)")
        XCTAssertEqual(EngineBridgeSigningProvider.syntheticIdentity(driverNames: ["I.CA SecureStore"],
                                                                    driverID: "secure_store").cardKindLabel,
                       "Karta I.CA")
        let ica = SigningIdentityInfo(id: "engine-cert:1", label: "Marián Čuprík OPRÁVNENIE 1042",
                                      issuerSummary: "I.CA EU Qualified CA-SK/RSA 10/2022", requiresPIN: true)
        XCTAssertEqual(ica.cardKindLabel, "Karta I.CA")
        let unknown = SigningIdentityInfo(id: "x", label: "Test", issuerSummary: "Neznáma CA")
        XCTAssertNil(unknown.cardKindLabel)
    }

    /// Each eID certificate read opens the BOK window, so a portal signature with the
    /// eID goes straight to signing, where the engine picks the card's signing key.
    func testOnlyAnEIDWithoutChosenCertificateOrStampSkipsDiscovery() {
        XCTAssertTrue(EngineBridgeSigningProvider.signsWithoutCertificateDiscovery(
            driverID: "eid", preferredSerial: nil, hasVisualStamp: false))
        XCTAssertFalse(EngineBridgeSigningProvider.signsWithoutCertificateDiscovery(
            driverID: "eid", preferredSerial: "42", hasVisualStamp: false))
        XCTAssertFalse(EngineBridgeSigningProvider.signsWithoutCertificateDiscovery(
            driverID: "eid", preferredSerial: nil, hasVisualStamp: true))
        XCTAssertFalse(EngineBridgeSigningProvider.signsWithoutCertificateDiscovery(
            driverID: "secure_store", preferredSerial: nil, hasVisualStamp: false))
        XCTAssertEqual(EngineBridgeSigningProvider.signingKeyOnToken, "*")
    }

    func testEnginePINUsesThePlaceholderOnlyForAnEmptyEIDEntry() {
        let placeholder = EngineBridgeSigningProvider.protectedAuthenticationPathPIN
        XCTAssertEqual(EngineBridgeSigningProvider.enginePIN(entered: "", driverID: "eid"), placeholder)
        XCTAssertEqual(EngineBridgeSigningProvider.enginePIN(entered: "123456", driverID: "eid"), "123456")
        XCTAssertNil(EngineBridgeSigningProvider.enginePIN(entered: "", driverID: "secure_store"))
        XCTAssertEqual(EngineBridgeSigningProvider.enginePIN(entered: "1234", driverID: "secure_store"), "1234")
    }

    func testTrustedListFailureIsSlovak() {
        let mapped = EngineBridgeSigningProvider.localizedEngineMessage(
            "The machine request could not be completed. [TRUSTED_LIST_UNAVAILABLE]")
        XCTAssertTrue(mapped.contains("dôveryhodných CA"))
        XCTAssertFalse(mapped.contains("machine request"))
    }

    func testPrimaryDriverPrefersEIDLikeCertificateDiscovery() {
        XCTAssertEqual(EngineBridgeSigningProvider.primaryDriverID(fingerprint: "eid,secure_store"), "eid")
        XCTAssertEqual(EngineBridgeSigningProvider.primaryDriverID(fingerprint: "secure_store"), "secure_store")
        XCTAssertNil(EngineBridgeSigningProvider.primaryDriverID(fingerprint: ""))
    }

    func testMandateDetectionDistinguishesCards() {
        XCTAssertFalse(EngineBridgeSigningProvider.isMandateCertificate(
            issuer: "SVK eID ACA2", displayName: "Marián Čuprík"))
        XCTAssertFalse(EngineBridgeSigningProvider.isMandateCertificate(
            issuer: "I.CA Public CA/RSA 05/2022", displayName: "Marián Čuprík"))
        XCTAssertFalse(EngineBridgeSigningProvider.isQualifiedCertificate(
            issuer: "I.CA Public CA/RSA 05/2022", displayName: "Marián Čuprík", qualification: nil))
        XCTAssertTrue(EngineBridgeSigningProvider.isMandateCertificate(
            issuer: "I.CA EU Qualified CA-SK/RSA 10/2022",
            displayName: "Marián Čuprík OPRÁVNENIE 1042",
            qualification: "QESIG"))
        XCTAssertTrue(EngineBridgeSigningProvider.isQualifiedCertificate(
            issuer: "I.CA EU Qualified CA-SK/RSA 10/2022",
            displayName: "Marián Čuprík OPRÁVNENIE 1042",
            qualification: "QESIG"))
    }

    func testIdentityInfoMapsCertificateFields() {
        let info = EngineBridgeSigningProvider.identityInfo(
            from: certificate(serial: "42", qualification: "QESIG"), driverID: "eid")
        XCTAssertEqual(info.id, "engine-cert:42")
        XCTAssertEqual(info.label, "Cert 42")
        XCTAssertEqual(info.issuerSummary, "eID SR")
        XCTAssertTrue(info.isQualified)
        XCTAssertFalse(info.isMandateCertificate, "eID issuer → nie mandate")
    }
}

final class EngineBridgeContainerTests: XCTestCase {
    private func unzipAsice(_ data: Data) -> [String: Data] {
        var result: [String: Data] = [:]
        var offset = 0
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int {
            Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
        }
        while offset + 30 <= bytes.count, u32(offset) == 0x04034b50 {
            let nameLength = u16(offset + 26)
            let extraLength = u16(offset + 28)
            let compressedSize = u32(offset + 18)
            let nameStart = offset + 30
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let dataStart = nameStart + nameLength + extraLength
            if u16(offset + 8) == 0 {
                result[name] = Data(bytes[dataStart..<dataStart + compressedSize])
            } else {
                result[name] = nil
            }
            offset = dataStart + compressedSize
        }
        return result
    }

    func testPackageContainerAddsMimetypeAndManifest() throws {
        let data = try EngineBridgeSigningProvider.packageContainer(entries: [
            ASiCEPackager.Entry(path: "dokument.pdf", data: Data("pdf".utf8)),
            ASiCEPackager.Entry(path: "dolozka.xml.xdcf", data: Data("xml".utf8))
        ])
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "ASiC-E musí byť ZIP")
        let zip = unzipAsice(data)
        XCTAssertEqual(String(decoding: zip["mimetype"] ?? Data(), as: UTF8.self),
                       ASiCEPackager.asicMimeType)
        XCTAssertNotNil(zip["META-INF/manifest.xml"])
        XCTAssertNotNil(zip["dokument.pdf"])
        XCTAssertNotNil(zip["dolozka.xml.xdcf"])
        let manifest = String(decoding: zip["META-INF/manifest.xml"] ?? Data(), as: UTF8.self)
        XCTAssertTrue(manifest.contains("dokument.pdf"))
        XCTAssertTrue(manifest.contains("dolozka.xml.xdcf"))
    }

    func testPackageContainerKeepsProvidedManifest() throws {
        let customManifest = "<manifest>custom</manifest>"
        let data = try EngineBridgeSigningProvider.packageContainer(entries: [
            ASiCEPackager.Entry(path: "mimetype",
                                data: Data(ASiCEPackager.asicMimeType.utf8),
                                storeUncompressed: true),
            ASiCEPackager.Entry(path: "META-INF/manifest.xml", data: Data(customManifest.utf8))
        ])
        let zip = unzipAsice(data)
        XCTAssertEqual(String(decoding: zip["META-INF/manifest.xml"] ?? Data(), as: UTF8.self),
                       customManifest)
    }
}

final class JavaEngineLocatorTests: XCTestCase {
    func testLocateFindsValidRootWithHelperPreference() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-root-\(UUID().uuidString)", isDirectory: true)
        let java = root.appendingPathComponent("runtime/bin/java")
        let jar = root.appendingPathComponent("app/autogram.jar")
        let helper = root.appendingPathComponent("Helpers/AutogramCLI-arm64")
        for directory in [java.deletingLastPathComponent(), jar.deletingLastPathComponent(),
                          helper.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("#!/bin/sh\n".utf8).write(to: java)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        try Data().write(to: jar)
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let locator = JavaEngineLocator(candidateRoots: [root.path])
        guard let installation = locator.locate() else {
            return XCTFail("Platný root nebol rozpoznaný.")
        }
        XCTAssertEqual(installation.helperURL.path, helper.path)
    }

    func testLocateReturnsNilWithoutJarOrExecutable() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-root-\(UUID().uuidString)", isDirectory: true)
        let locator = JavaEngineLocator(candidateRoots: [root.path])
        XCTAssertNil(locator.locate())
    }
}

final class MachineRequestEncodingTests: XCTestCase {
    private func request(format: EngineSigningOutputFormat, override: String?) -> EngineSigningRequest {
        EngineSigningRequest(sessionID: UUID(), driverID: "secure_store", certificateSerial: "1",
                             pin: Secret("1234"), files: [], outputFormat: format,
                             signatureLevelOverride: override)
    }

    /// A portal's XAdES Baseline B went out as Baseline T on the protocol v1 path,
    /// which ignored the override: with the timestamp switch off that failed with
    /// TSA_REQUIRED, with it on the portal got a timestamp it had not asked for.
    func testPortalBaselineBGoesOutWithoutATimestamp() {
        let payload = AutogramCLIEngine.levelAndTimestamp(for: request(format: .asiceXAdES, override: "XAdES_BASELINE_B"),
                                                          endpoints: [])

        XCTAssertEqual(payload.level, "XAdES_BASELINE_B")
        XCTAssertEqual(payload.timestamp, .object(["required": .bool(false), "servers": .array([])]))
    }

    func testAppFlowsKeepTheQualifiedTimestamp() {
        let payload = AutogramCLIEngine.levelAndTimestamp(for: request(format: .asiceXAdES, override: nil),
                                                          endpoints: ["https://tsa.example.test"])

        XCTAssertEqual(payload.level, "XAdES_BASELINE_T")
        XCTAssertEqual(payload.timestamp,
                       .object(["required": .bool(true), "servers": .array([.string("https://tsa.example.test")])]))
    }

    func testUnauthenticatedV1RequestKeepsDriversPayloadEmpty() throws {
        let request = MachineRequest(
            protocolVersion: 1,
            requestID: "drivers-test",
            operation: .drivers,
            payload: [:])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: MachineRequestEncoder.encode(request)) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertTrue(payload.isEmpty)
    }

    func testUnauthenticatedV2RequestKeepsPayloadEmpty() throws {
        let request = SecureMachineV2Request(
            envelope: MachineV2Request.capabilities(requestID: "capabilities-test"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: MachineV2RequestEncoder.encode(request)) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])

        XCTAssertTrue(payload.isEmpty)
    }
}

private struct ResolveDispatchProbeProvider: QualifiedSigningProviding {
    func availableIdentities() async -> [SigningIdentityInfo] { [] }

    func resolveIdentities(pin: String) async -> [SigningIdentityInfo]? {
        [SigningIdentityInfo(id: "concrete", label: pin, issuerSummary: "test")]
    }

    func sign(_ request: SigningRequest) async throws -> SignedConversionResult {
        throw SigningError.identityUnavailable
    }

    func inspectSignatures(in fileURL: URL) async -> [DocumentSignatureInfo] { [] }
}

final class SigningProviderDispatchTests: XCTestCase {
    func testResolveIdentitiesDispatchesThroughProtocolExistential() async {
        let provider: any QualifiedSigningProviding = ResolveDispatchProbeProvider()

        let identity = await provider.resolveIdentities(pin: "dispatch-test")?.first

        XCTAssertEqual(identity?.id, "concrete")
        XCTAssertEqual(identity?.label, "dispatch-test")
    }
}

final class EngineInspectionContractTests: XCTestCase {
    func testIncompleteEngineInspectionCannotBeAcceptedAsCompleted() {
        let inspection = PDFInspection(files: [
            InspectedPDF(id: "inspect", isSignable: false)
        ])

        XCTAssertThrowsError(
            try EngineBridgeSigningProvider.requireInspectableFile(
                in: [inspection]))
    }
    func testBulkInputInspectionDeduplicatesDuplicateURLs() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duplicate-input-\(UUID().uuidString).pdf")

        let results = await EngineBridgeSigningProvider()
            .inspectInputSignatures(in: [url, url])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[EnginePaths.canonical(url)]?.state, .unavailable)
    }

}

final class JavaEngineLiveProcessTests: XCTestCase {
    private var liveTestEnabled: Bool {
        ProcessInfo.processInfo.environment["AUTOGRAM_ENGINE_LIVE_TEST"] == "1"
    }

    func testCapabilitiesRoundtripAgainstRealEngineHelper() async throws {
        guard liveTestEnabled else {
            throw XCTSkip("Live test vyžaduje AUTOGRAM_ENGINE_LIVE_TEST=1.")
        }
        guard JavaEngineLocator().locate() != nil else {
            throw XCTSkip("Java engine nie je nainštalovaný.")
        }
        let engine = AutogramCLIEngine()
        let capabilities = try await engine.capabilities()
        XCTAssertTrue(capabilities.supportsQualifiedTimestamp)
        let drivers = try await engine.drivers()
        _ = drivers
        await engine.cancel()
    }

}

final class EngineBridgeLiveSignTests: XCTestCase {
    private var liveTestEnabled: Bool {
        ProcessInfo.processInfo.environment["AUTOGRAM_ENGINE_LIVE_TEST"] == "1"
    }

    func testV1SignRequestPassesProtocolValidation() async throws {
        guard liveTestEnabled else { throw XCTSkip("Vyžaduje AUTOGRAM_ENGINE_LIVE_TEST=1.") }
        guard JavaEngineLocator().locate() != nil else { throw XCTSkip("Engine nie je nainštalovaný.") }

        let engine = AutogramCLIEngine()
        let work = try EngineBridgeSigningProvider.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("document.pdf")
        try TestPDFBuilder.singlePageWhitePDF().write(to: source)

        let file = SigningFile(id: "document",
                               sourceURL: source.standardizedFileURL.resolvingSymlinksInPath())
        let request = EngineSigningRequest(sessionID: UUID(),
                                           driverID: "eid",
                                           certificateSerial: "123",
                                           pin: Secret("0000"),
                                           files: [file],
                                           outputFormat: .asiceXAdES)
        var events: [String] = []
        do {
            for try await event in engine.sign(request: request) {
                switch event {
                case .started: events.append("started")
                case .activity(let phase): events.append("activity:\(phase)")
                case .fileSigning(let id): events.append("signing:\(id)")
                case .completed(let id, let url): events.append("completed:\(id):\(url.lastPathComponent)")
                case .failed(let id, let failure): events.append("failed:\(id):\(failure)")
                case .cancelled: events.append("cancelled")
                }
            }
        } catch let failure as SigningFailure {
            events.append("throw:\(failure)")
        }
        print("V1 EVENTS: \(events)")
        let joined = events.joined(separator: "|")
        XCTAssertFalse(joined.contains("PROTOCOL_INVALID_REQUEST"), "V1 request musí prejsť validáciou: \(joined)")
        await engine.cancel()
    }

    func testV2VisibleSignRequestPassesProtocolValidation() async throws {
        guard liveTestEnabled else { throw XCTSkip("Vyžaduje AUTOGRAM_ENGINE_LIVE_TEST=1.") }
        guard JavaEngineLocator().locate() != nil else { throw XCTSkip("Engine nie je nainštalovaný.") }

        let engine = AutogramCLIEngine()
        let work = try EngineBridgeSigningProvider.makeWorkspace()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("document.pdf")
        try TestPDFBuilder.singlePageWhitePDF().write(to: source)

        let store = SignatureAssetStore(applicationSupportRoot: work)
        try FileManager.default.createDirectory(at: store.assetsDirectory, withIntermediateDirectories: true)
        let asset = SignatureAsset(id: UUID(), kind: .png, managedFilename: "art.png")
        try EngineBridgeSigningProvider.textArtworkPNG(fullName: "Test", timestamp: Date())
            .write(to: store.fileURL(for: asset))
        let rendered = try VisibleSignatureRenderer(assetStore: store).render(
            asset: asset,
            content: VisibleSignatureCardContent(signerName: "Test", certificateQualification: nil),
            signingTime: Date(),
            rotationDegrees: 0)

        let placement = VisibleSignaturePlacement(pageIndex: 0,
                                                  pageRect: CGRect(x: 100, y: 600, width: 200, height: 120),
                                                  rotationDegrees: 0)
        guard let page = PDFDocument(url: source)?.page(at: 0) else { return XCTFail("PDF") }
        let field = PDFCoordinateConverter().dssField(placement,
                                                      cropBox: page.bounds(for: .cropBox),
                                                      pageRotation: Int(page.rotation))
        let appearance = VisibleSignatureRequest(renderedPNGURL: rendered,
                                                 page: field.page,
                                                 originX: Double(field.originX),
                                                 originY: Double(field.originY),
                                                 width: Double(field.width),
                                                 height: Double(field.height),
                                                 signingTime: Date())

        let file = SigningFile(id: "document",
                               sourceURL: source.standardizedFileURL.resolvingSymlinksInPath(),
                               visibleAppearance: appearance)
        let request = EngineSigningRequest(sessionID: UUID(),
                                           driverID: "eid",
                                           certificateSerial: "123",
                                           pin: Secret("0000"),
                                           files: [file],
                                           outputFormat: .pades)
        var events: [String] = []
        do {
            for try await event in engine.sign(request: request) {
                switch event {
                case .started: events.append("started")
                case .activity(let phase): events.append("activity:\(phase)")
                case .fileSigning(let id): events.append("signing:\(id)")
                case .completed(let id, _): events.append("completed:\(id)")
                case .failed(let id, let failure): events.append("failed:\(id):\(failure)")
                case .cancelled: events.append("cancelled")
                }
            }
        } catch {
            events.append("throw:\(error)")
        }
        print("V2 EVENTS: \(events)")
        let joined = events.joined(separator: "|")
        XCTAssertFalse(joined.contains("PROTOCOL_INVALID_REQUEST"), "V2 request musí prejsť validáciou: \(joined)")
        XCTAssertFalse(joined.contains("MachineSessionProcessFailure"), "V2 session nesmie zlyhať na protokole: \(joined)")
        await engine.cancel()
    }
}
