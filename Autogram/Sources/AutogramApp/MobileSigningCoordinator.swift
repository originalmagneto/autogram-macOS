import Foundation
import Observation
import AutogramKit

/// Owns one AVM session at a time and the presentation flag of the QR sheet.
@MainActor
@Observable
final class MobileSigningCoordinator {
    var isPresented = false
    private(set) var session: AVMSigningSession?

    private let clientFactory: @MainActor () -> AVMClient
    private let pollInterval: Duration
    private let timeout: Duration

    init(clientFactory: @escaping @MainActor () -> AVMClient,
         pollInterval: Duration = .seconds(1),
         timeout: Duration = .seconds(900)) {
        self.clientFactory = clientFactory
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    convenience init(settingsStore: AppSettingsStore) {
        self.init(clientFactory: { AVMClient(baseURL: settingsStore.settings.avmBaseURLValue) })
    }

    func sign(_ request: AVMUploadRequest) async throws -> AVMSignedDocument {
        if let session, session.isActive { session.cancel() }
        let session = AVMSigningSession(client: clientFactory(), pollInterval: pollInterval, timeout: timeout)
        self.session = session
        isPresented = true
        defer {
            isPresented = false
            self.session = nil
        }
        return try await session.run(request)
    }

    func cancel() {
        session?.cancel()
    }
}
