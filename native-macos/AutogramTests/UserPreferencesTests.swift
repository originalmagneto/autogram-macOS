import Foundation
import Testing
@testable import Autogram

@Test func preferencesNeverEncodePin() throws {
    let data = try JSONEncoder().encode(UserPreferences.fixture)

    #expect(!String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("pin"))
}

@Test func customTimestampPreferencesKeepEndpointOrderWithoutEncodingCredentials() throws {
    let configuration = TimestampSourceConfiguration(
        source: .custom,
        customProvider: CustomTimestampProviderConfiguration(
            displayName: "Provider",
            urls: ["https://first.example.test", "https://second.example.test"],
            authentication: TimestampAuthenticationPreference(kind: .basic, username: "timestamp-user")
        )
    )

    let data = try JSONEncoder().encode(configuration)
    let text = String(decoding: data, as: UTF8.self)

    #expect(configuration.endpoints == ["https://first.example.test", "https://second.example.test"])
    #expect(!text.contains("timestamp-password"))
    #expect(!text.contains("token"))
}
