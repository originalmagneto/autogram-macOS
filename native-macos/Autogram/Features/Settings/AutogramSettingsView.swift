import SwiftUI

struct AutogramSettingsView: View {
    @AppStorage("preferences.driverID") private var driverID = ""
    @AppStorage("preferences.certificateSerial") private var certificateSerial = ""
    @AppStorage("preferences.outputPolicy") private var outputPolicyRaw = OutputPolicy.signedSuffix.rawValue
    @AppStorage("preferences.destinationBehavior") private var destinationBehaviorRaw = DestinationBehavior.besideSource.rawValue
    @AppStorage("preferences.revealInFinderAfterSigning") private var revealInFinderAfterSigning = true
    private let quickActionInstaller = QuickActionInstaller()
    @State private var quickActionInstalled = QuickActionInstaller().isInstalled
    @State private var quickActionError: String?

    var body: some View {
        Form {
            Section("Signing") {
                TextField("Preferred driver ID", text: $driverID)
                TextField("Preferred certificate serial", text: $certificateSerial)
                    .privacySensitive()
            }

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
                    if quickActionInstalled {
                        Button("Remove Finder Quick Action", role: .destructive) {
                            updateQuickAction(quickActionInstaller.remove)
                        }
                    } else {
                        Button("Install Finder Quick Action") {
                            updateQuickAction(quickActionInstaller.install)
                        }
                    }
                    Spacer()
                    Text(quickActionInstalled ? "Installed" : "Not installed")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                LabeledContent("Autogram helper", value: "Not connected")
                LabeledContent("ARM64 validation", value: "Not connected")
                LabeledContent("Middleware", value: "Not connected")
                LabeledContent("Protocol version", value: AppIdentity.protocolVersion)
                LabeledContent(
                    "Status",
                    value: LocalizedMessage.resolve(
                        messageKey: "diagnostic.status.redacted",
                        fallback: "Redacted diagnostics only"
                    )
                )
                Text(LocalizedMessage.resolve(
                    messageKey: "driver.ica.requirement",
                    fallback: "I.CA SecureStore 8.3.1 or newer is required."
                ))
                Link("Download I.CA SecureStore", destination: URL(string: "https://www.ica.cz/en/secure-store")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 20, for: .scrollContent)
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
            quickActionInstalled = quickActionInstaller.isInstalled
        } catch {
            quickActionError = error.localizedDescription
        }
    }
}
