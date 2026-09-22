import XCTest
import Chevron7Kit
@testable import Chevron7App

final class SettingsLearningCardTests: XCTestCase {
    func testSummaryListsCountsPerLabelInSlovak() {
        let text = LearningCardText.summary(counts: [
            .kind(.officialStamp): 12, .kind(.handwrittenSignature): 7, .negative: 3])
        XCTAssertEqual(text, "Pečiatky: 12 · Podpisy: 7 · Slepotlač: 0 · Parafy: 0 · Šnúrky: 0 · Pásky: 0 · Pečate: 0 · Ochranné prvky: 0 · Iné: 0 · Zamietnuté: 3")
    }

    func testEmptySummary() {
        XCTAssertEqual(LearningCardText.summary(counts: [:]),
                       "Pečiatky: 0 · Podpisy: 0 · Slepotlač: 0 · Parafy: 0 · Šnúrky: 0 · Pásky: 0 · Pečate: 0 · Ochranné prvky: 0 · Iné: 0 · Zamietnuté: 0")
    }
}
