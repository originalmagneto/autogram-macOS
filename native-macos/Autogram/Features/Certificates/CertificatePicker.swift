import SwiftUI

struct CertificatePicker: View {
    let certificates: [SigningCertificate]
    let showsRememberAsDefaultToggle: Bool
    let onSelect: (SigningCertificate, Bool) -> Void
    let onCancel: () -> Void
    @State private var selectedCertificate: SigningCertificate?
    @State private var rememberAsDefault = false

    init(
        certificates: [SigningCertificate],
        showsRememberAsDefaultToggle: Bool = true,
        onSelect: @escaping (SigningCertificate, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.certificates = certificates
        self.showsRememberAsDefaultToggle = showsRememberAsDefaultToggle
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            List(certificates) { certificate in
                Button {
                    selectedCertificate = certificate
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(certificate.displayName)
                            Text(certificateDetail(for: certificate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedCertificate == certificate {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .privacySensitive()
            }
            .accessibilityIdentifier("Certificate Picker")
            .frame(minHeight: 120)

            if showsRememberAsDefaultToggle {
                Toggle("Remember as default for this signing card", isOn: $rememberAsDefault)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button("Use Certificate") {
                    guard let selectedCertificate else { return }
                    onSelect(selectedCertificate, rememberAsDefault)
                }
                .accessibilityIdentifier("Use Certificate")
                .disabled(selectedCertificate == nil)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }

    private func certificateDetail(for certificate: SigningCertificate) -> String {
        let issuer = certificate.issuer.isEmpty ? "Certificate available" : certificate.issuer
        return "\(issuer), expires \(certificate.validUntil.formatted(date: .abbreviated, time: .omitted))"
    }
}
