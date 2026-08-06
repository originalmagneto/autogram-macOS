import Foundation
import Testing
@testable import Autogram

@Test func x8664OnlyDriverIsRejectedWithArm64Required() throws {
    let helperURL = URL(fileURLWithPath: "/fixture/helper")
    let driverURL = URL(fileURLWithPath: "/fixture/driver.dylib")
    let resolver = DriverResolver(lipo: FixtureLipo(architectures: [helperURL: [.arm64], driverURL: [.x86_64]]))

    #expect(throws: DriverRequirementError.arm64Required) {
        try resolver.resolve(helperURL: helperURL, driver: .init(url: driverURL))
    }
}

@Test func ica810IsRejectedWithMinimum831() throws {
    let helperURL = URL(fileURLWithPath: "/fixture/helper")
    let driverURL = URL(fileURLWithPath: "/fixture/driver.dylib")
    let resolver = DriverResolver(lipo: FixtureLipo(architectures: [helperURL: [.arm64], driverURL: [.arm64]]))

    #expect(throws: DriverRequirementError.icaSecureStoreUpdateRequired(minimum: "8.3.1")) {
        try resolver.resolve(helperURL: helperURL, driver: .icaSecureStore(url: driverURL, version: "8.1.0"))
    }
}

@Test func arm64HelperAndSelectedDriverResolveToOneResolvedDriver() throws {
    let helperURL = URL(fileURLWithPath: "/fixture/helper")
    let driverURL = URL(fileURLWithPath: "/fixture/driver.dylib")
    let resolver = DriverResolver(lipo: FixtureLipo(architectures: [helperURL: [.arm64], driverURL: [.arm64]]))

    let resolved = try resolver.resolve(helperURL: helperURL, driver: .icaSecureStore(url: driverURL, version: "8.3.1"))

    #expect(resolved == ResolvedDriver(helperURL: helperURL, driverURL: driverURL, architecture: .arm64, middlewareVersion: "8.3.1"))
}

private struct FixtureLipo: LipoProcess {
    let architectures: [URL: Set<MachOArchitecture>]

    func architectures(at url: URL) throws -> Set<MachOArchitecture> {
        architectures[url] ?? []
    }
}
