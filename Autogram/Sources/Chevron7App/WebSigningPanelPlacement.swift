// SPDX-FileCopyrightText: 2026 Marián Čuprík
// SPDX-License-Identifier: EUPL-1.2

import CoreGraphics

/// Where the web signing panel goes: centered over Safari's front window, or on the
/// screen under the mouse when no Safari window is found. Pure, so it is tested
/// with plain rectangles instead of real windows.
enum WebSigningPanelPlacement {
    struct Screen: Equatable {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// - Parameters:
    ///   - safariQuartzBounds: window bounds as `CGWindowListCopyWindowInfo` reports
    ///     them, top-left origin on the primary screen.
    ///   - screens: `screens[0]` is the primary screen.
    ///   - mouseLocation: Cocoa coordinates.
    static func origin(panelSize: CGSize, safariQuartzBounds: CGRect?, screens: [Screen],
                       mouseLocation: CGPoint) -> CGPoint {
        guard let primary = screens.first else { return .zero }
        if let quartz = safariQuartzBounds {
            let window = CGRect(x: quartz.minX, y: primary.frame.height - quartz.maxY,
                                width: quartz.width, height: quartz.height)
            let center = CGPoint(x: window.midX, y: window.midY)
            let screen = screens.first { $0.frame.contains(center) } ?? primary
            return clamped(CGPoint(x: center.x - panelSize.width / 2, y: center.y - panelSize.height / 2),
                           panelSize: panelSize, in: screen.visibleFrame)
        }
        let screen = screens.first { $0.frame.contains(mouseLocation) } ?? primary
        let area = screen.visibleFrame
        return clamped(CGPoint(x: area.midX - panelSize.width / 2, y: area.midY - panelSize.height / 2),
                       panelSize: panelSize, in: area)
    }

    private static func clamped(_ origin: CGPoint, panelSize: CGSize, in area: CGRect) -> CGPoint {
        CGPoint(x: min(max(origin.x, area.minX), max(area.minX, area.maxX - panelSize.width)),
                y: min(max(origin.y, area.minY), max(area.minY, area.maxY - panelSize.height)))
    }
}
