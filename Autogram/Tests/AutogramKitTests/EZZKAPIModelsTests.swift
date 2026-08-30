import XCTest
import AutogramKit

final class EZZKAPIModelsTests: XCTestCase {
    func testAvailableEvidenceResponseDecodesObservedEmptyResponse() throws {
        let data = Data(#"{"availableEvidenceNumbers":[],"description":"Neboli nájdené žiadne nespotrebované evidenčné čísla"}"#.utf8)

        let response = try JSONDecoder().decode(EZZKAvailableEvidenceResponse.self, from: data)

        XCTAssertEqual(response.availableEvidenceNumbers, [])
        XCTAssertEqual(response.description, "Neboli nájdené žiadne nespotrebované evidenčné čísla")
    }

    func testAvailableEvidenceResponseAllowsMissingDescription() throws {
        let data = Data(#"{"availableEvidenceNumbers":["1563-260830-1"]}"#.utf8)

        let response = try JSONDecoder().decode(EZZKAvailableEvidenceResponse.self, from: data)

        XCTAssertEqual(response.availableEvidenceNumbers, ["1563-260830-1"])
        XCTAssertNil(response.description)
    }

    func testFilesRequestRoundTripsObservedASiCPayload() throws {
        let request = EZZKFilesRequest(files: [
            EZZKFilePayload(
                fileName: "signed-record.asice",
                fileType: "application/vnd.etsi.asic-e+zip",
                value: "YWJj")
        ])

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(EZZKFilesRequest.self, from: data)

        XCTAssertEqual(decoded, request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let files = try XCTUnwrap(object["files"] as? [[String: Any]])
        XCTAssertEqual(files.first?["fileName"] as? String, "signed-record.asice")
        XCTAssertEqual(files.first?["fileType"] as? String, "application/vnd.etsi.asic-e+zip")
        XCTAssertEqual(files.first?["value"] as? String, "YWJj")
    }

    func testSubmissionReceiptRequiresReceiptValue() throws {
        let receipt = EZZKSubmissionReceipt(receipt: "accepted-123")
        let decoded = try JSONDecoder().decode(
            EZZKSubmissionReceipt.self,
            from: JSONEncoder().encode(receipt))

        XCTAssertEqual(decoded, receipt)
        XCTAssertThrowsError(try JSONDecoder().decode(
            EZZKSubmissionReceipt.self,
            from: Data(#"{}"#.utf8)))
    }
}
