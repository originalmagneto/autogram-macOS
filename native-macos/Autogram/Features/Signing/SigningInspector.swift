import AppKit
import SwiftUI

struct SigningInspector: View {
    let workspace: WorkspaceModel

    var body: some View {
        Form {
            Section("Signing") {
                LabeledContent("Profile", value: "PAdES baseline")
                LabeledContent("Timestamp", value: "Qualified")
            }

            if completedCount > 0 || failedCount > 0 {
                Section("Results") {
                    Text(summary)

                    ForEach(workspace.items) { item in
                        if item.status == .completed || item.status == .failed {
                            LabeledContent(item.descriptor.redactedDisplayName, value: item.status.resultLabel)
                            Button("Reveal \(item.descriptor.redactedDisplayName)") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.descriptor.sourceURL])
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 260, ideal: 300)
    }

    private var completedCount: Int {
        workspace.items.count { $0.status == .completed }
    }

    private var failedCount: Int {
        workspace.items.count { $0.status == .failed }
    }

    private var summary: String {
        "\(completedCount) file signed, \(failedCount) failed"
    }
}

private extension PDFItemStatus {
    var resultLabel: String {
        switch self {
        case .completed: "Signed"
        case .failed: "Failed"
        case .pending, .inspected: "Ready"
        case .signing: "Signing"
        }
    }
}
