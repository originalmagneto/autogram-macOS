import Foundation
import SwiftUI

@MainActor
@Observable
final class RecentDocumentStore {
    struct RecentDocument: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        let bookmarkData: Data
        let displayName: String
        let lastOpenedAt: Date
    }

    private static let storageKey = "sk.autogram.recentDocuments.v1"
    private static let maximumEntries = 8

    private let settingsStore: AppSettingsStore
    private let defaults: UserDefaults
    private(set) var entries: [RecentDocument]

    var isEnabled: Bool {
        settingsStore.settings.retainRecentDocuments
    }

    init(settingsStore: AppSettingsStore, defaults: UserDefaults = .standard) {
        self.settingsStore = settingsStore
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let storedEntries = try? JSONDecoder().decode([RecentDocument].self, from: data) {
            self.entries = Array(storedEntries.prefix(Self.maximumEntries))
        } else {
            self.entries = []
        }
    }

    func record(url: URL) {
        guard isEnabled,
              let bookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil) else {
            return
        }

        let matchingID = entries.first { entry in
            guard let resolvedURL = resolveBookmark(entry.bookmarkData) else {
                return false
            }
            return resolvedURL.standardizedFileURL == url.standardizedFileURL
        }?.id

        let updatedEntry = RecentDocument(
            id: UUID(),
            bookmarkData: bookmarkData,
            displayName: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            lastOpenedAt: Date())
        let remainingEntries = entries.filter { $0.id != matchingID }
        entries = Array(([updatedEntry] + remainingEntries).prefix(Self.maximumEntries))
        persist()
    }

    func resolve(_ entry: RecentDocument) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale),
            url.startAccessingSecurityScopedResource() else {
            return nil
        }
        return url
    }

    func isAvailable(_ entry: RecentDocument) -> Bool {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func withResolvedURL(
        _ entry: RecentDocument,
        operation: (URL) async -> Void
    ) async -> Bool {
        guard let url = resolve(entry) else {
            return false
        }
        defer { url.stopAccessingSecurityScopedResource() }
        await operation(url)
        return true
    }

    func remove(id: UUID) {
        let remainingEntries = entries.filter { $0.id != id }
        guard remainingEntries.count != entries.count else {
            return
        }
        entries = remainingEntries
        persist()
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func resolveBookmark(_ bookmarkData: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
