// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation

/// Time estimate shown before the reviewer commits to a training run.
/// First time from the phase 0 throughput (16 s/page on the M1 Max Mac
/// Studio), afterwards from this Mac's own last run stored with the model.
/// Always a range: the first estimate is rough by construction.
public enum DetectorTrainingEstimate {
    public static let firstRunSecondsPerPage = 16.0

    public static func range(pages: Int, secondsPerPage: Double?) -> (lowMinutes: Int, highMinutes: Int) {
        let total = Double(pages) * (secondsPerPage ?? firstRunSecondsPerPage)
        return (max(1, Int((total * 0.75 / 60).rounded(.down))),
                max(1, Int((total * 1.4 / 60).rounded(.up))))
    }

    public static func slovak(pages: Int, secondsPerPage: Double?) -> String {
        let (low, high) = range(pages: pages, secondsPerPage: secondsPerPage)
        return "približne \(low) až \(high) \(minuteForm(high))"
    }

    static func minuteForm(_ minutes: Int) -> String {
        switch minutes {
        case 1: return "minútu"
        case 2, 3, 4: return "minúty"
        default: return "minút"
        }
    }
}
