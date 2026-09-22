import Foundation
import Security
import CryptoKit

public enum PKCS11Error: LocalizedError, Sendable {
    case moduleNotFound
    case initializeFailed(UInt64)
    case sessionFailed(UInt64)
    case loginFailed(UInt64)
    case signFailed(UInt64)
    case attributeFailed(UInt64)
    case unsupportedMechanism

    public var errorDescription: String? {
        switch self {
        case .moduleNotFound: return "PKCS#11 modul eID nebol nájdený — nainštaluj eID middleware."
        case .initializeFailed(let rv): return "Inicializácia PKCS#11 zlyhala (0x\(String(rv, radix: 16)))."
        case .sessionFailed(let rv): return "Nepodarilo sa otvoriť session ku karte (0x\(String(rv, radix: 16)))."
        case .loginFailed(let rv): return "Prihlásenie na kartu zlyhalo (0x\(String(rv, radix: 16))) — skontroluj PIN."
        case .signFailed(let rv): return "Podpisovanie na karte zlyhalo (0x\(String(rv, radix: 16)))."
        case .attributeFailed(let rv): return "Čítanie objektu z karty zlyhalo (0x\(String(rv, radix: 16)))."
        case .unsupportedMechanism: return "Karta nepodporuje požadovaný podpisový mechanizmus."
        }
    }
}

public struct PKCS11Identity: Sendable {
    public var modulePath: String
    public var slotID: UInt64
    public var tokenLabel: String
    public var certificateDER: Data
    public var privateKeyHandle: UInt64
    public var isRSA: Bool
    public var subjectSummary: String
    public var issuerSummary: String
    public var isMandateCertificate: Bool
    public var isQualified: Bool
}

public final class PKCS11Module: @unchecked Sendable {
    public let path: String
    private let handle: UnsafeMutableRawPointer
    private var session: UInt64 = 0
    private var loggedIn = false
    private let lock = NSLock()

    public static let candidatePaths = [
        "/Applications/eID_klient.app/Contents/Frameworks/libPkcs11.dylib",
        "/opt/homebrew/lib/opensc-pkcs11.so",
        "/opt/homebrew/lib/onepin-opensc-pkcs11.so",
        "/Library/AWP/lib/libOcsCryptoki.dylib",
        "/Library/AWP/lib/libOcsPKCS11Wrapper.dylib",
        "/Library/Frameworks/GemaltoIDGo800PKCS11.framework/GemaltoIDGo800PKCS11",
        "/usr/local/lib/libidemiapkcs11.dylib",
        "/Library/OpenSC/lib/onepin-opensc-pkcs11.so",
        "/usr/local/lib/onepin-opensc-pkcs11.so",
        "/usr/lib/softhsm/libsofthsm2.so"
    ]

    public static func available() -> PKCS11Module? {
        if let override = ProcessInfo.processInfo.environment["PKCS11_MODULE_PATH"],
           FileManager.default.fileExists(atPath: override) {
            return PKCS11Module(path: override)
        }
        var fallback: PKCS11Module?
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            guard let module = PKCS11Module(path: path) else { continue }
            if !module.slotsWithTokens().isEmpty { return module }
            if fallback == nil { fallback = module }
        }
        return fallback
    }

    public init?(path: String) {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL),
              let symbol = dlsym(handle, "C_GetFunctionList") else { return nil }
        let getFunctionList = unsafeBitCast(symbol,
            to: (@convention(c)(UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> UInt64).self)
        var listPtr: UnsafeMutableRawPointer?
        guard getFunctionList(&listPtr) == 0, let list = listPtr else {
            dlclose(handle); return nil
        }
        self.path = path
        self.handle = handle

        let initialize: (@convention(c)(UnsafeMutableRawPointer?) -> UInt64) =
            unsafeBitCast(dlsym(handle, "C_Initialize"), to: (@convention(c)(UnsafeMutableRawPointer?) -> UInt64).self)

        var initArgs = CKInitializeArgs(
            createMutex: nil, destroyMutex: nil, lockMutex: nil, unlockMutex: nil,
            flags: 0x2, reserved: nil)
        let rvNoArgs = initialize(nil)
        var rv = rvNoArgs
        if rvNoArgs != 0 {
            rv = withUnsafeMutableBytes(of: &initArgs) { raw in
                initialize(UnsafeMutableRawPointer(mutating: raw.baseAddress!))
            }
        }
        guard rv == 0 || rv == 0x191 else { dlclose(handle); return nil }
        Thread.sleep(forTimeInterval: 0.3)
    }

    deinit {
        if session != 0 {
            if loggedIn {
                let logout: (@convention(c)(UInt64) -> UInt64) = unsafeBitCast(dlsym(handle, "C_Logout"), to: (@convention(c)(UInt64) -> UInt64).self)
                _ = logout(session)
            }
            let closeSession: (@convention(c)(UInt64) -> UInt64) = unsafeBitCast(dlsym(handle, "C_CloseSession"), to: (@convention(c)(UInt64) -> UInt64).self)
            _ = closeSession(session)
        }
        dlclose(handle)
    }

    private func cfunc<T>(_ name: String, as: T.Type) -> T {
        guard let symbol = dlsym(handle, name) else {
            fatalError("PKCS#11 modul neexportuje \(name)")
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    // MARK: - Slots & tokens

    public func slotsWithTokens() -> [UInt64] {
        typealias GetSlotList = @convention(c)(UInt8, UnsafeMutablePointer<UInt64>?, UnsafeMutablePointer<UInt64>) -> UInt64
        let getSlotList: GetSlotList = cfunc("C_GetSlotList", as: GetSlotList.self)
        var count: UInt64 = 0
        if ProcessInfo.processInfo.environment["PKCS11_DEBUG"] != nil { fputs("PKCS11: C_GetSlotList count\n", stderr) }
        guard getSlotList(1, nil, &count) == 0, count > 0 else { return [] }
        if ProcessInfo.processInfo.environment["PKCS11_DEBUG"] != nil { fputs("PKCS11: slotov: \(count)\n", stderr) }
        var slots = [UInt64](repeating: 0, count: Int(count))
        guard getSlotList(1, &slots, &count) == 0 else { return [] }
        return Array(slots[0..<Int(count)])
    }

    public func debugSlotReport() -> String {
        typealias GetSlotList = @convention(c)(UInt8, UnsafeMutablePointer<UInt64>?, UnsafeMutablePointer<UInt64>) -> UInt64
        typealias GetTokenInfo = @convention(c)(UInt64, UnsafeMutableRawPointer) -> UInt64
        typealias OpenSession = @convention(c)(UInt64, UInt64, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt64>) -> UInt64
        let getSlotList: GetSlotList = cfunc("C_GetSlotList", as: GetSlotList.self)
        let getTokenInfo: GetTokenInfo = cfunc("C_GetTokenInfo", as: GetTokenInfo.self)
        let openSession: OpenSession = cfunc("C_OpenSession", as: OpenSession.self)

        var out: [String] = []
        for present in [UInt8(0), UInt8(1)] {
            var count: UInt64 = 0
            guard getSlotList(present, nil, &count) == 0 else { out.append("slotList(\(present)) FAIL"); continue }
            var ids = [UInt64](repeating: 0, count: Int(count))
            _ = getSlotList(present, &ids, &count)
            out.append("slotList(present=\(present)): \(Array(ids[0..<Int(count)]))")
            for id in ids.prefix(Int(count)) {
                var buffer = [UInt8](repeating: 0, count: 512)
                let rv = getTokenInfo(id, &buffer)
                let label = rv == 0 ? String(decoding: Data(buffer[0..<32]).prefix { $0 != 0 }, as: UTF8.self) : ""
                var session: UInt64 = 0
                let osRV = openSession(id, 0x4, nil, &session)
                out.append("  slot \(id): tokenRV=0x\(String(rv, radix: 16)) label='\(label)' openRV=0x\(String(osRV, radix: 16))")
                if osRV == 0 {
                    let closeSession: (@convention(c)(UInt64) -> UInt64) = cfunc("C_CloseSession", as: (@convention(c)(UInt64) -> UInt64).self)
                    _ = closeSession(session)
                }
            }
        }
        return out.joined(separator: "\n")
    }

    public func tokenLabel(slotID: UInt64) -> String {
        typealias GetTokenInfo = @convention(c)(UInt64, UnsafeMutableRawPointer) -> UInt64
        let getTokenInfo: GetTokenInfo = cfunc("C_GetTokenInfo", as: GetTokenInfo.self)
        var buffer = [UInt8](repeating: 0, count: 512)
        guard getTokenInfo(slotID, &buffer) == 0 else { return "" }
        let label = Data(buffer[0..<32]).prefix { $0 != 0 }
        return String(decoding: label, as: UTF8.self)
    }

    // MARK: - Session & login

    private func ensureSession(slotID: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        if session != 0 { return }
        typealias OpenSession = @convention(c)(UInt64, UInt64, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt64>) -> UInt64
        let openSession: OpenSession = cfunc("C_OpenSession", as: OpenSession.self)
        var newSession: UInt64 = 0
        let rv = openSession(slotID, 0x4, nil, &newSession)
        guard rv == 0 else { throw PKCS11Error.sessionFailed(rv) }
        session = newSession
    }

    public func login(slotID: UInt64, pin: String) throws {
        try ensureSession(slotID: slotID)
        lock.lock(); defer { lock.unlock() }
        guard !loggedIn else { return }
        typealias Login = @convention(c)(UInt64, UInt64, UnsafePointer<UInt8>?, UInt64) -> UInt64
        let login: Login = cfunc("C_Login", as: Login.self)
        let pinBytes = Array(pin.utf8)
        let rv = login(session, 1, pinBytes.isEmpty ? nil : pinBytes, UInt64(pinBytes.count))
        guard rv == 0 else { throw PKCS11Error.loginFailed(rv) }
        loggedIn = true
    }

    // MARK: - Objects

    private func findObjects(objectClass: UInt64) throws -> [UInt64] {
        typealias FindObjectsInit = @convention(c)(UInt64, UnsafeRawPointer, UInt64) -> UInt64
        let findInit: FindObjectsInit = cfunc("C_FindObjectsInit", as: FindObjectsInit.self)

        var classValue = objectClass
        var classAttribute = CKAttribute(type: 0x00000000, pValue: nil, valueLen: 0)
        let initRV = withUnsafeMutableBytes(of: &classValue) { raw in
            classAttribute.pValue = raw.baseAddress
            classAttribute.valueLen = UInt64(MemoryLayout<UInt64>.size)
            return withUnsafeMutablePointer(to: &classAttribute) {
                findInit(session, UnsafeRawPointer($0), 1)
            }
        }
        guard initRV == 0 else { throw PKCS11Error.attributeFailed(initRV) }

        typealias FindObjects = @convention(c)(UInt64, UnsafeMutablePointer<UInt64>, UInt64, UnsafeMutablePointer<UInt64>, UnsafeMutableRawPointer?) -> UInt64
        let findObjects: FindObjects = cfunc("C_FindObjects", as: FindObjects.self)

        var handles: [UInt64] = []
        var batch = [UInt64](repeating: 0, count: 32)
        var batchCount: UInt64 = 0
        repeat {
            batchCount = 0
            let rv = findObjects(session, &batch, 32, &batchCount, nil)
            guard rv == 0 else { throw PKCS11Error.attributeFailed(rv) }
            if batchCount > 0 {
                handles.append(contentsOf: batch[0..<Int(batchCount)])
            }
        } while batchCount == 32
        let findFinal: (@convention(c)(UInt64) -> UInt64) = cfunc("C_FindObjectsFinal", as: (@convention(c)(UInt64) -> UInt64).self)
        _ = findFinal(session)
        return handles
    }

    private func attribute(_ object: UInt64, type: UInt64) throws -> Data {
        typealias GetAttributeValue = @convention(c)(UInt64, UnsafeRawPointer, UInt64) -> UInt64
        let getAttribute: GetAttributeValue = cfunc("C_GetAttributeValue", as: GetAttributeValue.self)

        var sizeAttribute = CKAttribute(type: type, pValue: nil, valueLen: 0)
        _ = withUnsafeMutablePointer(to: &sizeAttribute) { getAttribute(session, UnsafeRawPointer($0), 1) }
        let length = Int(sizeAttribute.valueLen)
        guard length > 0 else { return Data() }

        var value = Data(count: length)
        let rv = value.withUnsafeMutableBytes { raw -> UInt64 in
            var valueAttribute = CKAttribute(type: type, pValue: raw.baseAddress, valueLen: UInt64(length))
            return withUnsafeMutablePointer(to: &valueAttribute) {
                getAttribute(session, UnsafeRawPointer($0), 1)
            }
        }
        guard rv == 0 else { throw PKCS11Error.attributeFailed(rv) }
        return value
    }

    public func identities(slotID: UInt64) throws -> [PKCS11Identity] {
        try ensureSession(slotID: slotID)
        let certHandles = try findObjects(objectClass: 0x00000000)
        let keyHandles = try findObjects(objectClass: 0x00000001)

        var keyByID: [Data: (handle: UInt64, isRSA: Bool)] = [:]
        for key in keyHandles {
            let ckaIDOpt = try? attribute(key, type: 0x00000102)
            guard let ckaID = ckaIDOpt, !ckaID.isEmpty else { continue }
            let keyType = (try? attribute(key, type: 0x00000100)) ?? Data()
            let isRSA = keyType.first == 0
            keyByID[ckaID] = (key, isRSA)
        }

        var result: [PKCS11Identity] = []
        for certHandle in certHandles {
            guard let der = try? attribute(certHandle, type: 0x00000011), der.count > 100,
                  let facts = X509Inspector.facts(certificateData: der),
                  !KeychainIdentityScanner.isJunk(facts.subjectRFC2253),
                  !KeychainIdentityScanner.looksLikeRootCA(facts.subjectRFC2253) else { continue }
            let ckaID = (try? attribute(certHandle, type: 0x00000102)) ?? Data()
            guard let key = keyByID[ckaID] else { continue }

            let subjectSummary: String
            if let cfCert = SecCertificateCreateWithData(nil, der as CFData),
               let summary = SecCertificateCopySubjectSummary(cfCert) as String? {
                subjectSummary = summary
            } else {
                subjectSummary = facts.subjectRFC2253
            }
            let issuerCN = PKCS11Module.firstCN(facts.issuerRFC2253)
            let searchable = subjectSummary + " " + facts.issuerRFC2253

            result.append(PKCS11Identity(
                modulePath: path,
                slotID: slotID,
                tokenLabel: tokenLabel(slotID: slotID),
                certificateDER: der,
                privateKeyHandle: key.handle,
                isRSA: key.isRSA,
                subjectSummary: subjectSummary,
                issuerSummary: issuerCN ?? "PKCS#11",
                isMandateCertificate: KeychainIdentityScanner.looksMandate(searchable),
                isQualified: KeychainIdentityScanner.looksQualified(searchable) || issuerCN != nil))
        }
        return result
    }

    public func discoverIdentities() -> [PKCS11Identity] {
        var all: [PKCS11Identity] = []
        for slot in slotsWithTokens() {
            if let identities = try? identities(slotID: slot) {
                all.append(contentsOf: identities)
            }
        }
        return all
    }

    // MARK: - Signing

    public func sign(slotID: UInt64, privateKeyHandle: UInt64, isRSA: Bool,
                     digest: Data, pin: String) throws -> Data {
        try login(slotID: slotID, pin: pin)
        lock.lock(); defer { lock.unlock() }

        typealias SignInit = @convention(c)(UInt64, UnsafeMutableRawPointer, UInt64) -> UInt64
        typealias Sign = @convention(c)(UInt64, UnsafePointer<UInt8>, UInt64, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt64>) -> UInt64
        let signInit: SignInit = cfunc("C_SignInit", as: SignInit.self)
        let sign: Sign = cfunc("C_Sign", as: Sign.self)

        var mechanism = CKMechanism(type: isRSA ? 0x00000001 : 0x00001041,
                                    pParameter: nil, parameterLen: 0)
        let rvInit = withUnsafeMutableBytes(of: &mechanism) { raw in
            signInit(session, UnsafeMutableRawPointer(mutating: raw.baseAddress!), privateKeyHandle)
        }
        guard rvInit == 0 else {
            if rvInit == 0x70 { throw PKCS11Error.unsupportedMechanism }
            throw PKCS11Error.signFailed(rvInit)
        }

        let payload = isRSA ? Self.rsaDigestInfoSHA256(digest) : digest
        var signature = Data(count: isRSA ? 1024 : 256)
        var signatureLength: UInt64 = UInt64(signature.count)
        let rv = payload.withUnsafeBytes { raw in
            signature.withUnsafeMutableBytes { sigRaw in
                sign(session, raw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                     UInt64(payload.count),
                     sigRaw.baseAddress!.assumingMemoryBound(to: UInt8.self),
                     &signatureLength)
            }
        }
        guard rv == 0 else { throw PKCS11Error.signFailed(rv) }
        return signature.prefix(Int(signatureLength))
    }

    static func rsaDigestInfoSHA256(_ digest: Data) -> Data {
        DER.sequence([
            DER.sequence([DER.oid("2.16.840.1.101.3.4.2.1")]),
            DER.octetString(digest)
        ])
    }

    static func firstCN(_ rfc2253: String) -> String? {
        for part in rfc2253.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CN=") { return String(trimmed.dropFirst(3)) }
        }
        return nil
    }
}

struct CKInitializeArgs {
    var createMutex: UnsafeRawPointer?
    var destroyMutex: UnsafeRawPointer?
    var lockMutex: UnsafeRawPointer?
    var unlockMutex: UnsafeRawPointer?
    var flags: UInt64
    var reserved: UnsafeRawPointer?
}

struct CKAttribute {
    var type: UInt64
    var pValue: UnsafeMutableRawPointer?
    var valueLen: UInt64
}

struct CKMechanism {
    var type: UInt64
    var pParameter: UnsafeMutableRawPointer?
    var parameterLen: UInt64
}
