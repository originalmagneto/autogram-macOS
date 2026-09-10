import XCTest
@testable import AutogramKit

final class AVMDocumentKeyTests: XCTestCase {
    func testGeneratedKeyHas32BytesAndStrictBase64() throws {
        let key = AVMDocumentKey.generate()
        XCTAssertEqual(key.bytes.count, 32)
        let decoded = try XCTUnwrap(Data(base64Encoded: key.base64))
        XCTAssertEqual(decoded, key.bytes)
    }

    func testTwoGeneratedKeysDiffer() {
        XCTAssertNotEqual(AVMDocumentKey.generate(), AVMDocumentKey.generate())
    }

    func testQueryValuePercentEncodesPlusSlashAndEquals() throws {
        let raw = Data((0..<32).map { UInt8($0 * 8 % 256) })
        let key = try AVMDocumentKey(bytes: raw)
        XCTAssertFalse(key.queryValue.contains("+"))
        XCTAssertFalse(key.queryValue.contains("/"))
        XCTAssertFalse(key.queryValue.contains("="))
        XCTAssertEqual(key.queryValue.removingPercentEncoding, key.base64)
    }

    func testRejectsWrongLength() {
        XCTAssertThrowsError(try AVMDocumentKey(bytes: Data(repeating: 1, count: 16))) { error in
            guard case AVMDocumentKey.Failure.invalidLength(let count) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(count, 16)
        }
    }
}
