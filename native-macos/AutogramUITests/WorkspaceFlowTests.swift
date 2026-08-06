import XCTest

final class WorkspaceFlowTests: XCTestCase {
    @MainActor
    func testWorkspaceShowsEmptyStateThenPartialFailureResults() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["No PDF Selected"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchEnvironment["AUTOGRAM_FAKE_ENGINE"] = "partial-failure"
        app.launch()

        XCTAssertTrue(app.otherElements["Workspace Sidebar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Agreement.pdf"].exists)
        XCTAssertTrue(app.staticTexts["Invoice.pdf"].exists)

        let signButton = app.buttons["Sign"]
        XCTAssertTrue(signButton.isEnabled)
        signButton.click()

        XCTAssertTrue(app.staticTexts["Signed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Failed"].exists)
        XCTAssertTrue(app.staticTexts["1 file signed, 1 failed"].exists)
        XCTAssertTrue(app.buttons["Reveal Agreement.pdf"].exists)
        XCTAssertTrue(app.buttons["Reveal Invoice.pdf"].exists)
    }
}
