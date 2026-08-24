import Foundation
import CryptoKit
import AutogramKit

struct Request: Codable {
    var cmd: String
    var certSHA: String?
    var digest: String?
    var pin: String?
}

struct CertEntry: Codable {
    var derBase64: String
    var isRSA: Bool
    var keyHandle: UInt64
    var slot: UInt64
    var tokenLabel: String
    var subjectSummary: String
    var issuerSummary: String
    var isMandateCertificate: Bool
    var isQualified: Bool
}

struct Response: Codable {
    var ok: Bool
    var certs: [CertEntry]?
    var signature: String?
    var error: String?
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func emit(_ response: Response) {
    let data = try! JSONEncoder().encode(response)
    FileHandle.standardOutput.write(Data("{\"ok\":\(response.ok),".utf8) + data.dropFirst() + Data("\n".utf8))
}

guard let line = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
    emit(Response(ok: false, certs: nil, signature: nil, error: "prázdny vstup")); exit(0)
}
guard let data = line.data(using: .utf8),
      let request = try? JSONDecoder().decode(Request.self, from: data) else {
    emit(Response(ok: false, certs: nil, signature: nil, error: "nečitateľná požiadavka")); exit(0)
}

guard let module = PKCS11Module.available() else {
    emit(Response(ok: false, certs: nil, signature: nil, error: PKCS11Error.moduleNotFound.localizedDescription)); exit(0)
}

switch request.cmd {
case "list":
    var certs: [CertEntry] = []
    let slots = module.slotsWithTokens()
    for slot in slots {
        do {
            let identities = try module.identities(slotID: slot)
            for identity in identities {
                certs.append(CertEntry(
                    derBase64: identity.certificateDER.base64EncodedString(),
                    isRSA: identity.isRSA,
                    keyHandle: identity.privateKeyHandle,
                    slot: identity.slotID,
                    tokenLabel: identity.tokenLabel,
                    subjectSummary: identity.subjectSummary,
                    issuerSummary: identity.issuerSummary,
                    isMandateCertificate: identity.isMandateCertificate,
                    isQualified: identity.isQualified))
            }
        } catch {
            if ProcessInfo.processInfo.environment["PKCS11_DEBUG"] != nil {
                FileHandle.standardError.write(Data("DEBUG identities ERROR: \(error)\n".utf8))
            }
        }
    }
    emit(Response(ok: true, certs: certs, signature: nil, error: nil))

case "sign":
    guard let certSHA = request.certSHA,
          let digestB64 = request.digest,
          let digest = Data(base64Encoded: digestB64),
          let pin = request.pin else {
        emit(Response(ok: false, certs: nil, signature: nil, error: "neúplná požiadavka na podpis")); exit(0)
    }
    do {
        guard let identity = module.discoverIdentities().first(where: {
            sha256Hex($0.certificateDER) == certSHA.lowercased() }) else {
            emit(Response(ok: false, certs: nil, signature: nil, error: "certifikát sa na karte nenašiel")); exit(0)
        }
        let signature = try module.sign(slotID: identity.slotID,
                                        privateKeyHandle: identity.privateKeyHandle,
                                        isRSA: identity.isRSA,
                                        digest: digest,
                                        pin: pin)
        emit(Response(ok: true, certs: nil, signature: signature.base64EncodedString(), error: nil))
    } catch {
        emit(Response(ok: false, certs: nil, signature: nil, error: error.localizedDescription))
    }

default:
    emit(Response(ok: false, certs: nil, signature: nil, error: "neznámy príkaz \(request.cmd)"))
}
