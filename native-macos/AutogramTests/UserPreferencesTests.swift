import Foundation
import Testing
@testable import Autogram

@Test func preferencesNeverEncodePin() throws {
    let data = try JSONEncoder().encode(UserPreferences.fixture)

    #expect(!String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("pin"))
}
