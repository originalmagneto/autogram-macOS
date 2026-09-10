import Foundation
import CoreGraphics
import Observation

/// One document, one QR code, one signature. Drives upload, polling, timeout
/// and cancellation and exposes observable state for the QR sheet.
@MainActor
@Observable
public final class AVMSigningSession {
    public enum State: Equatable {
        case idle
        case uploading
        case waitingForScan(qrURL: URL)
        case downloading
        case signed(AVMSignedDocument)
        case failed(String)
        case cancelled
    }

    public private(set) var state: State = .idle
    public private(set) var qrImage: CGImage?
    public private(set) var deadline: Date?

    private let client: AVMClient
    private let pollInterval: Duration
    private let timeout: Duration
    private let qrSide: Int
    private var reference: AVMDocumentReference?
    private var runTask: Task<AVMSignedDocument, Error>?

    public init(client: AVMClient,
                pollInterval: Duration = .seconds(1),
                timeout: Duration = .seconds(900),
                qrSide: Int = 512) {
        self.client = client
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.qrSide = qrSide
    }

    public var isActive: Bool {
        switch state {
        case .uploading, .waitingForScan, .downloading: return true
        case .idle, .signed, .failed, .cancelled: return false
        }
    }

    public func run(_ request: AVMUploadRequest) async throws -> AVMSignedDocument {
        let task = Task<AVMSignedDocument, Error> { [weak self] in
            guard let self else { throw AVMError.cancelled }
            return try await self.execute(request)
        }
        runTask = task
        defer { runTask = nil }
        return try await task.value
    }

    public func cancel() {
        runTask?.cancel()
    }

    private func execute(_ request: AVMUploadRequest) async throws -> AVMSignedDocument {
        state = .uploading
        qrImage = nil
        deadline = nil
        do {
            let key = AVMDocumentKey.generate()
            let reference = try await client.upload(request, key: key)
            self.reference = reference
            try Task.checkCancellation()

            let qrURL = client.qrCodeURL(for: reference)
            qrImage = QRCodeRenderer.image(for: qrURL.absoluteString, side: qrSide)
            let start = ContinuousClock.now
            deadline = Date().addingTimeInterval(Self.seconds(timeout))
            state = .waitingForScan(qrURL: qrURL)

            while true {
                try Task.checkCancellation()
                if ContinuousClock.now - start >= timeout { throw AVMError.timeout }
                let result = try await client.fetchSigned(reference)
                switch result {
                case .pending:
                    try await Task.sleep(for: pollInterval)
                case .signed(let document):
                    state = .signed(document)
                    self.reference = nil
                    return document
                }
            }
        } catch is CancellationError {
            state = .cancelled
            scheduleDelete()
            throw AVMError.cancelled
        } catch let error as AVMError {
            if error == .cancelled {
                state = .cancelled
            } else {
                state = .failed(error.localizedDescription)
            }
            scheduleDelete()
            throw error
        } catch {
            state = .failed(error.localizedDescription)
            scheduleDelete()
            throw error
        }
    }

    /// Best-effort cleanup; the server deletes the document after 24 hours anyway.
    private func scheduleDelete() {
        guard let reference else { return }
        self.reference = nil
        let client = self.client
        Task.detached(priority: .utility) {
            try? await client.delete(reference)
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
