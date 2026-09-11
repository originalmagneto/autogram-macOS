import Foundation
import AutogramWebBridge

// On-demand launchd agent that owns the Mach service name.
//
// It exists because launchd, not the app, decides who may publish a named Mach
// service. The agent holds the name and does nothing else: the app registers
// its own anonymous endpoint here, the sandboxed Safari extension asks for that
// endpoint, and the two then talk directly. No document ever passes through it.

final class Rendezvous: NSObject, NSXPCListenerDelegate, WebBridgeRendezvousProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var endpoint: NSXPCListenerEndpoint?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WebBridgeRendezvousProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func registerApp(endpoint: NSXPCListenerEndpoint) {
        lock.lock()
        defer { lock.unlock() }
        self.endpoint = endpoint
    }

    func appEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        lock.lock()
        let current = endpoint
        lock.unlock()
        reply(current)
    }
}

let delegate = Rendezvous()
let listener = NSXPCListener(machServiceName: WebSigningBridge.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
