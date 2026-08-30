import Foundation

public struct InputSignatureInspectionResult: Sendable, Equatable {
    public enum State: String, Sendable, Equatable, Hashable {
        case valid
        case invalid
        case unknown
        case unavailable
    }

    public let state: State
    public let signatures: [DocumentSignatureInfo]
    public let oldestQualifiedTimestamp: Date?
    public let detail: String

    public init(
        state: State,
        signatures: [DocumentSignatureInfo],
        oldestQualifiedTimestamp: Date?,
        detail: String
    ) {
        self.state = state
        self.signatures = signatures
        self.oldestQualifiedTimestamp = oldestQualifiedTimestamp
        self.detail = detail
    }

    public static func completed(signatures: [DocumentSignatureInfo]) -> Self {
        let state: State
        if signatures.contains(where: { $0.state == .invalid }) {
            state = .invalid
        } else if signatures.contains(where: {
            $0.state == .indeterminate || $0.state == .unknown
        }) {
            state = .unknown
        } else {
            state = .valid
        }

        let oldestTimestamp = signatures
            .filter { $0.state == .valid && $0.hasQualifiedTimestamp }
            .compactMap(\.signingTime)
            .min()

        return Self(
            state: state,
            signatures: signatures,
            oldestQualifiedTimestamp: oldestTimestamp,
            detail: "Kontrola vstupných elektronických podpisov bola dokončená.")
    }

    public static func unavailable(detail: String) -> Self {
        Self(
            state: .unavailable,
            signatures: [],
            oldestQualifiedTimestamp: nil,
            detail: detail.isEmpty
                ? "Overenie vstupných elektronických podpisov nie je dostupné."
                : detail)
    }
}

public struct InputSignatureVerificationService: Sendable {
    private let provider: any QualifiedSigningProviding

    public init(provider: any QualifiedSigningProviding) {
        self.provider = provider
    }

    public func inspect(inputURL: URL) async -> InputSignatureInspectionResult {
        let url = inputURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .unavailable(detail: "Vstupný dokument nie je dostupný.")
        }
        return await provider.inspectInputSignatures(in: url)
    }

    public static func structuralInspection(at inputURL: URL) -> InputSignatureInspectionResult {
        let url = inputURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              data.starts(with: Data("%PDF-".utf8)) else {
            return .unavailable(detail: "Vstupný dokument nie je dostupný alebo nie je platný PDF súbor.")
        }

        let compact = data.filter { byte in
            byte != 0 && byte != 9 && byte != 10 && byte != 12 && byte != 13 && byte != 32
        }
        var decoded = Data()
        decoded.reserveCapacity(compact.count)
        var index = 0
        func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: byte - 48
            case 65...70: byte - 55
            case 97...102: byte - 87
            default: nil
            }
        }
        while index < compact.count {
            if compact[index] == 35, index + 2 < compact.count,
               let high = hexValue(compact[index + 1]),
               let low = hexValue(compact[index + 2]) {
                decoded.append(high * 16 + low)
                index += 3
            } else {
                decoded.append(compact[index])
                index += 1
            }
        }
        let source = String(decoding: decoded, as: UTF8.self)
        if source.contains("/ObjStm") {
            return .unavailable(detail: "Štruktúra PDF obsahuje komprimované objekty bez bezpečného lokálneho overenia podpisu.")
        }

        let hasSignatureField = source.contains("/FT/Sig")
            || source.contains("/Type/Sig")
            || source.contains("/ByteRange[")
        guard hasSignatureField else {
            return .completed(signatures: [])
        }
        let signature = DocumentSignatureInfo(
            id: "structural-signature",
            signerDisplayName: "Neoverený podpis",
            format: "PDF",
            state: .unknown,
            detail: "V dokumente sa nachádza digitálny podpis, ale jeho kryptografické overenie nie je dostupné.")
        return .completed(signatures: [signature])
    }
}
public enum SessionResultGuard {
    public static func accepts(
        resultFor: UUID,
        currentRecordID: UUID,
        taskIsCancelled: Bool
    ) -> Bool {
        resultFor == currentRecordID && !taskIsCancelled
    }
}
