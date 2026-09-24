// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import XCTest
import SwiftUI
import Chevron7Kit
@testable import Chevron7App

/// Every kind has its own colour; grey is reserved for rejected findings.
final class ElementKindColorTests: XCTestCase {
    func testEveryKindHasItsOwnNonGreyColour() {
        let kinds = SecurityElement.Kind.allCases
        XCTAssertEqual(kinds.count, 16)
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let resolved = kinds.map { ElementKindColor.color(for: $0).resolve(in: environment) }
            for (kind, colour) in zip(kinds, resolved) {
                let channels = [colour.red, colour.green, colour.blue]
                XCTAssertGreaterThan(channels.max()! - channels.min()!, 0.2, "\(kind) looks grey in \(scheme)")
                XCTAssertNotEqual(ElementKindColor.color(for: kind), .gray)
            }
            for i in resolved.indices {
                for j in resolved.indices where j > i {
                    let a = resolved[i], b = resolved[j]
                    let distance = abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
                    XCTAssertGreaterThan(distance, 0.1, "\(kinds[i]) and \(kinds[j]) look alike in \(scheme)")
                }
            }
        }
    }

    /// Explicit colours must read on white scanned paper (3:1) and on a dark inspector.
    func testExplicitColoursStayReadableOnPaperAndInDarkMode() {
        XCTAssertEqual(ElementKindColor.explicitRGB.count, 12)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        for (kind, rgb) in ElementKindColor.explicitRGB {
            let r = linear(Double((rgb >> 16) & 0xFF) / 255)
            let g = linear(Double((rgb >> 8) & 0xFF) / 255)
            let b = linear(Double(rgb & 0xFF) / 255)
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            XCTAssertGreaterThanOrEqual(1.05 / (luminance + 0.05), 3.0, "\(kind) too pale on paper")
            XCTAssertGreaterThanOrEqual(luminance, 0.12, "\(kind) too dark in dark mode")
        }
    }
}
