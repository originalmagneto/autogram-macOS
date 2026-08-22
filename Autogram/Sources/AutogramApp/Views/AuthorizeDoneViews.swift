import SwiftUI
import AutogramKit
import AppKit

struct AuthorizeView: View {
    @Bindable var store: ZakoSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Pred autorizáciou — kontrolný zoznam", systemImage: "checklist")
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
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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

                HStack {
                    Button {
                        store.step = .attestation
                    } label: {
                        Label("Späť", systemImage: "chevron.left")
                    }
                    Spacer()
                    authorizeButton
                }
            }
            .padding(22)
        }
        .task { await store.refreshIdentities() }
    }

    private var tokenStatusRow: some View {
        let tokens = KeychainIdentityScanner.connectedTokenNames()
        return Group {
            if tokens.isEmpty {
                Label("Žiadna karta nie je pripojená cez CryptoTokenKit — certifikáty sa hľadajú v Keychainu.",
                      systemImage: "creditcard.and.123")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Pripojené karty/tokeny: \(tokens.joined(separator: ", "))",
                      systemImage: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var checklistItems: [(Bool, String, String)] {
        [
            (store.document != nil, "Dokument načítaný", "doc.fill"),
            (!store.attestation.originalDocumentName.isEmpty, "Názov pôvodného dokumentu vyplnený", "text.badge.checkmark"),
            (store.securityElements.count > 0, "Bezpečnostné prvky potvrdené (\(store.securityElements.count))", "shield.checkerboard"),
            (store.effectiveSheetCount > 0, "Počet listov určený (\(store.effectiveSheetCount))", "rectangle.stack"),
            ((store.attestation.evidenceNumber ?? "").isEmpty == false, "Evidenčné číslo z EZZK", "number.square.fill"),
            (!store.attestation.performingPerson.fullName.isEmpty, "Identita osvedčujúcej osoby", "person.crop.circle"),
            (!store.attestation.performingPerson.registrationNumber.isEmpty, "Evidenčné číslo advokáta", "building.columns")
        ]
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Náležitosti doložky")
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
        .glassCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var certificateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Certifikát pre autorizáciu")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.identities.isEmpty {
                ProgressView("Vyhľadávam certifikáty…")
            } else {
                ForEach(store.identities) { identity in
                    IdentityRow(identity: identity,
                               isSelected: store.selectedIdentityID == identity.id,
                               onSelect: { store.selectedIdentityID = identity.id })
                }
            }

            Toggle(isOn: $store.includeQualifiedTimestamp) {
                Label("Pripojiť kvalifikovanú časovú pečiatku (QTS)", systemImage: "clock.badge.checkmark")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            LabeledRow(label: "Formát výstupu") {
                Picker("", selection: Binding(
                    get: { store.settings.pdfaMode },
                    set: { _ in })) {
                    Text(store.settings.pdfaMode.rawValue).tag(store.settings.pdfaMode)
                }
                .disabled(true)
                .labelsHidden()
            }
            LabeledRow(label: "Čas konverzie") {
                Text("serverový čas EZZK pri autorizácii")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .frame(width: 380)
    }

    @ViewBuilder
    private var authorizeButton: some View {
        Button {
            Task { await store.authorizeAndSign() }
        } label: {
            HStack(spacing: 8) {
                if !store.analysisProgressText.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "signature.badge.checkmark")
                }
                Text(store.analysisProgressText.isEmpty ? "Autorizovať konverziu" : store.analysisProgressText)
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Color.accentColor)
        .disabled(!store.analysisProgressText.isEmpty)
    }
}

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
                    .lineLimit(1)
                Text(identity.issuerSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !identity.hasPrivateKey {
                Text("vyžaduje PIN/BOK na karte")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if identity.isMandateCertificate {
                badge("MANDÁTNY", tint: .green)
            }
            if identity.isQualified {
                badge("QCP", tint: .blue)
            }
        }
        .padding(9)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11)
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

struct DoneView: View {
    let store: ZakoSessionStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.13))
                    .frame(width: 128, height: 128)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(Color.green.gradient)
            }

            VStack(spacing: 6) {
                Text("Zaručená konverzia bola ukončená")
                    .font(.title.weight(.semibold))
                if let result = store.result {
                    Text(result.signatureLabel + (result.isLegallyBinding ? "" : " — DEMO režim (nenaväzuje právne)"))
                        .font(.callout)
                        .foregroundStyle(result.isLegallyBinding ? Color.secondary : Color.orange)
                }
                if let evidence = store.attestation.evidenceNumber {
                    Text("Evidenčné číslo: \(evidence)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
            }

            if let directory = store.outputDirectory {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Výstupné súbory:")
                        .font(.subheadline.weight(.semibold))
                    Text(directory.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .glassCard(cornerRadius: 14, padding: 12)

                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(directory)
                    } label: {
                        Label("Otvoriť vo Finderi", systemImage: "folder")
                    }
                    Button {
                        exportAs()
                    } label: {
                        Label("Uložiť ako…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        startNewConversion()
                    } label: {
                        Label("Nová konverzia", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Konverzia dokončená").font(.headline)
            }
        }
    }

    private func exportAs() {
        guard let directory = store.outputDirectory else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (store.attestation.newDocumentName.isEmpty ? "dokument" : store.attestation.newDocumentName) + "-pdfa"
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
