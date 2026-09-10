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

    func testMobileSigningDefaultsAndRoundTrip() throws {
        let defaults = AppSettings()
        XCTAssertTrue(defaults.mobileSigningEnabled)
        XCTAssertEqual(defaults.avmBaseURL, "https://autogram.slovensko.digital/api/v1")
        XCTAssertEqual(defaults.avmBaseURLValue, AVMClient.publicBaseURL)

        var custom = defaults
        custom.mobileSigningEnabled = false
        custom.avmBaseURL = "https://avm.test/api/v1"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom))
        XCTAssertFalse(decoded.mobileSigningEnabled)
        XCTAssertEqual(decoded.avmBaseURLValue, URL(string: "https://avm.test/api/v1"))

        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.mobileSigningEnabled)

        var broken = defaults
        broken.avmBaseURL = "not a url"
        XCTAssertEqual(broken.avmBaseURLValue, AVMClient.publicBaseURL)
    }
}
