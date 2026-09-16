import Foundation

/// The app endpoint the rendezvous agent hands to the Safari extension, valid only
/// while the app that registered it is still connected.
///
/// Each registration is tied to the app's connection to the agent. When that
/// connection ends because the app quit, the endpoint is forgotten, so the next
/// request launches the app instead of receiving an endpoint nobody listens on.
public final class WebBridgeEndpointRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var endpoint: NSXPCListenerEndpoint?
    private var registration: Int?

    public init() {}

    public var current: NSXPCListenerEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return endpoint
    }

    public func register(_ endpoint: NSXPCListenerEndpoint, registration: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.endpoint = endpoint
        self.registration = registration
    }

    /// Called when the connection a registration came in on is interrupted or
    /// invalidated. A newer registration is kept.
    public func connectionEnded(registration: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard self.registration == registration else { return }
        endpoint = nil
        self.registration = nil
    }

    public func forget() {
        lock.lock()
        defer { lock.unlock() }
        endpoint = nil
        registration = nil
    }
}
