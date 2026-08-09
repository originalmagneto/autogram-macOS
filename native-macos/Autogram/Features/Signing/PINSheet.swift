import SwiftUI

struct PINSheet: View {
    @Binding var pin: String
    let title: String
    let submitTitle: String
    let onSubmit: (PINSubmission) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false

    init(
        pin: Binding<String>,
        title: String = "Enter PIN",
        submitTitle: String = "Sign with PIN",
        onSubmit: @escaping (PINSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _pin = pin
        self.title = title
        self.submitTitle = submitTitle
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
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
                Button(submitTitle) {
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
