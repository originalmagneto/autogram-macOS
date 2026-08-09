import Foundation
import Testing
@testable import Autogram

@Test func existingSignedOutputUsesNextNumberWithoutOverwrite() throws {
    try withTemporaryDirectory { directory in
        let source = directory.appending(path: "case.pdf")
        let existingOutput = directory.appending(path: "case_signed.pdf")
        try validPDF().write(to: source)
        try validPDF().write(to: existingOutput)

        let reservation = try OutputService().reserve(for: source)

        #expect(reservation.finalURL.lastPathComponent == "case_signed (2).pdf")
        #expect(!FileManager.default.fileExists(atPath: reservation.finalURL.path))
        #expect(try Data(contentsOf: existingOutput) == validPDF())
    }
}

@Test func symlinkedSourceOrIdenticalTargetIsRejected() throws {
    try withTemporaryDirectory { directory in
        let source = directory.appending(path: "case.pdf")
        let symlink = directory.appending(path: "case-link.pdf")
        try validPDF().write(to: source)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)

        #expect(throws: Error.self) {
            try OutputService().reserve(for: symlink)
        }
        #expect(throws: Error.self) {
            try OutputService().reserve(for: source, finalURL: source)
        }
    }
}

@Test func invalidPDFCannotBeFinalized() throws {
    try withTemporaryDirectory { directory in
        let source = directory.appending(path: "case.pdf")
        try validPDF().write(to: source)
        let reservation = try OutputService().reserve(for: source)
        try Data("not a PDF".utf8).write(to: reservation.temporaryURL)

        #expect(throws: Error.self) {
            try OutputService().finalize(reservation)
        }
        #expect(!FileManager.default.fileExists(atPath: reservation.finalURL.path))
    }
}

@Test func asiceOutputKeepsContainerExtensionAndFinalizes() throws {
    try withTemporaryDirectory { directory in
        let source = directory.appending(path: "case.asice")
        try validASiC().write(to: source)

        let reservation = try OutputService().reserve(for: source)
        try validASiC().write(to: reservation.temporaryURL)
        try OutputService().finalize(reservation)

        #expect(reservation.finalURL.lastPathComponent == "case_signed.asice")
        #expect(try Data(contentsOf: reservation.finalURL) == validASiC())
    }
}

private func validPDF() -> Data {
    Data("%PDF-1.7\\n%%EOF\\n".utf8)
}

private func validASiC() -> Data {
    Data([0x50, 0x4B, 0x03, 0x04])
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
