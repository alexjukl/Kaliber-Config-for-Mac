import Foundation
import AppKit
import Combine
import KaliberHID

/// A named snapshot of both devices: the mouse's three reports and which of the keyboard's
/// on-board profiles is active. Stored in ~/Library/Application Support/Kaliber Config/profiles.json.
struct AppProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mouseGeneral: [UInt8]?
    var mouseMode: [UInt8]?
    var mouseMatrix: [UInt8]?
    var keyboardProfile: Int?          // 0–2, nil = leave the keyboard alone

    var summary: String {
        var parts: [String] = []
        if let g = try? mouseGeneral.map({ try KoronaGeneral(raw: $0) }) {
            parts.append("Mouse: \(g.stages.filter(\.enabled).map { String($0.dpi) }.joined(separator: "/")) DPI, \(g.ledMode.name)")
        }
        if let k = keyboardProfile { parts.append("Keyboard: profile \(k + 1)") }
        return parts.isEmpty ? "Empty profile" : parts.joined(separator: " · ")
    }
}

/// "When this app is frontmost, use that profile."
struct AppRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var profileID: UUID
}

struct ProfileStoreData: Codable {
    var profiles: [AppProfile] = []
    var rules: [AppRule] = []
    var defaultProfileID: UUID?
    var automationEnabled = false
}

/// Profiles, per-app rules and the automatic switcher (the feature Synapse/G Hub users expect).
@MainActor
final class ProfileManager: ObservableObject {
    @Published var profiles: [AppProfile] = [] { didSet { save() } }
    @Published var rules: [AppRule] = [] { didSet { save() } }
    @Published var defaultProfileID: UUID? { didSet { save() } }
    @Published var automationEnabled = false { didSet { save(); if automationEnabled { evaluate(force: true) } } }
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var frontmostApp: (name: String, bundleID: String)?
    @Published private(set) var status = ""

    private unowned let monitor: DeviceMonitor
    private var observers: [Any] = []
    private var loading = true
    private var lastApplied: UUID?

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kaliber Config", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }()

    init(monitor: DeviceMonitor) {
        self.monitor = monitor
        if let data = try? Data(contentsOf: Self.fileURL), let d = try? JSONDecoder().decode(ProfileStoreData.self, from: data) {
            profiles = d.profiles; rules = d.rules; defaultProfileID = d.defaultProfileID; automationEnabled = d.automationEnabled
        }
        loading = false
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.frontmostChanged(app) }
        })
        // Devices arriving later should receive the current profile too.
        monitor.$mouse.dropFirst().sink { [weak self] m in if m != nil { Task { @MainActor in self?.evaluate(force: true) } } }.store(in: &cancellables)
        monitor.$keyboard.dropFirst().sink { [weak self] k in if k != nil { Task { @MainActor in self?.evaluate(force: true) } } }.store(in: &cancellables)
        if let app = NSWorkspace.shared.frontmostApplication { frontmostChanged(app) }
    }
    private var cancellables = Set<AnyCancellable>()

    private func save() {
        guard !loading else { return }
        let d = ProfileStoreData(profiles: profiles, rules: rules, defaultProfileID: defaultProfileID, automationEnabled: automationEnabled)
        if let data = try? JSONEncoder().encode(d) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    // MARK: Profiles

    /// Captures what is currently *on the devices* (applied state, not unsaved edits).
    func snapshotCurrent(named name: String) -> AppProfile {
        var p = AppProfile(name: name)
        if let m = monitor.mouse { p.mouseGeneral = m.savedGeneral?.raw; p.mouseMode = m.savedMode?.raw; p.mouseMatrix = m.savedMatrix?.raw }
        if let k = monitor.keyboard { p.keyboardProfile = k.savedInfo?.activeProfile }
        return p
    }

    func addProfileFromCurrent(named name: String) {
        let p = snapshotCurrent(named: name)
        profiles.append(p)
        if defaultProfileID == nil { defaultProfileID = p.id }
    }

    func updateProfileFromCurrent(_ id: UUID) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        var p = snapshotCurrent(named: profiles[i].name); p.id = id
        profiles[i] = p
    }

    func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        rules.removeAll { $0.profileID == id }
        if defaultProfileID == id { defaultProfileID = profiles.first?.id }
        if activeProfileID == id { activeProfileID = nil; lastApplied = nil }
    }

    /// Writes a profile to whichever devices are connected.
    func apply(_ id: UUID, reason: String = "manual") {
        guard let p = profiles.first(where: { $0.id == id }) else { return }
        var applied: [String] = []
        if let m = monitor.mouse, let g = p.mouseGeneral, let mo = p.mouseMode, let x = p.mouseMatrix {
            do {
                var general = try KoronaGeneral(raw: g)
                if let cur = m.savedGeneral { general.raw.replaceSubrange(52..<58, with: cur.raw[52..<58]) }
                let mode = try KoronaMode(raw: mo), matrix = try KoronaMatrix(raw: x)
                if general != m.savedGeneral { try m.mouse.write(general) }
                if mode.writePayload != m.savedMode?.writePayload { try m.mouse.write(mode) }
                if matrix != m.savedMatrix { try m.mouse.write(matrix) }
                m.reload(); applied.append("mouse")
            } catch { status = "Mouse: \(error.localizedDescription)" }
        }
        if let k = monitor.keyboard, let idx = p.keyboardProfile, var info = k.savedInfo, info.activeProfile != idx {
            do { info.activeProfile = idx; try k.keyboard.writeInfo(info); k.reload(); applied.append("keyboard") }
            catch { status = "Keyboard: \(error.localizedDescription)" }
        } else if monitor.keyboard != nil, p.keyboardProfile != nil { applied.append("keyboard") }
        activeProfileID = id; lastApplied = id
        status = "“\(p.name)” applied (\(reason))" + (applied.isEmpty ? " — no device connected" : "")
    }

    // MARK: Rules / automation

    func rule(for bundleID: String) -> AppRule? { rules.first { $0.bundleID == bundleID } }

    func setRule(bundleID: String, appName: String, profileID: UUID?) {
        rules.removeAll { $0.bundleID == bundleID }
        if let pid = profileID { rules.append(AppRule(bundleID: bundleID, appName: appName, profileID: pid)) }
        evaluate(force: true)
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app, let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier else { return }
        frontmostApp = (app.localizedName ?? bid, bid)
        evaluate()
    }

    /// Picks the profile for the frontmost app (rule → default) and applies it if it changed.
    func evaluate(force: Bool = false) {
        guard automationEnabled else { return }
        let target = frontmostApp.flatMap { rule(for: $0.bundleID)?.profileID } ?? defaultProfileID
        guard let target, force || target != lastApplied else { return }
        apply(target, reason: frontmostApp.map { "\($0.name) in front" } ?? "automatic")
    }
}
