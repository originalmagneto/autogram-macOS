import Foundation
import AutogramWebBridge

// Connects to the Mach service the running app publishes and calls status.
// Proves the app half of the Safari bridge without Safari, which is the only
// part of the chain that cannot be automated: enabling an unsigned extension is
// an in-memory Safari setting with no preference key.

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1

let agent = NSXPCConnection(machServiceName: WebSigningBridge.machServiceName, options: [])
agent.remoteObjectInterface = NSXPCInterface(with: WebBridgeRendezvousProtocol.self)
agent.resume()

agent.interruptionHandler = {
    FileHandle.standardError.write(Data("XPC spojenie prerušené: appka pravdepodobne nebeží.\n".utf8))
    semaphore.signal()
}
agent.invalidationHandler = {
    FileHandle.standardError.write(Data("XPC spojenie neplatné: služba \(WebSigningBridge.machServiceName) nie je publikovaná.\n".utf8))
    semaphore.signal()
}

guard let rendezvous = agent.remoteObjectProxyWithErrorHandler({ error in
    FileHandle.standardError.write(Data("XPC chyba: \(error.localizedDescription)\n".utf8))
    semaphore.signal()
}) as? WebBridgeRendezvousProtocol else {
    FileHandle.standardError.write(Data("Nepodarilo sa získať proxy agenta.\n".utf8))
    exit(1)
}

rendezvous.appEndpoint { endpoint in
    guard let endpoint else {
        FileHandle.standardError.write(Data("Agent beží, ale aplikácia sa uňho nezaregistrovala.\n".utf8))
        semaphore.signal()
        return
    }
    let app = NSXPCConnection(listenerEndpoint: endpoint)
    app.remoteObjectInterface = NSXPCInterface(with: WebSigningBridgeProtocol.self)
    app.resume()
    guard let proxy = app.remoteObjectProxyWithErrorHandler({ error in
        FileHandle.standardError.write(Data("Spojenie s aplikáciou zlyhalo: \(error.localizedDescription)\n".utf8))
        semaphore.signal()
    }) as? WebSigningBridgeProtocol else {
        semaphore.signal()
        return
    }
    proxy.status { ready, version in
        print("Mach service : \(WebSigningBridge.machServiceName) (launchd agent)")
        print("Autogram     : \(version)")
        print("Ready to sign: \(ready ? "áno" : "nie (sign handler nie je zapojený)")")
        print("")
        print("Transport funguje: agent našiel aplikáciu a tá odpovedala cez XPC.")
        exitCode = 0
        semaphore.signal()
    }
}

_ = semaphore.wait(timeout: .now() + 10)
agent.invalidate()
exit(exitCode)
