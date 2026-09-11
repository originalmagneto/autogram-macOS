import XCTest
@testable import AutogramKit

/// Guards the wire format between the browser extension and the app.
///
/// These fixtures are JSON exactly as `ditec.js` builds it. A round trip
/// through Swift on both sides proves nothing here: the first version of this
/// contract used an enum with an associated value, which Swift encodes as
/// `{"inline":{"_0":"..."}}` and JavaScript as `{"inline":"..."}`. Swift talking
/// to Swift passed; the real path failed on a state portal.
final class WebSignRequestWireFormatTests: XCTestCase {
    private func decode(_ json: String) throws -> WebSignRequest {
        try JSONDecoder().decode(WebSignRequest.self, from: Data(json.utf8))
    }

    func testDecodesThePdfRequestTheExtensionSends() throws {
        let request = try decode("""
        {
          "requestID": "ditec-1757600000000",
          "filename": "dokument.pdf",
          "content": "JVBERi0xLjQ=",
          "payloadMimeType": "application/pdf;base64",
          "signatureLevel": "PAdES_BASELINE_B"
        }
        """)

        XCTAssertEqual(request.filename, "dokument.pdf")
        XCTAssertEqual(request.content, "JVBERi0xLjQ=")
        XCTAssertEqual(request.signatureLevel, "PAdES_BASELINE_B")
        XCTAssertNil(request.eform)
        XCTAssertTrue(request.isBase64)
    }

    func testDecodesTheEFormRequestTheExtensionSends() throws {
        let request = try decode("""
        {
          "requestID": "ditec-1757600000001",
          "filename": "formular.xml",
          "content": "PFppYWRvc3QvPg==",
          "payloadMimeType": "application/xml;base64",
          "signatureLevel": "XAdES_BASELINE_B",
          "container": "ASiC_E",
          "eform": {
            "containerXmlns": "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1",
            "schema": "<xs:schema/>",
            "transformation": "<xsl:stylesheet/>",
            "identifier": "http://schemas.gov.sk/form/App.GeneralAgenda/1.9",
            "schemaIdentifier": null,
            "transformationIdentifier": null,
            "transformationLanguage": "sk",
            "transformationMediaDestinationTypeDescription": "HTML",
            "transformationTargetEnvironment": null,
            "embedUsedSchemas": true,
            "autoLoadEform": false,
            "fsFormID": null,
            "packaging": "ENVELOPING"
          }
        }
        """)

        let eform = try XCTUnwrap(request.eform)
        XCTAssertEqual(eform.identifier, "http://schemas.gov.sk/form/App.GeneralAgenda/1.9")
        XCTAssertEqual(eform.schema, "<xs:schema/>")
        XCTAssertEqual(eform.transformation, "<xsl:stylesheet/>")
        XCTAssertEqual(eform.transformationMediaDestinationTypeDescription, "HTML")
        XCTAssertTrue(eform.embedUsedSchemas)
        XCTAssertFalse(eform.autoLoadEform)
        XCTAssertEqual(eform.packaging, "ENVELOPING")
        XCTAssertNil(eform.fsFormID)
    }

    /// The optional eForm fields are frequently absent rather than null, because
    /// the shim omits what a portal did not provide.
    func testDecodesAnEFormWithOnlyTheRequiredFields() throws {
        let request = try decode("""
        {
          "requestID": "r",
          "filename": "f.xml",
          "content": "PHgvPg==",
          "payloadMimeType": "application/xml;base64",
          "signatureLevel": "XAdES_BASELINE_B",
          "eform": {
            "containerXmlns": "http://data.gov.sk/def/container/xmldatacontainer+xml/1.1",
            "embedUsedSchemas": false,
            "autoLoadEform": false
          }
        }
        """)

        let eform = try XCTUnwrap(request.eform)
        XCTAssertNil(eform.schema)
        XCTAssertNil(eform.identifier)
    }

    func testResponseEncodesTheShapeTheExtensionReads() throws {
        let response = WebSignResponse(requestID: "r", content: "AAA",
                                       signedBy: "CN=Test", issuedBy: "CN=CA")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(response), encoding: .utf8)

        XCTAssertEqual(json, #"{"content":"AAA","issuedBy":"CN=CA","requestID":"r","signedBy":"CN=Test"}"#)
    }
}
