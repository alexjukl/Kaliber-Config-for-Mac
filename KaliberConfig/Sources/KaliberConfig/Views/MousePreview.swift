import SwiftUI
import KaliberHID

/// Which tab of the mouse screen is showing; decides what the preview illustrates.
enum MousePreviewMode { case dpi, lighting, buttons }

/// A stylised top-down KORONA with its LED ring, drawn from the *pending* (unapplied) settings.
struct MousePreview: View {
    @ObservedObject var model: MouseModel
    let mode: MousePreviewMode

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.headline)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { ctx in
                MouseFigure(ring: ringColor(at: ctx.date.timeIntervalSinceReferenceDate), callouts: mode == .buttons ? callouts : [])
            }
            .frame(maxWidth: .infinity)
            Text(caption).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.isDirty { Label("Pending — press Apply", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
        }
        .padding()
    }

    private var title: String {
        switch mode { case .dpi: return "DPI indicator"; case .lighting: return "Lighting"; case .buttons: return "Button layout" }
    }

    private var animated: Bool {
        guard mode == .lighting, let g = model.general else { return false }
        return g.ledMode != .off && g.ledMode != .steady
    }

    private var caption: String {
        guard let g = model.general else { return "" }
        switch mode {
        case .dpi:
            let s = g.stages
            let live = max(1, min(Korona.stageCount, model.liveDPILevel))
            let st = s[live - 1]
            return "Stage \(live) of \(s.filter(\.enabled).count) enabled · \(st.dpi) DPI · \(st.color.name) indicator"
        case .lighting:
            let m = g.ledMode
            if m == .off { return "Lighting off" }
            var parts = [m.name]
            if m.hasSpeed { parts.append(["", "slow", "medium", "fast"][max(0, min(3, g.ledParam))]) }
            if m.hasBrightness { parts.append("brightness \(g.ledParam)/8") }
            return parts.joined(separator: " · ")
        case .buttons:
            return "Mode 1 assignments"
        }
    }

    private var callouts: [MouseFigure.Callout] {
        guard let x = model.matrix else { return [] }
        return (1...Korona.buttonCount).map { b in
            let a = x.action(mode: 1, button: b)
            let changed = model.savedMatrix.map { $0.action(mode: 1, button: b) != a } ?? false
            let short = a.name.replacingOccurrences(of: #" \(.*\)"#, with: "", options: .regularExpression)
            return MouseFigure.Callout(button: b, text: short, changed: changed)
        }
    }

    /// Colour of the LED ring for the current tab; `t` drives animations.
    private func ringColor(at t: TimeInterval) -> [Color] {
        guard let g = model.general else { return [.gray] }
        switch mode {
        case .buttons: return [Color.gray.opacity(0.35)]
        case .dpi:
            let live = max(1, min(Korona.stageCount, model.liveDPILevel))
            return [Color(g.stages[live - 1].color.rgb)]
        case .lighting:
            let colors = g.ledColors.map(Color.init)
            let speed = Double([0.5, 0.5, 1, 2][max(0, min(3, g.ledParam))])
            switch g.ledMode {
            case .off: return [Color.black.opacity(0.85)]
            case .steady: return [Color(g.ledColors[0]).opacity(0.25 + 0.75 * Double(max(1, min(8, g.ledParam))) / 8)]
            case .colorfulSteady: return (0..<7).map { Color(hue: Double($0) / 7, saturation: 1, brightness: 1) }
            case .colorfulStreaming, .streaming, .wave, .neon, .trailing:
                let phase = (t * 0.25 * speed * (g.ledReverse ? -1 : 1)).truncatingRemainder(dividingBy: 1)
                return (0..<12).map { Color(hue: (Double($0) / 12 + phase).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1) }
            case .breathing:
                let n = max(1, min(7, g.ledColorCount))
                let cycle = t * 0.4 * speed
                let i = Int(cycle) % n
                let b = 0.15 + 0.85 * (0.5 + 0.5 * sin(cycle * 2 * .pi))
                return [colors[i].opacity(b)]
            case .tail, .flicker, .response:
                let b = 0.2 + 0.8 * (0.5 + 0.5 * sin(t * 3 * speed))
                let c = g.ledReverse && g.ledMode == .response ? Color(hue: (t * 0.2).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1) : colors[0]
                return [c.opacity(b)]
            }
        }
    }
}

/// The mouse drawing. `ring` with one colour paints the LED ring solid; several colours paint a top→bottom gradient.
struct MouseFigure: View {
    struct Callout: Identifiable { let button: Int; let text: String; let changed: Bool; var id: Int { button } }
    let ring: [Color]
    let callouts: [Callout]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bodyRect = CGRect(x: w * 0.30, y: h * 0.06, width: w * 0.40, height: h * 0.88)
            ZStack {
                // LED ring around the base
                mouseShape(bodyRect.insetBy(dx: -w * 0.02, dy: -h * 0.015))
                    .fill(ringFill)
                    .shadow(color: (ring.first ?? .clear).opacity(0.7), radius: 10)
                mouseShape(bodyRect).fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
                // button split + wheel
                Path { p in p.move(to: CGPoint(x: bodyRect.midX, y: bodyRect.minY)); p.addLine(to: CGPoint(x: bodyRect.midX, y: bodyRect.minY + bodyRect.height * 0.42)) }
                    .stroke(Color.black.opacity(0.6), lineWidth: 1.5)
                Path { p in p.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + bodyRect.height * 0.42)); p.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + bodyRect.height * 0.42)) }
                    .stroke(Color.black.opacity(0.6), lineWidth: 1.5)
                // scroll wheel + DPI buttons: dark caps with the LED colour glowing around them
                let wheel = CGRect(x: bodyRect.midX - bodyRect.width * 0.06, y: bodyRect.minY + bodyRect.height * 0.06, width: bodyRect.width * 0.12, height: bodyRect.height * 0.16)
                let dpiRects = (0..<2).map { i in CGRect(x: bodyRect.midX - bodyRect.width * 0.06, y: bodyRect.minY + bodyRect.height * (0.245 + 0.07 * CGFloat(i)), width: bodyRect.width * 0.12, height: bodyRect.height * 0.05) }
                Path { p in
                    p.addRoundedRect(in: wheel.insetBy(dx: -2, dy: -2), cornerSize: CGSize(width: 4, height: 4))
                    for r in dpiRects { p.addRoundedRect(in: r.insetBy(dx: -2, dy: -2), cornerSize: CGSize(width: 3, height: 3)) }
                }
                .fill(ringFill)
                .shadow(color: (ring.first ?? .clear).opacity(0.5), radius: 4)
                Path { p in
                    p.addRoundedRect(in: wheel, cornerSize: CGSize(width: 3, height: 3))
                    for r in dpiRects { p.addRoundedRect(in: r, cornerSize: CGSize(width: 2, height: 2)) }
                }
                .fill(Color(white: 0.16))
                // side buttons (left side)
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.30))
                        .frame(width: bodyRect.width * 0.06, height: bodyRect.height * 0.10)
                        .position(x: bodyRect.minX + bodyRect.width * 0.03, y: bodyRect.minY + bodyRect.height * (0.40 + 0.12 * CGFloat(i)))
                }
                // callouts
                ForEach(callouts) { c in
                    let anchor = anchorPoint(for: c.button, in: bodyRect)
                    let left = c.button == 4 || c.button == 5 || c.button == 1
                    let labelX = left ? w * 0.13 : w * 0.87
                    Path { p in p.move(to: anchor); p.addLine(to: CGPoint(x: labelX + (left ? w * 0.10 : -w * 0.10), y: anchor.y)) }
                        .stroke(c.changed ? Color.orange : Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    Text(c.text).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center)
                        .foregroundStyle(c.changed ? .orange : .primary)
                        .frame(width: w * 0.24).position(x: labelX, y: anchor.y)
                    Circle().fill(c.changed ? Color.orange : Color.secondary).frame(width: 4, height: 4).position(anchor)
                }
            }
        }
        .aspectRatio(0.9, contentMode: .fit)
    }

    /// Colours run top→bottom over the whole figure, so the ring's left/right edges, the wheel and the DPI
    /// buttons all share the colour of their horizontal line (as on the real mouse).
    private var ringFill: AnyShapeStyle {
        if ring.count <= 1 { return AnyShapeStyle(ring.first ?? .gray) }
        return AnyShapeStyle(LinearGradient(colors: ring, startPoint: .top, endPoint: .bottom))
    }

    private func anchorPoint(for button: Int, in r: CGRect) -> CGPoint {
        switch button {
        case 1: return CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.20)
        case 2: return CGPoint(x: r.maxX - r.width * 0.28, y: r.minY + r.height * 0.20)
        case 3: return CGPoint(x: r.midX + r.width * 0.08, y: r.minY + r.height * 0.14)
        case 4: return CGPoint(x: r.minX + r.width * 0.03, y: r.minY + r.height * 0.52)
        case 5: return CGPoint(x: r.minX + r.width * 0.03, y: r.minY + r.height * 0.40)
        case 6: return CGPoint(x: r.midX + r.width * 0.06, y: r.minY + r.height * 0.27)
        default: return CGPoint(x: r.midX + r.width * 0.06, y: r.minY + r.height * 0.34)
        }
    }

    /// A mouse outline: rounded top, slightly wider palm.
    private func mouseShape(_ r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.45), control1: CGPoint(x: r.maxX - r.width * 0.05, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.05), control2: CGPoint(x: r.maxX - r.width * 0.1, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.45), control1: CGPoint(x: r.minX + r.width * 0.1, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - r.height * 0.05))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + r.height * 0.15), control2: CGPoint(x: r.minX + r.width * 0.05, y: r.minY))
        p.closeSubpath()
        return p
    }
}
