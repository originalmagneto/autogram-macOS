import SwiftUI

enum AppIdentity {
    static let bundleIdentifier = "digital.slovensko.autogram.native"
    static let minimumSystemVersion = "27.0"
    static let applicationVersion = "1.0"
    static let protocolVersion = "1"
}

@main
struct AutogramApp: App {
    @State private var workspace = WorkspaceModel.launchWorkspace()

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
