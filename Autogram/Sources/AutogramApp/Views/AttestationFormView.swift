import SwiftUI
import AutogramKit

struct AttestationFormView: View {
    @Bindable var store: ZakoSessionStore
    @State private var savedTemplateHint = false
    @State private var showingLivePreview = true

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ScrollView {
                    formContent
                        .padding(18)
                }
                .frame(minWidth: 460, idealWidth: 540)

                if showingLivePreview {
                    liveClausePreviewPane
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500)
                }
            }

            StickyActionBar {
                Button {
                    store.step = .analysis
                } label: {
                    Label("Späť na analýzu", systemImage: "chevron.left")
                }
                .controlSize(.large)

                Spacer()

                Button {
                    showingLivePreview.toggle()
                } label: {
                    Label(showingLivePreview ? "Skryť náhľad" : "Živý náhľad doložky", systemImage: "sidebar.right")
                }
                .controlSize(.large)

                Button {
                    store.recomputePreflight()
                    guard !store.hasUnresolvedPreflightErrors else { return }
                    store.step = .authorize
                    Task { await store.refreshIdentities() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Pokračovať na autorizáciu")
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.fetchingEvidenceNumber || store.hasUnresolvedPreflightErrors)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: store.attestation) { _, _ in
            store.recomputePreflight()
        }
        .onChange(of: store.securityElements) { _, _ in
            store.recomputePreflight()
        }
        .onChange(of: store.effectiveSheetCount) { _, _ in
            store.recomputePreflight()
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Osvedčovacia doložka zaručenej konverzie", systemImage: "building.columns.fill")
                    .font(.headline)

                Spacer()

                Menu {
                    Button {
                        store.loadLatestTemplate()
                    } label: {
                        Label("Načítať poslednú šablónu", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        store.saveTemplate()
                        savedTemplateHint = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            savedTemplateHint = false
                        }
                    } label: {
                        Label("Uložiť ako šablónu údajov", systemImage: "tray.and.arrow.down")
                    }

                    Divider()

                    Button {
                        store.saveProfileFromForm()
                    } label: {
                        Label("Uložiť údaje do profilu advokáta", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } label: {
                    Label("Šablóna a profil", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
            }

            if savedTemplateHint {
                Text("Šablóna bola úspešne uložená pre ďalšie konverzie.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if !store.preflightErrors.isEmpty || store.evidenceNumberError != nil {
                errorCard
            }

            section("Pôvodný listinný dokument", symbol: "doc.text") {
                LabeledRow(label: "Názov dokumentu") {
                    TextField("Napr. Plná moc / Kúpna zmluva", text: $store.attestation.originalDocumentName)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledRow(label: "Druh dokumentu") {
                    Picker("", selection: $store.attestation.originalDocumentTypeLabel) {
                        ForEach(["Zmluva", "Plná moc", "Rozsudok", "Osvedčenie", "Rozhodnutie", "Iný dokument"], id: \.self) {
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
                         ? "A4"
                         : store.attestation.paperSizeBreakdown
                             .map { "\($0.sizeClass.rawValue): \($0.sheets) listov" }
                             .joined(separator: ", "))
                        .font(.callout)
                }
            }
            inlineError(.missingOriginalName)
            inlineError(.invalidSheetCount)
            inlineError(.noSecurityElementsConfirmed)
            Toggle("Potvrdzujem, že vstupný dokument je originál alebo úradne osvedčená kópia.",
                   isOn: $store.attestation.originConfirmed)
                .toggleStyle(.switch)
            inlineError(.originNotConfirmed)

            section("Novovzniknutý elektronický dokument", symbol: "doc.badge.gearshape") {
                LabeledRow(label: "Názov výstupu (PDF/A)") {
                    TextField("Názov výstupného súboru", text: $store.attestation.newDocumentName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            inlineError(.missingNewDocumentName)

            section("Osoba vykonávajúca konverziu", symbol: "person.crop.circle.badge.checkmark") {
                LabeledRow(label: "Meno a priezvisko") {
                    TextField("JUDr. Meno Priezvisko", text: $store.attestation.performingPerson.fullName)
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
            inlineError(.missingPerformingPerson)
            inlineError(.missingRegistrationNumber)

            section("Evidencia záznamov o konverzii (CEZZK)", symbol: "number.square") {
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
                                Label(store.attestation.evidenceNumber == nil
                                      ? "Získať číslo" : "Znova získať číslo",
                                      systemImage: "number.square.fill")
                            }
                        }
                        .disabled(store.fetchingEvidenceNumber)
                        .controlSize(.small)
                    }
                }
                if let error = store.evidenceNumberError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                inlineError(.missingEvidenceNumber)
                Text("Číslo sa viaže na registráciu v evidencii záznamov. Záznam sa odošle do centrálnej evidencie do 24 hodín.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveClausePreviewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Živý náhľad doložky", systemImage: "doc.plaintext")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("§ 35-39 Zz")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(generatedClausePreviewText)
                    .font(.system(size: 11, design: .serif))
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
        }
    }

    private var generatedClausePreviewText: String {
        let name = store.attestation.originalDocumentName.isEmpty ? "Názov dokumentu" : store.attestation.originalDocumentName
        let person = store.attestation.performingPerson.fullName.isEmpty ? "JUDr. Meno Priezvisko" : store.attestation.performingPerson.fullName
        let sak = store.attestation.performingPerson.registrationNumber.isEmpty ? "XXXX" : store.attestation.performingPerson.registrationNumber
        let evidence = store.attestation.evidenceNumber ?? "XXXXXX"

        return """
        OSVEDČOVACIA DOLOŽKA O ZARUČENEJ KONVERZII
        podľa § 35 až 39 zákona č. 305/2013 Z. z. o e-Governmente

        1. Názov pôvodného dokumentu: \(name)
        2. Druh pôvodného dokumentu: \(store.attestation.originalDocumentTypeLabel)
        3. Počet listov pôvodného dokumentu: \(store.effectiveSheetCount)
        4. Počet neprázdnych strán pôvodného dokumentu: \(store.analysis.nonEmptyPages)
        5. Bezpečnostné prvky pôvodného dokumentu: \(store.confirmedSecurityElements.count) potvrdených prvkov
        6. Osoba vykonávajúca konverziu: \(person), advokát, ev. č. SAK: \(sak)
        7. Evidenčné číslo záznamu o zaručenej konverzii: \(evidence)
        8. Čas konverzie: bude určený časovou pečiatkou QTS pri autorizácii

        Tento elektronický dokument vznikol zaručenou konverziou z listinnej podoby a má rovnaké právne účinky ako pôvodný dokument.
        """
    }
    @ViewBuilder
    private func inlineError(_ error: AttestationValidationError) -> some View {
        if store.preflightErrors.contains(error) {
            Text(error.errorDescription ?? "")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Doložku nie je možné autorizovať: doplňte údaje:", systemImage: "exclamationmark.triangle.fill")
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
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
