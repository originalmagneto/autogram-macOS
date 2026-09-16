import XCTest
@testable import AutogramApp

final class AppLaunchModeTests: XCTestCase {
    func testWebSigningArgumentSelectsBackgroundMode() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Autogram macOS.app/Contents/MacOS/Autogram", "--web-signing"]), .webSigning)
    }

    func testOrdinaryLaunchIsNormal() {
        XCTAssertEqual(AppLaunchMode.from(arguments: ["/Applications/Autogram macOS.app/Contents/MacOS/Autogram"]), .normal)
        XCTAssertEqual(AppLaunchMode.from(arguments: ["Autogram", "-NSDocumentRevisionsDebugMode", "YES"]), .normal)
    }
}
