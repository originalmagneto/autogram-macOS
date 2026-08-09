import Darwin
import Foundation

struct OutputReservation: Sendable {
    let temporaryURL: URL
    let finalURL: URL
}

enum OutputServiceError: Error {
    case unsafeSource
    case unsafeTarget
    case sourceAndTargetAreIdentical
    case unableToReserveTemporaryFile
    case finalOutputAlreadyExists
    case unableToFinalize
}

struct OutputService {
    private let validator = PDFArtifactValidator()

    func reserve(for sourceURL: URL, finalURL requestedFinalURL: URL? = nil) throws -> OutputReservation {
        guard !isSymbolicLink(sourceURL) else { throw OutputServiceError.unsafeSource }
        let source = canonicalURL(sourceURL)
        let destination = try resolvedDestination(for: source, requestedFinalURL: requestedFinalURL)
        guard source != destination else { throw OutputServiceError.sourceAndTargetAreIdentical }

        let temporary = try reserveTemporarySibling(of: destination)
        return OutputReservation(temporaryURL: temporary, finalURL: destination)
    }

    func finalize(_ reservation: OutputReservation) throws {
        guard !pathExists(reservation.finalURL) else { throw OutputServiceError.finalOutputAlreadyExists }
        try validator.validate(at: reservation.temporaryURL, fileExtension: reservation.finalURL.pathExtension)
        guard moveWithoutReplacing(reservation.temporaryURL, to: reservation.finalURL) else {
            if pathExists(reservation.finalURL) { throw OutputServiceError.finalOutputAlreadyExists }
            throw OutputServiceError.unableToFinalize
        }
    }

    private func resolvedDestination(for source: URL, requestedFinalURL: URL?) throws -> URL {
        if let requestedFinalURL {
            guard !isSymbolicLink(requestedFinalURL) else { throw OutputServiceError.unsafeTarget }
            return canonicalURL(requestedFinalURL)
        }

        let directory = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let suffix = number == 1 ? "_signed" : "_signed (\(number))"
            let candidate = directory.appending(path: stem + suffix).appendingPathExtension(source.pathExtension)
            if !pathExists(candidate) { return candidate }
            number += 1
        }
    }

    private func reserveTemporarySibling(of finalURL: URL) throws -> URL {
        let directory = finalURL.deletingLastPathComponent()
        var template = directory
            .appending(path: ".\(finalURL.lastPathComponent).\(UUID().uuidString).XXXXXX")
            .path
            .utf8CString
        let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress) }
        guard descriptor >= 0 else { throw OutputServiceError.unableToReserveTemporaryFile }
        defer { close(descriptor) }
        return URL(fileURLWithPath: String(cString: Array(template)))
    }

    private func moveWithoutReplacing(_ source: URL, to destination: URL) -> Bool {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL)) == 0
            }
        }
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func pathExists(_ url: URL) -> Bool {
        var status = stat()
        return url.withUnsafeFileSystemRepresentation { lstat($0, &status) == 0 }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var status = stat()
        return url.withUnsafeFileSystemRepresentation {
            lstat($0, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
        }
    }
}
