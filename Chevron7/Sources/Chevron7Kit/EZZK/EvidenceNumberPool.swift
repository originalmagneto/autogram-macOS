// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Identity
import Foundation

/// Evidence numbers this app already allocated from EZZK today, so a fresh document can
/// reuse one instead of asking EZZK again. Verified live on test EZZK: each allocation
/// call returns exactly one new number; EZZK never returns a number it already gave out;
/// once the account's limit of unconsumed numbers is reached it refuses with code 113;
/// sending a record's own number consumes it; an unused number lapses at Bratislava
/// midnight (`EZZKEvidenceNumberPolicy.isUsable`).
public final class EvidenceNumberPool: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var number: String
        public var mode: AppSettings.EZZKMode
        public var allocatedAt: Date

        public init(number: String, mode: AppSettings.EZZKMode, allocatedAt: Date) {
            self.number = number
            self.mode = mode
            self.allocatedAt = allocatedAt
        }
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "\(ProductIdentity.bundleIdentifier).evidence-number-pool")
    private var entries: [Entry] = []

    /// Set when `allocated-numbers.json` exists but could not be decoded (for example a
    /// file written by a newer, not-yet-released build). While this is set the pool never
    /// writes to that file: the original file is left byte-for-byte untouched and the pool
    /// behaves as empty for the life of this instance, exactly like `LocalEvidenceStore`
    /// treats an unreadable register.
    public private(set) var loadError: String?
    private var loadFailed = false

    /// `directory` is the same root `LocalEvidenceStore` is given: this resolves to and
    /// creates `<directory>/Evidence/`, and reads/writes
    /// `<directory>/Evidence/allocated-numbers.json`.
    public init(directory: URL) {
        let base = directory.appendingPathComponent("Evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("allocated-numbers.json")

        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let loaded = try? JSONDecoder.standard.decode([Entry].self, from: data) {
            self.entries = loaded
            return
        }

        self.loadFailed = true
        self.loadError = "Zoznam pridelených evidenčných čísel sa nepodarilo načítať. Súbor sa nezmenil."
    }

    /// Records a number this app just received from EZZK.
    public func add(_ entry: Entry) {
        queue.sync {
            entries.append(entry)
            persistLocked()
        }
    }

    /// Drops a number once its record has been accepted (EZZK consumed it) or it should
    /// otherwise no longer be offered for reuse.
    public func remove(_ number: String) {
        queue.sync {
            entries.removeAll { $0.number == number }
            persistLocked()
        }
    }

    /// The first pooled number from `mode`, allocated on the same Bratislava day as `now`,
    /// that is not already carried by a register row in `used` - or `nil` when there is
    /// none, in which case the caller should allocate a new number from EZZK.
    public func reusable(mode: AppSettings.EZZKMode, at now: Date, excluding used: Set<String>) -> Entry? {
        queue.sync {
            entries.first {
                $0.mode == mode
                    && !used.contains($0.number)
                    && EZZKEvidenceNumberPolicy.isUsable(allocatedAt: $0.allocatedAt, at: now)
            }
        }
    }

    /// Drops entries EZZK has already consumed at midnight of an earlier Bratislava day.
    /// `reusable` alone already ignores them; this only keeps the file from growing forever.
    public func prune(before now: Date) {
        queue.sync {
            let kept = entries.filter { EZZKEvidenceNumberPolicy.isUsable(allocatedAt: $0.allocatedAt, at: now) }
            guard kept.count != entries.count else { return }
            entries = kept
            persistLocked()
        }
    }

    private func persistLocked() {
        // Never write over a file this build could not read.
        guard !loadFailed else { return }
        guard let data = try? JSONEncoder.pretty.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

public extension EZZKError {
    /// Shown when EZZK refuses allocation with code 113: the account already holds an
    /// unconsumed number, and this build's pool did not know about it (allocated before
    /// the pool existed, from another device, or already spent by `remove(_:)` locally
    /// while EZZK itself still counts it until midnight).
    static let numberLimitMessage =
        "EZZK vám už pridelilo evidenčné číslo, na ktoré ešte neprišiel záznam. Dokončite rozpracovanú konverziu alebo počkajte do polnoci."
}
