import Foundation
import AutogramWebBridge

// Connects to the Mach service the running app publishes and calls status.
// Proves the app half of the Safari bridge without Safari, which is the only
// part of the chain that cannot be automated: enabling an unsigned extension is
// an in-memory Safari setting with no preference key.

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1
// Tearing the connection down at the end fires the invalidation handler too,
// and reporting that as a failure would contradict the result just printed.
nonisolated(unsafe) var finished = false

let agent = NSXPCConnection(machServiceName: WebSigningBridge.machServiceName, options: [])
agent.remoteObjectInterface = NSXPCInterface(with: WebBridgeRendezvousProtocol.self)
agent.resume()

agent.interruptionHandler = {
    guard !finished else { return }
    FileHandle.standardError.write(Data("XPC spojenie prerušené: appka pravdepodobne nebeží.\n".utf8))
    semaphore.signal()
}
agent.invalidationHandler = {
    guard !finished else { return }
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
    if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--sign" {
        let path = CommandLine.arguments[2]
        guard let data = FileManager.default.contents(atPath: path) else {
            FileHandle.standardError.write(Data("Nepodarilo sa prečítať \(path)\n".utf8))
            semaphore.signal()
            return
        }
        let isXML = path.lowercased().hasSuffix(".xml")
        // An XML payload is treated as a state-portal eForm, with a self-contained
        // namespace so no registry lookup happens.
        let eform: EFormSigningAttributes? = isXML ? EFormSigningAttributes(
            schema: """
            <?xml version="1.0" encoding="UTF-8"?>
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns="http://probe.local/form/1.0"             targetNamespace="http://probe.local/form/1.0" elementFormDefault="qualified">            <xs:element name="Ziadost"><xs:complexType><xs:sequence>            <xs:element name="Meno" type="xs:string"/></xs:sequence></xs:complexType></xs:element></xs:schema>
            """,
            transformation: """
            <?xml version="1.0" encoding="UTF-8"?>
            <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"             xmlns:z="http://probe.local/form/1.0"><xsl:template match="/"><html><body><h1>            <xsl:value-of select="z:Ziadost/z:Meno"/></h1></body></html></xsl:template></xsl:stylesheet>
            """,
            identifier: "http://probe.local/form/1.0",
            transformationLanguage: "sk",
            transformationMediaDestinationTypeDescription: "HTML",
            transformationTargetEnvironment: "probe",
            embedUsedSchemas: true,
            packaging: "ENVELOPING") : nil
        let request = WebSignRequest(
            requestID: UUID().uuidString,
            filename: (path as NSString).lastPathComponent,
            content: data.base64EncodedString(),
            payloadMimeType: isXML ? "application/xml;base64" : "application/pdf;base64",
            signatureLevel: isXML ? "XAdES_BASELINE_B" : "PAdES_BASELINE_T",
            eform: eform)
        print("Posielam požiadavku na podpis: \(request.filename) (\(data.count) B)")
        print("V aplikácii sa má otvoriť okno so žiadosťou o PIN.")
        proxy.sign(request: try! JSONEncoder().encode(request)) { response, error in
            if let error {
                FileHandle.standardError.write(Data("Podpis zlyhal: \(error)\n".utf8))
                semaphore.signal()
                return
            }
            guard let response,
                  let decoded = try? JSONDecoder().decode(WebSignResponse.self, from: response),
                  let signed = Data(base64Encoded: decoded.content) else {
                FileHandle.standardError.write(Data("Odpoveď sa nepodarilo prečítať.\n".utf8))
                semaphore.signal()
                return
            }
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("webbridge-signed-\(decoded.requestID.prefix(8))")
                .appendingPathExtension(isXML ? "asice" : "pdf")
            try? signed.write(to: out)
            print("Podpísané: \(decoded.signedBy)")
            print("Vydal    : \(decoded.issuedBy)")
            print("Súbor    : \(out.path) (\(signed.count) B)")
            exitCode = 0
            finished = true
            semaphore.signal()
        }
        return
    }

    proxy.status { ready, version in
        print("Mach service : \(WebSigningBridge.machServiceName) (launchd agent)")
        print("Autogram     : \(version)")
        print("Ready to sign: \(ready ? "áno" : "nie (sign handler nie je zapojený)")")
        print("")
        print("Transport funguje: agent našiel aplikáciu a tá odpovedala cez XPC.")
        exitCode = 0
        finished = true
        semaphore.signal()
    }
}

_ = semaphore.wait(timeout: .now() + 300)
agent.invalidate()
exit(exitCode)
