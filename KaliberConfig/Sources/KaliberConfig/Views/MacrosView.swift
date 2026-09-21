import SwiftUI
import AppKit
import KaliberHID

struct MacrosView: View {
    @ObservedObject var model: MouseModel
    @State private var slot = 1

    var body: some View {
        HSplitView {
            List(1...Korona.macroSlots, id: \.self, selection: Binding(get: { slot }, set: { slot = $0 ?? 1 })) { s in
                let m = model.matrix?.macro(slot: s)
                VStack(alignment: .leading) {
                    Text("Slot \(s)")
                    Text(m == nil ? "Empty" : "\(m!.events.count) events, ×\(m!.repeatCount)").font(.caption).foregroundStyle(.secondary)
                }.tag(s)
            }
            .frame(minWidth: 140, maxWidth: 180)
            MacroEditor(model: model, slot: slot).id(slot)
                .frame(minWidth: 380)
        }
    }
}

struct MacroEditor: View {
    @ObservedObject var model: MouseModel
    let slot: Int
    @State private var macro: Macro
    @State private var recording = false
    @State private var monitor: Any?
    @State private var lastEvent: Date?
    @State private var pressedFlags: NSEvent.ModifierFlags = []

    init(model: MouseModel, slot: Int) {
        self.model = model; self.slot = slot
        _macro = State(initialValue: model.matrix?.macro(slot: slot) ?? Macro())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Macro slot \(slot)").font(.headline)
                Spacer()
                Button(recording ? "Stop recording" : "Record") { recording ? stop() : start() }
                    .buttonStyle(.borderedProminent).tint(recording ? .red : .accentColor)
                Button("Clear") { macro = Macro(); store() }.disabled(macro.events.isEmpty)
            }
            if recording {
                Text("Recording keys and mouse buttons — press keys now. Stop when done.").font(.caption).foregroundStyle(.red)
            }
            Stepper("Repeat count: \(macro.repeatCount)", value: $macro.repeatCount, in: 1...255).onChange(of: macro.repeatCount) { _, _ in store() }
            List {
                HStack {
                    Text("Key").frame(width: 120, alignment: .leading)
                    Text("Action").frame(width: 110, alignment: .leading)
                    Text("Delay after (ms)")
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(macro.events.indices, id: \.self) { i in
                    HStack {
                        Text(HIDUsage.name(macro.events[i].usage)).frame(width: 120, alignment: .leading)
                        Picker("", selection: $macro.events[i].release) { Text("Press").tag(false); Text("Release").tag(true) }
                            .labelsHidden().frame(width: 110).onChange(of: macro.events[i].release) { _, _ in store() }
                        TextField("ms", value: $macro.events[i].delayMs, format: .number).frame(width: 80).onSubmit { store() }
                        Spacer()
                    }
                }
                .onDelete { idx in macro.events.remove(atOffsets: idx); store() }
            }
            HStack {
                Text("\(macro.events.count) events · \(usedBytes) / \(Korona.macroSlotSize - 3) bytes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Remove last") { _ = macro.events.popLast(); store() }.disabled(macro.events.isEmpty)
            }
        }
        .padding(.leading)
        .onDisappear { stop() }
    }

    private var usedBytes: Int { 2 + macro.events.reduce(0) { $0 + ($1.delayMs > 0x7F ? 4 : 2) } }

    private func store() {
        guard var x = model.matrix else { return }
        if macro.events.isEmpty { x.setMacro(nil, slot: slot) }
        else if !x.setMacro(macro, slot: slot) { model.lastError = "Macro too long for the 128-byte slot"; return }
        model.matrix = x
    }

    private func start() {
        recording = true; lastEvent = nil; pressedFlags = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { ev in
            handle(ev)
            return ev.type == .keyDown || ev.type == .keyUp || ev.type == .flagsChanged ? nil : ev
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        store()
    }

    private func add(usage: UInt8, release: Bool) {
        let now = Date()
        if let last = lastEvent, !macro.events.isEmpty {
            macro.events[macro.events.count - 1].delayMs = max(1, min(9999, Int(now.timeIntervalSince(last) * 1000)))
        }
        macro.events.append(MacroEvent(usage: usage, release: release, delayMs: 1))
        lastEvent = now
    }

    private func handle(_ ev: NSEvent) {
        switch ev.type {
        case .keyDown where !ev.isARepeat:
            if let u = HIDUsage.usageForMacKeyCode[ev.keyCode] { add(usage: u, release: false) }
        case .keyUp:
            if let u = HIDUsage.usageForMacKeyCode[ev.keyCode] { add(usage: u, release: true) }
        case .flagsChanged:
            let pairs: [(NSEvent.ModifierFlags, UInt8)] = [(.control, 0xE0), (.shift, 0xE1), (.option, 0xE2), (.command, 0xE3)]
            for (flag, usage) in pairs {
                let now = ev.modifierFlags.contains(flag), before = pressedFlags.contains(flag)
                if now != before { add(usage: usage, release: !now) }
            }
            pressedFlags = ev.modifierFlags.intersection([.control, .shift, .option, .command])
        case .leftMouseDown: add(usage: 0xF0, release: false)
        case .leftMouseUp: add(usage: 0xF0, release: true)
        case .rightMouseDown: add(usage: 0xF1, release: false)
        case .rightMouseUp: add(usage: 0xF1, release: true)
        case .otherMouseDown where ev.buttonNumber == 2: add(usage: 0xF2, release: false)
        case .otherMouseUp where ev.buttonNumber == 2: add(usage: 0xF2, release: true)
        default: break
        }
    }
}
