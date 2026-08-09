import AppKit
import SwiftUI

struct SigningInspector: View {
    let workspace: WorkspaceModel
    @Binding var isPINSheetPresented: Bool
    @State private var pin = ""
    @State private var isCertificatePickerPresented = false

    var body: some View {
        Form {
            Section("Signing") {
                LabeledContent("Profile", value: "PAdES baseline")
                LabeledContent("Timestamp", value: "Qualified")
            }

            Section("Driver") {
                if workspace.isLoadingSigningEnvironment {
                    ProgressView("Discovering signing drivers")
                } else if workspace.selectableDrivers.count > 1 {
                    Picker("Driver", selection: Binding(
                        get: { workspace.selectedDriverID },
                        set: { workspace.selectDriver(id: $0) }
                    )) {
                        Text("Choose a driver").tag(Optional<String>.none)
                        ForEach(workspace.selectableDrivers) { driver in
                            Text(driver.displayName).tag(Optional(driver.id))
                        }
                    }
                } else if let driver = selectedDriver {
                    LabeledContent("Driver", value: driver.displayName)
                } else if !workspace.availableDrivers.isEmpty, workspace.tokenPresenceIsKnown {
                    Label("No connected signing card detected", systemImage: "exclamationmark.triangle")
                } else {
                    Label("No compatible signing driver detected", systemImage: "exclamationmark.triangle")
                }

                if let credentialError = workspace.credentialError {
                    Text(credentialError)
                        .foregroundStyle(.secondary)
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

            if let phase = workspace.signingActivityPhase {
                Section("Signing progress") {
                    ProgressView(phase.label)

                    if completedCount > 0 || failedCount > 0 {
                        ProgressView(value: Double(completedCount + failedCount), total: Double(workspace.items.count)) {
                            Text("Signing documents")
                        }
                        .accessibilityValue("\(completedCount + failedCount) of \(workspace.items.count) documents complete")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 260, ideal: 300)
        .sheet(isPresented: $isPINSheetPresented) {
            PINSheet(pin: $pin) { submission in
                Task {
                    let resolution = await workspace.resolveCertificates(using: submission)
                    isCertificatePickerPresented = resolution == .certificateSelectionRequired
                }
            } onCancel: {
                workspace.cancelCredentialFlow()
            }
        }
        .sheet(isPresented: $isCertificatePickerPresented, onDismiss: {
            workspace.cancelCredentialFlow()
        }) {
            CertificatePicker(certificates: workspace.discoveredCertificates) { certificate, rememberAsDefault in
                workspace.selectCertificateForSigning(certificate, rememberAsDefault: rememberAsDefault)
                isCertificatePickerPresented = false
            } onCancel: {
                isCertificatePickerPresented = false
                workspace.cancelCredentialFlow()
            }
        }
        .onDisappear {
            workspace.cancelCredentialFlow()
        }
    }

    private var selectedDriver: SigningDriver? {
        workspace.selectableDrivers.first { $0.id == workspace.selectedDriverID }
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
