import SwiftUI
import UniformTypeIdentifiers
import KaliberHID

struct MouseView: View {
    @ObservedObject var model: MouseModel
    @State private var tab = 0
    @State private var showRestoreImporter = false
    @State private var showBackupExporter = false
    @State private var confirmFactory = false

    /// Tabs with a device visual get the preview pane; Macros/Advanced don't.
    private var previewMode: MousePreviewMode? {
        switch tab { case 0: return .dpi; case 1: return .lighting; case 2: return .buttons; default: return nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.general == nil {
                VStack(spacing: 12) {
                    Text(model.lastError ?? "Reading mouse…").foregroundStyle(.secondary)
                    Button("Retry") { model.reload() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    TabView(selection: $tab) {
                        DPIView(model: model).tabItem { Text("DPI & Polling") }.tag(0)
                        LightingView(model: model).tabItem { Text("Lighting") }.tag(1)
                        ButtonsView(model: model).tabItem { Text("Buttons") }.tag(2)
                        MacrosView(model: model).tabItem { Text("Macros") }.tag(3)
                        AdvancedView(model: model).tabItem { Text("Advanced") }.tag(4)
                    }
                    .padding()
                    if let previewMode {
                        Divider()
                        MousePreview(model: model, mode: previewMode)
                            .frame(width: 250)
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
        .navigationTitle("KORONA")
        .navigationSubtitle(model.firmware.isEmpty ? "" : "Firmware \(model.firmware)")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Back up settings to file…") { showBackupExporter = true }
                    Button("Restore settings from file…") { showRestoreImporter = true }
                    Divider()
                    Button("Load factory defaults") { confirmFactory = true }
                    Button("Re-read from mouse") { model.reload() }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .fileExporter(isPresented: $showBackupExporter, document: BackupDocument(data: (try? model.backupData()) ?? Data()),
                      contentType: .json, defaultFilename: "KORONA-backup") { _ in }
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                do {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    try model.loadBackup(try Data(contentsOf: url))
                } catch { model.lastError = "Could not load backup: \(error.localizedDescription)" }
            }
        }
        .confirmationDialog("Load factory defaults?", isPresented: $confirmFactory) {
            Button("Load defaults") { model.loadFactoryDefaults() }
        } message: { Text("This fills in IOGEAR's shipping settings. Nothing is written to the mouse until you press Apply.") }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - DPI

struct DPIView: View {
    @ObservedObject var model: MouseModel
    @State private var showExtended = false

    private var dpiChoices: [Int] { Korona.dpiTable.filter { showExtended || $0 <= Korona.nativeMaxDPI } }

    var body: some View {
        Form {
            Section {
                ForEach(0..<Korona.stageCount, id: \.self) { i in stageRow(i) }
            } header: {
                HStack {
                    Text("DPI stages")
                    Spacer()
                    Text("Live stage: \(model.liveDPILevel)").foregroundStyle(.secondary).font(.caption)
                }
            } footer: {
                Toggle("Show interpolated DPI above 5000 (sensor native max is 5000)", isOn: $showExtended).font(.caption)
            }
            Section("Polling rate") {
                Picker("Report rate", selection: rateBinding) {
                    ForEach(PollingRate.allCases) { r in Text("\(r.hz) Hz").tag(r) }
                }.pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private func stageRow(_ i: Int) -> some View {
        let enabled = Binding<Bool>(
            get: { model.general?.stages[i].enabled ?? false },
            set: { v in
                guard var g = model.general else { return }
                var s = g.stages
                if !v, s.filter(\.enabled).count <= 1 { return }   // firmware needs ≥1 stage
                s[i].enabled = v; if v, s[i].dpi == 0 { s[i].dpi = 800 }
                g.stages = s; model.general = g
            })
        let dpi = Binding<Int>(
            get: { model.general?.stages[i].dpi ?? 0 },
            set: { v in guard var g = model.general else { return }; var s = g.stages; s[i].dpi = v; g.stages = s; model.general = g })
        let color = Binding<DPIColor>(
            get: { model.general?.stages[i].color ?? .off },
            set: { v in guard var g = model.general else { return }; var s = g.stages; s[i].color = v; g.stages = s; model.general = g })
        return HStack {
            Toggle(isOn: enabled) { Text("Stage \(i + 1)").frame(width: 60, alignment: .leading) }
            Picker("", selection: dpi) {
                ForEach(dpiChoices, id: \.self) { Text("\($0)").tag($0) }
                if !dpiChoices.contains(dpi.wrappedValue) { Text("\(dpi.wrappedValue)").tag(dpi.wrappedValue) }
            }.labelsHidden().frame(width: 100).disabled(!enabled.wrappedValue)
            Text("DPI").foregroundStyle(.secondary)
            Spacer()
            Picker("Indicator", selection: color) {
                ForEach(DPIColor.allCases) { c in
                    HStack { Circle().fill(Color(c.rgb)).frame(width: 10, height: 10); Text(c.name) }.tag(c)
                }
            }.frame(width: 150).disabled(!enabled.wrappedValue)
            if model.liveDPILevel == i + 1 { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Currently active stage") }
        }
    }

    private var rateBinding: Binding<PollingRate> {
        Binding(get: { model.mode?.rate(mode: 1) ?? .hz500 },
                set: { r in guard var m = model.mode else { return }; for mode in 1...3 { m.setRate(r, mode: mode) }; model.mode = m })
    }
}

// MARK: - Lighting

struct LightingView: View {
    @ObservedObject var model: MouseModel

    var body: some View {
        Form {
            Section("Effect") {
                Picker("Mode", selection: modeBinding) {
                    ForEach(LEDMode.allCases) { m in Text(m.name).tag(m) }
                }
                if let mode = model.general?.ledMode {
                    if mode.hasSpeed {
                        Picker("Speed", selection: paramBinding) { Text("Slow").tag(1); Text("Medium").tag(2); Text("Fast").tag(3) }.pickerStyle(.segmented)
                    }
                    if mode.hasBrightness {
                        HStack { Text("Brightness"); Slider(value: brightnessBinding, in: 1...8, step: 1); Text("\(paramBinding.wrappedValue)/8").monospacedDigit().frame(width: 32) }
                    }
                    if mode.hasDirection {
                        Toggle("Reverse direction", isOn: reverseBinding)
                    }
                    if mode == .response {
                        Toggle("Random colours", isOn: reverseBinding)
                    }
                }
            }
            if let mode = model.general?.ledMode, mode.colorSlots > 0, !(mode == .response && (model.general?.ledReverse ?? false)) {
                Section(mode.colorSlots == 1 ? "Colour" : "Colours (\(model.general?.ledColorCount ?? 0) used)") {
                    if mode.colorSlots > 1 {
                        Stepper("Number of colours: \(model.general?.ledColorCount ?? 1)", value: colorCountBinding, in: 1...7)
                    }
                    let n = mode.colorSlots == 1 ? 1 : max(1, model.general?.ledColorCount ?? 1)
                    ForEach(0..<n, id: \.self) { i in
                        ColorPicker("Colour \(i + 1)", selection: colorBinding(i), supportsOpacity: false)
                    }
                }
            }
            Section {
                Text("Effects are rendered by the mouse; the DPI indicator colours are set on the DPI tab. Byte-level details: docs/PROTOCOL-mouse.md.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var modeBinding: Binding<LEDMode> {
        Binding(get: { model.general?.ledMode ?? .off },
                set: { m in
                    guard var g = model.general else { return }
                    let old = g.ledMode
                    g.ledMode = m
                    if m == .steady, old != .steady { g.ledParam = 8 }                 // full brightness by default
                    if m.hasSpeed, !old.hasSpeed || !(1...3).contains(g.ledParam) { g.ledParam = 2 }
                    if m.colorSlots > 1, g.ledColorCount == 0 { g.ledColorCount = 1 }
                    if !m.hasDirection, m != .response { g.ledReverse = false }
                    model.general = g })
    }
    private var paramBinding: Binding<Int> {
        Binding(get: { model.general?.ledParam ?? 1 }, set: { v in guard var g = model.general else { return }; g.ledParam = v; model.general = g })
    }
    private var brightnessBinding: Binding<Double> {
        Binding(get: { Double(model.general?.ledParam ?? 8) }, set: { v in guard var g = model.general else { return }; g.ledParam = Int(v); model.general = g })
    }
    private var reverseBinding: Binding<Bool> {
        Binding(get: { model.general?.ledReverse ?? false }, set: { v in guard var g = model.general else { return }; g.ledReverse = v; model.general = g })
    }
    private var colorCountBinding: Binding<Int> {
        Binding(get: { model.general?.ledColorCount ?? 1 }, set: { v in guard var g = model.general else { return }; g.ledColorCount = v; model.general = g })
    }
    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(get: { Color(model.general?.ledColors[i] ?? .black) },
                set: { c in guard var g = model.general else { return }; var cs = g.ledColors; cs[i] = RGB(c); g.ledColors = cs; model.general = g })
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255) }
}

extension RGB {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8(clamping: Int(ns.redComponent * 255 + 0.5)), UInt8(clamping: Int(ns.greenComponent * 255 + 0.5)), UInt8(clamping: Int(ns.blueComponent * 255 + 0.5)))
    }
}

// MARK: - Advanced

struct AdvancedView: View {
    @ObservedObject var model: MouseModel
    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Firmware", value: model.firmware)
                LabeledContent("Sensor", value: model.general?.sensorCode == 0xB ? "PixArt PMW3325 (code 0xB)" : "code \(model.general?.sensorCode ?? 0)")
                LabeledContent("USB ID", value: String(format: "%04X:%04X", Korona.vendorID, Korona.productID))
                LabeledContent("Live DPI stage", value: "\(model.liveDPILevel)")
            }
            Section("Raw reports (as the mouse reported them)") {
                hexRow("0x04 general", model.savedGeneral?.raw ?? [])
                hexRow("0x08 mode", model.savedMode?.raw ?? [])
                hexRow("0x06 matrix (buttons)", Array((model.savedMatrix?.raw ?? []).dropFirst(Korona.matrixOffset)))
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
