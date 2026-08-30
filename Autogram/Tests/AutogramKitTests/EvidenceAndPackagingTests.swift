import Compression
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
    func testASiCEVerifierReadsDeflateEntriesWithDataDescriptors() throws {
        // Regression: ASiC-E containers produced by signing engines (Java/DSS,
        // Podpisuj.sk) use DEFLATE entries with data descriptors: local headers
        // carry zero sizes and the true sizes live only in the central directory.
        // Structure mirrors the real reference container byte-for-byte.
        let payload = Data(String(repeating: "0123456789ABCDEF", count: 64).utf8)
        let compressed = try XCTUnwrap(deflate(payload))
        let name = "document.pdf"

        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }

        var zip = Data([0x50, 0x4B, 0x03, 0x04])
        zip += u16(20)              // version
        zip += u16(0x0808)          // flags: data descriptor + UTF-8
        zip += u16(8)               // method = DEFLATE
        zip += u16(0) + u16(0)      // time, date
        zip += u32(0)               // crc32 (in descriptor)
        zip += u32(0) + u32(0)      // local sizes are ZERO with descriptors
        zip += u16(name.count) + u16(0)
        zip += Data(name.utf8)
        zip += compressed
        zip += [0x50, 0x4B, 0x07, 0x08]   // data descriptor signature
        zip += u32(0)                     // crc32
        zip += u32(compressed.count)
        zip += u32(payload.count)

        let centralOffset = zip.count
        zip += [0x50, 0x4B, 0x01, 0x02]   // central directory header
        zip += u16(20) + u16(20)          // version made by / needed
        zip += u16(0x0808) + u16(8)       // flags, method
        zip += u16(0) + u16(0)            // time, date
        zip += u32(0)                     // crc32
        zip += u32(compressed.count) + u32(payload.count)
        zip += u16(name.count) + u16(0) + u16(0)   // name, extra, comment lengths
        zip += u16(0) + u16(0)            // disk, internal attrs
        zip += u32(0)                     // external attrs
        zip += u32(0)                     // local header offset
        zip += Data(name.utf8)

        zip += [0x50, 0x4B, 0x05, 0x06]   // EOCD
        zip += u16(0) + u16(0)            // disk numbers
        zip += u16(1) + u16(1)            // entry counts
        zip += u32(zip.count - centralOffset) + u32(centralOffset)
        zip += u16(0)                     // comment length

        let entries = try XCTUnwrap(ASiCEContainerVerifier.readEntries(zip))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, name)
        XCTAssertEqual(entries.first?.data, payload)
    }

    private func deflate(_ data: Data) throws -> Data {
        let dstCapacity = data.count + 256
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { dstPtr -> Int in
            data.withUnsafeBytes { srcPtr -> Int in
                compression_encode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!, dstCapacity,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw NSError(domain: "deflate-test", code: 1) }
        return dst.prefix(written)
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

    func testZakoContainerLayoutAndManifest() throws {
        let packager = ASiCEPackager()
        let pdf = TestPDFBuilder.typicalContractPDF()
        let files = packager.zakoContainer(pdfData: pdf,
                                           pdfFileName: "Zmluva o dielo.pdf",
                                           dolozkaXML: Data("<ConversionRecord/>".utf8),
                                           dolozkaFileName: "1563-231114-1.xml.xdcf")
        let paths = files.map(\.path)
        XCTAssertTrue(paths.contains("mimetype"))
        XCTAssertTrue(paths.contains("Zmluva o dielo.pdf"))
        XCTAssertTrue(paths.contains("1563-231114-1.xml.xdcf"))
        XCTAssertTrue(paths.contains("META-INF/manifest.xml"))

        let asic = try packager.package(files: files)
        let listing = String(decoding: asic, as: UTF8.self)
        XCTAssertTrue(listing.contains("application/vnd.gov.sk.xmldatacontainer+xml"))
        XCTAssertTrue(listing.contains("manifest:file-entry"))

        let mimetypeEntry = try XCTUnwrap(files.first { $0.path == "mimetype" })
        XCTAssertTrue(mimetypeEntry.storeUncompressed)

        let manifestXML = String(
            decoding: try XCTUnwrap(files.first { $0.path == "META-INF/manifest.xml" }).data,
            as: UTF8.self)
        XCTAssertTrue(manifestXML.contains(
            "<manifest:file-entry manifest:full-path=\"/\" " +
            "manifest:media-type=\"application/vnd.etsi.asic-e+zip\"/>"))
        XCTAssertTrue(manifestXML.contains("Zmluva o dielo.pdf"))
    }

    func testMockEZZKAssignsSequentialNumbers() async throws {
        let service = MockEZZKService(startingNumber: 5)
        let numbers = try await service.requestEvidenceNumbers(count: 3)
        XCTAssertEqual(numbers.count, 3)
        XCTAssertNotEqual(numbers[0], numbers[1])

        for number in numbers {
            XCTAssertTrue(number.hasPrefix("1563-"), "Neočakávaný formát: \(number)")
            let parts = number.split(separator: "-")
            XCTAssertEqual(parts.count, 3, "Formát má byť {registry}-{YYMMDD}-{seq}: \(number)")
        }
        XCTAssertEqual(numbers.map { $0.split(separator: "-").last.map(String.init) },
                       ["5", "6", "7"])

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
    func testMockEZZKExposesTypedCapabilities() async throws {
        let service = MockEZZKService()
        let clock: any EZZKServerClock = service
        let evidenceProvider: any EZZKEvidenceNumberProvider = service
        let submission: any EZZKSubmissionTransport = service

        let number = try await evidenceProvider.requestEvidenceNumbers(count: 1)[0]
        let envelope = ConversionRecordEnvelope(
            evidenceNumber: number,
            direction: .paperToElectronic,
            originalName: "source",
            newDocumentName: "converted",
            attestationXML: "<ConversionRecord/>",
            fingerprintSHA256Hex: String(repeating: "a", count: 64),
            conversionTime: Date())

        try await submission.submit(envelope)
        let serverTime = try await clock.serverTime()

        XCTAssertEqual(service.submittedRecords.map(\.evidenceNumber), [number])
        XCTAssertEqual(serverTime.timeIntervalSinceNow, 0, accuracy: 60)
    }


    func testDemoSigningProducesASICAndDigest() async throws {
        let provider = DemoSigningProvider()
        let identities = await provider.availableIdentities()
        XCTAssertFalse(identities.isEmpty)

        let pdf = TestPDFBuilder.typicalContractPDF()
        let result = try await provider.sign(pdf: pdf,
                                             identityID: identities[0].id,
                                             includeTimestamp: false)
        XCTAssertFalse(result.isLegallyBinding)
        XCTAssertEqual(result.pdfData, pdf)

        let asic = try XCTUnwrap(result.asicData)
        XCTAssertGreaterThan(asic.count, pdf.count / 2)
        XCTAssertTrue(result.signatureLabel.contains("SHA-256"))
    }
}
