import SwiftUI

struct WorkspaceView: View {
    let workspace: WorkspaceModel
    @State private var inspectorPresented = true
    @State private var isPINSheetPresented = false

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
                    SigningInspector(
                        workspace: workspace,
                        isPINSheetPresented: $isPINSheetPresented
                    )
                }
                .onChange(of: workspace.selectedOutputFormat) { _, format in
                    if format == .asiceXAdES {
                        workspace.setVisibleSignatureEnabled(false)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            workspace.addPDFs(urls)
        }
        .task {
            await workspace.refreshSigningEnvironment()
            await workspace.refreshInspections()
        }
        .toolbar {
            ToolbarItem {
                Button("Add PDFs", systemImage: "plus") {
                    workspace.selectPDFs()
                }
                .help("Select PDF files to inspect and sign")
            }
            ToolbarItem {
                Button("Remove PDF", systemImage: "trash") {
                    workspace.removeSelectedItem()
                }
                .disabled(workspace.selection == nil)
                .help("Remove the selected PDF")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Sign", systemImage: "signature") {
                    inspectorPresented = true
                    isPINSheetPresented = true
                }
                .disabled(!workspace.canStartSigning || selectedDriver == nil)
                .help("Sign the selected PDFs")
            }
        }
    }

    private var selectedItem: PDFItem? {
        guard let selection = workspace.selection else { return workspace.items.first }
        return workspace.items.first { $0.id == selection }
    }

    private var selectedDriver: SigningDriver? {
        workspace.availableDrivers.first { $0.id == workspace.selectedDriverID }
    }
}
