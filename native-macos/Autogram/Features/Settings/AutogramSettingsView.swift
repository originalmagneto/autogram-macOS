import SwiftUI

struct AutogramSettingsView: View {
    let workspace: WorkspaceModel
    @AppStorage("preferences.outputPolicy") private var outputPolicyRaw = OutputPolicy.signedSuffix.rawValue
    @AppStorage("preferences.destinationBehavior") private var destinationBehaviorRaw = DestinationBehavior.besideSource.rawValue
    @AppStorage("preferences.revealInFinderAfterSigning") private var revealInFinderAfterSigning = true
    private let quickActionInstaller = QuickActionInstaller()
    private let timestampSourceStore = TimestampSourcePreferencesStore()
    @State private var quickActionStatus = QuickActionInstaller().status
    @State private var hasLegacyCLIQuickAction = QuickActionInstaller().hasLegacyCLIWorkflow
    @State private var quickActionError: String?
    @State private var defaultChangePIN = ""
    @State private var isDefaultChangePINPresented = false
    @State private var isDefaultCertificatePickerPresented = false
    @State private var tokenChangingDefault: RememberedSigningToken?
    @State private var timestampConfiguration = TimestampSourcePreferencesStore().load()
    @State private var timestampSecret = ""
    @State private var timestampSourceError: String?

    var body: some View {
        Form {
            Section("Output") {
                Picker("File name", selection: $outputPolicyRaw) {
                    Text("Add _signed suffix").tag(OutputPolicy.signedSuffix.rawValue)
                }
                Picker("Destination", selection: $destinationBehaviorRaw) {
                    Text("Beside source file").tag(DestinationBehavior.besideSource.rawValue)
                    Text("Ask each time").tag(DestinationBehavior.askEachTime.rawValue)
                }
                Toggle("Reveal signed file in Finder", isOn: $revealInFinderAfterSigning)
            }

            Section("Signing requirements") {
                LabeledContent("Formats", value: "PAdES or ASiC-E with XAdES")
                LabeledContent("Level", value: "Baseline T")
                LabeledContent("Timestamp", value: "Qualified timestamp required")
            }

            Section("Qualified timestamp source") {
                Picker("Timestamp Source", selection: Binding(
                    get: { timestampConfiguration.source },
                    set: { source in
                        timestampConfiguration.source = source
                        if source != .custom {
                            saveTimestampConfiguration()
                        }
                    }
                )) {
                    ForEach(TimestampSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }

                if timestampConfiguration.source == .custom {
                    TextField("Provider name", text: customProvider.displayName)
                    TextEditor(text: customProviderURLs)
                        .font(.body)
                        .frame(minHeight: 72)
                        .overlay(alignment: .topLeading) {
                            if customProviderURLs.wrappedValue.isEmpty {
                                Text("One timestamp URL per line, in fallback order")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Picker("Authentication", selection: customProviderAuthenticationKind) {
                        Text("None").tag(TimestampAuthenticationKind.none)
                        Text("Basic").tag(TimestampAuthenticationKind.basic)
                        Text("Bearer token").tag(TimestampAuthenticationKind.bearer)
                    }
                    if customProviderAuthenticationKind.wrappedValue == .basic {
                        TextField("Username", text: customProviderUsername)
                    }
                    if customProviderAuthenticationKind.wrappedValue != .none {
                        SecureField(customProviderAuthenticationKind.wrappedValue == .basic ? "Password" : "Bearer token",
                                    text: $timestampSecret)
                    }
                    HStack {
                        Button("Save Custom Provider") {
                            saveTimestampConfiguration()
                        }
                        if customProviderAuthenticationKind.wrappedValue != .none {
                            Button("Remove Credential", role: .destructive) {
                                removeTimestampCredential()
                            }
                        }
                    }
                    if let timestampSourceError {
                        Text(timestampSourceError)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Remembered signing cards") {
                signingCardControls
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
            timestampConfiguration = timestampSourceStore.load()
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
        .sheet(isPresented: $isDefaultChangePINPresented) {
            PINSheet(
                pin: $defaultChangePIN,
                title: "Unlock signing card",
                submitTitle: "Continue"
            ) { submission in
                guard let token = tokenChangingDefault else { return }
                Task {
                    let resolution = await workspace.resolveCertificatesForDefaultChange(
                        using: submission,
                        expectedTokenKey: token.tokenKey
                    )
                    isDefaultCertificatePickerPresented = resolution == .certificateSelectionRequired
                }
            } onCancel: {
                workspace.cancelCredentialFlow()
            }
        }
        .sheet(isPresented: $isDefaultCertificatePickerPresented, onDismiss: {
            workspace.cancelCredentialFlow()
            tokenChangingDefault = nil
        }) {
            CertificatePicker(
                certificates: workspace.discoveredCertificates,
                showsRememberAsDefaultToggle: false
            ) { certificate, _ in
                workspace.saveDefault(for: certificate)
                isDefaultCertificatePickerPresented = false
            } onCancel: {
                isDefaultCertificatePickerPresented = false
                workspace.cancelCredentialFlow()
            }
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
    private var signingCardControls: some View {
        if workspace.selectableDrivers.count > 1 {
            Picker("Signing card", selection: Binding(
                get: { workspace.selectedDriverID },
                set: { workspace.selectDriver(id: $0) }
            )) {
                Text("Choose a signing card").tag(Optional<String>.none)
                ForEach(workspace.selectableDrivers) { driver in
                    Text(driver.displayName).tag(Optional(driver.id))
                }
            }
        } else if let driver = workspace.selectableDrivers.first {
            LabeledContent("Signing card", value: driver.displayName)
        }

        if workspace.rememberedTokens.isEmpty {
            Text("Signing cards are remembered after you unlock them.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(workspace.rememberedTokens) { token in
                VStack(alignment: .leading, spacing: 8) {
                    Text(token.providerName)
                    Text(defaultDetail(for: token))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Change Default") {
                            tokenChangingDefault = token
                            isDefaultChangePINPresented = true
                        }
                        Button("Clear Default") {
                            workspace.clearDefault(for: token.tokenKey)
                        }
                        .disabled(token.certificateDefault == nil)
                        Button("Forget Token", role: .destructive) {
                            workspace.forgetToken(for: token.tokenKey)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func defaultDetail(for token: RememberedSigningToken) -> String {
        guard let certificateDefault = token.certificateDefault else {
            return "No default certificate"
        }
        return "Default: \(certificateDefault.commonName), \(certificateDefault.issuer), expires \(certificateDefault.validUntil.formatted(date: .abbreviated, time: .omitted))"
    }

    private var customProvider: Binding<CustomTimestampProviderConfiguration> {
        Binding(
            get: { timestampConfiguration.customProvider ?? CustomTimestampProviderConfiguration() },
            set: { timestampConfiguration.customProvider = $0 }
        )
    }

    private var customProviderURLs: Binding<String> {
        Binding(
            get: { customProvider.wrappedValue.urls.joined(separator: "\n") },
            set: { value in
                var provider = customProvider.wrappedValue
                provider.urls = value.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                customProvider.wrappedValue = provider
            }
        )
    }

    private var customProviderAuthenticationKind: Binding<TimestampAuthenticationKind> {
        Binding(
            get: { customProvider.wrappedValue.authentication.kind },
            set: { value in
                var provider = customProvider.wrappedValue
                provider.authentication.kind = value
                if value != .basic {
                    provider.authentication.username = nil
                }
                customProvider.wrappedValue = provider
            }
        )
    }

    private var customProviderUsername: Binding<String> {
        Binding(
            get: { customProvider.wrappedValue.authentication.username ?? "" },
            set: { value in
                var provider = customProvider.wrappedValue
                provider.authentication.username = value
                customProvider.wrappedValue = provider
            }
        )
    }

    private func saveTimestampConfiguration() {
        if timestampConfiguration.source == .custom {
            let provider = customProvider.wrappedValue
            guard !provider.urls.isEmpty else {
                timestampSourceError = "Add at least one timestamp URL."
                return
            }
            if provider.authentication.kind == .basic,
               (provider.authentication.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                timestampSourceError = "Add a Basic authentication username."
                return
            }
            if provider.authentication.kind != .none, timestampSecret.isEmpty {
                do {
                    if try timestampSourceStore.credential(for: provider) == nil {
                        timestampSourceError = "Add a timestamp credential."
                        return
                    }
                } catch {
                    timestampSourceError = "The timestamp credential could not be read from Keychain."
                    return
                }
            }
            do {
                if !timestampSecret.isEmpty {
                    try timestampSourceStore.replaceCredential(Secret(timestampSecret), for: provider)
                    timestampSecret = ""
                }
            } catch {
                timestampSourceError = "The timestamp credential could not be saved in Keychain."
                return
            }
        }
        timestampSourceStore.save(timestampConfiguration)
        timestampSourceError = nil
    }

    private func removeTimestampCredential() {
        do {
            try timestampSourceStore.replaceCredential(nil, for: customProvider.wrappedValue)
            timestampSecret = ""
            timestampSourceError = nil
        } catch {
            timestampSourceError = "The timestamp credential could not be removed from Keychain."
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
