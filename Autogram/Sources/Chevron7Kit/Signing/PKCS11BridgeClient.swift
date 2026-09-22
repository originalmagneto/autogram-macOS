import Foundation
import CryptoKit

public struct PKCS11RemoteIdentity: Sendable {
    public var certificateDER: Data
    public var isRSA: Bool
    public var slotID: UInt64
    public var keyHandle: UInt64
    public var tokenLabel: String
    public var subjectSummary: String
    public var issuerSummary: String
    public var isMandateCertificate: Bool
    public var isQualified: Bool
    public var certSHA256Hex: String
}

public enum PKCS11BridgeError: LocalizedError, Sendable {
    case helperNotFound
    case helperFailed(String)
    case rosettaMissing

    public var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "pkcs11-helper nebol nájdený — preinštaluj aplikáciu."
        case .helperFailed(let detail):
            return detail
        case .rosettaMissing:
            return "Pre eID podpisovanie je potrebná Rosetta 2 (softwareupdate --install-rosetta)."
        }
    }
}

public enum PKCS11BridgeClient {
    struct Response: Codable {
        var ok: Bool
        var certs: [Cert]?
        var signature: String?
        var error: String?

        struct Cert: Codable {
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
    }

    struct Request: Codable {
        var cmd: String
        var certSHA: String?
        var digest: String?
        var pin: String?
    }

    public static func helperURL() -> URL? {
        var candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pkcs11-helper"),
            URL(fileURLWithPath: "/Applications/Autogram macOS.app/Contents/MacOS/pkcs11-helper")
        ]
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent()
                .appendingPathComponent("pkcs11-helper"))
            candidates.append(executable.deletingLastPathComponent()
                .appendingPathComponent("../../../../x86_64-apple-macosx/release/pkcs11-helper")
                .standardized)
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @discardableResult
    static func run(request: Request, timeout: TimeInterval = 30) throws -> Response {
        guard let helper = helperURL() else { throw PKCS11BridgeError.helperNotFound }
        let process = Process()
        process.executableURL = helper
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] = "/Library/AWP/lib"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw PKCS11BridgeError.rosettaMissing
        }

        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0A)
        stdin.fileHandleForWriting.write(requestData)
        stdin.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(timeout)
        var output = Data()
        while Date() < deadline {
            let chunk = stdout.fileHandleForReading.availableData
            if !chunk.isEmpty {
                output.append(chunk)
                if output.contains(0x0A) { break }
            }
            if !process.isRunning {
                if !output.isEmpty { break }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        guard let line = output.split(separator: 0x0A).first,
              let response = try? JSONDecoder().decode(Response.self, from: Data(line)) else {
            throw PKCS11BridgeError.helperFailed("Helper neodpovedal.")
        }
        guard response.ok else {
            throw PKCS11BridgeError.helperFailed(response.error ?? "neznáma chyba helpera")
        }
        return response
    }

    public static func listIdentities() -> [PKCS11RemoteIdentity] {
        guard let response = try? run(request: Request(cmd: "list", certSHA: nil,
                                                       digest: nil, pin: nil)),
              let certs = response.certs else { return [] }
        return certs.map { cert in
            PKCS11RemoteIdentity(
                certificateDER: Data(base64Encoded: cert.derBase64) ?? Data(),
                isRSA: cert.isRSA,
                slotID: cert.slot,
                keyHandle: cert.keyHandle,
                tokenLabel: cert.tokenLabel,
                subjectSummary: cert.subjectSummary,
                issuerSummary: cert.issuerSummary,
                isMandateCertificate: cert.isMandateCertificate,
                isQualified: cert.isQualified,
                certSHA256Hex: AttestationClauseGenerator.sha256Hex(
                    of: Data(base64Encoded: cert.derBase64) ?? Data()))
        }
    }

    public static func sign(certSHA256Hex: String, pin: String, digest: Data) throws -> Data {
        let response = try run(request: Request(cmd: "sign",
                                                certSHA: certSHA256Hex.lowercased(),
                                                digest: digest.base64EncodedString(),
                                                pin: pin), timeout: 60)
        guard let signature = Data(base64Encoded: response.signature ?? "") else {
            throw PKCS11BridgeError.helperFailed("prázdny podpis")
        }
        return signature
    }
}
