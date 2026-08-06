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

    init() {
        let dependencies = AppLaunchDependencies.make()
        _workspace = State(initialValue: WorkspaceModel.launchWorkspace(
            engine: dependencies.engine,
            fixtureMode: dependencies.fixtureMode
        ))
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView(workspace: workspace)
        }
        .commands {
            AppCommands(workspace: workspace)
        }

        Settings {
            AutogramSettingsView()
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
