import SwiftUI
import AutogramKit

/// Confirmation for a signing request that arrived from a state portal.
///
/// The page never learns the PIN and never signs on its own: this sheet is the
/// only path from a browser request to the card.
struct WebSigningSheet: View {
    @Bindable var coordinator: WebSigningCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let pending = coordinator.pending {
                documentCard(pending)
            }

            timestampToggle

            if coordinator.mobileSigningAvailable {
                mobileOption
                Divider()
            }

            identityPicker
            pinField

            if let error = coordinator.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 540, maxWidth: 620)
        .sheet(isPresented: Bindable(coordinator.mobileSigning).isPresented) {
            if let session = coordinator.mobileSigning.session {
                MobileSigningSheet(session: session) {
                    coordinator.mobileSigning.cancel()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "signature")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Podpísať dokument zo stránky")
                    .font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                    Text("Pôvod: Webový portál cez rozšírenie Safari")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func documentCard(_ pending: WebSigningCoordinator.Pending) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let thumb = pending.pdfThumbnail {
                    VStack(spacing: 4) {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        Text("1. strana")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.request.filename)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(pending.kindDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(pending.sizeDescription)
                        Text("·")
                        Text(pending.request.signatureLevel.replacingOccurrences(of: "_", with: " "))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            if let excerpt = pending.xmlExcerpt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ukážka obsahu formulára (čiastočný náhľad):")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(excerpt)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .frame(maxHeight: 70)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    /// State portals ask for Baseline B, so without this the phone offers only
    /// the handwritten-equivalent signature and the qualified one stays greyed out.
    private var timestampToggle: some View {
        Toggle(isOn: $coordinator.addsQualifiedTimestamp) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pridať kvalifikovanú časovú pečiatku")
                    .font(.callout)
                Text(coordinator.addsQualifiedTimestamp
                     ? "Podpíše sa ako osvedčený podpis (\(coordinator.effectiveLevelDescription)). Portál môže takýto podpis odmietnuť, ak si ho nevyžiadal."
                     : "Podpíše sa presne tak, ako pýta stránka (\(coordinator.effectiveLevelDescription)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    /// Signing with the phone needs no reader and no PIN here, so it is offered
    /// first: on this path the eID is read over NFC and the PIN stays on the
    /// phone.
    private var mobileOption: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Podpísať mobilom")
                    .font(.callout.weight(.medium))
                Text("Občiansky preukaz cez NFC, bez čítačky.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Použiť mobil") {
                guard !coordinator.isWorking else { return }
                Task { await coordinator.confirmViaMobile() }
            }
            .disabled(coordinator.isWorking)
        }
        .padding(12)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var identityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alebo podpisovou kartou")
                .font(.caption)
                .foregroundStyle(.secondary)
            if coordinator.identities.isEmpty {
                HStack(spacing: 8) {
                    Text("Nenašiel sa žiadny certifikát.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Hľadať znova") {
                        Task { await coordinator.refreshIdentities() }
                    }
                    .buttonStyle(.link)
                }
            } else {
                Picker("", selection: $coordinator.selectedIdentityID) {
                    ForEach(coordinator.identities) { identity in
                        Text(identity.label).tag(Optional(identity.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var pinField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PIN karty")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("PIN", text: $coordinator.pin)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirm() }
        }
    }

    private var actions: some View {
        HStack {
            Button("Zrušiť", role: .cancel) { coordinator.cancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if coordinator.isWorking {
                ProgressView().controlSize(.small)
            }
            Button("Podpísať") { confirm() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isWorking || coordinator.selectedIdentityID == nil)
        }
    }

    private func confirm() {
        guard !coordinator.isWorking else { return }
        Task { await coordinator.confirm() }
    }
}
