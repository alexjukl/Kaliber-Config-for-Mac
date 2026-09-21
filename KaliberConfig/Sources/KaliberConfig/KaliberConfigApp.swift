import SwiftUI
import AppKit
import KaliberHID

@main
struct KaliberConfigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor: DeviceMonitor
    @StateObject private var profiles: ProfileManager

    init() {
        let m = DeviceMonitor()
        _monitor = StateObject(wrappedValue: m)
        _profiles = StateObject(wrappedValue: ProfileManager(monitor: m))
    }

    var body: some Scene {
        Window("Kaliber Config", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(profiles)
                .frame(minWidth: 820, minHeight: 540)
                .onReceive(profiles.$automationEnabled) { AppDelegate.keepRunning = $0 }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        // Menu-bar switcher appears while per-app automation is on.
        // Binding that only writes on a real change: MenuBarExtra sets isInserted on every render, and a
        // same-value write to an @Published property still publishes → endless re-render loop.
        MenuBarExtra("Kaliber Config", systemImage: "keyboard", isInserted: Binding(
            get: { profiles.automationEnabled },
            set: { if profiles.automationEnabled != $0 { profiles.automationEnabled = $0 } })) {
            MenuBarContent().environmentObject(profiles)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True while per-app automation is on: closing the window then leaves the app in the menu bar.
    static var keepRunning = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Developer aid: KALIBER_SNAPSHOT=<dir> renders the preview figures to PNG and quits.
        if let dir = ProcessInfo.processInfo.environment["KALIBER_SNAPSHOT"] {
            PreviewSnapshots.write(to: URL(fileURLWithPath: dir)); exit(0)
        }
        // When run as a bare SwiftPM executable there is no bundle to make us a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !Self.keepRunning }
}

@MainActor
enum PreviewSnapshots {
    static func write(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let actions: [ButtonAction] = [.leftClick, .rightClick, .middleClick, .back, .forward, .dpiUp, .macro(slot: 2, repeatMode: .count)]
        var callouts: [MouseFigure.Callout] = []
        for (i, a) in actions.enumerated() { callouts.append(MouseFigure.Callout(button: i + 1, text: a.name, changed: i == 6)) }
        var ring: [Color] = []
        for i in 0..<12 { ring.append(Color(hue: Double(i) / 12, saturation: 1, brightness: 1)) }
        let mouse = MouseFigure(ring: ring, callouts: callouts).frame(width: 250, height: 280).padding().background(Color(white: 0.95))
        var cells: [KeyboardFigure.Cell] = []
        for row in 0..<Hver.rows { for col in 0..<Hver.columns {
            let hl = row == 2 && col == 3
            let colour = Color(hue: Double(col) / 21, saturation: 1, brightness: 0.9)
            cells.append(KeyboardFigure.Cell(col: col, row: row, exists: true, color: colour, label: hl ? "Esc" : "", highlighted: hl)) } }
        let kb = KeyboardFigure(cells: cells).frame(width: 300).padding().background(Color(white: 0.95))
        for (name, view) in [("mouse", AnyView(mouse)), ("keyboard", AnyView(kb))] {
            let r = ImageRenderer(content: view); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
    }
}
