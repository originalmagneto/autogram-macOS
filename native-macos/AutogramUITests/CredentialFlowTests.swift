import XCTest

final class CredentialFlowTests: XCTestCase {
    @MainActor
    func testCertificateSelectionPresentsSecurePINSheet() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AUTOGRAM_FAKE_ENGINE"] = "credential-flow"
        app.launch()

        XCTAssertTrue(app.otherElements["Certificate Picker"].waitForExistence(timeout: 3))
        app.staticTexts["Test Certificate"].click()
        app.buttons["Use Certificate"].click()

        let pinField = app.secureTextFields["PIN"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Sign with PIN"].isEnabled)
        pinField.click()
        pinField.typeText("test-pin")
        XCTAssertTrue(app.buttons["Sign with PIN"].isEnabled)
    }
}
