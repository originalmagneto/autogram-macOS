import AppKit
import SwiftUI

struct SigningInspector: View {
    let workspace: WorkspaceModel
    @Binding var isPINSheetPresented: Bool
    let configuredDriverID: String
    let configuredCertificateSerial: String
    @State private var certificateSerial: String?
    @State private var pin = ""

    var body: some View {
        Form {
            Section("Signing") {
                LabeledContent("Profile", value: "PAdES baseline")
                LabeledContent("Timestamp", value: "Qualified")
            }

            if !workspace.credentialCertificates.isEmpty {
                Section("Certificate") {
                    CertificatePicker(
                        certificates: workspace.credentialCertificates,
                        selectedSerial: $certificateSerial
                    ) {
                        isPINSheetPresented = true
                    }
                }
            } else if !credentialsAreConfigured {
                Section("Certificate") {
                    Label("Signing configuration needed", systemImage: "gearshape")
                    Text("Choose a driver and certificate in Settings before signing.")
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Text("Open Settings")
                    }
                }
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

            if isSigning {
                Section("Signing progress") {
                    ProgressView(value: Double(completedCount + failedCount), total: Double(workspace.items.count)) {
                        Text("Signing documents")
                    }
                    .accessibilityValue("\(completedCount + failedCount) of \(workspace.items.count) documents complete")
                }
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 260, ideal: 300)
        .sheet(isPresented: $isPINSheetPresented) {
            PINSheet(pin: $pin) { secret in
                guard let signingCredentials else { return }
                Task {
                    await workspace.sign(
                        driverID: signingCredentials.driverID,
                        certificateSerial: signingCredentials.certificateSerial,
                        pin: secret
                    )
                }
            }
        }
    }

    private var credentialsAreConfigured: Bool {
        !configuredDriverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !configuredCertificateSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var signingCredentials: (driverID: String, certificateSerial: String)? {
        if !workspace.credentialCertificates.isEmpty {
            guard let certificateSerial else { return nil }
            return ("fixture-driver", certificateSerial)
        }

        guard credentialsAreConfigured else { return nil }
        return (configuredDriverID, configuredCertificateSerial)
    }

    private var completedCount: Int {
        workspace.items.count { $0.status == .completed }
    }

    private var failedCount: Int {
        workspace.items.count { $0.status == .failed }
    }

    private var isSigning: Bool {
        workspace.items.contains { $0.status == .signing }
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
