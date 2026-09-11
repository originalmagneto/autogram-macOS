import Foundation
import AppKit
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
        if let current {
            reply(current)
            return
        }
        // Nobody has registered, so Autogram is not running. Start it and wait:
        // otherwise every signature would need the person to launch the app
        // first, and the page would only ever hear that nothing is available.
        // The app can do nothing on its own with this - it raises a prompt that
        // has to be confirmed - so a page can cost the user a window, never a
        // signature.
        launchApp()
        waitForRegistration(reply: reply)
    }

    private func launchApp() {
        let workspace = NSWorkspace.shared
        if let url = appBundleURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            workspace.openApplication(at: url, configuration: configuration)
        } else {
            FileHandle.standardError.write(Data("Autogram bundle not found\n".utf8))
        }
    }

    /// The agent is installed inside the app bundle, so the app is three levels
    /// up from the binary. Falls back to asking the system by bundle id, which
    /// covers an agent copied elsewhere.
    private func appBundleURL() -> URL? {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidate = binary
            .deletingLastPathComponent()   // Helpers
            .deletingLastPathComponent()   // Contents
            .deletingLastPathComponent()   // Autogram macOS.app
        if candidate.pathExtension == "app", FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "sk.autogram.Autogram")
    }

    private func waitForRegistration(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        let deadline = Date().addingTimeInterval(20)
        func poll() {
            lock.lock()
            let current = endpoint
            lock.unlock()
            if let current {
                reply(current)
                return
            }
            guard Date() < deadline else {
                reply(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: poll)
        }
        poll()
    }
}

let delegate = Rendezvous()
let listener = NSXPCListener(machServiceName: WebSigningBridge.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
