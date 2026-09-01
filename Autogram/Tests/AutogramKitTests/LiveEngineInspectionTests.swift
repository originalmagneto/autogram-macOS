import Foundation
import XCTest
@testable import AutogramKit

final class LiveEngineInspectionTests: XCTestCase {
    func testProviderInspectionDoesNotRequireTrustedList() async throws {
        guard ProcessInfo.processInfo.environment["AUTOGRAM_ENGINE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Vyžaduje AUTOGRAM_ENGINE_LIVE_TEST=1.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-engine-inspection-\(UUID().uuidString).pdf")
        try TestPDFBuilder.singlePageWhitePDF().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await EngineBridgeSigningProvider().inspectInputSignatures(in: url)
        XCTAssertNotEqual(result.state, .unavailable, result.detail)
    }
}
