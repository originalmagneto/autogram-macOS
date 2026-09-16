import AppKit
import SwiftUI
import os

private final class WebSigningPanelDelegate: NSObject, NSWindowDelegate {
    private weak var coordinator: WebSigningCoordinator?

    init(coordinator: WebSigningCoordinator) {
        self.coordinator = coordinator
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.cancel()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            coordinator?.promptBecameKey()
        }
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
    private let log = Logger(subsystem: "sk.autogram.Autogram", category: "web-signing")
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
        log.notice("BOK handoff started, app active: \(NSApp.isActive, privacy: .public)")
        keyboardHandoff = Task { @MainActor [log] in
            var activated = Set<pid_t>()
            var reported = Set<pid_t>()
            while !Task.isCancelled {
                for app in NSWorkspace.shared.runningApplications {
                    let path = app.executableURL?.path ?? "-"
                    // Diagnostics: every eID client process seen while the BOK is expected.
                    if path.contains("eID") || path.contains("VirtualKeyboard"), !reported.contains(app.processIdentifier) {
                        reported.insert(app.processIdentifier)
                        log.notice("""
                            eID process pid=\(app.processIdentifier, privacy: .public) \
                            bundle=\(app.bundleIdentifier ?? "-", privacy: .public) path=\(path, privacy: .public) \
                            policy=\(app.activationPolicy.rawValue, privacy: .public) active=\(app.isActive, privacy: .public)
                            """)
                    }
                    guard Self.isEIDKeyboard(app), !activated.contains(app.processIdentifier) else { continue }
                    activated.insert(app.processIdentifier)
                    NSApp.yieldActivation(to: app)
                    let accepted = app.activate(from: .current, options: [])
                    log.notice("""
                        BOK window activation pid=\(app.processIdentifier, privacy: .public) \
                        accepted=\(accepted, privacy: .public) app active=\(NSApp.isActive, privacy: .public)
                        """)
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
        // Closing the BOK window hands activation back to this app, which raises
        // its main window over the prompt; the prompt takes the front and keyboard back.
        if NSApp.isActive {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
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

