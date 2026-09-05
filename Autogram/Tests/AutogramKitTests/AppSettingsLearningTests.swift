import XCTest
@testable import AutogramKit

final class AppSettingsLearningTests: XCTestCase {
    func testDefaultsAreOn() {
        let settings = AppSettings()
        XCTAssertTrue(settings.useFoundationModelClassifier)
        XCTAssertTrue(settings.learnFromReviews)
    }

    func testLegacyJSONWithoutNewKeysDecodesToDefaults() throws {
        let json = #"{"aiMode":"Interný (on-device Vision)"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertTrue(settings.useFoundationModelClassifier)
        XCTAssertTrue(settings.learnFromReviews)
    }

    func testTogglesRoundTrip() throws {
        var settings = AppSettings()
        settings.useFoundationModelClassifier = false
        settings.learnFromReviews = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.useFoundationModelClassifier)
        XCTAssertFalse(decoded.learnFromReviews)
    }
}
