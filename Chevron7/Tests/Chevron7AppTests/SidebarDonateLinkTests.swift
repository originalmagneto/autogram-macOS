// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import Foundation
import XCTest
@testable import Chevron7App

/// The quiet "Podporiť vývoj" row next to "Nastavenia": the same Buy Me a Coffee page as
/// the Help menu, with a plain label and an explanation, never a prompt.
final class SidebarDonateLinkTests: XCTestCase {
    func testOpensTheSamePageAsTheHelpMenu() {
        XCTAssertEqual(SidebarDonateLink.url, AppLinks.donate)
        XCTAssertEqual(SidebarDonateLink.url.scheme, "https")
        XCTAssertEqual(SidebarDonateLink.url.host, "buymeacoffee.com")
        XCTAssertEqual(SidebarDonateLink.url.path, "/chevron7")
    }

    func testWording() {
        XCTAssertEqual(SidebarDonateLink.title, "Podporiť vývoj")
        XCTAssertEqual(SidebarDonateLink.symbol, "cup.and.saucer")
        XCTAssertEqual(SidebarDonateLink.help,
                       "Chevron7 je zadarmo. Príspevok cez Buy Me a Coffee pomáha platiť vývoj a podpisovanie aplikácie.")
        XCTAssertEqual(SidebarDonateLink.accessibilityLabel, "Podporiť vývoj Chevron7 cez Buy Me a Coffee")
    }

    func testNoEmDashInAnyText() {
        for text in [SidebarDonateLink.title, SidebarDonateLink.help, SidebarDonateLink.accessibilityLabel] {
            XCTAssertFalse(text.contains("\u{2014}"), text)
        }
    }
}
