// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
@testable import Chevron7App

final class WebSigningPanelPlacementTests: XCTestCase {
    private let primary = WebSigningPanelPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
    private let panel = CGSize(width: 540, height: 600)

    func testCentersOverSafariOnThePrimaryScreen() {
        // Quartz: top-left origin. Window 1200x800 at (360, 140) -> Cocoa y = 1080 - 940 = 140.
        let origin = WebSigningPanelPlacement.origin(panelSize: panel,
            safariQuartzBounds: CGRect(x: 360, y: 140, width: 1200, height: 800),
            screens: [primary], mouseLocation: .zero)
        XCTAssertEqual(origin, CGPoint(x: 360 + 600 - 270, y: 140 + 400 - 300))
    }

    func testCentersOverSafariOnASecondScreenAbove() {
        let above = WebSigningPanelPlacement.Screen(
            frame: CGRect(x: 0, y: 1080, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 1080, width: 2560, height: 1415))
        // Quartz y of the upper screen's top is -1440; window 1000x900 at (780, -1170).
        let origin = WebSigningPanelPlacement.origin(panelSize: panel,
            safariQuartzBounds: CGRect(x: 780, y: -1170, width: 1000, height: 900),
            screens: [primary, above], mouseLocation: .zero)
        // Cocoa window minY = 1080 - (-1170 + 900) = 1350; center y = 1800.
        XCTAssertEqual(origin, CGPoint(x: 780 + 500 - 270, y: 1800 - 300))
    }

    func testClampsInsideTheVisibleFrame() {
        let origin = WebSigningPanelPlacement.origin(panelSize: panel,
            safariQuartzBounds: CGRect(x: 1700, y: 900, width: 400, height: 300),
            screens: [primary], mouseLocation: .zero)
        XCTAssertEqual(origin.x, 1920 - 540)
        XCTAssertEqual(origin.y, 0)
    }

    func testWithoutSafariCentersOnTheScreenUnderTheMouse() {
        let right = WebSigningPanelPlacement.Screen(
            frame: CGRect(x: 1920, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1440, height: 875))
        let origin = WebSigningPanelPlacement.origin(panelSize: panel, safariQuartzBounds: nil,
            screens: [primary, right], mouseLocation: CGPoint(x: 2500, y: 400))
        XCTAssertEqual(origin, CGPoint(x: 1920 + 720 - 270, y: 437.5 - 300))
    }
}
