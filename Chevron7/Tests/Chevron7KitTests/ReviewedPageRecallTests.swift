// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class ReviewedPageRecallTests: XCTestCase {
    private let documentHash = String(repeating: "a", count: 64)
    private let stampBox = NormalizedRect(x: 0.52, y: 0.2, width: 0.18, height: 0.12)
    private let sealBox = NormalizedRect(x: 0.03, y: 0.84, width: 0.11, height: 0.07)

    private func reviewed(page: Int, boxes: [ReviewedPageBox], hash: String? = nil) -> ReviewedBankPage {
        ReviewedBankPage(documentSHA256: hash ?? documentHash, pageIndex: page, boxes: boxes,
                         reviewedAt: Date(timeIntervalSince1970: 1_790_000_000), detectorVersion: "test/1")
    }

    private func suggestion(page: Int, kind: SecurityElement.Kind = .initial) -> SecurityElement {
        SecurityElement(kind: kind, pageIndex: page, boundingBox: .init(x: 0.6, y: 0.1, width: 0.05, height: 0.05),
                        confidence: 0.71, detectedByAI: true, reviewState: .pending, detectionSource: "contour; fm")
    }

    func testReviewedPageReplacesDetectionWithTheReviewersBoxes() {
        let pages = [reviewed(page: 0, boxes: [.init(kind: .officialStamp, box: stampBox),
                                               .init(kind: .waxSeal, box: sealBox)])]
        let result = ReviewedPageRecall.apply(to: [suggestion(page: 0), suggestion(page: 1)],
                                              documentSHA256: documentHash, reviewedPages: pages)

        XCTAssertEqual(result.filter { $0.pageIndex == 1 }.count, 1, "an unreviewed page keeps its detection")
        let recalled = result.filter { $0.pageIndex == 0 }
        XCTAssertEqual(Set(recalled.map(\.kind)), [.officialStamp, .waxSeal])
        XCTAssertEqual(Set(recalled.map(\.boundingBox)), [stampBox, sealBox])
        for element in recalled {
            // Every conversion needs its own human review: recalled boxes wait for it.
            XCTAssertEqual(element.reviewState, .pending)
            XCTAssertTrue(element.detectedByAI)
            XCTAssertEqual(element.detectionSource, ReviewedPageRecall.detectionSource)
            XCTAssertEqual(element.confidence, 1)
        }
    }

    func testPageReviewedWithoutElementsDropsItsSuggestions() {
        let result = ReviewedPageRecall.apply(to: [suggestion(page: 0)], documentSHA256: documentHash,
                                              reviewedPages: [reviewed(page: 0, boxes: [])])
        XCTAssertTrue(result.isEmpty)
    }

    func testReviewOfAnotherDocumentIsIgnored() {
        let detected = [suggestion(page: 0)]
        let result = ReviewedPageRecall.apply(
            to: detected, documentSHA256: documentHash,
            reviewedPages: [reviewed(page: 0, boxes: [.init(kind: .officialStamp, box: stampBox)],
                                     hash: String(repeating: "b", count: 64))])
        XCTAssertEqual(result, detected)
    }
}
