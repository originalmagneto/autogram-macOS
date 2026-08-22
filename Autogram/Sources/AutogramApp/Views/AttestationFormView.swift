import SwiftUI
import AutogramKit

struct AttestationFormView: View {
    @Bindable var store: ZakoSessionStore
    @State private var savedTemplateHint = false
    @State private var profileSavedHint = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Osvedčovacia doložka — automaticky predvyplnená", systemImage: "building.columns.fill")
                        .font(.headline)
                    Spacer()
                    Button {
                        store.loadLatestTemplate()
                    } label: {
                        Label("Načítať šablónu údajov", systemImage: "square.and.arrow.down")
                    }
                    .help("Načíta naposledy uloženú sadu údajov doložky — hodí sa pri opakovaných dokumentoch rovnakého typu (napr. plné mocnosti).")

                    Button {
                        store.saveTemplate()
                        savedTemplateHint = true
                    } label: {
                        Label("Uložiť ako šablónu", systemImage: "tray.and.arrow.down")
                    }
                    .help("Uloží aktuálne vyplnené údaje (názvy, druh dokumentu, profil) ako šablónu pre budúce konverzie rovnakých dokumentov.")
                }

                if savedTemplateHint {
                    Text("Šablóna uložená — pri ďalšej konverzii rovnakého typu dokumentu ju načítaš tlačidlom „Načítať šablónu údajov“.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if !store.validationErrors.isEmpty {
                    errorCard
                }

                profileCard


                section("Pôvodný listinný dokument", symbol: "doc.text") {
                    LabeledRow(label: "Názov dokumentu") {
                        TextField("Názov", text: $store.attestation.originalDocumentName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledRow(label: "Druh dokumentu") {
                        Picker("", selection: $store.attestation.originalDocumentTypeLabel) {
                            ForEach(["Zmluva", "Plná moc", "Rozsudok", "Osvedčenie", "Iný dokument"], id: \.self) {
                                Text($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    LabeledRow(label: "Počet listov / neprázdnych strán") {
                        Text("\(store.effectiveSheetCount) listov · \(store.analysis.nonEmptyPages) strán")
                            .font(.callout.monospacedDigit().weight(.medium))
                    }
                    LabeledRow(label: "Veľkosť listiny") {
                        Text(store.attestation.paperSizeBreakdown.isEmpty
                             ? "—"
                             : store.attestation.paperSizeBreakdown
                                 .map { "\($0.sizeClass.rawValue): \($0.sheets) listov" }
                                 .joined(separator: ", "))
                            .font(.callout)
                    }
                }

                section("Novovzniknutý elektronický dokument", symbol: "doc.badge.gearshape") {
                    LabeledRow(label: "Názov výstupu (PDF/A)") {
                        TextField("Názov", text: $store.attestation.newDocumentName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                section("Osoba vykonávajúca konverziu", symbol: "person.crop.circle.badge.checkmark") {
                    LabeledRow(label: "Meno a priezvisko") {
                        TextField("JUDr. Meno Priezvisko",
                                  text: $store.attestation.performingPerson.fullName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledRow(label: "Funkcia") {
                        TextField("advokát", text: $store.attestation.performingPerson.position)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                    LabeledRow(label: "Evidenčné číslo advokáta (SAK)") {
                        TextField("napr. 1234", text: $store.attestation.performingPerson.registrationNumber)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                    LabeledRow(label: "IČO kancelárie") {
                        TextField("IČO", text: $store.attestation.performingPerson.ico)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                section("Evidencia záznamov o konverzii", symbol: "number.square") {
                    LabeledRow(label: "Evidenčné číslo z EZZK") {
                        HStack(spacing: 10) {
                            if let number = store.attestation.evidenceNumber, !number.isEmpty {
                                Text(number)
                                    .font(.callout.monospacedDigit().weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.14), in: Capsule())
                            } else {
                                Text("nezískané")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                Task { await store.fetchEvidenceNumber() }
                            } label: {
                                if store.fetchingEvidenceNumber {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(store.attestation.evidenceNumber == nil ? "Získať číslo" : "Znovu",
                                          systemImage: "number.square.fill")
                                }
                            }
                            .disabled(store.fetchingEvidenceNumber)
                        }
                    }
                    Text("Číslo je jednorazové a viaže sa na Vašu registráciu v evidencii záznamov. Záznam sa po autorizácii odošle do centrálnej evidencie do 24 hodín.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        store.step = .analysis
                    } label: {
                        Label("Späť na analýzu", systemImage: "chevron.left")
                    }
                    Spacer()
                    Button {
                        store.step = .authorize
                        Task { await store.refreshIdentities() }
                    } label: {
                        Text("Pokračovať na autorizáciu")
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
            .padding(22)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Krok 3 — Osvedčovacia doložka")
                    .font(.headline)
            }
        }
    }

    private var profileCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Tvoje údaje (predvyplnenie)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.saveProfileFromForm()
                        profileSavedHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            profileSavedHint = false
                        }
                    } label: {
                        Label("Uložiť ako môj profil", systemImage: "externaldrive.badge.checkmark")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    TextField("Titul Meno Priezvisko",
                              text: $store.attestation.performingPerson.fullName)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                    TextField("Funkcia (advokát)",
                              text: $store.attestation.performingPerson.position)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField("SAK č.",
                              text: $store.attestation.performingPerson.registrationNumber)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    TextField("IČO kancelárie",
                              text: $store.attestation.performingPerson.ico)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                if profileSavedHint {
                    Text("Profil uložený — pri ďalších konverziách sa automaticky predvyplní.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Doložku nie je možné autorizovať — doplňte údaje:", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(store.validationErrors.enumerated()), id: \.offset) { _, error in
                Text("• \(error.errorDescription ?? "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func section<Content: View>(_ title: String, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) { content() }
                .glassCard(cornerRadius: 14, padding: 14)
        }
    }
}

struct LabeledRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: 190, idealWidth: 230, alignment: .leading)
            value
            Spacer(minLength: 0)
        }
    }
}
