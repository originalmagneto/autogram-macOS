// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Chevron7Kit
import Foundation

/// Slovak texts and flags shared by the ZaKo Done screen and Register konverzií for a
/// row's EZZK submission state. Pure values, so the wording is tested without SwiftUI.
enum EZZKRecordPresentation {
    /// Revision 5 ruling 7, kept after the live check of ruling R12 (EZZK accepted a late
    /// record for processing).
    static let lateWarning =
        "Záznam sa neodoslal v deň pridelenia čísla. EZZK ho môže odmietnuť alebo evidovať ako oneskorený."
    static let resignLater =
        "Záznam podpíšte znova novou konverziou; opakovaný podpis z Registra príde neskôr."
    static let unknownExplanation =
        "EZZK mohlo záznam dostať, preto sa znova neodošle: najprv overte v EZZK, či ho má. Ak ho nemá, záznam sa odošle znova."

    enum Tone: Equatable {
        case success, pending, warning, failure
    }

    /// Whether EZZK has the record (accepted or processed; "Zapísané v CEZZK" from part A).
    static func isSent(_ status: EvidenceRecord.Status) -> Bool {
        switch status {
        case .submitted, .acceptedForProcessing, .processed: return true
        default: return false
        }
    }

    /// Whether EZZK refused the record, or part A marked the send as failed.
    static func isFailed(_ status: EvidenceRecord.Status) -> Bool {
        status == .rejected || status == .submissionFailed
    }

    /// Rows "Odoslať" may send: nothing reached EZZK yet (an unknown outcome is verified instead).
    static func isSendable(_ status: EvidenceRecord.Status) -> Bool {
        switch status {
        case .signed, .queuedForSubmission, .submissionFailed, .late: return true
        default: return false
        }
    }

    /// Rows "Overiť v EZZK" may look up.
    static func isVerifiable(_ status: EvidenceRecord.Status) -> Bool {
        status == .outcomeUnknown || status == .acceptedForProcessing
    }

    static func tone(for status: EvidenceRecord.Status) -> Tone {
        switch status {
        case .submitted, .acceptedForProcessing, .processed: return .success
        case .outcomeUnknown, .late: return .warning
        case .rejected, .recordUnsigned, .submissionFailed: return .failure
        case .draft, .awaitingNumber, .readyToSign, .signed, .queuedForSubmission: return .pending
        }
    }

    /// Why the row needs the advocate, in Slovak, or nil when it does not.
    static func stateExplanation(for record: EvidenceRecord) -> [String] {
        switch record.status {
        case .rejected:
            var line = "EZZK záznam odmietlo"
            if let code = record.ezzkResultCode { line = "EZZK vrátilo kód \(code)" }
            if let description = record.ezzkResultDescription, !description.isEmpty {
                line += ": \(description)"
            }
            return [line]
        case .outcomeUnknown:
            return nonEmpty(record.ezzkResultDescription) + [unknownExplanation]
        case .late:
            return [lateWarning] + nonEmpty(record.ezzkResultDescription)
        case .recordUnsigned:
            return nonEmpty(record.ezzkResultDescription) + [unsignedWarning(for: record), resignLater]
        case .signed, .queuedForSubmission, .submissionFailed:
            return nonEmpty(record.ezzkResultDescription)
        default:
            return []
        }
    }

    /// The client documents already carry the number in their clause, but EZZK has no
    /// record under it; a new conversion gets a new number, so these outputs must not reach the client.
    static func unsignedWarning(for record: EvidenceRecord) -> String {
        let number = record.evidenceNumber.map { " \($0)" } ?? ""
        return "Dokumenty pre klienta nesú evidenčné číslo\(number), ku ktorému sa do EZZK neodoslal žiadny záznam. Neodovzdávajte ich klientovi: nová konverzia dostane nové evidenčné číslo."
    }

    static func modeLine(_ mode: AppSettings.EZZKMode?) -> String? {
        mode.map { "Režim EZZK pri podpise: \($0.label)" }
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sk_SK")
        formatter.timeZone = EZZKEvidenceNumberPolicy.timeZone
        formatter.dateFormat = "d. M. yyyy HH:mm"
        return formatter.string(from: date)
    }

    private static func nonEmpty(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return [text]
    }
}

/// The EZZK part of the ZaKo Done screen, built from the stored register row.
struct ZakoDonePresentation: Equatable {
    enum Action: Equatable {
        case none
        /// "Odoslať do EZZK".
        case send
        /// "Overiť v EZZK"; `availableAt` is when an unknown outcome may be looked up.
        case verify(availableAt: Date?)
    }

    let title: String
    let symbol: String
    let tone: EZZKRecordPresentation.Tone
    let lines: [String]
    let action: Action
    let isActionEnabled: Bool
    /// What went wrong in the flow and is not already said above, or nil.
    let error: String?

    /// - Parameters:
    ///   - record: the conversion's register row, as stored now.
    ///   - lastError: the ZaKo flow's last error, and `lastErrorStatus` the row state it described.
    ///   - archiveCopyError: the failed copy of the record next to the outputs, which stays true.
    ///   - nextStatusCheck: when the row's next lookup is due (`EZZKStatusChecker.nextStatusCheck`).
    init(record: EvidenceRecord?, lastError: String?, lastErrorStatus: EvidenceRecord.Status?,
         archiveCopyError: String?, nextStatusCheck: Date?, now: Date) {
        guard let record else {
            title = "Konverzia nie je zapísaná v Registri konverzií"
            symbol = "exclamationmark.triangle.fill"
            tone = .failure
            lines = []
            action = .none
            isActionEnabled = false
            error = lastError
            return
        }
        let status = record.status
        tone = EZZKRecordPresentation.tone(for: status)
        switch status {
        case .processed, .submitted:
            title = "Zaručená konverzia je dokončená, záznam je spracovaný v EZZK"
            symbol = "checkmark.seal.fill"
        case .acceptedForProcessing:
            title = "Zaručená konverzia je dokončená, EZZK prijalo záznam na spracovanie"
            symbol = "checkmark.seal.fill"
        case .outcomeUnknown:
            title = "Nie je známe, či EZZK záznam dostalo"
            symbol = "questionmark.circle.fill"
        case .rejected:
            title = "EZZK záznam o konverzii odmietlo"
            symbol = "xmark.seal.fill"
        case .recordUnsigned:
            title = "Dokumenty sú podpísané, záznam o konverzii nie"
            symbol = "exclamationmark.triangle.fill"
        case .late:
            title = "Dokumenty sú podpísané, záznam je oneskorený"
            symbol = "clock.badge.exclamationmark.fill"
        default:
            title = "Dokumenty sú podpísané, záznam ešte nie je v EZZK"
            symbol = "tray.and.arrow.up.fill"
        }

        var lines = EZZKRecordPresentation.stateExplanation(for: record)
        if status == .acceptedForProcessing {
            lines.append("Spracovanie záznamu sa overuje v EZZK automaticky.")
        }
        let mode = record.ezzkMode
        if EZZKRecordPresentation.isSendable(status) {
            if mode == .production {
                lines.append(EZZKError.submissionUnavailable.errorDescription ?? "")
                action = .none
            } else {
                action = .send
            }
        } else if EZZKRecordPresentation.isVerifiable(status), mode != .production {
            action = .verify(availableAt: status == .outcomeUnknown ? nextStatusCheck : nil)
        } else {
            action = .none
        }
        if case .verify(let availableAt?) = action, availableAt > now {
            lines.append("Overiť v EZZK bude možné od \(EZZKRecordPresentation.timeText(availableAt)).")
            isActionEnabled = false
        } else {
            isActionEnabled = action != .none
        }
        if let modeLine = EZZKRecordPresentation.modeLine(mode) { lines.append(modeLine) }
        self.lines = lines

        // The flow's error describes the row as ZaKo last saw it. Lines already shown, or
        // repeating the row's own description, are left out; once the row has moved on
        // (the periodic check), only the archive copy failure is still true.
        if let lastError, lastErrorStatus == status {
            let description = record.ezzkResultDescription ?? ""
            let remaining = lastError.split(separator: "\n").map(String.init).filter { line in
                !lines.contains(line) && (description.isEmpty || !line.contains(description))
            }
            error = remaining.isEmpty ? nil : remaining.joined(separator: "\n")
        } else {
            error = archiveCopyError
        }
    }
}
