import SwiftUI

struct WorkspaceView: View {
    let workspace: WorkspaceModel
    @State private var inspectorPresented = true

    var body: some View {
        Group {
            if workspace.items.isEmpty {
                ContentUnavailableView {
                    Label("No PDF Selected", systemImage: "doc.richtext")
                } description: {
                    Text("Select a PDF to inspect and sign with a qualified timestamp.")
                } actions: {
                    Button("Select PDF…") {
                        workspace.selectPDFs()
                    }
                }
            } else {
                NavigationSplitView {
                    PDFListView(workspace: workspace)
                } detail: {
                    PDFDetailView(item: selectedItem)
                }
                .navigationSplitViewStyle(.balanced)
                .inspector(isPresented: $inspectorPresented) {
                    SigningInspector(workspace: workspace)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            workspace.addPDFs(urls)
        }
        .toolbar {
            ToolbarItem {
                Button("Add PDFs", systemImage: "plus") {
                    workspace.selectPDFs()
                }
            }
            ToolbarItem {
                Button("Remove PDF", systemImage: "trash") {
                    workspace.removeSelectedItem()
                }
                .disabled(workspace.selection == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Sign", systemImage: "signature") {
                    Task { await workspace.sign() }
                }
                .disabled(workspace.items.isEmpty)
            }
        }
    }

    private var selectedItem: PDFItem? {
        guard let selection = workspace.selection else { return workspace.items.first }
        return workspace.items.first { $0.id == selection }
    }
}
