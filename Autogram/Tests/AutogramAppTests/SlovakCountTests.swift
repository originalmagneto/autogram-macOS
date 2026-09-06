import XCTest
@testable import AutogramApp

final class SlovakCountTests: XCTestCase {
    func testPluralFormsFollowSlovakRules() {
        XCTAssertEqual(SlovakCount.phrase(1, "strana", "strany", "strán"), "1 strana")
        XCTAssertEqual(SlovakCount.phrase(2, "strana", "strany", "strán"), "2 strany")
        XCTAssertEqual(SlovakCount.phrase(4, "prvok", "prvky", "prvkov"), "4 prvky")
        XCTAssertEqual(SlovakCount.phrase(5, "prvok", "prvky", "prvkov"), "5 prvkov")
        XCTAssertEqual(SlovakCount.phrase(0, "list", "listy", "listov"), "0 listov")
    }
}
