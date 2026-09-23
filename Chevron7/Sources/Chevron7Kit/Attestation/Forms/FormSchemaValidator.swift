// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Validates a form document against its official XML schema with libxml2's `xmllint`,
/// which ships with macOS. Runs before anything is signed.
public struct FormSchemaValidator: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case validatorUnavailable
        case invalid(details: String)

        public var errorDescription: String? {
            switch self {
            case .validatorUnavailable:
                return "Kontrola podľa oficiálnej schémy nie je dostupná (chýba /usr/bin/xmllint)."
            case .invalid(let details):
                return "Dokument nezodpovedá oficiálnej schéme formulára:\n\(details)"
            }
        }
    }

    private let xmllintURL: URL

    public init(xmllintURL: URL = URL(fileURLWithPath: "/usr/bin/xmllint")) {
        self.xmllintURL = xmllintURL
    }

    public func validate(_ xml: Data, against form: OfficialForm) throws {
        guard FileManager.default.isExecutableFile(atPath: xmllintURL.path) else {
            throw Failure.validatorUnavailable
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chevron7-form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schemaURL = directory.appendingPathComponent("schema.xsd")
        let documentURL = directory.appendingPathComponent("document.xml")
        try form.schema.write(to: schemaURL)
        try xml.write(to: documentURL)

        let process = Process()
        process.executableURL = xmllintURL
        process.arguments = ["--nonet", "--noout", "--schema", schemaURL.path, documentURL.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Read before waiting so a long error report cannot fill the pipe and block xmllint.
        let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = output.split(separator: "\n")
                .filter { !$0.hasSuffix("fails to validate") }
                .prefix(5)
                .map { $0.replacingOccurrences(of: documentURL.path + ":", with: "riadok ") }
                .joined(separator: "\n")
            throw Failure.invalid(details: details)
        }
    }
}
