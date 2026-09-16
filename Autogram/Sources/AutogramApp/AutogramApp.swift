import SwiftUI
import AutogramKit

@MainActor
@Observable
final class AutogramAppModel {
    let settingsStore: AppSettingsStore
    let recentDocumentStore: RecentDocumentStore
    let signingStore: SigningSessionStore
    let zakoStore: ZakoSessionStore
    let ezzkSessionController: EZZKSessionController
    let signedDocumentStore: SignedDocumentStore
    let webSigning: WebSigningCoordinator

    init() {
        let settings = AppSettingsStore()
        let recentDocuments = RecentDocumentStore(settingsStore: settings)
        settingsStore = settings
        recentDocumentStore = recentDocuments
        ezzkSessionController = settings.ezzkSessionController
        signingStore = SigningSessionStore(
            signingProvider: settings.signingProvider,
            settingsStore: settings,
            recentDocumentStore: recentDocuments)
        zakoStore = ZakoSessionStore(settingsStore: settings, exampleBank: settings.exampleBank)
        let signedDocuments = SignedDocumentStore()
        signedDocumentStore = signedDocuments
        signingStore.signedDocumentStore = signedDocuments
        webSigning = WebSigningCoordinator(settingsStore: settings, signedDocumentStore: signedDocuments)

        // Browser requests reach the app through the Safari extension and the
        // launchd rendezvous; nothing signs without the sheet this raises.
        let coordinator = webSigning
        WebBridgeListener.shared.setSignHandler { request in
            try await coordinator.handle(request)
        }
    }
}

struct AutogramCommandActions {
    let openDocument: () -> Void
    let addFiles: () -> Void
    let toggleSidebar: () -> Void
    /// Recent documents for the File menu; empty when the feature is off.
    let recentDocuments: [RecentDocumentStore.RecentDocument]
    let openRecent: (RecentDocumentStore.RecentDocument) -> Void
    let clearRecent: () -> Void
}

private struct AutogramCommandActionsKey: FocusedValueKey {
    typealias Value = AutogramCommandActions
}

extension FocusedValues {
    var autogramCommandActions: AutogramCommandActions? {
        get { self[AutogramCommandActionsKey.self] }
        set { self[AutogramCommandActionsKey.self] = newValue }
    }
}

@main
struct AutogramApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AutogramAppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(model.ezzkSessionController)
                .frame(minWidth: MacOS27Layout.rootMinimumWidth, minHeight: 640)
                .frame(idealWidth: 1320, idealHeight: 860)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1320, height: 860)
        // A portal request started the app: only the signing panel, no main window.
        .defaultLaunchBehavior(AppLaunchMode.current == .webSigning ? .suppressed : .automatic)
        // Window restoration would reopen the last main window despite the suppression.
        .restorationBehavior(AppLaunchMode.current == .webSigning ? .disabled : .automatic)
        .commands {
            AutogramCommands()
        }

        // A regular window instead of the Settings scene: the Settings scene sizes
        // its window from the hosting view's preferred size and cannot be resized.
        Window("Nastavenia", id: SettingsWindow.id) {
            SettingsView(settingsStore: model.settingsStore, waitForLearningWrites: { await model.zakoStore.waitForBankWrites() })
                .environment(model.ezzkSessionController)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 940, height: 720)
        .windowResizability(.contentMinSize)
    }
}

private struct AutogramCommands: Commands {
    @FocusedValue(\.autogramCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                actions?.openDocument()
            } label: {
                Label("Otvoriť súbor…", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions == nil)

            Button {
                actions?.addFiles()
            } label: {
                Label("Pridať súbory…", systemImage: "plus.rectangle.on.folder")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Menu("Otvoriť nedávne") {
                let recents = actions?.recentDocuments ?? []
                if recents.isEmpty {
                    Text("Žiadne nedávne dokumenty")
                } else {
                    ForEach(recents) { entry in
                        Button {
                            actions?.openRecent(entry)
                        } label: {
                            Label(entry.displayName, systemImage: "doc")
                        }
                    }
                    Divider()
                    Button {
                        actions?.clearRecent()
                    } label: {
                        Label("Vymazať menu", systemImage: "trash")
                    }
                }
            }
            .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button {
                actions?.toggleSidebar()
            } label: {
                Label("Zobraziť alebo skryť sidebar", systemImage: "sidebar.left")
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .appSettings) {
            OpenSettingsButton {
                Label("Nastavenia…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // A portal request started the app: no Dock icon and no menu bar until the
        // person opens Autogram themselves.
        if AppLaunchMode.current == .webSigning {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FinderQuickActionService.installQuickAction()
        WebBridgeListener.shared.start()
    }

    /// The launch open event asks for an untitled main window; a web-signing launch
    /// shows only the signing panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        AppLaunchMode.current != .webSigning || NSApp.activationPolicy() == .regular
    }

    /// Dock, Finder or Spotlight while the app already runs: become a regular app,
    /// and let SwiftUI open the main window when none is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.becomeRegularApp()
        Self.openMainWindowIfNeeded()
        return true
    }

    /// The main window scene is suppressed after a web-signing launch, so reopening
    /// does not bring one back by itself. The File > New Window command (⌘N) does.
    @MainActor
    static func openMainWindowIfNeeded() {
        let hasMainWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
        guard !hasMainWindow, let item = newWindowMenuItem(in: NSApp.mainMenu), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    @MainActor
    private static func newWindowMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.keyEquivalent == "n", item.keyEquivalentModifierMask == .command, item.action != nil {
                return item
            }
            if let found = newWindowMenuItem(in: item.submenu) {
                return found
            }
        }
        return nil
    }

    @MainActor
    static func becomeRegularApp() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

enum SettingsWindow {
    static let id = "settings"
}

/// Opens (or fronts) the settings window; replaces `SettingsLink` now that the
/// settings live in a regular `Window` scene.
struct OpenSettingsButton<Label: View>: View {
    @Environment(\.openWindow) private var openWindow
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            AppDelegate.becomeRegularApp()
            openWindow(id: SettingsWindow.id)
        } label: {
            label()
        }
    }
}
