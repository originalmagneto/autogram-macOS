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
