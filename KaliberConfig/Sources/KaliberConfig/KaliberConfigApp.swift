import SwiftUI
import AppKit

@main
struct KaliberConfigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = DeviceMonitor()

    var body: some Scene {
        WindowGroup("Kaliber Config") {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When run as a bare SwiftPM executable there is no bundle to make us a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
