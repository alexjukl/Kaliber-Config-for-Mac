import Foundation

/// Protocol constants for the Kaliber Gaming KORONA (GME631), Sinowealth 258A:1007, FwProtocol 7.
/// See docs/PROTOCOL-mouse.md.
public enum Korona {
    public static let vendorID = 0x258A
    public static let productID = 0x1007
    public static let vendorUsagePage = 0xFF00

    public static let generalReport: UInt8 = 0x04
    public static let modeReport: UInt8 = 0x08
    public static let matrixReport: UInt8 = 0x06
    public static let notifyReport: UInt8 = 0x07

    public static let generalLength = 58
    public static let modeLength = 8
    public static let matrixLength = 1144

    public static let stageCount = 8
    public static let buttonCount = 7        // physical buttons (Cfg.ini KM=14)
    public static let matrixButtons = 10     // slots per mode in the matrix
    public static let modeCount = 3
    public static let macroSlots = 8
    public static let macroSlotSize = 128
    public static let matrixOffset = 1024

    /// DPI values selectable in the vendor UI (Cfg.ini DPISET). Wire code = index + 1.
    public static let dpiTable: [Int] = Array(stride(from: 200, through: 5000, by: 100)) + Array(stride(from: 5500, through: 10000, by: 500))
    /// Sensor spec maximum for the PMW3325 in this mouse.
    public static let nativeMaxDPI = 5000

    public static func dpiCode(for dpi: Int) -> UInt8 {
        if let i = dpiTable.firstIndex(of: dpi) { return UInt8(i + 1) }
        // nearest entry
        let nearest = dpiTable.min { abs($0 - dpi) < abs($1 - dpi) } ?? 400
        return UInt8((dpiTable.firstIndex(of: nearest) ?? 3) + 1)
    }

    public static func dpi(forCode code: UInt8) -> Int {
        let i = Int(code & 0x7F) - 1
        return dpiTable.indices.contains(i) ? dpiTable[i] : 0
    }
}

public struct RGB: Equatable, Hashable, Codable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let black = RGB(0, 0, 0)
}

public enum LEDMode: Int, CaseIterable, Codable, Sendable, Identifiable {
    case off = 0
    case colorfulStreaming = 1, steady, breathing, tail, neon, colorfulSteady, flicker, response, streaming, wave, trailing

    public var id: Int { rawValue }
    public var name: String {
        switch self {
        case .off: return "Off"
        case .colorfulStreaming: return "Colorful Streaming"
        case .steady: return "Steady"
        case .breathing: return "Breathing"
        case .tail: return "Tail"
        case .neon: return "Neon"
        case .colorfulSteady: return "Colorful Steady"
        case .flicker: return "Flicker"
        case .response: return "Response"
        case .streaming: return "Streaming"
        case .wave: return "Wave"
        case .trailing: return "Trailing"
        }
    }
    /// Number of user colours the vendor UI exposes for this mode (0 = fixed palette).
    public var colorSlots: Int {
        switch self {
        case .steady: return 1
        case .breathing, .response: return 7
        case .tail, .flicker, .trailing, .wave: return 1
        default: return 0
        }
    }
    public var hasSpeed: Bool { self != .off && self != .steady && self != .colorfulSteady }
    public var hasBrightness: Bool { self == .steady }
    public var hasDirection: Bool { self == .colorfulStreaming || self == .streaming }
}

public enum PollingRate: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case hz125 = 1, hz250 = 2, hz500 = 3, hz1000 = 4
    public var id: UInt8 { rawValue }
    public var hz: Int { [125, 250, 500, 1000][Int(rawValue) - 1] }
}

/// Per-stage DPI indicator colour codes understood by the firmware.
public enum DPIColor: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case off = 0, red, green, blue, cyan, yellow, magenta, white
    public var id: UInt8 { rawValue }
    public var name: String { ["Off", "Red", "Green", "Blue", "Cyan", "Yellow", "Magenta", "White"][Int(rawValue)] }
    public var rgb: RGB {
        switch self {
        case .off: return .black
        case .red: return RGB(255, 0, 0)
        case .green: return RGB(0, 255, 0)
        case .blue: return RGB(0, 0, 255)
        case .cyan: return RGB(0, 255, 255)
        case .yellow: return RGB(255, 255, 0)
        case .magenta: return RGB(255, 0, 255)
        case .white: return RGB(255, 255, 255)
        }
    }
}

public struct DPIStage: Equatable, Codable, Sendable {
    public var dpi: Int
    public var enabled: Bool
    public var color: DPIColor
    public init(dpi: Int, enabled: Bool, color: DPIColor) { self.dpi = dpi; self.enabled = enabled; self.color = color }
}

// MARK: - Report 0x04

/// The 58-byte "general data" block. All unknown bytes are preserved verbatim in `raw`.
public struct KoronaGeneral: Equatable, Codable, Sendable {
    public var raw: [UInt8]

    public init(raw: [UInt8]) throws {
        guard raw.count == Korona.generalLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }

    public var sensorCode: Int { Int(raw[2] >> 4) }
    public var firmware: String { String(bytes: raw[52..<58], encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "" }
    public var xyIndependent: Bool { raw[2] & 1 != 0 }
    /// Mode number the host last wrote (1–3); not reliably live.
    public var hostMode: Int { Int(raw[1] >> 4) }

    public var stages: [DPIStage] {
        get {
            (0..<Korona.stageCount).map { i in
                let v = raw[4 + i]
                return DPIStage(dpi: Korona.dpi(forCode: v), enabled: v & 0x80 == 0 && v & 0x7F != 0, color: DPIColor(rawValue: raw[43 + i]) ?? .off)
            }
        }
        set {
            precondition(newValue.count == Korona.stageCount)
            var enabled = 0
            for (i, s) in newValue.enumerated() {
                raw[4 + i] = s.dpi == 0 ? 0x80 : Korona.dpiCode(for: s.dpi) | (s.enabled ? 0 : 0x80)
                raw[43 + i] = s.color.rawValue
                if s.enabled { enabled += 1 }
            }
            for i in Korona.stageCount..<16 { raw[4 + i] = 0x80 }   // Y slots unused (XY locked)
            raw[2] &= 0xF0                                          // XY independent off
            raw[1] = (raw[1] & 0xF0) | UInt8(enabled & 0x0F)
        }
    }

    public var ledMode: LEDMode {
        get { LEDMode(rawValue: Int(raw[20] >> 4)) ?? .off }
        set {
            raw[20] = (UInt8(newValue.rawValue) << 4) | (raw[20] & 0x0F)
            if newValue == .off { raw[51] |= 0x02 } else { raw[51] &= ~0x02 }
        }
    }
    /// Low nibble of byte 20: speed 1–3 for animated modes, brightness 1–8 for Steady.
    public var ledParam: Int {
        get { Int(raw[20] & 0x0F) }
        set { raw[20] = (raw[20] & 0xF0) | UInt8(clamping: max(0, min(15, newValue))) }
    }
    public var ledOff: Bool { raw[51] & 0x02 != 0 }
    /// Byte 21: colour count (Breathing/Response) or reverse-direction flag (streaming modes).
    public var ledAux: UInt8 { get { raw[21] } set { raw[21] = newValue } }
    public var ledReverse: Bool {
        get { raw[21] & 0x80 != 0 }
        set { if newValue { raw[21] |= 0x80 } else { raw[21] &= 0x7F } }
    }
    public var ledColorCount: Int {
        get { Int(raw[21] & 0x7F) }
        set { raw[21] = (raw[21] & 0x80) | UInt8(clamping: max(0, min(7, newValue))) }
    }
    public var ledColors: [RGB] {
        get { (0..<7).map { RGB(raw[22 + $0 * 3], raw[23 + $0 * 3], raw[24 + $0 * 3]) } }
        set {
            for (i, c) in newValue.prefix(7).enumerated() { raw[22 + i * 3] = c.r; raw[23 + i * 3] = c.g; raw[24 + i * 3] = c.b }
        }
    }
    public var flags: UInt8 { raw[51] }
}

// MARK: - Report 0x08

public struct KoronaMode: Equatable, Codable, Sendable {
    public var raw: [UInt8]
    public init(raw: [UInt8]) throws {
        guard raw.count == Korona.modeLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }
    public var activeMode: Int { get { Int(raw[0]) } set { raw[0] = UInt8(max(1, min(3, newValue))) } }
    public func rate(mode: Int) -> PollingRate { PollingRate(rawValue: raw[mode]) ?? .hz500 }
    public mutating func setRate(_ r: PollingRate, mode: Int) { raw[mode] = r.rawValue }
    /// Live DPI level (1-based) as reported by the firmware after the DPI buttons are used.
    public var liveDPILevel: Int { Int(raw[4]) }
    /// Bytes to send for a plain "set mode/rates" write (vendor leaves 4–7 zero).
    public var writePayload: [UInt8] { [raw[0], raw[1], raw[2], raw[3], 0, 0, 0, 0] }
}

// MARK: - Report 0x06: matrix + macros

public enum MediaKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case playPause, stop, next, previous, volumeUp, volumeDown, mute
    case mediaPlayer, explorer, email, calculator
    case search, home, browserBack, browserForward, browserStop, refresh, favorites
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .playPause: return "Play / Pause"; case .stop: return "Stop"; case .next: return "Next track"; case .previous: return "Previous track"
        case .volumeUp: return "Volume up"; case .volumeDown: return "Volume down"; case .mute: return "Mute"
        case .mediaPlayer: return "Media player"; case .explorer: return "File explorer"; case .email: return "E-mail"; case .calculator: return "Calculator"
        case .search: return "Search"; case .home: return "Home page"; case .browserBack: return "Browser back"; case .browserForward: return "Browser forward"
        case .browserStop: return "Browser stop"; case .refresh: return "Refresh"; case .favorites: return "Favorites"
        }
    }
    /// (consumer byte, launcher byte, browser byte)
    var masks: (UInt8, UInt8, UInt8) {
        switch self {
        case .next: return (0x01, 0, 0); case .previous: return (0x02, 0, 0); case .stop: return (0x04, 0, 0); case .playPause: return (0x08, 0, 0)
        case .mute: return (0x10, 0, 0); case .volumeUp: return (0x40, 0, 0); case .volumeDown: return (0x80, 0, 0)
        case .mediaPlayer: return (0, 0x01, 0); case .explorer: return (0, 0x02, 0); case .email: return (0, 0x10, 0); case .calculator: return (0, 0x20, 0)
        case .search: return (0, 0, 0x01); case .home: return (0, 0, 0x02); case .browserBack: return (0, 0, 0x04); case .browserForward: return (0, 0, 0x08)
        case .browserStop: return (0, 0, 0x10); case .refresh: return (0, 0, 0x20); case .favorites: return (0, 0, 0x40)
        }
    }
}

public enum MacroRepeat: Int, CaseIterable, Codable, Sendable, Identifiable {
    case count = 0x0190, untilReleased = 0x0290, untilAnyKey = 0x0490
    public var id: Int { rawValue }
    public var name: String {
        switch self { case .count: return "Repeat N times"; case .untilReleased: return "Repeat while held"; case .untilAnyKey: return "Repeat until any key" }
    }
}

/// What a mouse button does. `hardwareCode` is the matrix value with the low nibble cleared.
public enum ButtonAction: Equatable, Hashable, Codable, Sendable {
    case leftClick, rightClick, middleClick, back, forward
    case doubleClick, scrollUp
    case disabled
    case dpiLoop, dpiUp, dpiDown, rgbToggle
    case pollingSwitch, modeSwitch, rgbNext            // unverified on hardware
    case fire(rate: UInt8)
    case key(usage: UInt8, modifiers: UInt8)
    case combo(modifiers: UInt8, key1: UInt8, key2: UInt8)
    case media(MediaKey)
    case macro(slot: Int, repeatMode: MacroRepeat)
    case raw(UInt32)

    public var hardwareCode: UInt32 {
        switch self {
        case .leftClick: return 0xF010
        case .rightClick: return 0xF110
        case .middleClick: return 0xF210
        case .back: return 0xF310
        case .forward: return 0xF410
        case .doubleClick: return 0x0232_F020
        case .scrollUp: return 0x0130
        case .disabled: return 0x0150
        case .dpiLoop: return 0x0040
        case .dpiUp: return 0x2040
        case .dpiDown: return 0x4040
        case .rgbToggle: return 0x0250
        case .pollingSwitch: return 0x0650
        case .modeSwitch: return 0x0450
        case .rgbNext: return 0x0750
        case .fire(let rate): return (UInt32(rate & 0x0F) << 8) | 0x8040
        case .key(let usage, let mods): return 0x20 | (UInt32(usage) << 8) | (UInt32(mods) << 16)
        case .combo(let mods, let k1, let k2): return 0x60 | (UInt32(mods) << 8) | (UInt32(k1) << 16) | (UInt32(k2) << 24)
        case .media(let m): let (a, b, c) = m.masks; return 0x70 | (UInt32(a) << 8) | (UInt32(b) << 16) | (UInt32(c) << 24)
        case .macro(let slot, let mode): return UInt32(mode.rawValue) | (UInt32(slot & 0x0F) << 12)
        case .raw(let v): return v & 0xFFFF_FFF0
        }
    }

    public init(hardwareCode raw: UInt32) {
        let v = raw & 0xFFFF_FFF0
        let fixed: [UInt32: ButtonAction] = [
            0xF010: .leftClick, 0xF110: .rightClick, 0xF210: .middleClick, 0xF310: .back, 0xF410: .forward,
            0x0232_F020: .doubleClick, 0x0130: .scrollUp, 0x0150: .disabled, 0x0040: .dpiLoop, 0x2040: .dpiUp,
            0x4040: .dpiDown, 0x0250: .rgbToggle, 0x0650: .pollingSwitch, 0x0450: .modeSwitch, 0x0750: .rgbNext,
        ]
        if let a = fixed[v] { self = a; return }
        let b0 = UInt8(v & 0xF0), b1 = UInt8((v >> 8) & 0xFF), b2 = UInt8((v >> 16) & 0xFF), b3 = UInt8((v >> 24) & 0xFF)
        switch b0 {
        case 0x40 where b1 & 0x80 != 0: self = .fire(rate: b1 & 0x0F)
        case 0x20: self = .key(usage: b1, modifiers: b2)
        case 0x60: self = .combo(modifiers: b1, key1: b2, key2: b3)
        case 0x70:
            if let m = MediaKey.allCases.first(where: { $0.masks == (b1, b2, b3) }) { self = .media(m) } else { self = .raw(v) }
        case 0x90:
            let base = Int(v & 0x0FF0)
            if let mode = MacroRepeat(rawValue: base) { self = .macro(slot: Int((v >> 12) & 0x0F), repeatMode: mode) } else { self = .raw(v) }
        default: self = .raw(v)
        }
    }

    public var name: String {
        switch self {
        case .leftClick: return "Left click"; case .rightClick: return "Right click"; case .middleClick: return "Middle click"
        case .back: return "Back (button 4)"; case .forward: return "Forward (button 5)"
        case .doubleClick: return "Double click"; case .scrollUp: return "Scroll up"; case .disabled: return "Disabled"
        case .dpiLoop: return "DPI loop"; case .dpiUp: return "DPI +"; case .dpiDown: return "DPI −"; case .rgbToggle: return "RGB on / off"
        case .pollingSwitch: return "Polling rate switch"; case .modeSwitch: return "Mode switch"; case .rgbNext: return "Next RGB effect"
        case .fire(let r): return "Fire key (rate \(r))"
        case .key(let u, let m): return "Key \(HIDUsage.name(u))" + (m == 0 ? "" : " + " + HIDUsage.modifierNames(m))
        case .combo(let m, let k1, let k2): return "Combo " + ([HIDUsage.modifierNames(m), HIDUsage.name(k1), k2 == 0 ? "" : HIDUsage.name(k2)].filter { !$0.isEmpty }.joined(separator: " + "))
        case .media(let m): return m.name
        case .macro(let s, let mode): return "Macro \(s) (\(mode.name))"
        case .raw(let v): return String(format: "Raw 0x%08X", v)
        }
    }
}

public struct MacroEvent: Equatable, Codable, Sendable {
    public var usage: UInt8      // HID keyboard usage, 0xE0–0xE3 modifiers, 0xF0–0xF2 mouse L/R/M
    public var release: Bool
    public var delayMs: Int      // delay before the next event, 1…9999
    public init(usage: UInt8, release: Bool, delayMs: Int) { self.usage = usage; self.release = release; self.delayMs = delayMs }
}

public struct Macro: Equatable, Codable, Sendable {
    public var repeatCount: Int = 1
    public var events: [MacroEvent] = []
    public init() {}

    /// Encodes into a 128-byte slot (MacProtocol=2). Returns nil if the macro does not fit.
    public func encode() -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: Korona.macroSlotSize)
        let rc = max(1, min(0xFFFF, repeatCount))
        out[0] = UInt8(rc >> 8); out[1] = UInt8(rc & 0xFF)
        var i = 2
        for e in events {
            let flag: UInt8 = e.release ? 0x80 : 0
            let d = max(0, min(9999, e.delayMs))
            if d > 0x7F {
                guard i + 4 <= Korona.macroSlotSize - 3 else { return nil }
                out[i] = flag | UInt8(d % 100); out[i + 1] = e.usage; out[i + 2] = UInt8(d / 100); out[i + 3] = 3; i += 4
            } else {
                guard i + 2 <= Korona.macroSlotSize - 3 else { return nil }
                out[i] = flag | UInt8(max(1, d)); out[i + 1] = e.usage; i += 2
            }
        }
        return out
    }

    public static func decode(_ slot: [UInt8]) -> Macro? {
        guard slot.count >= 4 else { return nil }
        var m = Macro()
        m.repeatCount = Int(slot[0]) << 8 | Int(slot[1])
        if m.repeatCount == 0 { m.repeatCount = 1 }
        var i = 2
        while i + 1 < slot.count, slot[i] != 0 || slot[i + 1] != 0 {
            let flag = slot[i] & 0x80 != 0
            var delay = Int(slot[i] & 0x7F)
            let usage = slot[i + 1]
            if i + 3 < slot.count, slot[i + 3] == 3, delay < 100 {
                delay += Int(slot[i + 2]) * 100; i += 4
            } else { i += 2 }
            m.events.append(MacroEvent(usage: usage, release: flag, delayMs: delay))
        }
        return m.events.isEmpty && m.repeatCount == 1 ? nil : m
    }
}

/// The 1144-byte report 0x06: 8 × 128-byte macro slots followed by the 3 × 10 button matrix.
public struct KoronaMatrix: Equatable, Codable, Sendable {
    public var raw: [UInt8]
    public init(raw: [UInt8]) throws {
        guard raw.count == Korona.matrixLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }

    private func offset(mode: Int, button: Int) -> Int { Korona.matrixOffset + ((mode - 1) * Korona.matrixButtons + (button - 1)) * 4 }

    public func code(mode: Int, button: Int) -> UInt32 {
        let o = offset(mode: mode, button: button)
        return UInt32(raw[o]) | UInt32(raw[o + 1]) << 8 | UInt32(raw[o + 2]) << 16 | UInt32(raw[o + 3]) << 24
    }
    public func action(mode: Int, button: Int) -> ButtonAction { ButtonAction(hardwareCode: code(mode: mode, button: button)) }

    public mutating func set(_ action: ButtonAction, mode: Int, button: Int) {
        let v = (action.hardwareCode & 0xFFFF_FFF0) | UInt32(button & 0x0F)
        let o = offset(mode: mode, button: button)
        raw[o] = UInt8(v & 0xFF); raw[o + 1] = UInt8((v >> 8) & 0xFF); raw[o + 2] = UInt8((v >> 16) & 0xFF); raw[o + 3] = UInt8(v >> 24)
    }

    public func macro(slot: Int) -> Macro? {
        guard (1...Korona.macroSlots).contains(slot) else { return nil }
        let start = (slot - 1) * Korona.macroSlotSize
        return Macro.decode(Array(raw[start..<start + Korona.macroSlotSize]))
    }

    @discardableResult
    public mutating func setMacro(_ macro: Macro?, slot: Int) -> Bool {
        guard (1...Korona.macroSlots).contains(slot) else { return false }
        let start = (slot - 1) * Korona.macroSlotSize
        let bytes = macro?.encode() ?? [UInt8](repeating: 0, count: Korona.macroSlotSize)
        guard bytes.count == Korona.macroSlotSize else { return false }
        raw.replaceSubrange(start..<start + Korona.macroSlotSize, with: bytes)
        return true
    }
}

// MARK: - Device

/// High-level access to a connected KORONA mouse.
public final class KoronaMouse {
    public let device: HIDDevice
    public init(device: HIDDevice) { self.device = device }

    public func readGeneral() throws -> KoronaGeneral { try KoronaGeneral(raw: try device.getFeature(id: Korona.generalReport, length: Korona.generalLength)) }
    public func write(_ g: KoronaGeneral) throws { try device.setFeature(id: Korona.generalReport, payload: g.raw) }
    public func readMode() throws -> KoronaMode { try KoronaMode(raw: try device.getFeature(id: Korona.modeReport, length: Korona.modeLength)) }
    public func write(_ m: KoronaMode) throws { try device.setFeature(id: Korona.modeReport, payload: m.writePayload) }
    public func readMatrix() throws -> KoronaMatrix { try KoronaMatrix(raw: try device.getFeature(id: Korona.matrixReport, length: Korona.matrixLength)) }
    public func write(_ m: KoronaMatrix) throws { try device.setFeature(id: Korona.matrixReport, payload: m.raw) }
}
