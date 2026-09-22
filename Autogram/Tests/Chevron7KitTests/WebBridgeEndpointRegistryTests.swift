import Foundation
import XCTest
@testable import Chevron7Kit

/// The agent used to keep the app's endpoint after the app quit, so every later
/// request got a dead endpoint instead of a launch, and signing from Safari only
/// worked while Chevron7 was already open.
final class WebBridgeEndpointRegistryTests: XCTestCase {
    func testRegisteredEndpointIsReturnedWhileTheAppIsConnected() {
        let registry = WebBridgeEndpointRegistry()
        let endpoint = NSXPCListener.anonymous().endpoint

        registry.register(endpoint, registration: 1)

        XCTAssertTrue(registry.current === endpoint)
    }

    func testEndpointIsForgottenWhenTheAppConnectionEnds() {
        let registry = WebBridgeEndpointRegistry()
        registry.register(NSXPCListener.anonymous().endpoint, registration: 1)

        registry.connectionEnded(registration: 1)

        XCTAssertNil(registry.current)
    }

    /// A relaunched app registers before the old connection's end is reported.
    func testAnOldConnectionEndingKeepsTheNewerRegistration() {
        let registry = WebBridgeEndpointRegistry()
        registry.register(NSXPCListener.anonymous().endpoint, registration: 1)
        let newer = NSXPCListener.anonymous().endpoint
        registry.register(newer, registration: 2)

        registry.connectionEnded(registration: 1)

        XCTAssertTrue(registry.current === newer)
    }

    func testForgetClearsTheEndpoint() {
        let registry = WebBridgeEndpointRegistry()
        registry.register(NSXPCListener.anonymous().endpoint, registration: 1)

        registry.forget()

        XCTAssertNil(registry.current)
    }
}
