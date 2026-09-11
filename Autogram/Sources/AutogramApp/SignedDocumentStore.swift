import Foundation
import SwiftUI

/// History of what was signed, kept apart from the list of recently *opened*
/// documents: the two answer different questions, and mixing them would hide
/// signatures behind a preference that is about reopening files.
///
/// This is not the Evidence register. That one is the legal record of zaručená
/// konverzia, with evidence numbers and CEZZK submission, and only conversions
/// belong in it.
@MainActor
@Observable
final class SignedDocumentStore {
    /// Where the signing request came from.
    enum Origin: String, Codable, Sendable {
        case app
        case browser

        var label: String {
            switch self {
            case .app: return "V aplikácii"
            case .browser: return "Z prehliadača"
            }
        }
    }

    /// What actually held the private key.
    enum Method: String, Codable, Sendable {
        case card
        case mobile

        var label: String {
            switch self {
            case .card: return "Kartou"
            case .mobile: return "Mobilom (NFC)"
            }
        }

        var sfSymbol: String {
            switch self {
            case .card: return "creditcard"
            case .mobile: return "iphone.gen3.radiowaves.left.and.right"
            }
        }
    }

    struct SignedDocument: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        let displayName: String
        let signedAt: Date
        let origin: Origin
        let method: Method
        let signatureLevel: String
        let signedBy: String
        /// Absolute path, when a copy was kept. Browser signatures can be
        /// configured not to keep one, and then there is nothing to reopen.
        let path: String?

        var wasSavedLocally: Bool { path != nil }

        var levelLabel: String { signatureLevel.replacingOccurrences(of: "_", with: " ") }

        /// True when the file is still where it was written.
        var isAvailable: Bool {
            guard let path else { return false }
            return FileManager.default.fileExists(atPath: path)
        }

        var url: URL? { path.map { URL(fileURLWithPath: $0) } }
    }

    private static let storageKey = "sk.autogram.signedDocuments.v1"
    private static let maximumEntries = 30

    private let defaults: UserDefaults
    private(set) var entries: [SignedDocument]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([SignedDocument].self, from: data) {
            self.entries = Array(stored.prefix(Self.maximumEntries))
        } else {
            self.entries = []
        }
    }

    func record(displayName: String, origin: Origin, method: Method,
                signatureLevel: String, signedBy: String, url: URL?) {
        let entry = SignedDocument(
            id: UUID(),
            displayName: displayName,
            signedAt: Date(),
            origin: origin,
            method: method,
            signatureLevel: signatureLevel,
            signedBy: signedBy,
            path: url?.path)
        entries = Array(([entry] + entries).prefix(Self.maximumEntries))
        persist()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
