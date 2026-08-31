import SwiftUI
import AutogramKit
import AppKit

enum AIPromptPreset: String, CaseIterable, Identifiable {
    case legalDocuments = "Právne dokumenty"
    case conservativeReview = "Konzervatívna kontrola"
    case signaturesAndInitials = "Podpisy a parafy"
    case stampsAndEmbossedElements = "Pečiatky a reliéfne prvky"
    case customPrompt = "Vlastný prompt"

    var id: String { rawValue }

    var promptText: String? {
        switch self {
        case .legalDocuments:
            return LLMVisionParser.systemPrompt
        case .conservativeReview:
            return LLMVisionParser.systemPrompt
                + "\nBuď pri klasifikácii mimoriadne konzervatívny a prvok vynechaj pri akejkoľvek neistote."
        case .signaturesAndInitials:
            return LLMVisionParser.systemPrompt
                + "\nZameraj sa najmä na každý fyzicky viditeľný podpis alebo parafu."
        case .stampsAndEmbossedElements:
            return LLMVisionParser.systemPrompt
                + "\nZameraj sa najmä na každý fyzicky viditeľný výskyt pečiatky alebo reliéfneho prvku."
        case .customPrompt:
            return nil
        }
    }
}

struct SettingsView: View {
    @Bindable var settingsStore: AppSettingsStore
    @State private var newTSAURL = ""
    @State private var tsaTestStatus: String?
    @State private var isTestingTSA = false
    @State private var tsaToDelete: String?
    @State private var showTSADeleteConfirmation = false
    @State private var profileToDelete: UUID?
    @State private var showProfileDeleteConfirmation = false
    @State private var ezzkEvidenceCount = "1"
    @State private var ezzkEvidenceValidation: String?
    @State private var pendingEZZKEvidenceCount = 0
    @State private var finderQuickActionStatus: String?

    @State private var selectedPromptPreset: AIPromptPreset = .legalDocuments

    @State private var showEZZKEvidenceConfirmation = false
    var body: some View {
        TabView {
            settingsTabContent(aiTab)
            .tabItem { Label("AI Vision", systemImage: "brain.head.profile") }

            settingsTabContent(conversionTab)
            .tabItem { Label("Konverzia PDF/A", systemImage: "doc.badge.gearshape") }

            settingsTabContent(ezzkTab)
            .tabItem { Label("EZZK", systemImage: "number.square") }

            settingsTabContent(finderQuickActionTab)
            .tabItem { Label("Finder Quick Action", systemImage: "finder") }

            settingsTabContent(profilesTab)
            .tabItem { Label("Profily advokáta", systemImage: "person.crop.circle.badge.checkmark") }
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 840, idealHeight: 940)
        .confirmationDialog("Naozaj chcete odstrániť tento TSA server?",
                           isPresented: $showTSADeleteConfirmation,
                           titleVisibility: .visible) {
            Button("Odstrániť TSA server", role: .destructive) {
                if let server = tsaToDelete {
                    settingsStore.settings.customTSAServers.removeAll { $0 == server }
                    if settingsStore.settings.selectedTSAURL == server {
                        settingsStore.settings.selectedTSAURL = TimestampAuthority.legacyDefaultURL
                    }
                }
                tsaToDelete = nil
            }
            Button("Zrušiť", role: .cancel) { tsaToDelete = nil }
        } message: {
            Text("Server bude odstránený zo zoznamu vlastných TSA služieb.")
        }
        .confirmationDialog("Naozaj chcete odstrániť tento profil?",
                           isPresented: $showProfileDeleteConfirmation,
                           titleVisibility: .visible) {
            Button("Odstrániť profil", role: .destructive) {
                if let id = profileToDelete {
                    settingsStore.settings.profiles.removeAll { $0.id == id }
                    if settingsStore.settings.activeProfileID == id {
                        settingsStore.settings.activeProfileID = settingsStore.settings.profiles.first?.id
                    }
                }
                profileToDelete = nil
            }
            Button("Zrušiť", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("Profil a jeho údaje budú odstránené z tejto aplikácie.")
        }
        .confirmationDialog(
            "Vyžiadať evidenčné čísla z EZZK?",
            isPresented: $showEZZKEvidenceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Vyžiadať \(pendingEZZKEvidenceCount) čísel") {
                Task {
                    await settingsStore.ezzkSessionController.requestEvidenceNumbers(
                        count: pendingEZZKEvidenceCount)
                }
            }
            Button("Zrušiť", role: .cancel) {}
        } message: {
            Text("EZZK pridelí \(pendingEZZKEvidenceCount) nových evidenčných čísel. Pokračovať?")
        }
    }

    private func settingsTabContent<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: 960, alignment: .topLeading)
            .padding(.vertical, 18)
            .padding(.horizontal, 28)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }


    // MARK: - Tab 1: AI Vision
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Poskytovateľ AI Vision detekcie")
                    .font(.headline)

                VStack(spacing: 8) {
                    aiProviderRow(
                        mode: .omlxLocal,
                        title: "oMLX (Apple Silicon MLX)",
                        subtitle: "Lokálne MLX servovanie modelov Qwen2.5-VL / Llama-3.2-Vision (localhost:8000)",
                        icon: "apple.logo"
                    )

                    aiProviderRow(
                        mode: .ollamaLocal,
                        title: "Ollama (Local Vision)",
                        subtitle: "Lokálny Ollama server pre modely LLaVA / Llama-Vision (localhost:11434)",
                        icon: "laptopcomputer"
                    )

                    aiProviderRow(
                        mode: .builtInOnDevice,
                        title: "Interný režim (On-Device Vision)",
                        subtitle: "Základné počítačové videnie priamo na Macu bez externých serverov",
                        icon: "bolt.badge.checkmark"
                    )

                    aiProviderRow(
                        mode: .customAPIKey,
                        title: "Vlastný API kľúč (OpenAI / Claude / Gemini)",
                        subtitle: "Cloudové OpenAI-compatible API s bezpečným uložením kľúča v Kľúčenke",
                        icon: "key.fill"
                    )

                    aiProviderRow(
                        mode: .disabled,
                        title: "Vypnuté",
                        subtitle: "Využívať iba základné pravidlá bez asistencie AI",
                        icon: "xmark.circle"
                    )
                }

                Text("Vstavané on-device pravidlá bežia vždy. Klasifikačný prompt sa použije iba pre oMLX, Ollama a Custom API; zvolený AI režim dopĺňa detekciu bezpečnostných prvkov podľa § 37.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                aiReadinessRows
            }
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Label("Naposledy otvorené dokumenty", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Toggle(
                    "Pamätať naposledy otvorené dokumenty",
                    isOn: $settingsStore.settings.retainRecentDocuments)

                Text("Uloží najviac osem bezpečných bookmarkov pre rýchly návrat po reštarte. Obsah dokumentov sa do zoznamu neukladá.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 14, padding: 16)

            if settingsStore.settings.aiMode == .omlxLocal {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Konfigurácia oMLX (Apple Silicon)", systemImage: "apple.logo")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("API Endpoint")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                            TextField("http://localhost:8000/v1", text: $settingsStore.settings.omlxURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        GridRow {
                            Text("Vision Model")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("mlx-community/Qwen2.5-VL-7B-Instruct-4bit", text: $settingsStore.settings.omlxModel)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Text("oMLX beží na Apple Silicon s natívnou akceleráciou GPU/Neural Engine. Odporúčané modely: Qwen2.5-VL, Llama-3.2-11B-Vision-Instruct.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .glassCard(cornerRadius: 14, padding: 16)
            }

            if settingsStore.settings.aiMode == .ollamaLocal {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Konfigurácia Ollama", systemImage: "laptopcomputer")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Server URL")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                            TextField("http://localhost:11434", text: $settingsStore.settings.ollamaURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        GridRow {
                            Text("Model")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("llava / llama3.2-vision", text: $settingsStore.settings.ollamaModel)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Text("100 % offline spracovanie priamo na Macu cez lokálny Ollama server.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .glassCard(cornerRadius: 14, padding: 16)
            }

            if settingsStore.settings.aiMode == .customAPIKey {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Vlastný API kľúč", systemImage: "key.fill")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Base URL")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                            TextField("https://api.openai.com/v1", text: $settingsStore.settings.openAICompatibleBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        GridRow {
                            Text("Model")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            TextField("gpt-4o-mini", text: $settingsStore.settings.openAICompatibleModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        GridRow {
                            Text("API kľúč (Keychain)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            SecureField("sk-…", text: Binding(
                                get: { KeychainStore.load(account: "ai.apikey") ?? "" },
                                set: { newValue in
                                    if newValue.isEmpty {
                                        KeychainStore.delete(account: "ai.apikey")
                                    } else {
                                        _ = KeychainStore.save(secret: newValue, account: "ai.apikey")
                                    }
                                }))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Text("Kľúč sa ukladá výhradne do systémovej Kľúčenky tohto Macu.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .glassCard(cornerRadius: 14, padding: 16)
            }

            let promptEnabled = settingsStore.settings.aiMode.supportsPromptOverride
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Klasifikačný prompt pre LLM")
                        .font(.headline)
                    Spacer()
                    Button("Obnoviť predvolený") {
                        settingsStore.settings.aiPrompt = nil
                        selectedPromptPreset = .legalDocuments
                    }
                    .controlSize(.small)
                    .disabled(!promptEnabled)
                }

                Picker("Predvoľba promptu", selection: $selectedPromptPreset) {
                    ForEach(AIPromptPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!promptEnabled)
                .onChange(of: selectedPromptPreset) { _, preset in
                    if let promptText = preset.promptText {
                        settingsStore.settings.aiPrompt = promptText
                    }
                }

                TextEditor(text: Binding(
                    get: { settingsStore.settings.aiPrompt ?? "" },
                    set: { newValue in
                        selectedPromptPreset = .customPrompt
                        settingsStore.settings.aiPrompt =
                            newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil : newValue
                    }))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 100)
                    .padding(4)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .disabled(!promptEnabled)

                Text(promptEnabled
                     ? "Prázdne pole znamená schválený predvolený prompt. Prompt sa použije iba pre oMLX, Ollama a vlastné API."
                     : "Vstavaný detektor beží vždy. Prompt sa pre interný alebo vypnutý režim nepoužíva.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 14, padding: 16)
            .onAppear {
                let current = settingsStore.settings.aiPrompt
                selectedPromptPreset = AIPromptPreset.allCases.first {
                    $0.promptText == current
                } ?? (current == nil ? .legalDocuments : .customPrompt)
            }
        }
    }

    @ViewBuilder
    private var aiReadinessRows: some View {
        let mode = settingsStore.settings.aiMode
        VStack(alignment: .leading, spacing: 6) {
            Text("Pripravenosť zvolenej konfigurácie")
                .font(.caption.weight(.semibold))
            switch mode {
            case .omlxLocal:
                readinessRow("oMLX URL", value: settingsStore.settings.omlxURL,
                             isReady: validEndpoint(settingsStore.settings.omlxURL))
                readinessRow("oMLX model", value: settingsStore.settings.omlxModel,
                             isReady: !settingsStore.settings.omlxModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .ollamaLocal:
                readinessRow("Ollama URL", value: settingsStore.settings.ollamaURL,
                             isReady: validEndpoint(settingsStore.settings.ollamaURL))
                readinessRow("Ollama model", value: settingsStore.settings.ollamaModel,
                             isReady: !settingsStore.settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .customAPIKey:
                readinessRow("Custom API URL", value: settingsStore.settings.openAICompatibleBaseURL,
                             isReady: validEndpoint(settingsStore.settings.openAICompatibleBaseURL))
                readinessRow("Custom API model", value: settingsStore.settings.openAICompatibleModel,
                             isReady: !settingsStore.settings.openAICompatibleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                readinessRow("Custom API keychain key", value: KeychainStore.load(account: "ai.apikey") == nil ? "Chýba" : "Uložený",
                             isReady: !(KeychainStore.load(account: "ai.apikey") ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .builtInOnDevice, .disabled:
                Text("Vstavaný detektor beží vždy. Prompt sa v tomto režime nepoužíva.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func readinessRow(_ label: String, value: String, isReady: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isReady ? .green : .orange)
            Text(label)
                .font(.caption2.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func validEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    private func aiProviderRow(mode: AppSettings.AIMode, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = settingsStore.settings.aiMode == mode

        return Button {
            settingsStore.settings.aiMode = mode
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Vybraný" : "Nevybraný")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Tab 2: Konverzia PDF/A
    private var conversionTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spôsob konverzie do PDF/A")
                    .font(.headline)

                Picker("Režim PDF/A", selection: $settingsStore.settings.pdfaMode) {
                    ForEach(PDFAConversionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Vektorová konverzia zachováva textovú vrstvu; rasterizovaná garancia (200 dpi) vyrovná problematické skeny. Obe možnosti spĺňajú štandard PDF/A-2b.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 14) {
                Label("Časová pečiatka (RFC 3161 TSA)", systemImage: "clock.badge.checkmark")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Aktívna TSA")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)

                        Picker("Aktívna TSA", selection: $settingsStore.settings.selectedTSAURL) {
                            ForEach(settingsStore.settings.availableTSAServers) { server in
                                Text("\(server.name) (\(server.url))").tag(server.url)
                            }
                        }
                        .accessibilityLabel("Aktívna TSA")
                    }
                }

                if !settingsStore.settings.customTSAServers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vlastné TSA servery")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(settingsStore.settings.customTSAServers, id: \.self) { server in
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                Text(server)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    tsaToDelete = server
                                    showTSADeleteConfirmation = true
                                } label: {
                                    Label("Odstrániť TSA server", systemImage: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("https://vlastna-tsa.sk/tsp", text: $newTSAURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Pridať TSA") {
                        let trimmed = newTSAURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, !settingsStore.settings.customTSAServers.contains(trimmed) else { return }
                        settingsStore.settings.customTSAServers.append(trimmed)
                        newTSAURL = ""
                    }
                    .disabled(newTSAURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack(spacing: 10) {
                    Button {
                        testTSAConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingTSA {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.horizontal.circle")
                            }
                            Text("Otestovať spojenie")
                        }
                    }
                    .disabled(isTestingTSA || settingsStore.settings.selectedTSAURL.isEmpty)

                    if let status = tsaTestStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.hasPrefix("✓") ? Color.green : Color.red)
                    }
                }
            }
            .glassCard(cornerRadius: 14, padding: 16)
        }
    }

    private func testTSAConnection() {
        isTestingTSA = true
        tsaTestStatus = nil
        let urlString = settingsStore.settings.selectedTSAURL
        Task {
            defer { isTestingTSA = false }
            guard let url = URL(string: urlString), url.scheme != nil else {
                tsaTestStatus = "✗ Neplatná adresa TSA."
                return
            }
            do {
                let reply = try await RFC3161TimestampClient()
                    .requestToken(for: Data("autogram-tsa-connectivity-test".utf8), tsaURL: url)
                if let time = reply.genTime {
                    tsaTestStatus = "✓ Pečiatka prijatá (\(AttestationClauseGenerator.isoFormatter.string(from: time)))"
                } else {
                    tsaTestStatus = "✓ Token prijatý (\(reply.token.count) B)."
                }
            } catch {
                tsaTestStatus = "✗ \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Tab 3: EZZK
    private var ezzkTab: some View {
        let controller = settingsStore.ezzkSessionController

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ezzkEnvironmentCard(controller)
                ezzkSessionCard(controller)
            }

            HStack(alignment: .top, spacing: 14) {
                ezzkEvidenceCard(controller)
                ezzkSubmissionCard
            }

            ezzkMigrationCard
        }
        .frame(maxWidth: 960, alignment: .topLeading)
    }

    private func ezzkEnvironmentCard(_ controller: EZZKSessionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Prostredie EZZK", systemImage: "server.rack")
                .font(.headline)

            Picker("Prostredie", selection: Binding(
                get: { controller.selectedEnvironment },
                set: { controller.selectedEnvironment = $0 }
            )) {
                Text(controller.isDemoMode ? "Demo (lokálne)" : "Sandbox")
                    .tag(EZZKEnvironment.sandbox)
                Text("Produkcia (uzavreté)")
                    .tag(EZZKEnvironment.production)
                    .disabled(!controller.canSelectProduction)
            }
            .pickerStyle(.segmented)
            .disabled(!controller.canChangeEnvironment)

            Text(controller.isDemoMode
                 ? "Demo používa iba lokálnu simuláciu."
                 : "Sandbox je testovacie prostredie. Produkcia sa sprístupní až po potvrdení autorizačnej brány.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().opacity(0.5)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ezzkEndpointRow(
                    label: "Portál",
                    value: controller.isDemoMode
                        ? "Nepoužíva sa v demo režime"
                        : controller.selectedEnvironment.portalBaseURL.absoluteString)
                ezzkEndpointRow(
                    label: "REST API",
                    value: controller.isDemoMode
                        ? "Nepoužíva sa v demo režime"
                        : controller.selectedEnvironment.apiBaseURL.absoluteString)
                ezzkEndpointRow(
                    label: "Authority",
                    value: controller.isDemoMode ? "Demo lokálne" : controller.selectedEnvironment.authorityID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private func ezzkEndpointRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func ezzkSessionCard(_ controller: EZZKSessionController) -> some View {
        let presentation = controller.isDemoMode
            ? (title: "Demo lokálne", symbol: "theatermasks", color: Color.orange)
            : ezzkStatePresentation(controller.state)

        return VStack(alignment: .leading, spacing: 10) {
            Label("Prístup k EZZK", systemImage: "person.badge.key")
                .font(.headline)

            Label(presentation.title, systemImage: presentation.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(presentation.color)

            Text("Prihlásenie prebehne v zabezpečenom okne EZZK. Login ani heslo sa nezadávajú do nastavení Autogramu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Kontrola")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.lastConnectivityCheck?.formatted(date: .abbreviated, time: .shortened)
                         ?? "Zatiaľ neoverené")
                        .font(.caption)
                }
                GridRow {
                    Text("Čísla")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(controller.availableEvidenceNumberCount.map(String.init) ?? "Zatiaľ neoverené")
                        .font(.caption.monospacedDigit())
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await controller.login() }
                } label: {
                    Label("Prihlásiť cez EZZK", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!controller.canStartLogin)

                Button {
                    Task { await controller.refresh() }
                } label: {
                    Label(
                        controller.hasActiveSession ? "Obnoviť reláciu" : "Prihlásiť / obnoviť",
                        systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!controller.canRefresh)
                if case .authenticating = controller.state {
                    Button("Zrušiť čakanie", role: .cancel) {
                        controller.cancelLogin()
                    }
                    .controlSize(.small)
                }

                if controller.hasActiveSession {
                    Button("Odhlásiť", role: .destructive) {
                        controller.logout()
                    }
                    .controlSize(.small)
                }
            }

            if !controller.hasAuthenticationCallbackConfiguration {
                Label(
                    "OAuth callback nie je nakonfigurovaný. Vyžaduje sa autogram://ezzk/callback.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !controller.hasNativeCallbackConfiguration {
                Label(
                    "Používa sa zabezpečené webové presmerovanie portálu EZZK.",
                    systemImage: "safari")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !controller.isDemoMode {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Vyžaduje sa nastavenie správcom EZZK",
                        systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(
                        "Správca musí povoliť callback autogram://ezzk/callback pre OAuth klienta login-app. Toto sa nedá nastaviť v Autograme.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .authenticating = controller.state {
                Label(
                    "Autogram čaká na návrat z prihlasovacieho okna EZZK. Ak sa zobrazila chyba redirect_uri, zvoľte Zrušiť čakanie.",
                    systemImage: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .failed(let message) = controller.state {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private func ezzkEvidenceCard(_ controller: EZZKSessionController) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Evidenčné čísla", systemImage: "number.square.fill")
                .font(.headline)

            Text("Vyžiadajte čísla až po úspešnom prihlásení do EZZK.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Počet", text: $ezzkEvidenceCount)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onChange(of: ezzkEvidenceCount) { _, _ in
                        ezzkEvidenceValidation = nil
                    }

                Button("Vyžiadať čísla") {
                    requestEZZKEvidenceNumbers()
                }
                .controlSize(.small)
                .disabled(!controller.hasActiveSession || controller.state == .authenticating)
            }

            if let validation = ezzkEvidenceValidation {
                Text(validation)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                Text("Každá požiadavka vyžaduje výslovné potvrdenie.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private var ezzkSubmissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Odoslanie podpísaného ASiC-E", systemImage: "arrow.up.doc")
                .font(.headline)

            Label("Čaká na overený ASiC-E workflow", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Odoslanie zostáva vypnuté, kým workflow nevytvorí a neoverí samostatný podpísaný ASiC-E súbor.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private var ezzkMigrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kontaktné údaje pre migráciu", systemImage: "archivebox")
                .font(.headline)

            Text("Tieto údaje slúžia iba na migráciu. Nepoužívajú sa na OAuth prihlasovanie.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Notifikačný e-mail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("advokat@kancelaria.sk", text: $settingsStore.settings.ezzkNotificationEmail)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Adresa eDesk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("elektronická schránka", text: $settingsStore.settings.ezzkEdeskAddress)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, padding: 16)
    }

    private func requestEZZKEvidenceNumbers() {
        let value = ezzkEvidenceCount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(value), count > 0 else {
            ezzkEvidenceValidation = "Zadajte kladný počet evidenčných čísel."
            return
        }

        ezzkEvidenceValidation = nil
        pendingEZZKEvidenceCount = count
        showEZZKEvidenceConfirmation = true
    }

    private func ezzkStatePresentation(
        _ state: EZZKSessionController.State
    ) -> (title: String, symbol: String, color: Color) {
        switch state {
        case .signedOut:
            ("Odhlásené", "person.crop.circle", .secondary)
        case .authenticating:
            ("Overuje sa", "arrow.triangle.2.circlepath", .orange)
        case .authenticated:
            ("Prihlásené", "checkmark.seal.fill", .green)
        case .expired:
            ("Relácia vypršala", "clock.badge.exclamationmark", .orange)
        case .failed:
            ("Chyba relácie", "exclamationmark.triangle.fill", .red)
        }
    }
    // MARK: - Tab 4: Finder Quick Action
    private var finderQuickActionTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Podpisovanie z Findera", systemImage: "finder")
                    .font(.headline)

                Text(
                    "Quick Action je samostatné Automator workflow. Spúšťa starý Autogram CLI helper v pozadí, takže hlavné okno aplikácie sa pri podpise neotvorí."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Výstupom je podpísané PDF vo formáte PAdES Baseline T s kvalifikovanou časovou pečiatkou. Workflow zobrazí iba výber ovládača, certifikátu a PIN/BOK dialóg."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(spacing: 10) {
                    Button("Nainštalovať Quick Action") {
                        finderQuickActionStatus = FinderQuickActionService.installQuickAction()
                            ? "Quick Action bola nainštalovaná do služieb Findera."
                            : "Quick Action sa nepodarilo nainštalovať."
                    }
                    .controlSize(.small)

                    Button("Obnoviť služby") {
                        finderQuickActionStatus = FinderQuickActionService.refreshServicesCache()
                            ? "Registrácia služieb bola odoslaná systému macOS."
                            : "Registráciu služieb sa nepodarilo obnoviť."
                    }
                    .controlSize(.small)

                    if let finderQuickActionStatus {
                        Text(finderQuickActionStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Label("Aktivácia vo Findere", systemImage: "questionmark.circle")
                    .font(.headline)

                Text(
                    """
                    1. Nainštalujte Autogram do priečinka /Applications.
                    2. Kliknite na Nainštalovať Quick Action vyššie. Autogram ju uloží do ~/Library/Services.
                    3. Vo Findere otvorte Quick Actions → Customize... a zaškrtnite \(FinderQuickActionService.menuTitle).
                    4. Vo Findere označte jeden alebo viac PDF súborov.
                    5. Kliknite pravým tlačidlom myši a zvoľte Quick Actions → \(FinderQuickActionService.menuTitle).
                    6. Autogram vyberie dostupný podpisový certifikát, pričom mandátny certifikát uprednostní. PIN alebo BOK zadáte iba počas podpisu.
                    """
                )
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Ak položka nie je ani v Customize..., ukončite a znova spustite Autogram, kliknite na Obnoviť služby a reštartujte Finder. Workflow prijíma iba PDF súbory, nie ASiC-E kontajnery. PIN sa nikdy neukladá do nastavení."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14, padding: 16)
        }
    }

    // MARK: - Tab 5: Profily advokáta
    private var profilesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Správa profilov advokáta")
                    .font(.headline)

                Spacer()

                Button {
                    let profile = AdvocateProfile()
                    settingsStore.settings.profiles.append(profile)
                    settingsStore.settings.activeProfileID = profile.id
                } label: {
                    Label("Nový profil", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if settingsStore.settings.profiles.isEmpty {
                Text("Zatiaľ nemáte vytvorený profil. Kliknite na 'Nový profil' pre pridanie údajov advokáta.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .glassCard(cornerRadius: 14)
            } else {
                ForEach($settingsStore.settings.profiles) { $profile in
                    let isActive = settingsStore.settings.activeProfileID == profile.id

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(profile.displayName.isEmpty ? "Nový profil" : profile.displayName)
                                .font(.headline)

                            if isActive {
                                Text("AKTÍVNY")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.green)
                            }

                            Spacer()

                            if !isActive {
                                Button("Nastaviť ako aktívny") {
                                    settingsStore.settings.activeProfileID = profile.id
                                }
                                .controlSize(.small)
                            }

                            if settingsStore.settings.profiles.count > 1 {
                                Button(role: .destructive) {
                                    profileToDelete = profile.id
                                    showProfileDeleteConfirmation = true
                                } label: {
                                    Label("Odstrániť profil", systemImage: "trash")
                                }
                                .controlSize(.small)
                            }
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("Meno a priezvisko")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 160, alignment: .leading)
                                TextField("JUDr. Meno Priezvisko", text: $profile.fullName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Funkcia")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("advokát", text: $profile.position)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Evidenčné číslo SAK")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("1234", text: $profile.registrationNumber)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("IČO kancelárie")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("IČO", text: $profile.ico)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Názov kancelárie")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("Advokátska kancelária…", text: $profile.officeName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Adresa kancelárie")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                TextField("Ulica, PSČ a mesto", text: $profile.officeAddress)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Toggle("Právnická osoba (kancelária)", isOn: $profile.isLegalEntity)
                            .font(.callout)
                            .toggleStyle(.switch)
                    }
                    .glassCard(cornerRadius: 14, padding: 16)
                }
            }
        }
    }
}

extension AdvocateProfile {
    var displayName: String {
        fullName.isEmpty ? officeName : fullName
    }
}
