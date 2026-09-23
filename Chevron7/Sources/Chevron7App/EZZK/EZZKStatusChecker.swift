// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import Foundation
import Observation

/// The one place that moves conversion-register rows through EZZK: ZaKo after
/// authorization, the Register's "Odoslať" and "Overiť v EZZK", and a check every five
/// minutes while the app runs. Every path applies `EZZKSubmissionCoordinator`'s rules and
/// goes through here, so one row is never sent or looked up by two paths at once (EZZK
/// stores a second copy of a record sent twice, result 106).
///
/// A row is only handled by the EZZK that allocated its number: a row of another mode is
/// refused (manual actions) or skipped (periodic check). A row without a stored mode
/// (written before part B2) is sent only by hand, in the current mode, as ZaKo always did.
@MainActor
@Observable
final class EZZKStatusChecker {
    /// The result of a manual action on one row.
    enum RowResult {
        /// The row as it is now, changed or not.
        case row(EvidenceRecord)
        /// Nothing was done; the Slovak reason says why.
        case refused(String)

        var record: EvidenceRecord? {
            if case .row(let record) = self { return record }
            return nil
        }

        var refusal: String? {
            if case .refused(let reason) = self { return reason }
            return nil
        }
    }

    /// What "Odoslať" in the Register did to the pending rows.
    struct PendingSummary: Equatable {
        /// Accepted for processing or processed.
        var accepted = 0
        /// Still unknown: waiting for a lookup, never resent.
        var unknown = 0
        /// Not sent (nothing reached EZZK); they wait for the next attempt.
        var waiting = 0
        var rejected = 0
        var unsigned = 0
        /// Rows of another EZZK mode or rows another action is handling.
        var skipped = 0
        /// Set when nothing could be done at all (the register is unreadable).
        var refusal: String?

        /// True only when every pending row was accepted.
        var isSuccess: Bool {
            refusal == nil && accepted > 0 && unknown + waiting + rejected + unsigned + skipped == 0
        }

        /// One Slovak line for the Register header.
        var feedback: String {
            if let refusal { return refusal }
            let parts = [
                (accepted, "Prijaté na spracovanie v EZZK"),
                (unknown, "Výsledok neznámy, overí sa v EZZK"),
                (waiting, "Čaká na odoslanie"),
                (rejected, "Odmietnuté v EZZK"),
                (unsigned, "Záznam nepodpísaný"),
                (skipped, "Preskočené (iný režim EZZK alebo prebieha iná akcia)")
            ].filter { $0.0 > 0 }.map { "\($0.1): \($0.0)." }
            return parts.isEmpty ? "Žiadny záznam nečaká na odoslanie." : parts.joined(separator: " ")
        }
    }

    static let checkInterval: TimeInterval = 5 * 60
    /// Automatic sends of one row per Bratislava day. After that the row waits for
    /// "Odoslať" in the Register, so a request EZZK keeps refusing before its operation
    /// runs is not sent every five minutes.
    static let automaticAttemptsPerDay = 3

    static let recordFromOtherModeMessage =
        "Záznam bol vytvorený v inom režime EZZK, preto sa v tomto režime neodošle. Prepnite režim EZZK späť a odošlite ho znova."
    static let rowBusyMessage =
        "Záznam sa práve odosiela alebo overuje v EZZK. Skúste to o chvíľu."
    static let missingRowMessage = "Záznam sa v Registri konverzií nenašiel."

    /// Increases whenever a row is stored, so views that read rows from the register
    /// (which is not observable itself) redraw.
    private(set) var changeCount = 0

    @ObservationIgnored private let evidenceStore: LocalEvidenceStore
    @ObservationIgnored private let numberPool: EvidenceNumberPool
    @ObservationIgnored private let currentMode: () -> AppSettings.EZZKMode
    @ObservationIgnored private let makeCoordinator: () -> EZZKSubmissionCoordinator
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var automaticAttempts: [UUID: [Date]] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(evidenceStore: LocalEvidenceStore,
         numberPool: EvidenceNumberPool,
         currentMode: @escaping () -> AppSettings.EZZKMode,
         makeCoordinator: @escaping () -> EZZKSubmissionCoordinator,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.evidenceStore = evidenceStore
        self.numberPool = numberPool
        self.currentMode = currentMode
        self.makeCoordinator = makeCoordinator
        self.now = now
    }

    /// The app's checker: submits with the account controller's service for the current
    /// mode. Demo sends to the local `MockEZZKService` and has nothing to look up, so a
    /// lookup there answers "processed" (ruling R4); outside Demo the lookup is the
    /// controller's public `GetConversionRecord`.
    convenience init(evidenceStore: LocalEvidenceStore,
                     numberPool: EvidenceNumberPool,
                     controller: EZZKAccountController) {
        self.init(
            evidenceStore: evidenceStore,
            numberPool: numberPool,
            currentMode: { controller.mode },
            makeCoordinator: {
                let lookup: EZZKRecordLookupFunction
                if controller.isDemoMode {
                    lookup = EZZKRecordLookupFunction { _ in EZZKRecordLookup(isProcessed: true, info: nil) }
                } else {
                    lookup = EZZKRecordLookupFunction { number in
                        try await controller.lookUp(evidenceNumber: number)
                    }
                }
                return EZZKSubmissionCoordinator(submitter: controller.service, lookup: lookup)
            })
    }

    // MARK: - Periodic check

    /// Starts the check every five minutes, after dropping pooled evidence numbers that
    /// lapsed at an earlier midnight. Called once at launch by the app model.
    func start() {
        guard loop == nil else { return }
        numberPool.prune(before: now())
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runOnce()
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// One pass over the register: late rows are marked, pending rows of this mode are
    /// sent (at most `automaticAttemptsPerDay` a day each), and unknown or accepted rows
    /// are looked up when their next check is due. Rows without an evidence number, of
    /// another mode, without a mode, or already being handled are left alone. A row
    /// resolved in this pass is sent in the next one at the earliest.
    func runOnce() async {
        guard evidenceStore.loadError == nil else { return }
        let mode = currentMode()
        let coordinator = makeCoordinator()
        for snapshot in evidenceStore.records {
            guard Self.hasEvidenceNumber(snapshot), snapshot.ezzkMode == mode,
                  !inFlight.contains(snapshot.id) else { continue }
            switch snapshot.status {
            case .signed, .queuedForSubmission, .submissionFailed, .late:
                guard takeAutomaticAttempt(for: snapshot.id) else {
                    // Still marked late when its day has passed, even without a send.
                    await perform(snapshot.id) { record in coordinator.markLateIfNeeded(record) }
                    continue
                }
                await perform(snapshot.id) { record in
                    await Self.send(record, with: coordinator, store: self.evidenceStore)
                }
            case .outcomeUnknown, .acceptedForProcessing:
                guard let due = coordinator.nextStatusCheck(for: snapshot), due <= now() else { continue }
                await perform(snapshot.id) { record in
                    record.status == .outcomeUnknown
                        ? await coordinator.resolveUnknown(record)
                        : await coordinator.refreshStatus(record)
                }
            default:
                continue
            }
        }
    }

    // MARK: - Manual actions

    /// Sends one row now ("Odoslať", and ZaKo right after authorization): a row whose day
    /// has passed is marked late first, an unknown outcome is looked up first and only
    /// sent when EZZK does not know the number.
    func submit(id: UUID) async -> RowResult {
        if let refusal = refusal(for: id) { return .refused(refusal) }
        let coordinator = makeCoordinator()
        let result = await perform(id) { record in
            await Self.send(record, with: coordinator, store: self.evidenceStore)
        }
        return result.map(RowResult.row) ?? .refused(Self.missingRowMessage)
    }

    /// Looks one row up now ("Overiť v EZZK"): an unknown outcome is resolved (no sooner
    /// than five minutes after the attempt, see `nextStatusCheck(for:)`), an accepted row
    /// is refreshed. Nothing is sent.
    func verify(id: UUID) async -> RowResult {
        if let refusal = refusal(for: id) { return .refused(refusal) }
        let coordinator = makeCoordinator()
        let result = await perform(id) { record in
            switch record.status {
            case .outcomeUnknown: return await coordinator.resolveUnknown(record)
            case .acceptedForProcessing: return await coordinator.refreshStatus(record)
            default: return record
            }
        }
        return result.map(RowResult.row) ?? .refused(Self.missingRowMessage)
    }

    /// "Odoslať" in the Register: every pending row of the current mode goes through
    /// `submit(id:)`, unknown outcomes included (they are only looked up).
    func submitPending() async -> PendingSummary {
        var summary = PendingSummary()
        if let loadError = evidenceStore.loadError {
            summary.refusal = loadError
            return summary
        }
        let pending = evidenceStore.records.filter(\.status.isSubmissionPendingState)
        for row in pending {
            switch await submit(id: row.id) {
            case .refused:
                summary.skipped += 1
            case .row(let record):
                switch record.status {
                case .acceptedForProcessing, .processed: summary.accepted += 1
                case .outcomeUnknown: summary.unknown += 1
                case .rejected: summary.rejected += 1
                case .recordUnsigned: summary.unsigned += 1
                default: summary.waiting += 1
                }
            }
        }
        return summary
    }

    /// When the row's next automatic lookup is due, or nil when none is planned.
    func nextStatusCheck(for record: EvidenceRecord) -> Date? {
        makeCoordinator().nextStatusCheck(for: record)
    }

    func isBusy(_ id: UUID) -> Bool {
        inFlight.contains(id)
    }

    // MARK: - Internals

    private func refusal(for id: UUID) -> String? {
        if let loadError = evidenceStore.loadError { return loadError }
        guard let record = evidenceStore.record(id: id) else { return Self.missingRowMessage }
        if let mode = record.ezzkMode, mode != currentMode() { return Self.recordFromOtherModeMessage }
        if inFlight.contains(id) { return Self.rowBusyMessage }
        return nil
    }

    /// Runs `change` on the stored row while no other path may touch it, stores what it
    /// returns when something changed, and returns the row as it is afterwards. Nil when
    /// the row is gone or busy.
    @discardableResult
    private func perform(_ id: UUID,
                         _ change: (EvidenceRecord) async -> EvidenceRecord) async -> EvidenceRecord? {
        guard !inFlight.contains(id), let record = evidenceStore.record(id: id) else { return nil }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        let updated = await change(record)
        guard updated.updatedAt != record.updatedAt || updated.status != record.status else { return record }
        // A row the advocate deleted meanwhile is not brought back.
        guard evidenceStore.record(id: id) != nil else { return updated }
        evidenceStore.upsert(updated)
        changeCount += 1
        if updated.status == .acceptedForProcessing || updated.status == .processed,
           let number = updated.evidenceNumber {
            // EZZK consumed the number with the record, so it is never offered again.
            numberPool.remove(number)
        }
        return updated
    }

    /// Marks a row late when its day has passed, looks an unknown outcome up first, then
    /// sends the row with its stored record container.
    private static func send(_ record: EvidenceRecord, with coordinator: EZZKSubmissionCoordinator,
                             store: LocalEvidenceStore) async -> EvidenceRecord {
        var updated = coordinator.markLateIfNeeded(record)
        if updated.status == .outcomeUnknown {
            updated = await coordinator.resolveUnknown(updated)
        }
        return await coordinator.submit(updated, container: store.recordContainerData(for: updated))
    }

    /// Counts an automatic send of the row today (Bratislava), or returns false when the
    /// row already had `automaticAttemptsPerDay` of them.
    private func takeAutomaticAttempt(for id: UUID) -> Bool {
        let current = now()
        let today = (automaticAttempts[id] ?? []).filter {
            EZZKEvidenceNumberPolicy.isUsable(allocatedAt: $0, at: current)
        }
        guard today.count < Self.automaticAttemptsPerDay else {
            automaticAttempts[id] = today
            return false
        }
        automaticAttempts[id] = today + [current]
        return true
    }

    private static func hasEvidenceNumber(_ record: EvidenceRecord) -> Bool {
        !(record.evidenceNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }
}
