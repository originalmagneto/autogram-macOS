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
