import SwiftUI

enum AppIdentity {
    static let bundleIdentifier = "digital.slovensko.autogram.native"
    static let minimumSystemVersion = "27.0"
    static let applicationVersion = "1.0"
    static let protocolVersion = "1"
}

@main
struct AutogramApp: App {
    @State private var workspace: WorkspaceModel
    @NSApplicationDelegateAdaptor(OpenDocumentAppDelegate.self) private var appDelegate

    init() {
        let dependencies = AppLaunchDependencies.make()
        _workspace = State(initialValue: WorkspaceModel.launchWorkspace(
            engine: dependencies.engine,
            fixtureMode: dependencies.fixtureMode
        ))
        let quickActionInstaller = QuickActionInstaller()
        try? quickActionInstaller.maintainIfInstalled()
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(workspace: workspace)
                .onAppear {
                    appDelegate.openEventHandler = OpenEventHandler(workspace: workspace)
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        await OpenEventHandler(workspace: workspace).handle([url])
                    }
                }
        }
        .commands {
            AppCommands(workspace: workspace)
        }

        Settings {
            AutogramSettingsView(workspace: workspace)
        }
    }
}

struct AppLaunchDependencies {
    let engine: any SigningEngine
    let fixtureMode: String?

    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppLaunchDependencies {
        #if DEBUG
        if let fixtureMode = environment["AUTOGRAM_FAKE_ENGINE"],
           ["partial-failure", "credential-flow"].contains(fixtureMode) {
            return AppLaunchDependencies(engine: FakeSigningEngine.launchEngine(environment: environment), fixtureMode: fixtureMode)
        }
        #endif
        return AppLaunchDependencies(engine: AutogramCLIEngine(), fixtureMode: nil)
    }
}
