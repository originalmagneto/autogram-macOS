// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7Kit

final class DetectorTrainingReadinessTests: XCTestCase {
    private func page(sha: String, index: Int, labels: [String],
                      reviewedAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> ReviewedBankPage {
        ReviewedBankPage(documentSHA256: sha, pageIndex: index,
                         boxes: labels.map { label in
                             ReviewedPageBox(kind: kind(for: label),
                                             box: .init(x: 0, y: 0, width: 0.1, height: 0.1))
                         },
                         reviewedAt: reviewedAt, detectorVersion: "t")
    }

    func testOverallFractionTakesBindingGate() {
        XCTAssertEqual(DetectorTrainingReadiness.overallFraction(pages: 1, documents: 1, newSince: 0, trainedBefore: false),
                       0.025, accuracy: 1e-9)
        XCTAssertEqual(DetectorTrainingReadiness.overallFraction(pages: 40, documents: 8, newSince: 0, trainedBefore: false), 1)
        XCTAssertEqual(DetectorTrainingReadiness.overallFraction(pages: 40, documents: 2, newSince: 0, trainedBefore: false), 0.25)
    }

    func testOverallFractionRetraining() {
        XCTAssertEqual(DetectorTrainingReadiness.overallFraction(pages: 60, documents: 12, newSince: 10, trainedBefore: true), 0.5)
        XCTAssertEqual(DetectorTrainingReadiness.overallFraction(pages: 60, documents: 12, newSince: 99, trainedBefore: true), 1)
    }

    private func kind(for label: String) -> SecurityElement.Kind {
        switch label {
        case "officialStamp": return .officialStamp
        case "handwrittenSignature": return .handwrittenSignature
        default: return .initial
        }
    }

    private func manyPages(count: Int, docs: Int) -> [ReviewedBankPage] {
        (0..<count).map { i in
            page(sha: "doc\(i % docs)", index: i,
                 labels: Array(repeating: "officialStamp", count: 4))
        }
    }

    func testOfferDueAtGate() {
        let report = DetectorTrainingReadiness.report(
            pages: manyPages(count: 40, docs: 8), lastRunAt: nil,
            learnOn: true, offersEnabled: true, snoozedUntil: nil)
        XCTAssertTrue(report.offerDue)
        XCTAssertEqual(report.reviewedPages, 40)
        XCTAssertEqual(report.documents, 8)
        XCTAssertEqual(report.trainedLabels, ["officialStamp"])
    }

    func testNoOfferBelowGate() {
        let few = DetectorTrainingReadiness.report(
            pages: manyPages(count: 39, docs: 8), lastRunAt: nil,
            learnOn: true, offersEnabled: true, snoozedUntil: nil)
        XCTAssertFalse(few.offerDue)
        let fewDocs = DetectorTrainingReadiness.report(
            pages: manyPages(count: 40, docs: 7), lastRunAt: nil,
            learnOn: true, offersEnabled: true, snoozedUntil: nil)
        XCTAssertFalse(fewDocs.offerDue)
    }

    func testLabelLeftOutBelow15Boxes() {
        let report = DetectorTrainingReadiness.report(
            pages: [page(sha: "d", index: 0, labels: ["officialStamp"])],
            lastRunAt: nil, learnOn: true, offersEnabled: true, snoozedUntil: nil)
        XCTAssertTrue(report.trainedLabels.isEmpty)
        XCTAssertEqual(report.leftOutLabels["officialStamp"], 1)
    }

    func testRetrainingNeeds20NewReviews() {
        let lastRun = Date(timeIntervalSince1970: 2_000_000)
        let old = manyPages(count: 40, docs: 8).map { p in
            ReviewedBankPage(documentSHA256: p.documentSHA256, pageIndex: p.pageIndex,
                             boxes: p.boxes, reviewedAt: Date(timeIntervalSince1970: 1_000_000),
                             detectorVersion: p.detectorVersion)
        }
        var fewNew = old
        fewNew += (0..<19).map { i in
            page(sha: "new\(i)", index: 0, labels: ["officialStamp"],
                 reviewedAt: Date(timeIntervalSince1970: 3_000_000))
        }
        XCTAssertFalse(DetectorTrainingReadiness.report(
            pages: fewNew, lastRunAt: lastRun, learnOn: true,
            offersEnabled: true, snoozedUntil: nil).offerDue)
        let enoughNew = fewNew + [page(sha: "newX", index: 0, labels: ["officialStamp"],
                                       reviewedAt: Date(timeIntervalSince1970: 3_000_000))]
        XCTAssertTrue(DetectorTrainingReadiness.report(
            pages: enoughNew, lastRunAt: lastRun, learnOn: true,
            offersEnabled: true, snoozedUntil: nil).offerDue)
    }

    func testSnoozeSuppressesOffer() {
        let pages = manyPages(count: 40, docs: 8)
        let snoozed = DetectorTrainingReadiness.report(
            pages: pages, lastRunAt: nil, learnOn: true, offersEnabled: true,
            snoozedUntil: Date(timeIntervalSince1970: 9_000_000),
            now: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertFalse(snoozed.offerDue)
        let expired = DetectorTrainingReadiness.report(
            pages: pages, lastRunAt: nil, learnOn: true, offersEnabled: true,
            snoozedUntil: Date(timeIntervalSince1970: 500_000),
            now: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertTrue(expired.offerDue)
    }

    func testOffersOffSuppressesOffer() {
        let report = DetectorTrainingReadiness.report(
            pages: manyPages(count: 40, docs: 8), lastRunAt: nil,
            learnOn: true, offersEnabled: false, snoozedUntil: nil)
        XCTAssertFalse(report.offerDue)
    }

    func testLearningOffSuppressesOffer() {
        let report = DetectorTrainingReadiness.report(
            pages: manyPages(count: 40, docs: 8), lastRunAt: nil,
            learnOn: false, offersEnabled: true, snoozedUntil: nil)
        XCTAssertFalse(report.offerDue)
    }

    func testTrainingStateRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = TrainingState(lastRunAt: Date(timeIntervalSince1970: 1_000_000),
                                  secondsPerPage: 16,
                                  snoozedUntil: Date(timeIntervalSince1970: 2_000_000))
        try TrainingState.save(state, in: folder)
        let loaded = try TrainingState.load(from: folder)
        XCTAssertEqual(loaded, state)
    }

    func testTrainingStateDefaultsWhenMissing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(try TrainingState.load(from: folder), TrainingState())
    }
}
