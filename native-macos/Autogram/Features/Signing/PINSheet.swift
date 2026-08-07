import SwiftUI

struct PINSheet: View {
    @Binding var pin: String
    let onSubmit: (PINSubmission) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter PIN")
                .font(.headline)

            SecureField("PIN", text: $pin)
                .accessibilityIdentifier("PIN")

            HStack {
                Spacer()
                Button("Cancel") {
                    pin = ""
                    onCancel()
                    dismiss()
                }
                Button("Sign with PIN") {
                    let submission = PINSubmission(
                        certificatePIN: Secret(pin),
                        signingPIN: Secret(pin)
                    )
                    pin = ""
                    submitted = true
                    onSubmit(submission)
                    dismiss()
                }
                .disabled(pin.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
        .onDisappear {
            pin = ""
            if !submitted {
                onCancel()
            }
        }
    }
}

struct PINSubmission: Sendable {
    let certificatePIN: Secret
    let signingPIN: Secret
}
