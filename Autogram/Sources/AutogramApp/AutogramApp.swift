import SwiftUI

@main
struct AutogramApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 980, minHeight: 640)
                .frame(idealWidth: 1320, idealHeight: 860)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1320, height: 860)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registers the in-process NSServices provider (Finder Quick Action).
        NSApp.servicesProvider = ServicesProvider()

        // Flush the system services cache so Finder sees the registered Quick Action.
        let pbs = Process()
        pbs.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        pbs.arguments = ["-update"]
        try? pbs.run()
    }
}
