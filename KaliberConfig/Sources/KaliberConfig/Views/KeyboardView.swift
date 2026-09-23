import SwiftUI
import UniformTypeIdentifiers
import KaliberHID

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @State private var tab = 0
    @State private var showRestoreImporter = false
    @State private var showBackupExporter = false

    private var previewMode: KeyboardPreviewMode? {
        switch tab { case 0: return .lighting; case 1: return .keys; default: return nil }   // Macros/Advanced: no visual
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.info == nil {
                VStack(spacing: 12) {
                    Text(model.lastError ?? "Reading keyboard…").foregroundStyle(.secondary)
                    Button("Retry") { model.reload() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Picker("Profile", selection: $model.editingProfile) {
                        ForEach(0..<Hver.profileCount, id: \.self) { p in
                            Text("Profile \(p + 1)" + (model.info?.activeProfile == p ? " (active)" : "")).tag(p)
                        }
                    }.pickerStyle(.segmented).frame(maxWidth: 420)
                    Spacer()
                    Button("Make active") {
                        guard var i = model.info else { return }; i.activeProfile = model.editingProfile; model.info = i
                    }.disabled(model.info?.activeProfile == model.editingProfile)
                }
                .padding(.horizontal).padding(.top, 8)
                HStack(spacing: 0) {
                    TabView(selection: $tab) {
                        KeyboardLightingView(model: model).tabItem { Text("Lighting") }.tag(0)
                        KeyboardKeysView(model: model).tabItem { Text("Keys") }.tag(1)
                        KeyboardMacrosView(model: model).tabItem { Text("Macros") }.tag(2)
                        KeyboardAdvancedView(model: model).tabItem { Text("Advanced") }.tag(3)
                    }
                    .padding()
                    if let previewMode {
                        Divider()
                        KeyboardPreview(model: model, mode: previewMode)
                            .frame(width: 300)
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                Divider()
                HStack {
                    if let e = model.lastError { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(1) }
                    else { Text(model.status).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Button("Revert") { model.revert() }.disabled(!model.isDirty)
                    Button("Apply") { model.apply() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!model.isDirty || model.busy)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .navigationTitle("HVER PRO X")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Back up settings to file…") { showBackupExporter = true }
                    Button("Restore settings from file…") { showRestoreImporter = true }
                    Divider()
                    Button("Re-read from keyboard") { model.reload() }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .fileExporter(isPresented: $showBackupExporter, document: BackupDocument(data: (try? model.backupData()) ?? Data()),
                      contentType: .json, defaultFilename: "HVER-PRO-X-backup") { _ in }
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                do {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    try model.loadBackup(try Data(contentsOf: url))
                } catch { model.lastError = "Could not load backup: \(error.localizedDescription)" }
            }
        }
    }
}

struct KeyboardLightingView: View {
    @ObservedObject var model: KeyboardModel

    private var p: Int { model.editingProfile }
    private var profile: HverProfile? { model.profiles.indices.contains(p) ? model.profiles[p] : nil }
    private func update(_ f: (inout HverProfile) -> Void) {
        guard model.profiles.indices.contains(p) else { return }
        var x = model.profiles[p]; f(&x); model.profiles[p] = x
    }

    var body: some View {
        Form {
            if let pr = profile {
                Section("Effect") {
                    Picker("Pattern", selection: Binding(get: { pr.mode }, set: { m in update { $0.mode = m } })) {
                        ForEach(HverLightMode.allCases.filter { model.info?.availableModes.contains($0.rawValue) ?? true }) { Text($0.name).tag($0) }
                    }
                    if !HverLightMode.allCases.contains(where: { $0.rawValue == pr.modeRaw }) {
                        Text("Unknown pattern id \(pr.modeRaw) stored on the keyboard").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Brightness")
                        Slider(value: Binding(get: { Double(pr.brightness) }, set: { v in update { $0.brightness = Int(v) } }), in: 0...4, step: 1)
                        Text("\(pr.brightness)/4").monospacedDigit().frame(width: 32)
                    }
                    if pr.mode.hasSpeed {
                        Picker("Speed", selection: Binding(get: { 3 - pr.speedWire }, set: { v in update { $0.speedWire = 3 - v } })) {
                            Text("Slowest").tag(0); Text("Slow").tag(1); Text("Fast").tag(2); Text("Fastest").tag(3)
                        }.pickerStyle(.segmented)
                    }
                    if pr.mode.hasDirection {
                        Toggle("Reverse direction", isOn: Binding(get: { pr.reversed }, set: { v in update { $0.reversed = v } }))
                    }
                }
                if pr.mode == .custom {
                    Section("Per-key colours") {
                        KeyColourPainter(model: model, profile: p)
                    }
                }
                if pr.mode.hasColour {
                    Section("Colour") {
                        Toggle("Colourful (cycle through colours)", isOn: Binding(get: { pr.colourful }, set: { v in update { $0.colourful = v } }))
                        if !pr.colourful {
                            ColorPicker("Colour", selection: Binding(get: { Color(pr.colour) }, set: { c in update { $0.colour = RGB(c) } }), supportsOpacity: false)
                        }
                    }
                }
                Section("USB") {
                    Picker("Report rate", selection: Binding(get: { pr.reportRateIndex }, set: { v in update { $0.reportRateIndex = v } })) {
                        Text("125 Hz").tag(0); Text("250 Hz").tag(1); Text("500 Hz").tag(2); Text("1000 Hz").tag(3)
                    }.pickerStyle(.segmented)
                    Text("Report-rate mapping follows the original software's order and is not yet verified on hardware; the keyboard may re-enumerate after a change.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("Fn+PgUp / Fn+PgDn change brightness live but are not stored; values written here persist.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyboardKeysView: View {
    @ObservedObject var model: KeyboardModel
    @State private var filter = ""

    private var p: Int { model.editingProfile }
    private var map: HverKeyMap? { model.keyMaps.indices.contains(p) ? model.keyMaps[p] : nil }

    /// Indices of physical keys (entries that exist in the factory map), in matrix order.
    private var physical: [Int] {
        guard let d = model.defaultKeyMap else { return Array(0..<Hver.keyCount) }
        return (0..<Hver.keyCount).filter { d[$0] != .none }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filter keys", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Text("\(remapped) remapped").foregroundStyle(.secondary).font(.caption)
                Button("Restore factory layout") {
                    guard let d = model.defaultKeyMap, model.keyMaps.indices.contains(p) else { return }
                    model.keyMaps[p] = d
                }.disabled(model.defaultKeyMap == nil || map == model.defaultKeyMap)
            }
            List {
                ForEach(physical.filter { i in filter.isEmpty || (model.defaultKeyMap?[i].name ?? "").localizedCaseInsensitiveContains(filter) }, id: \.self) { i in
                    HStack {
                        Text(model.defaultKeyMap?[i].name ?? "Key \(i)").frame(width: 140, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        KeyAssignmentPicker(model: model, profile: p, index: i)
                        if let d = model.defaultKeyMap, let m = map, m[i] != d[i] {
                            Image(systemName: "pencil.circle.fill").foregroundStyle(.orange).help("Changed from factory")
                        }
                        Spacer()
                    }
                }
            }
            Text("Keys can become another key, a media function, a macro (define them on the Macros tab), a mouse button, or be disabled. Fn-layer functions are handled by the keyboard itself.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var remapped: Int {
        guard let d = model.defaultKeyMap, let m = map else { return 0 }
        return (0..<Hver.keyCount).filter { m[$0] != d[$0] }.count
    }
}

struct KeyboardAdvancedView: View {
    @ObservedObject var model: KeyboardModel
    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("USB ID", value: String(format: "%04X:%04X (SONiX)", Hver.vendorID, Hver.productID))
                LabeledContent("Active profile", value: "\((model.savedInfo?.activeProfile ?? 0) + 1)")
                LabeledContent("Patterns offered", value: (model.info?.availableModes ?? []).map(String.init).joined(separator: ", "))
            }
            Section("Raw blocks (as read)") {
                hexRow("Info (0x03)", model.savedInfo?.raw ?? [])
                ForEach(0..<model.savedProfiles.count, id: \.self) { i in hexRow("Profile \(i + 1) block", model.savedProfiles[i].raw) }
            }
        }
        .formStyle(.grouped)
    }
    private func hexRow(_ title: String, _ bytes: [UInt8]) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(bytes.map { String(format: "%02x", $0) }.joined(separator: " ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
}


/// Assigns one physical key: category + value, writing the 3-byte key-map entry.
struct KeyAssignmentPicker: View {
    @ObservedObject var model: KeyboardModel
    let profile: Int
    let index: Int

    enum Category: String, CaseIterable, Identifiable { case key = "Key", media = "Media", macro = "Macro", mouse = "Mouse", disabled = "Disabled"; var id: String { rawValue } }

    private var current: HverKey { model.keyMaps.indices.contains(profile) ? model.keyMaps[profile][index] : .none }
    private func set(_ k: HverKey) { if model.keyMaps.indices.contains(profile) { model.keyMaps[profile][index] = k } }

    private var category: Category {
        switch current {
        case .key, .modifier, .raw: return .key
        case .media: return .media
        case .macro: return .macro
        case .mouseButton, .mouseWheel: return .mouse
        case .none: return .disabled
        }
    }
    private static let usageChoices: [UInt8] = HIDUsage.names.keys.filter { $0 < 0xF0 }.sorted()

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { category }, set: { c in
                switch c {
                case .key: set(model.defaultKeyMap?[index] ?? .key(usage: 0x04))
                case .media: set(.media(usage: HverMediaKey.playPause.rawValue))
                case .macro: set(.macro(index: 0))
                case .mouse: set(.mouseButton(mask: 1))
                case .disabled: set(.none)
                }
            })) {
                ForEach(Category.allCases) { c in
                    // A macro key must point at an existing macro — offer the category only once one exists.
                    if c != .macro || !model.macros.isEmpty || category == .macro { Text(c.rawValue).tag(c) }
                }
            }.labelsHidden().frame(width: 95)

            switch category {
            case .key:
                Picker("", selection: Binding<UInt8>(get: { current.usage ?? 0 }, set: { set(HverKey.from(usage: $0)) })) {
                    ForEach(Self.usageChoices, id: \.self) { u in Text(HIDUsage.name(u)).tag(u) }
                    if case .raw = current { Text(current.name).tag(UInt8(0)) }
                }.labelsHidden().frame(width: 150)
            case .media:
                Picker("", selection: Binding<UInt16>(get: { if case .media(let u) = current { return u } else { return 0 } }, set: { set(.media(usage: $0)) })) {
                    ForEach(HverMediaKey.allCases) { m in Text(m.name).tag(m.rawValue) }
                }.labelsHidden().frame(width: 150)
            case .macro:
                Picker("", selection: Binding<Int>(get: { if case .macro(let i) = current { return i } else { return 0 } }, set: { set(.macro(index: $0)) })) {
                    ForEach(model.macros.indices, id: \.self) { i in Text(model.macros[i].name.isEmpty ? "Macro \(i + 1)" : model.macros[i].name).tag(i) }
                }.labelsHidden().frame(width: 150)
            case .mouse:
                Picker("", selection: Binding<Int>(get: {
                    switch current { case .mouseButton(let m): return Int(m); case .mouseWheel(let up): return up ? 10 : 11; default: return 1 }
                }, set: { v in set(v == 10 ? .mouseWheel(up: true) : v == 11 ? .mouseWheel(up: false) : .mouseButton(mask: UInt8(v))) })) {
                    Text("Left button").tag(1); Text("Right button").tag(2); Text("Middle button").tag(4); Text("Wheel up").tag(10); Text("Wheel down").tag(11)
                }.labelsHidden().frame(width: 150)
            case .disabled:
                Text("No function").foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            }
        }
    }
}
