import SwiftUI

struct AppCommands: Commands {
    let workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Select PDF…") {
                workspace.selectPDFs()
            }
                .keyboardShortcut("o", modifiers: .command)
        }
    }
}
