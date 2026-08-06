import XCTest

final class CredentialFlowTests: XCTestCase {
    @MainActor
    func testCertificateSelectionPresentsSecurePINSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AUTOGRAM_FAKE_ENGINE"] = "credential-flow"
        app.launch()

        let certificate = app.staticTexts["Test Certificate"]
        XCTAssertTrue(certificate.waitForExistence(timeout: 3))
        certificate.click()
        app.buttons["Use Certificate"].click()

        let pinField = app.secureTextFields["PIN"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Sign with PIN"].isEnabled)
        pinField.click()
        pinField.typeText("test-pin")
        XCTAssertTrue(app.buttons["Sign with PIN"].isEnabled)
    }
}
