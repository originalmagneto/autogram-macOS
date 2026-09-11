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
        .commands {
            AutogramCommands()
        }

        // A regular window instead of the Settings scene: the Settings scene sizes
        // its window from the hosting view's preferred size and cannot be resized.
        Window("Nastavenia", id: SettingsWindow.id) {
            SettingsView(settingsStore: model.settingsStore)
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
            Button("Otvoriť súbor…") {
                actions?.openDocument()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions == nil)

            Button("Pridať súbory…") {
                actions?.addFiles()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Menu("Otvoriť nedávne") {
                let recents = actions?.recentDocuments ?? []
                if recents.isEmpty {
                    Text("Žiadne nedávne dokumenty")
                } else {
                    ForEach(recents) { entry in
                        Button(entry.displayName) {
                            actions?.openRecent(entry)
                        }
                    }
                    Divider()
                    Button("Vymazať menu") {
                        actions?.clearRecent()
                    }
                }
            }
            .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Zobraziť alebo skryť sidebar") {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .appSettings) {
            OpenSettingsButton {
                Text("Nastavenia…")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {

        FinderQuickActionService.installQuickAction()
        WebBridgeListener.shared.start()
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
            openWindow(id: SettingsWindow.id)
        } label: {
            label()
        }
    }
}
