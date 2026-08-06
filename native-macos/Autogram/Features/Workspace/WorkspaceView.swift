import SwiftUI

struct WorkspaceView: View {
    let workspace: WorkspaceModel
    @AppStorage("preferences.driverID") private var driverID = ""
    @AppStorage("preferences.certificateSerial") private var certificateSerial = ""
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
                        isPINSheetPresented: $isPINSheetPresented,
                        configuredDriverID: driverID,
                        configuredCertificateSerial: certificateSerial
                    )
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
                .disabled(workspace.items.isEmpty || !credentialsAreConfigured)
                .help("Sign the selected PDFs")
            }
        }
    }

    private var selectedItem: PDFItem? {
        guard let selection = workspace.selection else { return workspace.items.first }
        return workspace.items.first { $0.id == selection }
    }

    private var credentialsAreConfigured: Bool {
        !driverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !certificateSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
