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
        zakoStore = ZakoSessionStore(settingsStore: settings)
    }
}

struct AutogramCommandActions {
    let openDocument: () -> Void
    let addFiles: () -> Void
    let toggleSidebar: () -> Void
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

        Settings {
            SettingsView(settingsStore: model.settingsStore)
                .environment(model.ezzkSessionController)
        }
        .defaultSize(width: 1080, height: 940)
        .windowResizability(.contentSize)
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
        }

        CommandGroup(after: .sidebar) {
            Button("Zobraziť alebo skryť sidebar") {
                actions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(actions == nil)
        }

        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Text("Nastavenia…")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registers the in-process NSServices provider (Finder Quick Action).
        NSApp.servicesProvider = ServicesProvider()

        // Flush the system services cache so Finder sees the registered Quick Action.
        let pbs = Process()
        pbs.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        pbs.arguments = ["-update"]
        try? pbs.run()
    }
}
