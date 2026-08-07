import SwiftUI

struct AutogramSettingsView: View {
    let workspace: WorkspaceModel
    @AppStorage("preferences.outputPolicy") private var outputPolicyRaw = OutputPolicy.signedSuffix.rawValue
    @AppStorage("preferences.destinationBehavior") private var destinationBehaviorRaw = DestinationBehavior.besideSource.rawValue
    @AppStorage("preferences.revealInFinderAfterSigning") private var revealInFinderAfterSigning = true
    private let quickActionInstaller = QuickActionInstaller()
    @State private var quickActionStatus = QuickActionInstaller().status
    @State private var hasLegacyCLIQuickAction = QuickActionInstaller().hasLegacyCLIWorkflow
    @State private var quickActionError: String?

    var body: some View {
        Form {
            Section("Output") {
                Picker("File name", selection: $outputPolicyRaw) {
                    Text("Add _signed suffix").tag(OutputPolicy.signedSuffix.rawValue)
                }
                Picker("Destination", selection: $destinationBehaviorRaw) {
                    Text("Beside source PDF").tag(DestinationBehavior.besideSource.rawValue)
                    Text("Ask each time").tag(DestinationBehavior.askEachTime.rawValue)
                }
                Toggle("Reveal signed PDF in Finder", isOn: $revealInFinderAfterSigning)
            }

            Section("Signing requirements") {
                LabeledContent("Profile", value: "PAdES Baseline T")
                LabeledContent("Timestamp", value: "Qualified timestamp required")
            }

            Section("Finder") {
                Text("Install a Quick Action to open one or more selected PDFs in Autogram from Finder.")
                HStack {
                    if quickActionStatus == .nativeInstalled {
                        Button("Remove Finder Quick Action", role: .destructive) {
                            updateQuickAction(quickActionInstaller.remove)
                        }
                    } else {
                        Button("Install Finder Quick Action") {
                            updateQuickAction(quickActionInstaller.install)
                        }
                    }
                    Spacer()
                    Text(quickActionStatus.finderStatusText)
                        .foregroundStyle(.secondary)
                }
                if hasLegacyCLIQuickAction {
                    Text("Legacy CLI Quick Action detected. It is a separate old action and will not be removed automatically.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                diagnostics
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 20, for: .scrollContent)
        .onAppear {
            quickActionStatus = quickActionInstaller.status
            hasLegacyCLIQuickAction = quickActionInstaller.hasLegacyCLIWorkflow
            Task { @MainActor in
                await workspace.refreshSigningEnvironment()
            }
        }
        .alert("Finder Quick Action", isPresented: Binding(
            get: { quickActionError != nil },
            set: { if !$0 { quickActionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(quickActionError ?? "")
        }
    }

    private func updateQuickAction(_ action: () throws -> Void) {
        do {
            try action()
            quickActionStatus = quickActionInstaller.status
            hasLegacyCLIQuickAction = quickActionInstaller.hasLegacyCLIWorkflow
        } catch {
            quickActionError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        if workspace.isLoadingSigningEnvironment {
            LabeledContent("Status", value: "Checking signing environment")
            LabeledContent("Autogram helper", value: "Checking")
            LabeledContent("ARM64 validation", value: "Checking")
            LabeledContent("Middleware", value: "Checking")
            LabeledContent("Protocol version", value: "Checking")
        } else if let error = workspace.credentialError {
            LabeledContent("Status", value: "Unavailable")
            LabeledContent("Autogram helper", value: "Unavailable")
            LabeledContent("ARM64 validation", value: "Unavailable")
            LabeledContent("Middleware", value: "Unavailable")
            LabeledContent("Protocol version", value: "Unavailable")
            Text(error)
                .foregroundStyle(.secondary)
        } else if let capabilities = workspace.signingEnvironment {
            LabeledContent("Status", value: "Ready")
            LabeledContent("Autogram helper", value: "Connected")
            LabeledContent(
                "ARM64 validation",
                value: workspace.availableDrivers.isEmpty ? "No middleware detected" : "Validated for detected middleware"
            )
            LabeledContent("Installed middleware", value: middlewareDescription)
            LabeledContent("Connected signing card", value: connectedCardDescription)
            LabeledContent("Protocol version", value: String(capabilities.protocolVersion))
            if secureStoreDetected {
                Text("I.CA SecureStore detected and ARM64 validated.")
                    .foregroundStyle(.secondary)
            } else {
                Text("I.CA SecureStore not detected.")
                    .foregroundStyle(.secondary)
                Link("Download I.CA SecureStore", destination: URL(string: "https://www.ica.cz/en/secure-store")!)
            }
        } else {
            LabeledContent("Status", value: "Unavailable")
            LabeledContent("Autogram helper", value: "Unavailable")
            LabeledContent("ARM64 validation", value: "Unavailable")
            LabeledContent("Middleware", value: "Unavailable")
            LabeledContent("Protocol version", value: "Unavailable")
        }
    }

    private var middlewareDescription: String {
        let names = workspace.availableDrivers.map(friendlyDriverName)
        return names.isEmpty ? "No middleware detected" : names.joined(separator: ", ")
    }

    private var connectedCardDescription: String {
        let names = workspace.connectedDrivers.map(friendlyDriverName)
        if !names.isEmpty {
            return names.joined(separator: ", ")
        }
        return workspace.tokenPresenceIsKnown ? "No connected signing card" : "Card presence unavailable"
    }

    private var secureStoreDetected: Bool {
        workspace.availableDrivers.contains { driver in
            driver.id.lowercased().contains("secure_store") ||
                driver.displayName.localizedCaseInsensitiveContains("securestore") ||
                driver.displayName.localizedCaseInsensitiveContains("secure store")
        }
    }

    private func friendlyDriverName(_ driver: SigningDriver) -> String {
        secureStoreIdentifier(driver) ? "I.CA SecureStore" : driver.displayName
    }

    private func secureStoreIdentifier(_ driver: SigningDriver) -> Bool {
        driver.id.lowercased().contains("secure_store") ||
            driver.displayName.localizedCaseInsensitiveContains("securestore") ||
            driver.displayName.localizedCaseInsensitiveContains("secure store")
    }
}

private extension QuickActionInstaller.Status {
    var finderStatusText: String {
        switch self {
        case .nativeInstalled:
            "Installed"
        case .legacyCLIInstalled:
            "Native action not installed"
        case .notInstalled:
            "Not installed"
        }
    }
}
