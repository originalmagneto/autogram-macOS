import SwiftUI

struct WorkspaceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No PDF Selected", systemImage: "doc.richtext")
        } description: {
            Text("Select a PDF to inspect and sign it.")
        } actions: {
            Button("Select PDF…") {}
                .disabled(true)
        }
    }
}
