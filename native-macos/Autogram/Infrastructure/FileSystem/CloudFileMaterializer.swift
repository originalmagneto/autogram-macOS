import Foundation

enum CloudFileMaterializationFailure: Error, Sendable, Equatable {
    case cloudMaterializationFailed(URL)
}

enum CloudFileState: Sendable, Equatable {
    case local
    case notDownloaded
    case materialized
}

struct CloudFileCoordinator: Sendable {
    private let readState: @Sendable (URL) throws -> CloudFileState
    private let requestDownload: @Sendable (URL) throws -> Void

    init(
        state: @escaping @Sendable (URL) throws -> CloudFileState,
        startDownloading: @escaping @Sendable (URL) throws -> Void
    ) {
        readState = state
        requestDownload = startDownloading
    }

    func state(of fileURL: URL) throws -> CloudFileState {
        try readState(fileURL)
    }

    func startDownloading(_ fileURL: URL) throws {
        try requestDownload(fileURL)
    }

    static let live = CloudFileCoordinator(
        state: { fileURL in
            try coordinatedState(of: fileURL)
        },
        startDownloading: { fileURL in
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }
    )

    private static func coordinatedState(of fileURL: URL) throws -> CloudFileState {
        var coordinationError: NSError?
        var result: Result<CloudFileState, Error>?

        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let values = try coordinatedURL.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ])

                guard values.isUbiquitousItem == true else { return .local }
                return values.ubiquitousItemDownloadingStatus == .current ? .materialized : .notDownloaded
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        return try result?.get() ?? .local
    }
}

struct CloudFileMaterializer: Sendable {
    private let coordinator: CloudFileCoordinator
    private let timeout: Duration
    private let pollInterval: Duration

    init(
        coordinator: CloudFileCoordinator = .live,
        timeout: Duration = .seconds(30),
        pollInterval: Duration = .milliseconds(100)
    ) {
        self.coordinator = coordinator
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    func materialize(_ fileURL: URL) async throws {
        do {
            switch try coordinator.state(of: fileURL) {
            case .local, .materialized:
                return
            case .notDownloaded:
                try coordinator.startDownloading(fileURL)
            }

            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: pollInterval)
                if try coordinator.state(of: fileURL) == .materialized {
                    return
                }
            }
        } catch {
            throw CloudFileMaterializationFailure.cloudMaterializationFailed(fileURL)
        }

        throw CloudFileMaterializationFailure.cloudMaterializationFailed(fileURL)
    }
}
