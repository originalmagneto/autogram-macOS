import Testing
@testable import Autogram

@Test func applicationIdentityIsStable() {
    #expect(AppIdentity.bundleIdentifier == "digital.slovensko.autogram.native")
    #expect(AppIdentity.minimumSystemVersion == "27.0")
}
