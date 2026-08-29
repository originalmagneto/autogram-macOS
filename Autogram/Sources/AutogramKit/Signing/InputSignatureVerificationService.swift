import Foundation

public struct InputSignatureInspectionResult: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
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
