import SwiftUI
import AutogramKit
import AppKit

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
    @State private var showEZZKEvidenceConfirmation = false
    var body: some View {
        TabView {
            settingsTabContent(aiTab)
            .tabItem { Label("AI Vision", systemImage: "brain.head.profile") }

            settingsTabContent(conversionTab)
            .tabItem { Label("Konverzia PDF/A", systemImage: "doc.badge.gearshape") }

            settingsTabContent(ezzkTab)
            .tabItem { Label("EZZK", systemImage: "number.square") }

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

                Text("Vstavané on-device pravidlá bežia vždy. Zvolený AI režim dopĺňa detekciu úradných pečiatok a vlastnoručných podpisov podľa § 37.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
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

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Klasifikačný prompt pre LLM")
                        .font(.headline)
                    Spacer()
                    Button("Obnoviť predvolený") {
                        settingsStore.settings.aiPrompt = nil
                    }
                    .controlSize(.small)
                }

                TextEditor(text: Binding(
                    get: { settingsStore.settings.aiPrompt ?? "" },
                    set: { newValue in
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

                Text("Prázdne pole znamená predvolený prompt pre § 37 (pečiatky, vlastnoručné podpisy, reliéfne pečate, parafy).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 14, padding: 16)
        }
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

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Centrálna evidencia záznamov o konverzii (IS EZZK)", systemImage: "number.square")
                    .font(.headline)

                Text("EZZK používa pevne určené OAuth a REST identity. Nastavenia IČO, používateľského mena a hesla nie sú prihlasovacími údajmi pre OAuth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Prostredie", selection: Binding(
                        get: { controller.selectedEnvironment },
                        set: { controller.selectedEnvironment = $0 }
                    )) {
                        Text("Sandbox").tag(EZZKEnvironment.sandbox)
                        Text("Produkcia (uzavreté)")
                            .tag(EZZKEnvironment.production)
                            .disabled(!controller.canSelectProduction)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!controller.canChangeEnvironment)

                    Text("Sandbox je predvolené prostredie. Produkčné prostredie zostáva deaktivované, kým nie je otvorená autorizačná brána.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Portál")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 180, alignment: .leading)
                        Text(controller.selectedEnvironment.portalBaseURL.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }

                    GridRow {
                        Text("REST API")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(controller.selectedEnvironment.apiBaseURL.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }

                    GridRow {
                        Text("Identita autority")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(controller.selectedEnvironment.authorityID)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 14) {
                Label("Relácia EZZK", systemImage: "person.badge.key")
                    .font(.headline)

                let statePresentation = ezzkStatePresentation(controller.state)
                Label(statePresentation.title, systemImage: statePresentation.symbol)
                    .foregroundStyle(statePresentation.color)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Posledná kontrola spojenia")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 180, alignment: .leading)
                        Text(controller.lastConnectivityCheck.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "Zatiaľ neoverené")
                            .font(.callout)
                    }

                    GridRow {
                        Text("Dostupné evidenčné čísla")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(controller.availableEvidenceNumberCount.map(String.init) ?? "Zatiaľ neoverené")
                            .font(.callout.monospacedDigit())
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await controller.login() }
                    } label: {
                        Label("Prihlásiť cez EZZK", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canStartLogin)

                    Button {
                        Task { await controller.refresh() }
                    } label: {
                        Label("Obnoviť session", systemImage: "arrow.clockwise")
                    }
                    .disabled(!controller.canRefresh)

                    Button("Odhlásiť", role: .destructive) {
                        controller.logout()
                    }
                    .disabled(!controller.hasActiveSession)
                }

                if !controller.hasNativeCallbackConfiguration {
                    Label(
                        "Prihlásenie je vypnuté. Vyžaduje sa konfigurácia operátora EZZK s natívnym callbackom.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if case .failed(let message) = controller.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 14) {
                Label("Evidenčné čísla", systemImage: "number.square.fill")
                    .font(.headline)

                HStack(spacing: 10) {
                    TextField("Počet", text: $ezzkEvidenceCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: ezzkEvidenceCount) { _, _ in
                            ezzkEvidenceValidation = nil
                        }

                    Button("Vyžiadať čísla") {
                        requestEZZKEvidenceNumbers()
                    }
                    .disabled(!controller.hasActiveSession || controller.state == .authenticating)
                }

                if let validation = ezzkEvidenceValidation {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Požiadavka sa odošle až po výslovnom potvrdení. Pri chybe sa lokálne evidenčné záznamy nemenia.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 12) {
                Label("Odoslanie podpísaného ASiC-E", systemImage: "arrow.up.doc")
                    .font(.headline)

                Button("Odoslať podpísaný ASiC-E") {}
                    .disabled(true)

                Text("Odoslanie je vypnuté. Aktuálny workflow neposkytuje overený podpísaný ASiC-E súbor a potrebnú EZZK capability. Metadáta ConversionRecordEnvelope sa neposielajú ako náhrada súboru.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Label("Kontaktné údaje pre migráciu", systemImage: "archivebox")
                    .font(.headline)

                Text("Staršie IČO, používateľské meno a heslo zostávajú iba ako migračné údaje. Nepoužívajú sa na OAuth autentifikáciu ani na zostavenie sandboxovej alebo produkčnej služby.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Notifikačný e-mail")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 180, alignment: .leading)
                        TextField("advokat@kancelaria.sk", text: $settingsStore.settings.ezzkNotificationEmail)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text("Adresa eDesk")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("elektronická schránka", text: $settingsStore.settings.ezzkEdeskAddress)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .glassCard(cornerRadius: 14, padding: 16)
        }
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

    // MARK: - Tab 4: Profily advokáta
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
