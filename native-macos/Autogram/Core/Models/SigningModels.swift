import Foundation

struct SigningFile: Sendable, Equatable, Identifiable {
    let id: String
    let sourceURL: URL

    var redactedDisplayName: String {
        sourceURL.lastPathComponent
    }

    init(id: String, sourceURL: URL) {
        self.id = id
        self.sourceURL = sourceURL
    }
}

struct SigningRequest: Sendable {
    let sessionID: UUID
    let driverID: String
    let certificateSerial: String
    let pin: Secret
    let files: [SigningFile]

    init(
        sessionID: UUID,
        driverID: String,
        certificateSerial: String,
        pin: Secret,
        files: [SigningFile]
    ) {
        self.sessionID = sessionID
        self.driverID = driverID
        self.certificateSerial = certificateSerial
        self.pin = pin
        self.files = files
    }
}

enum SessionState: Sendable, Equatable {
    case idle
    case inspectingFiles
    case resolvingDriver
    case loadingCertificates
    case selectingCertificate
    case awaitingPIN
    case signing(progress: BatchProgress)
    case completed(BatchSummary)
    case partiallyCompleted(BatchSummary)
    case failed(SigningFailure)
    case cancelled
}

enum SigningActivityPhase: Sendable, Equatable {
    case inspectingDocuments
    case readingSigningCard
    case loadingCertificates
    case preparingSignatures
    case signingDocuments
    case validatingSignedDocuments
    case savingSignedDocuments

    var label: String {
        switch self {
        case .inspectingDocuments:
            "Inspecting documents"
        case .readingSigningCard:
            "Reading the signing card"
        case .loadingCertificates:
            "Loading certificates"
        case .preparingSignatures:
            "Preparing signatures"
        case .signingDocuments:
            "Signing documents and requesting a qualified timestamp"
        case .validatingSignedDocuments:
            "Validating signed documents"
        case .savingSignedDocuments:
            "Saving signed documents"
        }
    }

    init?(machinePhase: String) {
        switch machinePhase {
        case "preparing":
            self = .preparingSignatures
        case "signing":
            self = .signingDocuments
        case "validating":
            self = .validatingSignedDocuments
        case "saving":
            self = .savingSignedDocuments
        default:
            return nil
        }
    }
}

struct BatchProgress: Sendable, Equatable {
    let total: Int
    let completed: Int
    let failed: Int

    init(total: Int, completed: Int = 0, failed: Int = 0) {
        self.total = total
        self.completed = completed
        self.failed = failed
    }
}

struct BatchSummary: Sendable, Equatable {
    let succeeded: Int
    let failed: Int

    init(succeeded: Int, failed: Int) {
        self.succeeded = succeeded
        self.failed = failed
    }
}

enum SigningEvent: Sendable, Equatable {
    case started
    case activity(SigningActivityPhase)
    case fileSigning(String)
    case completed(String, outputURL: URL)
    case failed(String, SigningFailure)
    case cancelled
}

enum SigningFailure: Error, Sendable, Equatable {
    case invalidTransition
    case engine(String)
    case fileFailed(String)
}

extension SigningFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidTransition:
            "The signing workflow entered an invalid state."
        case .engine(let message):
            message
        case .fileFailed:
            "A PDF could not be signed."
        }
    }
}

final class Secret: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    convenience init(_ value: String) {
        self.init(bytes: Array(value.utf8))
    }

    deinit {
        zeroize()
    }

    func consumeBytes() -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }

        guard !bytes.isEmpty else { return nil }
        let consumed = bytes
        zeroize()
        return consumed
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        zeroize()
    }

    private func zeroize() {
        for index in bytes.indices {
            bytes[index] = 0
        }
        bytes.removeAll(keepingCapacity: false)
    }
}

extension Array where Element == UInt8 {
    mutating func zeroize() {
        for index in indices {
            self[index] = 0
        }
        removeAll(keepingCapacity: false)
    }
}
