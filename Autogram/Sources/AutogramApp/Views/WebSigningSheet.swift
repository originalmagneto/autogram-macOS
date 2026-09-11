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
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "signature")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Podpísať dokument zo stránky")
                    .font(.headline)
                Text("Požiadavku poslalo rozšírenie v prehliadači.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func documentCard(_ pending: WebSigningCoordinator.Pending) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pending.request.filename)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Text(pending.kindDescription)
                Text("·")
                Text(pending.sizeDescription)
                Text("·")
                Text(pending.request.signatureLevel.replacingOccurrences(of: "_", with: " "))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var identityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Podpisový certifikát")
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
