import SwiftUI
import AppKit
import KaliberHID

/// Categories shown in the button picker; each maps to one or more `ButtonAction`s.
enum ActionCategory: String, CaseIterable, Identifiable {
    case mouse = "Mouse", dpi = "DPI", key = "Keyboard key", combo = "Key combination", media = "Multimedia", macro = "Macro", fire = "Fire key", lighting = "Lighting", other = "Other"
    var id: String { rawValue }

    static func of(_ a: ButtonAction) -> ActionCategory {
        switch a {
        case .leftClick, .rightClick, .middleClick, .back, .forward, .doubleClick, .scrollUp: return .mouse
        case .dpiLoop, .dpiUp, .dpiDown: return .dpi
        case .key: return .key
        case .combo: return .combo
        case .media: return .media
        case .macro: return .macro
        case .fire: return .fire
        case .rgbToggle, .rgbNext: return .lighting
        case .disabled, .pollingSwitch, .modeSwitch, .raw: return .other
        }
    }

    var presets: [ButtonAction] {
        switch self {
        case .mouse: return [.leftClick, .rightClick, .middleClick, .back, .forward, .doubleClick, .scrollUp]
        case .dpi: return [.dpiLoop, .dpiUp, .dpiDown]
        case .lighting: return [.rgbToggle, .rgbNext]
        case .other: return [.disabled, .pollingSwitch, .modeSwitch]
        case .media: return MediaKey.allCases.map { .media($0) }
        case .key: return [.key(usage: 0x04, modifiers: 0)]
        case .combo: return [.combo(modifiers: 0x01, key1: 0x06, key2: 0)]
        case .macro: return [.macro(slot: 1, repeatMode: .count)]
        case .fire: return [.fire(rate: 5)]
        }
    }
}

struct ButtonsView: View {
    @ObservedObject var model: MouseModel
    static let buttonNames = ["Left button", "Right button", "Scroll wheel click", "Side button (rear, Back)", "Side button (front, Forward)", "Top button (front, DPI +)", "Top button (rear, DPI −)"]

    var body: some View {
        Form {
            Section("Button assignments") {
                ForEach(1...Korona.buttonCount, id: \.self) { b in
                    ButtonRow(model: model, button: b)
                }
            }
            Section {
                Text("At least one button should stay a left click. “Polling rate switch” and “Mode switch” are exposed by the original software but could not be verified on this firmware.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ButtonRow: View {
    @ObservedObject var model: MouseModel
    let button: Int
    @State private var editing = false

    private var action: ButtonAction { model.matrix?.action(mode: 1, button: button) ?? .disabled }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(ButtonsView.buttonNames[button - 1])
                Text(action.name).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change…") { editing = true }
        }
        .popover(isPresented: $editing, arrowEdge: .trailing) {
            ActionEditor(model: model, action: action) { new in
                guard var x = model.matrix else { return }
                x.set(new, mode: 1, button: button); model.matrix = x
            }
            .frame(width: 380)
            .padding()
        }
    }
}

struct ActionEditor: View {
    @ObservedObject var model: MouseModel
    let onChange: (ButtonAction) -> Void
    @State private var category: ActionCategory
    @State private var action: ButtonAction
    @State private var fireRate: Double
    @State private var macroSlot: Int
    @State private var macroMode: MacroRepeat

    init(model: MouseModel, action: ButtonAction, onChange: @escaping (ButtonAction) -> Void) {
        self.model = model; self.onChange = onChange
        _category = State(initialValue: ActionCategory.of(action))
        _action = State(initialValue: action)
        if case .fire(let r) = action { _fireRate = State(initialValue: Double(r)) } else { _fireRate = State(initialValue: 5) }
        if case .macro(let s, let m) = action { _macroSlot = State(initialValue: s); _macroMode = State(initialValue: m) }
        else { _macroSlot = State(initialValue: 1); _macroMode = State(initialValue: .count) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Function", selection: $category) { ForEach(ActionCategory.allCases) { Text($0.rawValue).tag($0) } }
                .onChange(of: category) { _, c in if ActionCategory.of(action) != c { set(c.presets[0]) } }

            switch category {
            case .mouse, .dpi, .lighting, .other, .media:
                Picker("Action", selection: Binding(get: { action }, set: { set($0) })) {
                    ForEach(category.presets, id: \.self) { Text($0.name).tag($0) }
                }
            case .key:
                KeyCaptureField(mode: .single, action: action) { set($0) }
                Text("Click the field, then press the key (with modifiers if wanted).").font(.caption).foregroundStyle(.secondary)
            case .combo:
                KeyCaptureField(mode: .combo, action: action) { set($0) }
                Text("Click the field, hold modifiers and press up to two keys.").font(.caption).foregroundStyle(.secondary)
            case .fire:
                HStack { Text("Rate"); Slider(value: $fireRate, in: 1...15, step: 1) { _ in set(.fire(rate: UInt8(fireRate))) }; Text("\(Int(fireRate))") }
                Text("Repeats left clicks while held (rate code 1–15 as in the original software).").font(.caption).foregroundStyle(.secondary)
            case .macro:
                Picker("Macro slot", selection: $macroSlot) {
                    ForEach(1...Korona.macroSlots, id: \.self) { s in
                        Text("Slot \(s)" + (model.matrix?.macro(slot: s) == nil ? " (empty)" : "")).tag(s)
                    }
                }.onChange(of: macroSlot) { _, _ in set(.macro(slot: macroSlot, repeatMode: macroMode)) }
                Picker("Repeat", selection: $macroMode) { ForEach(MacroRepeat.allCases) { Text($0.name).tag($0) } }
                    .onChange(of: macroMode) { _, _ in set(.macro(slot: macroSlot, repeatMode: macroMode)) }
                Text("Record macros on the Macros tab.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Current: \(action.name)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func set(_ a: ButtonAction) { action = a; onChange(a) }
}

/// A focusable field that captures the next key press(es) and turns them into a `ButtonAction`.
struct KeyCaptureField: View {
    enum Mode { case single, combo }
    let mode: Mode
    let action: ButtonAction
    let onCapture: (ButtonAction) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var comboKeys: [UInt8] = []
    @State private var comboMods: UInt8 = 0

    var body: some View {
        HStack {
            Text(recording ? "Press keys…" : action.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(recording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(recording ? Color.accentColor : .clear))
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
            Button(recording ? "Stop" : "Record") { toggle() }
        }
        .onDisappear { stop() }
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true; comboKeys = []; comboMods = 0
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { ev in
            handle(ev); return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func handle(_ ev: NSEvent) {
        let mods = modifierMask(ev.modifierFlags)
        switch ev.type {
        case .keyDown:
            guard !ev.isARepeat, let usage = HIDUsage.usageForMacKeyCode[ev.keyCode] else { return }
            if mode == .single {
                onCapture(.key(usage: usage, modifiers: mods)); stop()
            } else {
                comboMods = mods
                if !comboKeys.contains(usage), comboKeys.count < 2 { comboKeys.append(usage) }
                onCapture(.combo(modifiers: comboMods, key1: comboKeys[0], key2: comboKeys.count > 1 ? comboKeys[1] : 0))
                if comboKeys.count == 2 { stop() }
            }
        case .keyUp:
            if mode == .combo, !comboKeys.isEmpty { stop() }
        case .flagsChanged:
            if mode == .combo { comboMods = mods; if !comboKeys.isEmpty { onCapture(.combo(modifiers: comboMods, key1: comboKeys[0], key2: comboKeys.count > 1 ? comboKeys[1] : 0)) } }
        default: break
        }
    }

    private func modifierMask(_ f: NSEvent.ModifierFlags) -> UInt8 {
        var m: UInt8 = 0
        if f.contains(.control) { m |= 0x01 }
        if f.contains(.shift) { m |= 0x02 }
        if f.contains(.option) { m |= 0x04 }
        if f.contains(.command) { m |= 0x08 }
        return m
    }
}
