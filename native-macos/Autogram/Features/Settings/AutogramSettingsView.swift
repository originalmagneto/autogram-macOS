import SwiftUI

struct AutogramSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("App Version", value: AppIdentity.applicationVersion)
            LabeledContent("Protocol Version", value: AppIdentity.protocolVersion)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }
}
