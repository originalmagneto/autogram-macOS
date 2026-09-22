import XCTest
@testable import Chevron7Kit

/// The rename to Chevron7 stops where Autogram becomes a dependency. These pin
/// the values a later refactor could otherwise change without noticing.
final class RenameBoundaryTests: XCTestCase {
    /// The Autogram v mobile app opens links only for this host, so any other
    /// value silently breaks NFC signing with the phone.
    func testMobileRelayStaysOnSlovenskoDigital() {
        XCTAssertEqual(AVMClient.publicBaseURL.absoluteString, "https://autogram.slovensko.digital/api/v1")
    }

    /// The phone scans this link; a default client must produce it on the public host.
    func testQRCodeLinkPointsAtTheRelayThePhoneOpens() throws {
        let key = try AVMDocumentKey(bytes: Data(repeating: 7, count: 32))
        let reference = AVMDocumentReference(guid: "g1", key: key, lastModified: "")
        let url = AVMClient().qrCodeURL(for: reference)
        XCTAssertEqual(url.host, "autogram.slovensko.digital")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://autogram.slovensko.digital/api/v1/qr-code?guid=g1&key="))
    }
}
