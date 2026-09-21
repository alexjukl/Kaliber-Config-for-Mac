import SwiftUI
import AppKit
import KaliberHID

/// Profiles & per-app automation screen.
struct ProfilesView: View {
    @EnvironmentObject var manager: ProfileManager
    @EnvironmentObject var monitor: DeviceMonitor
    @State private var newName = ""
    @State private var showAppPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Switch profiles automatically when the frontmost app changes", isOn: $manager.automationEnabled)
                if manager.automationEnabled {
                    LabeledContent("Frontmost app", value: manager.frontmostApp?.name ?? "—")
                    LabeledContent("Active profile", value: manager.profiles.first { $0.id == manager.activeProfileID }?.name ?? "—")
                }
                Text("The app keeps running in the menu bar while automation is on, so profiles switch even with this window closed.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Automation") }

            Section("Profiles") {
                if manager.profiles.isEmpty {
                    Text("No profiles yet. Set up the mouse and keyboard the way you like, apply, then save that as a profile.").foregroundStyle(.secondary)
                }
                ForEach($manager.profiles) { $p in
                    HStack {
                        VStack(alignment: .leading) {
                            TextField("Name", text: $p.name).textFieldStyle(.plain).font(.body.weight(.medium))
                            Text(p.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manager.activeProfileID == p.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Currently applied") }
                        Menu {
                            Button("Apply now") { manager.apply(p.id) }
                            Button("Update from current device settings") { manager.updateProfileFromCurrent(p.id) }
                            Divider()
                            Button("Delete", role: .destructive) { manager.deleteProfile(p.id) }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 30)
                    }
                }
                HStack {
                    TextField("New profile name", text: $newName).onSubmit(addProfile)
                    Button("Save current settings as profile", action: addProfile).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || (monitor.mouse == nil && monitor.keyboard == nil))
                }
                Picker("Default profile (apps without a rule)", selection: Binding(get: { manager.defaultProfileID }, set: { manager.defaultProfileID = $0; manager.evaluate(force: true) })) {
                    Text("None").tag(UUID?.none)
                    ForEach(manager.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            Section("Per-app rules") {
                if manager.rules.isEmpty { Text("No rules. Add an app and choose which profile it should use.").foregroundStyle(.secondary) }
                ForEach(manager.rules) { r in
                    HStack {
                        AppIcon(bundleID: r.bundleID)
                        VStack(alignment: .leading) { Text(r.appName); Text(r.bundleID).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Picker("", selection: Binding(get: { r.profileID }, set: { manager.setRule(bundleID: r.bundleID, appName: r.appName, profileID: $0) })) {
                            ForEach(manager.profiles) { Text($0.name).tag($0.id) }
                        }.labelsHidden().frame(width: 180)
                        Button { manager.setRule(bundleID: r.bundleID, appName: r.appName, profileID: nil) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Menu("Add running app…") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") { addRule(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!) }
                        }
                    }.frame(width: 180)
                    Button("Choose app from disk…") { chooseApp() }
                }.disabled(manager.profiles.isEmpty)
            }
            if !manager.status.isEmpty { Section { Text(manager.status).font(.caption).foregroundStyle(.secondary) } }
        }
        .formStyle(.grouped)
        .navigationTitle("Profiles & Automation")
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func addProfile() {
        let n = newName.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        manager.addProfileFromCurrent(named: n); newName = ""
    }

    private func addRule(bundleID: String, name: String) {
        guard let pid = manager.defaultProfileID ?? manager.profiles.first?.id else { return }
        manager.setRule(bundleID: bundleID, appName: name, profileID: pid)
    }

    private func chooseApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let b = Bundle(url: url), let bid = b.bundleIdentifier {
            let name = (b.infoDictionary?["CFBundleDisplayName"] as? String) ?? (b.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            addRule(bundleID: bid, name: name)
        }
    }
}

struct AppIcon: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
        } else { Image(systemName: "app.dashed").frame(width: 20, height: 20) }
    }
}

/// Menu-bar switcher.
struct MenuBarContent: View {
    @EnvironmentObject var manager: ProfileManager
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if manager.profiles.isEmpty { Text("No profiles saved yet") }
        ForEach(manager.profiles) { p in
            Button { manager.apply(p.id) } label: {
                if manager.activeProfileID == p.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
            }
        }
        Divider()
        Toggle("Switch automatically per app", isOn: $manager.automationEnabled)
        if let f = manager.frontmostApp, manager.automationEnabled { Text("Frontmost: \(f.name)").font(.caption) }
        Divider()
        Button("Open Kaliber Config") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        Button("Quit") { NSApp.terminate(nil) }
    }
}
