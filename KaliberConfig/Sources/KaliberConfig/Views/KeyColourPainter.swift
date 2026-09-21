import SwiftUI
import KaliberHID

/// Per-key colour editor for the keyboard's "Custom" pattern: a 6×21 grid of keys, click to paint.
struct KeyColourPainter: View {
    @ObservedObject var model: KeyboardModel
    let profile: Int
    @State private var brush = Color.red

    private var set: Int { model.profiles.indices.contains(profile) ? model.profiles[profile].customSet : 0 }
    private var pageKey: String { KeyboardModel.pageKey(profile, set) }
    private var page: HverColourPage? { model.colourPages[pageKey] }

    private func update(_ f: (inout HverColourPage) -> Void) {
        guard var p = model.colourPages[pageKey] else { return }
        f(&p); model.colourPages[pageKey] = p
    }

    private func label(col: Int, row: Int) -> String {
        guard let d = model.defaultKeyMap else { return "" }
        let k = d[col * Hver.rows + row]
        if k == .none { return "" }
        let n = k.name
        let short: [String: String] = ["Backspace": "⌫", "Return": "↩", "Caps Lock": "Caps", "Print Screen": "PrtSc", "Scroll Lock": "ScrLk",
                                       "Page Up": "PgUp", "Page Down": "PgDn", "Num Lock": "Num", "Keypad Enter": "Ent", "Escape": "Esc",
                                       "Insert": "Ins", "Delete": "Del", "Space": "␣", "Right Ctrl": "RCtrl", "Right Shift": "RShift", "Right Alt": "RAlt", "Right Cmd": "RWin", "Cmd": "Win"]
        return (short[n] ?? n).replacingOccurrences(of: "Keypad ", with: "K")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Colour set", selection: Binding(get: { set }, set: { s in
                    guard model.profiles.indices.contains(profile) else { return }
                    model.profiles[profile].customSet = s; model.loadColourPage(profile: profile, set: s)
                })) { ForEach(0..<Hver.colourSets, id: \.self) { Text("Set \($0 + 1)").tag($0) } }.frame(width: 160)
                ColorPicker("Brush", selection: $brush, supportsOpacity: false)
                Button("Fill all") { update { $0.fill(RGB(brush)) } }
                Button("Clear all") { update { $0.fill(.black) } }
                Spacer()
                Text("Click or drag over keys to paint").font(.caption).foregroundStyle(.secondary)
            }
            if let p = page {
                let cell: CGFloat = 40, gap: CGFloat = 3
                VStack(spacing: gap) {
                    ForEach(0..<Hver.rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<Hver.columns, id: \.self) { col in
                                let lbl = label(col: col, row: row)
                                let c = p[col: col, row: row]
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(lbl.isEmpty ? Color.clear : Color(c))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(lbl.isEmpty ? Color.clear : Color.secondary.opacity(0.4)))
                                    .overlay(Text(lbl).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.5)
                                        .foregroundStyle(Int(c.r) + Int(c.g) + Int(c.b) > 380 ? .black : .white).padding(1))
                                    .frame(width: cell - gap, height: cell - gap)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { g in
                    let col = Int(g.location.x / cell), row = Int(g.location.y / cell)
                    guard (0..<Hver.columns).contains(col), (0..<Hver.rows).contains(row), !label(col: col, row: row).isEmpty else { return }
                    let b = RGB(brush)
                    if p[col: col, row: row] != b { update { $0[col: col, row: row] = b } }
                })
            } else {
                ProgressView("Reading colour set \(set + 1)…").onAppear { model.loadColourPage(profile: profile, set: set) }
            }
        }
        .onAppear { model.loadColourPage(profile: profile, set: set) }
    }
}
