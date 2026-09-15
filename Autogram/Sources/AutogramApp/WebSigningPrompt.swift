import AppKit
import SwiftUI

private final class WebSigningPanelDelegate: NSObject, NSWindowDelegate {
    private weak var coordinator: WebSigningCoordinator?

    init(coordinator: WebSigningCoordinator) {
        self.coordinator = coordinator
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.cancel()
    }
}

/// Shows the browser signing prompt in a floating panel instead of a sheet.
///
/// A sheet lives on the app's own window, and since macOS Sonoma an app in the
/// background cannot reliably pull itself in front: `activate(ignoringOtherApps:)`
/// is deprecated and the system grants it only sometimes. The request would then
/// sit behind Safari with nothing to show for it.
///
/// A panel ordered front regardless of activation appears over the browser
/// without stealing the keyboard. Clicking it activates the app the ordinary
/// way, which is what every password prompt on this platform does.
@MainActor
final class WebSigningPrompt {
    private var panel: NSPanel?
    private var delegate: WebSigningPanelDelegate?

    func show(coordinator: WebSigningCoordinator) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let hosting = NSHostingView(rootView: WebSigningSheet(coordinator: coordinator))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: max(size.width, 520), height: max(size.height, 460))),
            styleMask: [.titled, .closable, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false)
        panel.title = "Podpísať dokument zo stránky"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 420)
        panel.center()

        let delegate = WebSigningPanelDelegate(coordinator: coordinator)
        panel.delegate = delegate
        self.delegate = delegate
        self.panel = panel

        panel.orderFrontRegardless()
        // Bounces the Dock icon. Activation itself is the system's call, but a
        // request for attention is always honoured.
        NSApp.requestUserAttention(.criticalRequest)
    }

    func hide() {
        panel?.delegate = nil
        panel?.close()
        panel = nil
        delegate = nil
    }
}

