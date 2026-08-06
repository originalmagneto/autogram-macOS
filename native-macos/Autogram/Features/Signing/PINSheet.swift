import SwiftUI

struct PINSheet: View {
    @Binding var pin: String
    let onSubmit: (Secret) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter PIN")
                .font(.headline)

            SecureField("PIN", text: $pin)
                .accessibilityIdentifier("PIN")

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Sign with PIN") {
                    let secret = Secret(pin)
                    pin = ""
                    onSubmit(secret)
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
        }
    }
}
