import Foundation
import Testing
@testable import Autogram

@Test func localFileReturnsImmediatelyThroughCoordinator() async throws {
    let fileURL = URL(fileURLWithPath: "/tmp/local.pdf")
    let coordinator = CloudFileCoordinator(
        state: { _ in .local },
        startDownloading: { _ in
            Issue.record("Local files must not start a cloud download")
        }
    )
    let materializer = CloudFileMaterializer(coordinator: coordinator)

    try await materializer.materialize(fileURL)
}

@Test func cloudDownloadTimeoutFailsThatFile() async {
    let fileURL = URL(fileURLWithPath: "/tmp/cloud.pdf")
    let coordinator = CloudFileCoordinator(
        state: { _ in .notDownloaded },
        startDownloading: { _ in }
    )
    let materializer = CloudFileMaterializer(
        coordinator: coordinator,
        timeout: .zero,
        pollInterval: .zero
    )

    await #expect(throws: CloudFileMaterializationFailure.cloudMaterializationFailed(fileURL)) {
        try await materializer.materialize(fileURL)
    }
}
