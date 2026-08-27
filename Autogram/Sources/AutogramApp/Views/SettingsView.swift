import SwiftUI
import AutogramKit
import AppKit

struct SettingsView: View {
    @Bindable var settingsStore: AppSettingsStore
    @State private var newTSAURL = ""
    @State private var tsaTestStatus: String?
    @State private var isTestingTSA = false
    @State private var ezzkSavedHint = false

    var body: some View {
        TabView {
            ScrollView {
                aiTab
                    .frame(maxWidth: 680)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
            }
            .tabItem { Label("AI Vision", systemImage: "brain.head.profile") }

            ScrollView {
                conversionTab
                    .frame(maxWidth: 680)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
            }
            .tabItem { Label("Konverzia PDF/A", systemImage: "doc.badge.gearshape") }

            ScrollView {
                ezzkTab
                    .frame(maxWidth: 680)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
            }
            .tabItem { Label("EZZK", systemImage: "number.square") }

            ScrollView {
                profilesTab
                    .frame(maxWidth: 680)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
            }
            .tabItem { Label("Profily advokáta", systemImage: "person.crop.circle.badge.checkmark") }
        }
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
            .liquidGlass(cornerRadius: 14, padding: 16)

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
                .liquidGlass(cornerRadius: 14, padding: 16)
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
                .liquidGlass(cornerRadius: 14, padding: 16)
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
                .liquidGlass(cornerRadius: 14, padding: 16)
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
            .liquidGlass(cornerRadius: 14, padding: 16)
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
    }

    // MARK: - Tab 2: Konverzia PDF/A
    private var conversionTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spôsob konverzie do PDF/A")
                    .font(.headline)

                Picker("", selection: $settingsStore.settings.pdfaMode) {
                    ForEach(PDFAConversionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Vektorová konverzia zachováva textovú vrstvu; rasterizovaná garancia (300 dpi) vyrovná problematické skeny. Obe možnosti spĺňajú štandard PDF/A-2b.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .liquidGlass(cornerRadius: 14, padding: 16)

            VStack(alignment: .leading, spacing: 14) {
                Label("Časová pečiatka (RFC 3161 TSA)", systemImage: "clock.badge.checkmark")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Aktívna TSA")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)

                        Picker("", selection: $settingsStore.settings.selectedTSAURL) {
                            ForEach(settingsStore.settings.availableTSAServers) { server in
                                Text("\(server.name) (\(server.url))").tag(server.url)
                            }
                        }
                        .labelsHidden()
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
                                    settingsStore.settings.customTSAServers.removeAll { $0 == server }
                                    if settingsStore.settings.selectedTSAURL == server {
                                        settingsStore.settings.selectedTSAURL = TimestampAuthority.legacyDefaultURL
                                    }
                                } label: {
                                    Image(systemName: "trash")
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
            .liquidGlass(cornerRadius: 14, padding: 16)
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Centrálna evidencia záznamov o konverzii (IS EZZK)", systemImage: "number.square")
                    .font(.headline)

                Text("Údaje z registrácie na portáli ezzk.iomo.sk. Bez vyplnených údajov beží evidencia v lokálnom DEMO režime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("IČO kancelárie")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 170, alignment: .leading)
                        TextField("IČO", text: $settingsStore.settings.ezzkICO)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text("Prihlasovacie meno")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("username", text: $settingsStore.settings.ezzkUsername)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text("Heslo (Keychain)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        SecureField("heslo", text: $settingsStore.ezzkPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        Text("Notifikačný e-mail")
                            .font(.callout)
                            .foregroundStyle(.secondary)
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

                HStack {
                    Button {
                        settingsStore.saveEZZKPassword()
                        ezzkSavedHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            ezzkSavedHint = false
                        }
                    } label: {
                        Label("Uložiť prístupy do Kľúčenky", systemImage: "lock.shield")
                    }
                    .buttonStyle(.borderedProminent)

                    if ezzkSavedHint {
                        Text("✓ Uložené")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 4)
            }
            .liquidGlass(cornerRadius: 14, padding: 16)
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
                    .liquidGlass(cornerRadius: 14)
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
                                    settingsStore.settings.profiles.removeAll { $0.id == profile.id }
                                    if settingsStore.settings.activeProfileID == profile.id {
                                        settingsStore.settings.activeProfileID = settingsStore.settings.profiles.first?.id
                                    }
                                } label: {
                                    Image(systemName: "trash")
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
                        }

                        Toggle("Právnická osoba (kancelária)", isOn: $profile.isLegalEntity)
                            .font(.callout)
                            .toggleStyle(.switch)
                    }
                    .liquidGlass(cornerRadius: 14, padding: 16)
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
