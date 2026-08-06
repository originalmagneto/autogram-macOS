import SwiftUI

struct PDFListView: View {
    let workspace: WorkspaceModel

    var body: some View {
        @Bindable var workspace = workspace

        List(selection: $workspace.selection) {
            ForEach(workspace.items) { item in
                HStack {
                    Image(systemName: "doc.richtext")
                    Text(item.descriptor.redactedDisplayName)
                    Spacer()
                    Text(item.status.workspaceLabel)
                        .foregroundStyle(item.status.workspaceColor)
                }
                .tag(item.id)
            }
            .onMove(perform: workspace.moveItems)
            .onDelete(perform: workspace.removeItems)
        }
        .accessibilityIdentifier("Workspace Sidebar")
        .navigationTitle("PDFs")
    }
}

private extension PDFItemStatus {
    var workspaceLabel: String {
        switch self {
        case .pending: "Ready"
        case .inspected: "Ready"
        case .signing: "Signing"
        case .completed: "Signed"
        case .failed: "Failed"
        }
    }

    var workspaceColor: Color {
        switch self {
        case .failed: .red
        case .completed: .green
        default: .secondary
        }
    }
}
