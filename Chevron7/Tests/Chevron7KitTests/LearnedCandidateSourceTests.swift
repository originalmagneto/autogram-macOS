// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class LearnedCandidateSourceTests: XCTestCase {
    func testLearnedSourceLabelRenders() {
        let candidate = DetectionCandidate(pageIndex: 0, box: .zero, sources: [.learned])
        XCTAssertEqual(candidate.sourceLabel, "learned")
    }
}
