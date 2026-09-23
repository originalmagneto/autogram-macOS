// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import AppKit
import Chevron7Kit

/// The one place the main window asks the signing provider which card sits in the
/// reader. `availableIdentities()` only probes the drivers (or returns certificates
/// already read), so polling it never reads a card or asks for a PIN. The sidebar
/// badge reads `identities` in every section; the signing store gets each result
/// through `onRefresh` instead of polling on its own.
@MainActor
@Observable
final class CardReaderStatus {
    private(set) var identities: [SigningIdentityInfo] = []

    /// Receives every discovery, changed or not, so a store that cleared its own
    /// list (a reset, a failed batch) gets the card back on the next poll.
    @ObservationIgnored var onRefresh: (([SigningIdentityInfo]) -> Void)?
    /// True while something else talks to the card (signing, reading certificates,
    /// the browser signing panel's own watch), so the reader is left alone.
    @ObservationIgnored var isPaused: () -> Bool = { false }

    @ObservationIgnored private let discover: () async -> [SigningIdentityInfo]
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var isRefreshing = false

    init(interval: Duration = .seconds(3), discover: @escaping () async -> [SigningIdentityInfo]) {
        self.interval = interval
        self.discover = discover
    }

    func refresh() async {
        guard !isRefreshing, !isPaused() else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let discovered = await discover()
        guard !isPaused() else { return }
        if discovered != identities { identities = discovered }
        onRefresh?(discovered)
    }

    /// Polls until the calling task is cancelled, but only while the app is active.
    func watch(isAppActive: () -> Bool = { NSApp.isActive }) async {
        while !Task.isCancelled {
            if isAppActive() { await refresh() }
            try? await Task.sleep(for: interval)
        }
    }
}

/// What the sidebar card badge shows. The reader decides whether a card is
/// connected; the section's store only picks which of its certificates to name.
struct SmartcardBadge: Equatable {
    let isConnected: Bool
    let label: String
    let detail: String

    init(section: RootView.SidebarSection,
         reader: [SigningIdentityInfo],
         signingSelectedID: String?,
         zakoSelectedID: String?,
         isDemo: Bool) {
        let selectedID = section == .zako ? zakoSelectedID : signingSelectedID
        let identity = reader.first(where: { $0.id == selectedID })
            ?? reader.first(where: \.isMandateCertificate)
            ?? reader.first
        isConnected = identity != nil
        if let identity {
            label = identity.label
            detail = [identity.cardKindLabel, "čítačka je pripravená"]
                .compactMap { $0 }.joined(separator: " · ")
        } else {
            label = isDemo ? "DEMO režim" : "Karta nepripojená"
            detail = "Vložte eID alebo SAK kartu"
        }
    }
}
