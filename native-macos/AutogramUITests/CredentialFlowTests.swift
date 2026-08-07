import XCTest

final class CredentialFlowTests: XCTestCase {
    @MainActor
    func testDiscoveredCredentialSignsAfterPINEntry() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AUTOGRAM_FAKE_ENGINE"] = "credential-flow"
        app.launch()

        let signButton = app.buttons["Sign"]
        XCTAssertTrue(signButton.waitForExistence(timeout: 3))
        XCTAssertTrue(signButton.isEnabled)
        signButton.click()

        let pinField = app.secureTextFields["PIN"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Sign with PIN"].isEnabled)
        pinField.click()
        pinField.typeText("test-pin")
        XCTAssertTrue(app.buttons["Sign with PIN"].isEnabled)
        app.buttons["Sign with PIN"].click()

        XCTAssertTrue(app.staticTexts["Signed"].waitForExistence(timeout: 3))
    }
}
