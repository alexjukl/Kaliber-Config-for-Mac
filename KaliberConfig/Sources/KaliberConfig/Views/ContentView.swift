import SwiftUI
import KaliberHID

enum SidebarItem: Hashable { case mouse, keyboard, profiles }

struct ContentView: View {
    @EnvironmentObject var monitor: DeviceMonitor
    @State private var selection: SidebarItem? = .mouse

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Devices") {
                    Label {
                        VStack(alignment: .leading) {
                            Text("KORONA mouse")
                            Text(monitor.mouse == nil ? "Not connected" : "Connected").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "computermouse.fill").foregroundStyle(monitor.mouse == nil ? .secondary : .primary) }
                    .tag(SidebarItem.mouse)
                    Label {
                        VStack(alignment: .leading) {
                            Text("HVER PRO X keyboard")
                            Text(monitor.keyboard == nil ? "Not connected" : "Connected").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "keyboard.fill").foregroundStyle(monitor.keyboard == nil ? .secondary : .primary) }
                    .tag(SidebarItem.keyboard)
                }
                Section {
                    Label("Profiles & Automation", systemImage: "rectangle.stack.badge.person.crop").tag(SidebarItem.profiles)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if monitor.access != .granted {
                PermissionView()
            } else {
                switch selection {
                case .profiles: ProfilesView()
                case .keyboard:
                    if let k = monitor.keyboard { KeyboardView(model: k).id(ObjectIdentifier(k)) }
                    else { NotConnectedView(name: "HVER PRO X keyboard") }
                default:
                    if let m = monitor.mouse { MouseView(model: m).id(ObjectIdentifier(m)) }
                    else { NotConnectedView(name: "KORONA mouse") }
                }
            }
        }
    }
}

struct NotConnectedView: View {
    let name: String
    var body: some View {
        ContentUnavailableView("\(name) not connected", systemImage: "cable.connector.slash",
                               description: Text("Plug the device into a USB port. It is detected automatically."))
    }
}

struct PermissionView: View {
    @EnvironmentObject var monitor: DeviceMonitor
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Input Monitoring permission needed").font(.title2.bold())
            Text("macOS treats the mouse's configuration channel as a keyboard device, so this app needs the Input Monitoring permission to talk to it. It never reads what you type.")
                .multilineTextAlignment(.center).frame(maxWidth: 460).foregroundStyle(.secondary)
            HStack {
                if monitor.access == .unknown {
                    Button("Request access…") { monitor.requestAccess() }.buttonStyle(.borderedProminent)
                }
                Button("Open System Settings") { NSWorkspace.shared.open(HIDAccess.settingsURL) }
            }
            if monitor.access == .denied {
                Text("Enable “Kaliber Config” under Privacy & Security → Input Monitoring, then come back here (or relaunch the app).")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                Button("Still denied after enabling? Reset permission and ask again") { monitor.resetAccess() }
                    .font(.callout)
                Text("Needed once after updating from a build with a different signature — macOS keeps the old record.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(40)
    }
}
