import SwiftUI
import AutogramKit

struct SettingsView: View {
    @Bindable var settingsStore: AppSettingsStore
    @State private var newProfileName = ""
    @State private var newTSAURL = ""
    @State private var tsaTestStatus: String?
    @State private var isTestingTSA = false

    var body: some View {
        TabView {
            aiTab.tabItem { Label("AI Vision", systemImage: "brain.head.profile") }
            conversionTab.tabItem { Label("Konverzia PDF/A", systemImage: "doc.badge.gearshape") }
            ezzkTab.tabItem { Label("EZZK", systemImage: "number.square") }
            profilesTab.tabItem { Label("Profily advokáta", systemImage: "person.crop.circle.badge.checkmark") }
        }
        .padding(18)
    }

    private var aiTab: some View {
        Form {
            Picker("Režim detekcie prvkov", selection: $settingsStore.settings.aiMode) {
                ForEach(AppSettings.AIMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text("Vstavaná on-device detekcia beží vždy a jej výsledky sa nedajú vypnúť — zvolený AI režim len pridáva ďalšie nálezy (IoU deduplikácia). Všetky prvky je možné kedykoľvek upraviť, presunúť alebo vymazať ručne.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GroupBox("Klasifikačný prompt pre LLM") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: Binding(
                        get: { settingsStore.settings.aiPrompt ?? "" },
                        set: { newValue in
                            settingsStore.settings.aiPrompt =
                                newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil : newValue
                        }))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 560, height: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.12)))

                    HStack {
                        Text("Prázdne = predvolený prompt. Vlastný text nahradí klasifikačné inštrukcie; formát JSON odpovede je vynútený automaticky.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Obnoviť predvolený") {
                            settingsStore.settings.aiPrompt = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(4)
            }

            GroupBox("Lokálny model (Ollama)") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledRow(label: "Server") {
                        TextField("http://localhost:11434",
                                  text: $settingsStore.settings.ollamaURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                    }
                    LabeledRow(label: "Model") {
                        TextField("llava / llama3.2-vision", text: $settingsStore.settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                    }
                    Text("100 % offline spracovanie priamo na Macu. Odporúčané modely: llava, qwen2-vl.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Vlastný API kľúč (OpenAI-compatible)") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledRow(label: "Base URL") {
                        TextField("https://api.openai.com/v1",
                                  text: $settingsStore.settings.openAICompatibleBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 340)
                    }
                    LabeledRow(label: "Model") {
                        TextField("gpt-4o-mini", text: $settingsStore.settings.openAICompatibleModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 340)
                    }
                    LabeledRow(label: "API kľúč (Keychain)") {
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
                            .frame(width: 340)
                    }
                    Text("Kľúč sa ukladá výhradne do macOS Kľúčenky tohto Macu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var conversionTab: some View {
        Form {
            Picker("Spôsob konverzie do PDF/A", selection: $settingsStore.settings.pdfaMode) {
                ForEach(PDFAConversionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            GroupBox("Časová pečiatka (RFC 3161 TSA)") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Aktívna TSA", selection: $settingsStore.settings.selectedTSAURL) {
                        ForEach(settingsStore.settings.availableTSAServers) { server in
                            Text("\(server.name) — \(server.url)").tag(server.url)
                        }
                    }
                    .frame(width: 520)

                    Text("Predvolené servery zodpovedajú originálnej aplikácii Autogram (Sectigo Qualified, Belgian TSA) a slovenskej kvalifikovanej TSA CA Disig. Vlastné servery môžeš pridať nižšie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !settingsStore.settings.customTSAServers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vlastné servery").font(.subheadline.weight(.semibold))
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
                                            settingsStore.settings.selectedTSAURL =
                                                TimestampAuthority.legacyDefaultURL
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("https://vasa-tsa.example.com/tsp", text: $newTSAURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 340)
                        Button("Pridať vlastnú TSA") {
                            let trimmed = newTSAURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty,
                                  !settingsStore.settings.customTSAServers.contains(trimmed) else { return }
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
                .padding(4)
            }

            Text("Vektorová konverzia zachováva text a vektorovú grafiku; rasterizovaná garancia vykreslí stránky do 300 dpi obrazu — vhodné pre problematické skeny. Výstup je v oboch prípadoch doplnený o XMP metadáta pdfaid (PDF/A-2b) a sRGB OutputIntent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
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

    private var ezzkTab: some View {
        Form {
            Section {
                Text("Údaje z registrácie v evidencii záznamov o zaručenej konverzii (ezzk.iomo.sk). Bez vyplnených údajov beží aplikácia v DEMO režime evidencie.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LabeledRow(label: "IČO") {
                TextField("IČO advokátskej kancelárie", text: $settingsStore.settings.ezzkICO)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            LabeledRow(label: "Prihlasovacie meno") {
                TextField("username", text: $settingsStore.settings.ezzkUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            LabeledRow(label: "Heslo (Keychain)") {
                SecureField("heslo", text: $settingsStore.ezzkPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit { settingsStore.saveEZZKPassword() }
            }
            LabeledRow(label: "Notifikačný e-mail") {
                TextField("advokat@kancelaria.sk", text: $settingsStore.settings.ezzkNotificationEmail)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            LabeledRow(label: "Adresa elektronickej schránky") {
                TextField("edesk", text: $settingsStore.settings.ezzkEdeskAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            Button("Uložiť prístupy do Kľúčenky") {
                settingsStore.saveEZZKPassword()
            }
            .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
    }

    private var profilesTab: some View {
        Form {
            if settingsStore.settings.profiles.isEmpty {
                Text("Zatiaľ žiadny profil. Pridajte profil advokáta pre automatické predvyplňovanie doložky.")
                    .foregroundStyle(.secondary)
            }
            ForEach($settingsStore.settings.profiles) { $profile in
                GroupBox(profile.displayName.isEmpty ? "Nový profil" : profile.displayName) {
                    VStack(spacing: 8) {
                        LabeledRow(label: "Meno a priezvisko") {
                            TextField("JUDr. Meno Priezvisko", text: $profile.fullName)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 12) {
                            LabeledRow(label: "Funkcia") {
                                TextField("advokát", text: $profile.position)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                            }
                            LabeledRow(label: "Evidenčné číslo SAK") {
                                TextField("1234", text: $profile.registrationNumber)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                            LabeledRow(label: "IČO") {
                                TextField("IČO", text: $profile.ico)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 140)
                            }
                        }
                        LabeledRow(label: "Názov kancelárie") {
                            TextField("Advokátska kancelária…", text: $profile.officeName)
                                .textFieldStyle(.roundedBorder)
                        }
                        Toggle("Právnická osoba (kancelária)", isOn: $profile.isLegalEntity)
                            .toggleStyle(.switch)

                        Picker("Aktívny profil", selection: $settingsStore.settings.activeProfileID) {
                            Text("(vybrať)").tag(UUID?.none)
                            Text(profile.displayName.isEmpty ? "profil" : profile.displayName)
                                .tag(UUID?.some(profile.id))
                        }
                        .frame(width: 260)
                    }
                }
            }

            HStack {
                Button {
                    let profile = AdvocateProfile()
                    settingsStore.settings.profiles.append(profile)
                    if settingsStore.settings.activeProfileID == nil {
                        settingsStore.settings.activeProfileID = profile.id
                    }
                } label: {
                    Label("Pridať profil", systemImage: "plus")
                }
                Spacer()
            }
        }
        .formStyle(.grouped)
    }
}

extension AdvocateProfile {
    var displayName: String {
        fullName.isEmpty ? officeName : fullName
    }
}
