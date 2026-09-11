import Foundation
import AutogramKit
import AutogramWebBridge
import os

/// Publishes the Mach service the Safari web extension handler connects to.
///
/// The handler is sandboxed and can do nothing useful on its own, so everything
/// it receives from a state portal arrives here. Only the extension inside our
/// own bundle is entitled to look the service up.
final class WebBridgeListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    static let shared = WebBridgeListener()

    private let log = Logger(subsystem: "sk.autogram.Autogram", category: "web-bridge")
    private var listener: NSXPCListener?
    private var rendezvous: NSXPCConnection?
    private let lock = NSLock()
    private var signHandler: (@Sendable (WebSignRequest) async throws -> WebSignResponse)?

    /// Installs the handler that turns a portal request into a real signature.
    /// Kept injectable so the transport can be exercised without the signing UI.
    func setSignHandler(_ handler: @escaping @Sendable (WebSignRequest) async throws -> WebSignResponse) {
        lock.lock()
        defer { lock.unlock() }
        signHandler = handler
    }

    /// Publishes an anonymous listener and registers it with the launchd agent.
    ///
    /// launchd owns the Mach service name and only hands it to the process it
    /// launches, so the app cannot claim it directly. It publishes an anonymous
    /// endpoint instead and leaves the name to the agent.
    func start() {
        guard listener == nil else { return }
        let listener = NSXPCListener.anonymous()
        listener.delegate = self
        listener.resume()
        self.listener = listener

        let connection = NSXPCConnection(machServiceName: WebSigningBridge.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: WebBridgeRendezvousProtocol.self)
        connection.resume()
        self.rendezvous = connection

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [log] error in
            log.error("Web bridge agent unreachable: \(error.localizedDescription, privacy: .public)")
        }) as? WebBridgeRendezvousProtocol else {
            log.error("Web bridge agent proxy unavailable")
            return
        }
        proxy.registerApp(endpoint: listener.endpoint)
        log.info("Web bridge registered with \(WebSigningBridge.machServiceName, privacy: .public)")
    }

    func stop() {
        rendezvous?.invalidate()
        rendezvous = nil
        listener?.invalidate()
        listener = nil
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WebSigningBridgeProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

/// Carries the XPC reply closure into the signing task. NSXPC guarantees the
/// reply is invoked at most once, which this type does not itself enforce.
private final class ReplyBox: @unchecked Sendable {
    let value: (Data?, String?) -> Void

    init(_ value: @escaping (Data?, String?) -> Void) {
        self.value = value
    }
}

extension WebBridgeListener: WebSigningBridgeProtocol {
    func status(reply: @escaping (Bool, String) -> Void) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "dev"
        lock.lock()
        let ready = signHandler != nil
        lock.unlock()
        reply(ready, version)
    }

    func sign(request: Data, reply: @escaping (Data?, String?) -> Void) {
        lock.lock()
        let handler = signHandler
        lock.unlock()

        guard let handler else {
            reply(nil, "Podpisovanie z prehliadača zatiaľ nie je v tejto zostave zapojené.")
            return
        }

        let decoded: WebSignRequest
        do {
            decoded = try JSONDecoder().decode(WebSignRequest.self, from: request)
        } catch {
            log.error("Rejected a malformed web sign request: \(String(describing: error), privacy: .public)")
            reply(nil, "Požiadavka na podpis je poškodená.")
            return
        }

        // NSXPC hands back a plain closure; the signing work is async, so it is
        // carried across the task boundary explicitly.
        let sendableReply = ReplyBox(reply)
        Task {
            do {
                let response = try await handler(decoded)
                sendableReply.value(try JSONEncoder().encode(response), nil)
            } catch {
                sendableReply.value(nil, error.localizedDescription)
            }
        }
    }
}
