import Foundation
import AutogramWebBridge

#if canImport(SafariServices)
import SafariServices
#endif

/// Safari web extension handler.
///
/// Safari runs this sandboxed, so it can neither spawn the signing engine nor
/// reach the card. It is a relay and nothing else: it forwards the extension's
/// native message to the app over the Mach service the app publishes, and hands
/// the answer back.
@objc(AutogramWebExtensionHandler)
final class AutogramWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        forward(message: message) { reply in
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private func forward(message: Any?, completion: @escaping ([String: Any]) -> Void) {
        guard let message = message as? [String: Any],
              let kind = message["kind"] as? String else {
            completion(["ok": false, "error": "Neplatná správa z rozšírenia."])
            return
        }

        let connection = NSXPCConnection(machServiceName: WebSigningBridge.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: WebSigningBridgeProtocol.self)
        connection.resume()

        // Only one reply may ever be delivered: the sandbox turns a missing app
        // into an interruption rather than an error, so both paths land here.
        let replied = Replied()
        let finish: ([String: Any]) -> Void = { payload in
            guard replied.claim() else { return }
            connection.invalidate()
            completion(payload)
        }

        let unavailable = ["ok": false, "error": "Autogram macOS nebeží alebo nie je dostupný."] as [String: Any]
        connection.interruptionHandler = { finish(unavailable) }
        connection.invalidationHandler = { finish(unavailable) }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            finish(["ok": false, "error": "Spojenie s Autogramom zlyhalo: \(error.localizedDescription)"])
        }) as? WebSigningBridgeProtocol else {
            finish(unavailable)
            return
        }

        switch kind {
        case "status":
            proxy.status { ready, version in
                finish(["ok": true, "ready": ready, "version": version])
            }
        case "sign":
            guard let requestJSON = message["request"] as? String,
                  let data = requestJSON.data(using: .utf8) else {
                finish(["ok": false, "error": "Požiadavka na podpis je poškodená."])
                return
            }
            proxy.sign(request: data) { response, error in
                if let error {
                    finish(["ok": false, "error": error])
                    return
                }
                guard let response, let text = String(data: response, encoding: .utf8) else {
                    finish(["ok": false, "error": "Autogram vrátil prázdnu odpoveď."])
                    return
                }
                finish(["ok": true, "response": text])
            }
        default:
            finish(["ok": false, "error": "Neznámy typ správy: \(kind)"])
        }
    }
}

/// Guards the single-reply rule across the XPC handlers, which can fire on
/// different queues.
private final class Replied: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// The appex entry point lives in Foundation but is not surfaced to Swift, so it
// is declared directly. Xcode templates get this from the NSExtensionMain
// linker flag; a SwiftPM-built extension has to ask for it by name.
@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

exit(NSExtensionMain())
