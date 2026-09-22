// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

public enum EZZKEvidenceNumberPolicy {
    public static let timeZone = TimeZone(identifier: "Europe/Bratislava")!

    /// EZZK consumes an unused number at midnight of its allocation day, Slovak time.
    /// A number without an allocation time (typed by hand or older data) is not judged.
    public static func isUsable(allocatedAt: Date?, at serverTime: Date) -> Bool {
        guard let allocatedAt else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(allocatedAt, inSameDayAs: serverTime)
    }

    /// A number fetched in one EZZK mode was never allocated by another one (a demo number
    /// is a local simulation, a test number is not a production number). A number without a
    /// mode (typed by hand or older data) is not judged.
    public static func isFromCurrentMode(numberMode: AppSettings.EZZKMode?,
                                         currentMode: AppSettings.EZZKMode) -> Bool {
        guard let numberMode else { return true }
        return numberMode == currentMode
    }

    /// The name the clause gives the person, following `AttestationClauseGenerator`: the
    /// office for a legal entity or when an office name is set, otherwise the full name.
    public static func personName(for profile: AdvocateProfile) -> String {
        let office = profile.officeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.isLegalEntity || !office.isEmpty {
            return office.isEmpty ? fullName : office
        }
        return fullName
    }

    /// A Slovak warning when the clause names a different person than the EZZK account,
    /// or nil when they match or the account identity is not filled in.
    public static func identityMismatch(clausePerson: AdvocateProfile, accountName: String,
                                        accountICO: String) -> String? {
        let name = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !significantDigits(accountICO).isEmpty else { return nil }
        var issues: [String] = []
        let clauseName = personName(for: clausePerson)
        if normalized(clauseName) != normalized(name) {
            issues.append("názov osoby v doložke „\(clauseName)“ sa líši od EZZK účtu „\(name)“")
        }
        if significantDigits(clausePerson.ico) != significantDigits(accountICO) {
            issues.append("IČO v doložke „\(clausePerson.ico)“ sa líši od IČO EZZK účtu „\(accountICO)“")
        }
        guard !issues.isEmpty else { return nil }
        return "Doložka nezodpovedá EZZK účtu: " + issues.joined(separator: "; ") + "."
    }

    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// EZZK shows IČO padded to twelve digits (`000042249180`); the clause uses eight.
    private static func significantDigits(_ value: String) -> String {
        String(value.filter(\.isNumber).drop { $0 == "0" })
    }
}
