// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Whether consequential EZZK calls (allocating or consuming an evidence number, sending a
/// record) may run on production. Read-only calls (login, server time, lookup) never need it.
/// Refused unless production is enabled for everyone or the owner switch is set on this Mac:
/// `defaults write app.slovensko.chevron7 EZZKProductionOwnerSwitch -bool YES`. The switch only
/// unlocks calls with the EZZK account the person already signed in with, so it grants nobody
/// access they do not have.
public struct EZZKProductionPolicy: Sendable, Equatable {
    /// Flipped to true by the release that enables production for everyone, after the owner's
    /// first live production conversion was processed (spec "Rollout", step 3).
    public static let enabledForEveryone = false
    public static let ownerSwitchKey = "EZZKProductionOwnerSwitch"

    public let allowsConsequentialCalls: Bool

    public init(allowsConsequentialCalls: Bool) {
        self.allowsConsequentialCalls = allowsConsequentialCalls
    }

    public static let refused = EZZKProductionPolicy(allowsConsequentialCalls: false)
    public static let allowed = EZZKProductionPolicy(allowsConsequentialCalls: true)

    public static func current(defaults: UserDefaults) -> EZZKProductionPolicy {
        EZZKProductionPolicy(allowsConsequentialCalls: enabledForEveryone || defaults.bool(forKey: ownerSwitchKey))
    }

    /// The error a consequential call gets, or nil when it may run.
    public func refusal(environment: EZZKEnvironment, submitting: Bool) -> EZZKError? {
        guard environment == .production, !allowsConsequentialCalls else { return nil }
        return submitting ? .submissionUnavailable : .productionAllocationDisabled
    }
}
