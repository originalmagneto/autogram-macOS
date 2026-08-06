import SwiftUI

struct CertificatePicker: View {
    let certificates: [SigningCertificate]
    @Binding var selectedSerial: String?
    let onContinue: () -> Void

    var body: some View {
        List(certificates, selection: $selectedSerial) { certificate in
            VStack(alignment: .leading, spacing: 2) {
                Text(certificate.displayName)
                Text("Serial: \(certificate.serialNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(Optional(certificate.serialNumber))
        }
        .accessibilityIdentifier("Certificate Picker")
        .frame(minHeight: 120)

        Button("Use Certificate") {
            onContinue()
        }
        .accessibilityIdentifier("Use Certificate")
        .disabled(selectedSerial == nil)
    }
}
