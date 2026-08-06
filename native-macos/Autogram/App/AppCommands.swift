import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Select PDF…") {}
                .keyboardShortcut("o", modifiers: .command)
                .disabled(true)
        }
    }
}
