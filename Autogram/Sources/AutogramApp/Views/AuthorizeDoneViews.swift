import SwiftUI
import AutogramKit
import AppKit

struct AuthorizeView: View {
    @Bindable var store: ZakoSessionStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Pred autorizáciou: kontrolný zoznam", systemImage: "checklist")
                        .font(.headline)

                    tokenStatusRow

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            checklistCard
                            certificateCard
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            checklistCard
                            certificateCard
                        }
                    }

                    if let error = store.lastError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !store.validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(store.validationErrors.enumerated()), id: \.offset) { _, err in
                                Text("• \(err.errorDescription ?? "")")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(20)
            }

            StickyActionBar {
                Button {
                    store.step = .attestation
                } label: {
                    Label("Späť na doložku", systemImage: "chevron.left")
                }
                .controlSize(.large)

                Spacer()

                authorizeButton
            }
        }
        .task { await store.refreshIdentities() }
    }

    private var tokenStatusRow: some View {
        Group {
            if store.signingProvider is DemoSigningProvider {
                Label("Demo režim: kvalifikovaná karta nie je pripojená.",
                      systemImage: "creditcard.and.123")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.identities.isEmpty {
                Label("Karta nie je detegovaná: vložte eID alebo advokátsky preukaz.",
                      systemImage: "creditcard.and.123")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.isCertificateTypePending {
                Label("Karta je pripojená. Typ certifikátu sa overí po zadaní PIN.",
                      systemImage: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Karta je pripojená, certifikáty načítané.",
                      systemImage: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var checklistItems: [(Bool, String, String)] {
        let identitySelected = store.selectedIdentityID != nil && store.selectedIdentity != nil
        let qtsReady = !store.includeQualifiedTimestamp ||
            !store.settings.selectedTSAURL.trimmingCharacters(in: .whitespaces).isEmpty
        return [
            (store.attestation.originConfirmed,
             "Originál alebo úradne osvedčená kópia potvrdená", "checkmark.seal"),
            (!store.attestation.originalDocumentName.trimmingCharacters(in: .whitespaces).isEmpty,
             "Názov pôvodného dokumentu vyplnený", "text.badge.checkmark"),
            (!store.attestation.newDocumentName.trimmingCharacters(in: .whitespaces).isEmpty,
             "Názov elektronického dokumentu vyplnený", "doc.badge.gearshape"),
            (store.effectiveSheetCount > 0,
             "Počet listov určený (\(store.effectiveSheetCount))", "rectangle.stack"),
            (store.securityElements.count > 0,
             "Bezpečnostné prvky potvrdené (\(store.securityElements.count))", "shield.checkerboard"),
            ((store.attestation.evidenceNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty == false,
             "Evidenčné číslo z EZZK", "number.square.fill"),
            (!store.attestation.performingPerson.fullName.trimmingCharacters(in: .whitespaces).isEmpty,
             "Osoba vykonávajúca konverziu vyplnená", "person.crop.circle"),
            (!store.attestation.performingPerson.registrationNumber.trimmingCharacters(in: .whitespaces).isEmpty,
             "Evidenčné číslo advokáta vyplnené", "building.columns"),
            (identitySelected, "Identita pre podpis vybraná", "person.badge.key"),
            (store.mandateRequirementSatisfied, "Mandátny certifikát SAK pripravený", "checkmark.seal"),
            (qtsReady, store.includeQualifiedTimestamp
                ? "QTS pripravená s TSA službou" : "QTS nepoužitá", "clock.badge.checkmark")
        ]
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zákonné náležitosti doložky")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(checklistItems.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Image(systemName: item.0 ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(item.0 ? Color.green : Color.secondary)
                    Image(systemName: item.2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(item.1)
                        .font(.callout)
                }
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var certificateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Podpisový certifikát pre autorizáciu")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.identities.isEmpty {
                ProgressView("Vyhľadávam certifikáty…")
                    .controlSize(.small)
            } else {
                ForEach(store.identities) { identity in
                    IdentityRow(identity: identity,
                               isSelected: store.selectedIdentityID == identity.id,
                               onSelect: { store.selectedIdentityID = identity.id })
                }
            }

            if !store.signingProviderIsDemo {
                SecureField("PIN karty", text: $store.signingPIN)
                    .textFieldStyle(.roundedBorder)
                Label("Certifikát sa vyberie pri autorizácii. eID klient zobrazí natívny BOK dialóg až pri podpise.",
                      systemImage: "key.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $store.includeQualifiedTimestamp) {
                Label("Kvalifikovaná časová pečiatka (QTS)", systemImage: "clock.badge.checkmark")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if store.requiresMandateOverride {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Zvolený certifikát nie je mandátnym certifikátom pre zaručenú konverziu.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Toggle(isOn: $store.allowNonMandateOverride) {
                        Text("Rozumiem: pokračovať s ne-mandátnym certifikátom")
                            .font(.caption2)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .glassCard(cornerRadius: 14, padding: 14)
        .frame(width: 380)
    }

    @ViewBuilder
    private var authorizeButton: some View {
        Button {
            Task { await store.authorizeAndSign() }
        } label: {
            HStack(spacing: 8) {
                if store.isAuthorizing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "signature.badge.checkmark")
                }
                Text(store.isAuthorizing ? store.analysisProgressText : "Autorizovať konverziu")
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.indigo)
        .disabled(store.isAuthorizing || !store.isPreflightComplete)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Identity Row Component
struct IdentityRow: View {
    let identity: SigningIdentityInfo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(identity.issuerSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !identity.hasPrivateKey {
                    Text("vyžaduje PIN/BOK na karte")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if identity.isMandateCertificate {
                badge("MANDÁTNY", tint: .green)
            }
            if identity.isQualified {
                badge("QCP", tint: .blue)
            } else if !identity.id.hasPrefix("demo") {
                badge("KOMERČNÝ", tint: .orange)
            }
        }
        .padding(9)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.07)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Step 5: Done View for ZaKo
struct DoneView: View {
    let store: ZakoSessionStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            let isQueued = store.submissionStatus == .queuedForSubmission
            ZStack {
                Circle()
                    .fill((isQueued ? Color.orange : Color.green).opacity(0.12))
                    .frame(width: 130, height: 130)
                Image(systemName: isQueued ? "tray.and.arrow.up.fill" : "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(isQueued ? Color.orange : Color.green)
            }

            VStack(spacing: 6) {
                Text(isQueued
                     ? "Súbor je podpísaný; zápis do CEZZK čaká"
                     : "Zaručená konverzia bola úspešne dokončená")
                    .font(.title2.weight(.bold))

                if let result = store.result {
                    Text(result.isLegallyBinding
                         ? "Kvalifikovaný elektronický podpis a doložka pripojené"
                         : "DEMO režim: konverzia nemá právne účinky")
                        .font(.callout)
                        .foregroundStyle(result.isLegallyBinding ? Color.secondary : Color.orange)
                }

                if isQueued, let record = store.evidenceStore.record(id: store.currentRecordID) {
                    Text("Odoslanie sa zopakuje najneskôr do \(record.submissionDeadline, style: .date) \(record.submissionDeadline, style: .time).")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button {
                        Task { await store.retryQueuedSubmission() }
                    } label: {
                        Label("Znova odoslať do CEZZK", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }

                if let evidence = store.attestation.evidenceNumber {
                    HStack(spacing: 6) {
                        Text("Evidenčné číslo:")
                            .foregroundStyle(.secondary)
                        Text(evidence)
                            .font(.callout.monospacedDigit().weight(.bold))
                    }
                    .padding(.top, 2)
                }
            }

            if let directory = store.outputDirectory {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Priečinok s vygenerovanými súbormi:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(directory.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .glassCard(cornerRadius: 12, padding: 12)
                .frame(maxWidth: 520)

                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(directory)
                    } label: {
                        Label("Ukázať vo Finderi", systemImage: "folder")
                    }
                    .controlSize(.large)

                    Button {
                        exportAs()
                    } label: {
                        Label("Uložiť ako…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        startNewConversion()
                    } label: {
                        Label("Nová konverzia", systemImage: "plus")
                    }
                    .controlSize(.large)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exportAs() {
        guard let directory = store.outputDirectory else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (store.attestation.newDocumentName.isEmpty ? "dokument" : store.attestation.newDocumentName) + "-konvertovane"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                      includingPropertiesForKeys: nil)) ?? []
            if let pdf = files.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
                try? FileManager.default.copyItem(at: pdf, to: url)
            }
        }
    }

    private func startNewConversion() {
        store.resetSession(keepingProfile: true)
        store.step = .intake
    }
}
