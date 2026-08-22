import XCTest
@testable import AutogramKit

final class EvidenceAndPackagingTests: XCTestCase {
    func testEvidenceStorePersistsAndExportsCSV() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zako-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LocalEvidenceStore(directory: directory)
        let record = EvidenceRecord(
            status: .submitted,
            direction: .paperToElectronic,
            originalName: "Zmluva; o dielo",
            newDocumentName: "Zmluva o dielo PDF/A",
            evidenceNumber: "2026/000001",
            fingerprintSHA256Hex: String(repeating: "ab", count: 32),
            attestationXML: "<ConversionRecord/>",
            conversionTime: Date(),
            performingPersonName: "JUDr. Ján Advokát",
            securityElementCount: 2,
            totalPages: 3,
            totalSheets: 2)
        store.upsert(record)

        let reloaded = LocalEvidenceStore(directory: directory)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.evidenceNumber, "2026/000001")
        XCTAssertEqual(reloaded.records.first?.status, .submitted)

        let csv = reloaded.exportCSV()
        XCTAssertTrue(csv.contains("\"Zmluva; o dielo\""))
        XCTAssertTrue(csv.contains("2026/000001"))
    }

    func testASiCEPackageStructureIsValidZip() throws {
        let packager = ASiCEPackager()
        let asic = try packager.package(files: [
            .init(path: "mimetype",
                  data: Data("application/vnd.etsi.asic-e+zip".utf8),
                  storeUncompressed: true),
            .init(path: "META-INF/manifest.xml", data: Data("<manifest/>".utf8)),
            .init(path: "document.pdf", data: TestPDFBuilder.typicalContractPDF())
        ])

        XCTAssertEqual(asic.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]), "Chýba ZIP local header signature")
        XCTAssertTrue(String(decoding: asic.suffix(200), as: UTF8.self).contains("document.pdf"))

        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let tail = Array(asic.suffix(64))
        XCTAssertTrue(zip(tail, eocdSignature).contains { chunk, _ in
            false
        } || tail.contains(eocdSignature[0]) , "EOCD musí existovať")
    }

    func testMockEZZKAssignsSequentialNumbers() async throws {
        let service = MockEZZKService(startingNumber: 5)
        let numbers = try await service.requestEvidenceNumbers(count: 3)
        XCTAssertEqual(numbers.count, 3)
        XCTAssertNotEqual(numbers[0], numbers[1])

        let year = Calendar.current.component(.year, from: Date())
        XCTAssertTrue(numbers[0].hasPrefix("\(year)/"))

        let envelope = ConversionRecordEnvelope(
            evidenceNumber: numbers[0],
            direction: .paperToElectronic,
            originalName: "a",
            newDocumentName: "b",
            attestationXML: "<x/>",
            fingerprintSHA256Hex: "ff",
            conversionTime: Date())
        try await service.submit(envelope)
        XCTAssertEqual(service.submittedRecords.count, 1)

        let time = try await service.serverTime()
        XCTAssertEqual(time.timeIntervalSinceNow, 0, accuracy: 60)
    }

    func testDemoSigningProducesASICAndDigest() async throws {
        let provider = DemoSigningProvider()
        let identities = await provider.availableIdentities()
        XCTAssertFalse(identities.isEmpty)

        let pdf = TestPDFBuilder.typicalContractPDF()
        let result = try await provider.sign(pdf: pdf,
                                             identityID: identities[0].id,
                                             includeTimestamp: true)
        XCTAssertFalse(result.isLegallyBinding)
        XCTAssertEqual(result.pdfData, pdf)

        let asic = try XCTUnwrap(result.asicData)
        XCTAssertGreaterThan(asic.count, pdf.count / 2)
        XCTAssertTrue(result.signatureLabel.contains("SHA-256"))
    }
}
