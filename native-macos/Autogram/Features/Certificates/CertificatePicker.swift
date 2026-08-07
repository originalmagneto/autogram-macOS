import SwiftUI

struct CertificatePicker: View {
    let certificates: [SigningCertificate]
    let onSelect: (SigningCertificate) -> Void
    let onCancel: () -> Void
    @State private var selectedCertificate: SigningCertificate?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            List(certificates) { certificate in
                Button {
                    selectedCertificate = certificate
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(certificate.displayName)
                            Text(redactedSerialDetail(for: certificate))
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

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button("Use Certificate") {
                    guard let selectedCertificate else { return }
                    onSelect(selectedCertificate)
                }
                .accessibilityIdentifier("Use Certificate")
                .disabled(selectedCertificate == nil)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }

    private func redactedSerialDetail(for certificate: SigningCertificate) -> String {
        let suffix = certificate.serialNumber.suffix(4)
        return suffix.isEmpty ? "Serial available" : "Serial ending in \(suffix)"
    }
}
