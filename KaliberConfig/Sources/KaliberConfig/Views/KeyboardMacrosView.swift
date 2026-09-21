import SwiftUI
import AppKit
import KaliberHID

/// Macro list + editor for the keyboard (macros live on the keyboard, shared by the three profiles).
struct KeyboardMacrosView: View {
    @ObservedObject var model: KeyboardModel
    @State private var selection: Int? = 0

    var body: some View {
        HSplitView {
            VStack(spacing: 6) {
                List(selection: $selection) {
                    ForEach(model.macros.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Text(model.macros[i].name.isEmpty ? "Macro \(i + 1)" : model.macros[i].name)
                            Text("\(model.macros[i].events.count) events · ×\(model.macros[i].repeatCount)").font(.caption).foregroundStyle(.secondary)
                        }.tag(i)
                    }
                }
                HStack {
                    Button { model.macros.append(HverMacro(name: "Macro \(model.macros.count + 1)")); selection = model.macros.count - 1 } label: { Image(systemName: "plus") }
                    Button {
                        if let s = selection, model.macros.indices.contains(s) { model.macros.remove(at: s); reindexKeys(removed: s); selection = model.macros.isEmpty ? nil : min(s, model.macros.count - 1) }
                    } label: { Image(systemName: "minus") }.disabled(selection == nil || model.macros.isEmpty)
                    Spacer()
                    Text("\(model.macroAreaBytes) / \(model.macroCapacity) B").font(.caption).foregroundStyle(model.macroAreaBytes > model.macroCapacity ? .red : .secondary)
                }.padding(.horizontal, 4)
            }
            .frame(minWidth: 160, maxWidth: 220)
            if let s = selection, model.macros.indices.contains(s) {
                HverMacroEditor(model: model, index: s).id(s).frame(minWidth: 380)
            } else {
                ContentUnavailableView("No macro selected", systemImage: "list.bullet", description: Text("Add a macro with “+”, then assign it to a key on the Keys tab."))
                    .frame(minWidth: 380)
            }
        }
    }

    /// Key-map entries point at macros by index; keep them valid after a deletion.
    private func reindexKeys(removed: Int) {
        for p in model.keyMaps.indices {
            for i in 0..<Hver.keyCount {
                if case .macro(let idx) = model.keyMaps[p][i] {
                    if idx == removed { model.keyMaps[p][i] = model.defaultKeyMap?[i] ?? .none }
                    else if idx > removed { model.keyMaps[p][i] = .macro(index: idx - 1) }
                }
            }
        }
    }
}

struct HverMacroEditor: View {
    @ObservedObject var model: KeyboardModel
    let index: Int
    @State private var recording = false
    @State private var monitor: Any?
    @State private var lastEvent: Date?
    @State private var pressedFlags: NSEvent.ModifierFlags = []

    private var macro: Binding<HverMacro> {
        Binding(get: { model.macros.indices.contains(index) ? model.macros[index] : HverMacro() },
                set: { if model.macros.indices.contains(index) { model.macros[index] = $0 } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Name", text: macro.name).frame(maxWidth: 220)
                Spacer()
                Button(recording ? "Stop recording" : "Record") { recording ? stop() : start() }
                    .buttonStyle(.borderedProminent).tint(recording ? .red : .accentColor)
                Button("Clear") { macro.wrappedValue.events = [] }.disabled(macro.wrappedValue.events.isEmpty)
            }
            if recording { Text("Recording keys and mouse buttons — press keys now, then Stop.").font(.caption).foregroundStyle(.red) }
            Stepper("Repeat count: \(macro.wrappedValue.repeatCount)", value: macro.repeatCount, in: 1...255)
            List {
                HStack { Text("Event").frame(width: 150, alignment: .leading); Text("Action").frame(width: 110, alignment: .leading); Text("Delay before (ms)") }
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(macro.wrappedValue.events.indices, id: \.self) { i in
                    HStack {
                        Text(name(macro.wrappedValue.events[i].kind)).frame(width: 150, alignment: .leading)
                        Picker("", selection: macro.events[i].release) { Text("Press").tag(false); Text("Release").tag(true) }.labelsHidden().frame(width: 110)
                        TextField("ms", value: macro.events[i].delayMs, format: .number).frame(width: 80)
                        Spacer()
                    }
                }
                .onDelete { idx in macro.wrappedValue.events.remove(atOffsets: idx) }
            }
            HStack {
                Text("\(macro.wrappedValue.events.count) events · delays are stored in 10 ms steps").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Remove last") { _ = macro.wrappedValue.events.popLast() }.disabled(macro.wrappedValue.events.isEmpty)
            }
        }
        .padding(.leading)
        .onDisappear { stop() }
    }

    private func name(_ k: HverMacroEvent.Kind) -> String {
        switch k {
        case .key(let u): return HIDUsage.name(u)
        case .modifier(let b): return HIDUsage.name(0xE0 + UInt8(b.trailingZeroBitCount))
        case .consumer(let u): return HverMediaKey(rawValue: u)?.name ?? String(format: "Consumer 0x%X", u)
        case .mouseButton(let m): return m == 1 ? "Mouse left" : m == 2 ? "Mouse right" : "Mouse middle"
        case .mouseWheel(let up): return up ? "Wheel up" : "Wheel down"
        case .raw(let t, let p): return String(format: "raw type %d 0x%04X", t, p)
        }
    }

    private func start() {
        recording = true; lastEvent = nil; pressedFlags = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { ev in
            handle(ev)
            return ev.type == .keyDown || ev.type == .keyUp || ev.type == .flagsChanged ? nil : ev
        }
    }
    private func stop() { recording = false; if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }

    private func add(_ kind: HverMacroEvent.Kind, release: Bool) {
        let now = Date()
        let delay = lastEvent.map { max(10, min(40950, Int(now.timeIntervalSince($0) * 1000))) } ?? 10
        macro.wrappedValue.events.append(HverMacroEvent(kind: kind, release: release, delayMs: delay))
        lastEvent = now
    }

    private func handle(_ ev: NSEvent) {
        switch ev.type {
        case .keyDown where !ev.isARepeat: if let u = HIDUsage.usageForMacKeyCode[ev.keyCode] { add(.key(usage: u), release: false) }
        case .keyUp: if let u = HIDUsage.usageForMacKeyCode[ev.keyCode] { add(.key(usage: u), release: true) }
        case .flagsChanged:
            let pairs: [(NSEvent.ModifierFlags, UInt8)] = [(.control, 0x01), (.shift, 0x02), (.option, 0x04), (.command, 0x08)]
            for (flag, bit) in pairs {
                let now = ev.modifierFlags.contains(flag), before = pressedFlags.contains(flag)
                if now != before { add(.modifier(bit: bit), release: !now) }
            }
            pressedFlags = ev.modifierFlags.intersection([.control, .shift, .option, .command])
        case .leftMouseDown: add(.mouseButton(mask: 1), release: false)
        case .leftMouseUp: add(.mouseButton(mask: 1), release: true)
        case .rightMouseDown: add(.mouseButton(mask: 2), release: false)
        case .rightMouseUp: add(.mouseButton(mask: 2), release: true)
        case .otherMouseDown where ev.buttonNumber == 2: add(.mouseButton(mask: 4), release: false)
        case .otherMouseUp where ev.buttonNumber == 2: add(.mouseButton(mask: 4), release: true)
        default: break
        }
    }
}
