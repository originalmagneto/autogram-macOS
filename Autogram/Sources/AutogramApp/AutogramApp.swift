import SwiftUI

@main
struct AutogramApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.automatic)
    }
}
