import Foundation
import CryptoTokenKit
import AutogramKit

@MainActor
@Observable
final class CardPresenceMonitor {
    static let shared = CardPresenceMonitor()

    private(set) var connectedTokens: [String] = []
    private(set) var lastChangeAt: Date?
    var onTokensChanged: (@Sendable () async -> Void)?

    private let watcher = TKTokenWatcher()
    private var tokenIDsObservation: NSKeyValueObservation?

    private init() {
        connectedTokens = Self.cleaned(watcher.tokenIDs)
        watcher.setInsertionHandler { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        tokenIDsObservation = watcher.observe(\.tokenIDs, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let cleaned = Self.cleaned(watcher.tokenIDs)
        guard cleaned != connectedTokens else { return }
        connectedTokens = cleaned
        lastChangeAt = Date()
        let callback = onTokensChanged
        Task { await callback?() }
    }

    private static func cleaned(_ ids: [String]) -> [String] {
        ids.map { tokenID in
            tokenID.replacingOccurrences(of: "com.", with: "")
                .replacingOccurrences(of: ".tokenextension", with: "")
                .replacingOccurrences(of: ".pkcs11", with: "")
                .replacingOccurrences(of: ".token", with: "")
        }.sorted()
    }
}
