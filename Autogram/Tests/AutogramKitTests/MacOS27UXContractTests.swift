import Foundation
import XCTest
@testable import AutogramKit

final class MacOS27UXContractTests: XCTestCase {
    private var packageURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
    }

    func testMacOS27DeploymentContract() throws {
        let package = try String(contentsOf: packageURL, encoding: .utf8)
        XCTAssertTrue(package.contains(".macOS(\"27.0\")"))
    }

    func testEvidenceStatusDoesNotDependOnTimerOnly() {
        XCTAssertEqual(EvidenceRecord.submissionDeadlineInterval, 24 * 3600)
    }

    func testInspectorLayoutCanCollapseWithoutWideningRoot() {
        XCTAssertEqual(MacOS27Layout.inspectorMinimumWidth, 0)
        XCTAssertLessThan(
            MacOS27Layout.rootMinimumWidth,
            MacOS27Layout.canvasMinimumWidth + MacOS27Layout.inspectorIdealWidth)
    }
}
