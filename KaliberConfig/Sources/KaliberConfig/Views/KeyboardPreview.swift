import SwiftUI
import KaliberHID

enum KeyboardPreviewMode { case lighting, keys }

/// A miniature HVER PRO X (the 6×21 matrix) rendered from the pending settings of the profile being edited.
struct KeyboardPreview: View {
    @ObservedObject var model: KeyboardModel
    let mode: KeyboardPreviewMode

    private var p: Int { model.editingProfile }
    private var profile: HverProfile? { model.profiles.indices.contains(p) ? model.profiles[p] : nil }

    var body: some View {
        VStack(spacing: 10) {
            Text(mode == .lighting ? "Lighting · Profile \(p + 1)" : "Key layout · Profile \(p + 1)").font(.headline)
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { ctx in
                KeyboardFigure(cells: cells(at: ctx.date.timeIntervalSinceReferenceDate))
            }
            Text(caption).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.isDirty { Label("Pending — press Apply", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
        }
        .padding()
        .onChange(of: profile?.mode == .custom ? profile?.customSet : nil) { _, set in
            if let set { model.loadColourPage(profile: p, set: set) }
        }
        .onAppear { if let pr = profile, pr.mode == .custom { model.loadColourPage(profile: p, set: pr.customSet) } }
    }

    private var animated: Bool {
        guard mode == .lighting, let pr = profile else { return false }
        if pr.mode == .custom { return false }
        if pr.mode == .fixedSingleColour { return pr.colourful }
        return pr.mode != .rainbowFixed || pr.colourful
    }

    private var caption: String {
        guard let pr = profile else { return "" }
        switch mode {
        case .lighting:
            var parts = [pr.mode.name, "brightness \(pr.brightness)/4"]
            if pr.mode.hasSpeed { parts.append(["slowest", "slow", "fast", "fastest"][max(0, min(3, 3 - pr.speedWire))]) }
            if pr.mode == .custom { parts.append("set \(pr.customSet + 1)") }
            return parts.joined(separator: " · ")
        case .keys:
            guard let d = model.defaultKeyMap, model.keyMaps.indices.contains(p) else { return "" }
            let n = (0..<Hver.keyCount).filter { model.keyMaps[p][$0] != d[$0] }.count
            return n == 0 ? "Factory layout" : "\(n) key\(n == 1 ? "" : "s") remapped (highlighted)"
        }
    }

    /// One cell per matrix position: fill colour, label, and whether it is highlighted (changed).
    private func cells(at t: TimeInterval) -> [KeyboardFigure.Cell] {
        var out: [KeyboardFigure.Cell] = []
        let d = model.defaultKeyMap
        for row in 0..<Hver.rows {
            for col in 0..<Hver.columns {
                let mi = col * Hver.rows + row
                let exists = d.map { $0[mi] != .none } ?? true
                var cell = KeyboardFigure.Cell(col: col, row: row, exists: exists, color: Color(white: 0.25), label: "", highlighted: false)
                if !exists { out.append(cell); continue }
                switch mode {
                case .lighting: cell.color = lightingColor(col: col, row: row, at: t)
                case .keys:
                    if model.keyMaps.indices.contains(p) {
                        let k = model.keyMaps[p][mi]
                        let changed = d.map { $0[mi] != k } ?? false
                        cell.highlighted = changed
                        cell.label = changed ? (k == .none ? "✕" : shortName(k.name)) : ""
                        cell.color = changed ? .orange : Color(white: 0.3)
                    }
                }
                out.append(cell)
            }
        }
        return out
    }

    private func shortName(_ n: String) -> String {
        let short: [String: String] = ["Backspace": "⌫", "Return": "↩", "Caps Lock": "Caps", "Space": "␣", "Escape": "Esc", "Delete": "Del", "Insert": "Ins",
                                       "Page Up": "PgUp", "Page Down": "PgDn", "Print Screen": "PrtSc", "Scroll Lock": "ScrLk", "Num Lock": "Num", "Cmd": "Win"]
        return short[n] ?? n.replacingOccurrences(of: "Keypad ", with: "K")
    }

    private func lightingColor(col: Int, row: Int, at t: TimeInterval) -> Color {
        guard let pr = profile else { return .gray }
        let bright = 0.15 + 0.85 * Double(pr.brightness) / 4
        let speed = [0.5, 1, 1.6, 2.4][max(0, min(3, 3 - pr.speedWire))]
        let dir: Double = pr.reversed ? -1 : 1
        let x = Double(col) / Double(Hver.columns), y = Double(row) / Double(Hver.rows)
        func rainbow(_ phase: Double) -> Color { Color(hue: ((phase).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: bright) }
        switch pr.mode {
        case .custom:
            let page = model.colourPages[KeyboardModel.pageKey(p, pr.customSet)]
            guard let c = page?[col: col, row: row] else { return Color(white: 0.25) }
            return Color(c).opacity(bright)
        case .fixedSingleColour:
            return pr.colourful ? rainbow(t * 0.1 * speed) : Color(pr.colour).opacity(bright)
        case .rainbowFixed:
            return pr.colourful ? rainbow(x) : Color(pr.colour).opacity(bright)
        case .rainbowBreathing:
            let b = 0.5 + 0.5 * sin(t * 1.5 * speed)
            return (pr.colourful ? rainbow(x) : Color(pr.colour)).opacity(bright * (0.2 + 0.8 * b))
        case .sevenColourCycle:
            return rainbow(floor(t * 0.7 * speed) / 7)
        case .rainbowRotation, .rainbowTwist:
            let ang = atan2(y - 0.5, x - 0.5) / (2 * .pi)
            return rainbow(ang + t * 0.15 * speed * dir)
        case .fallingRainbow, .rainbowRain, .rainbowEbbAndFlow:
            return rainbow(y * 0.8 - t * 0.2 * speed * dir)
        case .rainbowScan:
            let pos = (t * 0.25 * speed * dir).truncatingRemainder(dividingBy: 1)
            let dist = abs(((x - pos) + 1.5).truncatingRemainder(dividingBy: 1) - 0.5)
            return rainbow(x).opacity(max(0.1, 1 - dist * 4))
        case .rainbowRipple, .rainbowEruption:
            let r = hypot(x - 0.5, (y - 0.5) * 0.6)
            return rainbow(r * 1.5 - t * 0.2 * speed * dir)
        default:
            // reactive / wave-type effects: flowing rainbow across the keyboard
            return rainbow(x + t * 0.12 * speed * dir)
        }
    }
}

struct KeyboardFigure: View {
    struct Cell: Identifiable { let col: Int, row: Int, exists: Bool; var color: Color; var label: String; var highlighted: Bool
        var id: Int { row * Hver.columns + col } }
    let cells: [Cell]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 1.5
            let cw = (geo.size.width - gap * CGFloat(Hver.columns - 1)) / CGFloat(Hver.columns)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12))
                    .padding(-4)
                ForEach(cells) { c in
                    if c.exists {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(c.color)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(c.highlighted ? Color.white : .clear, lineWidth: 1))
                            .overlay(Text(c.label).font(.system(size: max(5, cw * 0.45))).minimumScaleFactor(0.4).lineLimit(1).foregroundStyle(.black))
                            .frame(width: cw, height: cw)
                            .position(x: cw / 2 + CGFloat(c.col) * (cw + gap), y: cw / 2 + CGFloat(c.row) * (cw + gap))
                    }
                }
            }
            .frame(height: cw * CGFloat(Hver.rows) + gap * CGFloat(Hver.rows - 1))
        }
        .aspectRatio(CGFloat(Hver.columns) / CGFloat(Hver.rows), contentMode: .fit)
        .padding(4)
    }
}
