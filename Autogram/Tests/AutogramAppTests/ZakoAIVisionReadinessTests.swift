import XCTest
import AutogramKit
@testable import AutogramApp

@MainActor
final class ZakoAIVisionReadinessTests: XCTestCase {
    func testBuiltInModesReportBuiltInOnly() {
        let builtIn = ZakoSessionStore.aiVisionReadiness(
            for: AppSettings(aiMode: .builtInOnDevice))
        let disabled = ZakoSessionStore.aiVisionReadiness(
            for: AppSettings(aiMode: .disabled))

        guard case .builtInOnly(mode: .builtInOnDevice) = builtIn else {
            return XCTFail("Interný režim musí byť označený ako built-in only")
        }
        guard case .builtInOnly(mode: .disabled) = disabled else {
            return XCTFail("Vypnutý režim musí byť označený ako built-in only")
        }
    }

    func testMissingSelectedExternalConfigurationIsUnavailable() {
        let settings = AppSettings(aiMode: .omlxLocal, omlxURL: "", omlxModel: "")
        let readiness = ZakoSessionStore.aiVisionReadiness(for: settings)

        guard case .unavailable(provider: .omlxLocal, let reason) = readiness else {
            return XCTFail("Chýbajúca oMLX konfigurácia nesmie byť úspešná")
        }
        XCTAssertTrue(reason.contains("URL"))
    }
}
