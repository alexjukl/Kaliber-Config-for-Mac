import Foundation
import Combine
import KaliberHID

/// Editable state for a connected HVER PRO X: info block, the three profile blocks and their key maps.
@MainActor
final class KeyboardModel: ObservableObject {
    let keyboard: HverKeyboard

    @Published var info: HverInfo?
    @Published var profiles: [HverProfile] = []
    @Published var keyMaps: [HverKeyMap] = []
    @Published private(set) var savedInfo: HverInfo?
    @Published private(set) var savedProfiles: [HverProfile] = []
    @Published private(set) var savedKeyMaps: [HverKeyMap] = []
    @Published var defaultKeyMap: HverKeyMap?
    /// Per-key colour pages keyed by "profile.set"; only pages that were opened in the UI are loaded.
    @Published var colourPages: [String: HverColourPage] = [:]
    @Published private(set) var savedColourPages: [String: HverColourPage] = [:]
    @Published var editingProfile = 0

    @Published private(set) var status = ""
    @Published var lastError: String?
    @Published private(set) var busy = false

    init(device: HIDDevice) {
        keyboard = HverKeyboard(device: device)
        reload()
    }

    var isDirty: Bool { info != savedInfo || profiles != savedProfiles || keyMaps != savedKeyMaps || colourPages != savedColourPages }

    static func pageKey(_ profile: Int, _ set: Int) -> String { "\(profile).\(set)" }

    /// Loads the colour page for `profile`/`set` from the keyboard if it is not cached yet.
    func loadColourPage(profile: Int, set: Int) {
        let key = Self.pageKey(profile, set)
        guard colourPages[key] == nil else { return }
        do {
            let page = try keyboard.readColourPage(profile: profile, set: set)
            colourPages[key] = page; savedColourPages[key] = page
        } catch { lastError = error.localizedDescription }
    }

    func reload() {
        do {
            let i = try keyboard.readInfo()
            let ps = try (0..<Hver.profileCount).map { try keyboard.readProfile($0) }
            let ks = try (0..<Hver.profileCount).map { try keyboard.readKeyMap(profile: $0) }
            info = i; savedInfo = i
            profiles = ps; savedProfiles = ps
            keyMaps = ks; savedKeyMaps = ks
            colourPages = [:]; savedColourPages = [:]
            editingProfile = i.activeProfile
            for (idx, pr) in ps.enumerated() where pr.mode == .custom { loadColourPage(profile: idx, set: pr.customSet) }
            if defaultKeyMap == nil { defaultKeyMap = try? keyboard.readDefaultKeyMap() }
            lastError = nil
            status = "Read from keyboard (active profile \(i.activeProfile + 1))"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revert() { info = savedInfo; profiles = savedProfiles; keyMaps = savedKeyMaps; colourPages = savedColourPages; status = "Changes discarded" }

    func apply() {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            for p in 0..<Hver.profileCount where profiles.indices.contains(p) {
                if profiles[p] != savedProfiles[p] { try keyboard.writeProfile(profiles[p], index: p); savedProfiles[p] = profiles[p] }
                if keyMaps[p] != savedKeyMaps[p] { try keyboard.writeKeyMap(keyMaps[p], profile: p); savedKeyMaps[p] = keyMaps[p] }
            }
            for (key, page) in colourPages where page != savedColourPages[key] {
                let parts = key.split(separator: ".").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                try keyboard.writeColourPage(page, profile: parts[0], set: parts[1]); savedColourPages[key] = page
            }
            if let i = info, i != savedInfo { try keyboard.writeInfo(i); savedInfo = try keyboard.readInfo(); info = savedInfo }
            status = "Applied to keyboard"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Backup / restore

    struct Backup: Codable {
        var version = 1
        var date: Date
        var info: [UInt8]
        var profiles: [[UInt8]]
        var keyMaps: [[UInt8]]
        var colourPages: [String: [UInt8]]? = nil
    }

    func backupData() throws -> Data {
        guard let i = savedInfo else { throw HIDError.deviceGone }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        return try enc.encode(Backup(date: Date(), info: i.raw, profiles: savedProfiles.map(\.raw), keyMaps: savedKeyMaps.map(\.raw), colourPages: savedColourPages.mapValues(\.raw)))
    }

    func loadBackup(_ data: Data) throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(Backup.self, from: data)
        var i = try HverInfo(raw: b.info)
        if let cur = info { i.raw.replaceSubrange(0..<10, with: cur.raw[0..<10]) }   // keep this unit's identity bytes
        info = i
        profiles = try b.profiles.map { try HverProfile(raw: $0) }
        keyMaps = try b.keyMaps.map { try HverKeyMap(raw: $0) }
        for (k, v) in b.colourPages ?? [:] { colourPages[k] = try HverColourPage(raw: v) }
        status = "Backup loaded — press Apply to write it to the keyboard"
    }
}
