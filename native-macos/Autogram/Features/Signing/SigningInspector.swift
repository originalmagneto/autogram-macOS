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

            Section("Existing Signatures") {
                signatureInspection
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

    private var selectedItem: PDFItem? {
        guard let selection = workspace.selection else { return workspace.items.first }
        return workspace.items.first { $0.id == selection }
    }

    @ViewBuilder
    private var signatureInspection: some View {
        if let selectedItem {
            switch selectedItem.inspection {
            case .pending:
                ProgressView("Inspecting signatures")
            case .failed:
                Label("Signature inspection failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .completed(let document) where document.signatures.isEmpty:
                Label("No signatures found", systemImage: "signature")
                    .foregroundStyle(.secondary)
            case .completed(let document):
                Label(signatureSummary(for: document.signatures), systemImage: aggregateValidationState(for: document.signatures).symbolName)
                    .foregroundStyle(aggregateValidationState(for: document.signatures).tint)

                ForEach(document.signatures) { signature in
                    SignatureDisclosureRow(signature: signature)
                }
            }
        } else {
            ContentUnavailableView("No document selected", systemImage: "doc")
        }
    }

    private func signatureSummary(for signatures: [ExistingPDFSignature]) -> String {
        "\(signatures.count) \(signatures.count == 1 ? "signature" : "signatures") · \(aggregateValidationState(for: signatures).label)"
    }

    private func aggregateValidationState(for signatures: [ExistingPDFSignature]) -> SignatureValidationState {
        if signatures.contains(where: { $0.validationState == .invalid }) {
            return .invalid
        }
        if signatures.contains(where: { $0.validationState == .indeterminate }) {
            return .indeterminate
        }
        return .valid
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

private struct SignatureDisclosureRow: View {
    let signature: ExistingPDFSignature

    var body: some View {
        DisclosureGroup {
            if let signingTime = signature.signingTime {
                LabeledContent("Signed", value: signingTime.formatted(date: .abbreviated, time: .shortened))
            }

            LabeledContent("Format", value: friendlyFormat)
            if signature.hasQualifiedTimestamp {
                Label("Qualified timestamp", systemImage: "clock.badge.checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Label("No qualified timestamp", systemImage: "clock.badge.xmark")
                    .foregroundStyle(.orange)
            }

            ForEach(signature.documents, id: \.self) { document in
                Label(document, systemImage: "doc")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: signature.validationState.symbolName)
                    .foregroundStyle(signature.validationState.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(signature.signerDisplayName ?? "Unknown signer")
                    Text(signature.validationState.label)
                        .font(.caption)
                        .foregroundStyle(signature.validationState.tint)
                }
            }
        }
    }

    private var friendlyFormat: String {
        switch signature.format {
        case "PAdES_BASELINE_B": "PAdES Baseline B"
        case "PAdES_BASELINE_T": "PAdES Baseline T"
        case "PAdES_BASELINE_LT": "PAdES Baseline LT"
        case "PAdES_BASELINE_LTA": "PAdES Baseline LTA"
        case let format?: format.replacingOccurrences(of: "_", with: " ")
        case nil: "PAdES"
        }
    }
}

private extension SignatureValidationState {
    var label: String {
        switch self {
        case .valid: "Valid"
        case .invalid: "Invalid"
        case .indeterminate: "Validation indeterminate"
        }
    }

    var symbolName: String {
        switch self {
        case .valid: "checkmark.seal"
        case .invalid: "xmark.seal"
        case .indeterminate: "questionmark.diamond"
        }
    }

    var tint: Color {
        switch self {
        case .valid: .green
        case .invalid: .red
        case .indeterminate: .orange
        }
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
