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
    private var middlewareInputDepth = 0
    private var keyboardHandoff: Task<Void, Never>?

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

    /// Moves the keyboard to the PIN field's window, when the system allows it.
    ///
    /// An app in the background cannot take the keyboard since macOS Sonoma, so
    /// this only helps once the person has clicked the prompt or the app.
    func focus() {
        guard let panel, NSApp.isActive else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Steps aside while the eID client asks for the BOK.
    ///
    /// The eID PKCS#11 module, running inside the signing engine, starts the eID
    /// client's `VirtualKeyboard` process for the BOK. A process started that way
    /// is not activated, so the keyboard stayed with this floating panel. The
    /// panel drops to the normal level so it cannot cover that window, and each
    /// BOK window that appears is activated from here, which the system allows
    /// while this app is the active one.
    func beginMiddlewareInput() {
        middlewareInputDepth += 1
        guard middlewareInputDepth == 1 else { return }
        panel?.level = .normal
        keyboardHandoff?.cancel()
        keyboardHandoff = Task { @MainActor in
            var activated = Set<pid_t>()
            while !Task.isCancelled {
                for app in NSWorkspace.shared.runningApplications
                where Self.isEIDKeyboard(app) && !activated.contains(app.processIdentifier) {
                    activated.insert(app.processIdentifier)
                    NSApp.yieldActivation(to: app)
                    app.activate(from: .current, options: [])
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func endMiddlewareInput() {
        guard middlewareInputDepth > 0 else { return }
        middlewareInputDepth -= 1
        guard middlewareInputDepth == 0 else { return }
        keyboardHandoff?.cancel()
        keyboardHandoff = nil
        guard let panel else { return }
        panel.level = .floating
        panel.orderFrontRegardless()
    }

    private static func isEIDKeyboard(_ app: NSRunningApplication) -> Bool {
        guard let executable = app.executableURL else { return false }
        return executable.lastPathComponent == "VirtualKeyboard" && executable.path.contains("eID")
    }

    func hide() {
        keyboardHandoff?.cancel()
        keyboardHandoff = nil
        middlewareInputDepth = 0
        panel?.delegate = nil
        panel?.close()
        panel = nil
        delegate = nil
    }
}

