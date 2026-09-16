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
    private let registry = WebBridgeEndpointRegistry()
    private var registrationCount = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: WebBridgeRendezvousProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func registerApp(endpoint: NSXPCListenerEndpoint) {
        lock.lock()
        registrationCount += 1
        let registration = registrationCount
        lock.unlock()
        registry.register(endpoint, registration: registration)
        // The app keeps this connection open while it runs. When it quits the
        // connection ends and its endpoint is forgotten; a remembered endpoint
        // of a quit app made every later request fail instead of launching it.
        if let connection = NSXPCConnection.current() {
            let registry = self.registry
            connection.invalidationHandler = { registry.connectionEnded(registration: registration) }
            connection.interruptionHandler = { registry.connectionEnded(registration: registration) }
        }
    }

    func appEndpoint(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        let appIsRunning = Self.appIsRunning()
        if let current = registry.current, appIsRunning {
            reply(current)
            return
        }
        if appIsRunning {
            // Already starting, typically for the previous request: wait for it to
            // register. Opening a running app again would count as a reopen and
            // bring up its main window and Dock icon.
            waitForRegistration(reply: reply)
            return
        }
        registry.forget()
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
            // Tells the app it was started for a portal request, so it shows only
            // the signing panel: no main window, no Dock icon.
            configuration.arguments = ["--web-signing"]
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

    private static func appIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "sk.autogram.Autogram").isEmpty
    }

    private func waitForRegistration(reply: @escaping (NSXPCListenerEndpoint?) -> Void) {
        let deadline = Date().addingTimeInterval(20)
        let registry = self.registry
        func poll() {
            if let current = registry.current {
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
