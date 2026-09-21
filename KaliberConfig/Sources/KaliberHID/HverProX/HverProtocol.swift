import Foundation

/// Protocol constants for the Kaliber Gaming HVER PRO X (GKB730), SONiX 0C45:8503.
/// See docs/PROTOCOL-keyboard.md.
public enum Hver {
    public static let vendorID = 0x0C45
    public static let productID = 0x8503
    public static let vendorUsagePage = 0xFF1C
    public static let vendorUsage = 0x92

    public static let reportID: UInt8 = 0x04
    public static let packetLength = 64
    public static let chunk = 0x38
    public static let profileCount = 3
    public static let profileBlockLength = 0x2A
    public static let infoLength = 0x2C
    public static let keyCount = 126
    public static let keyMapLength = 378
    public static let rows = 6, columns = 21
    public static let colourSets = 3
    public static let colourPageLength = 378
    public static let colourPageStride = 0x200
    public static let colourChunk = 0x36            // 18 keys per packet
    /// Macro area size = info[11] << 7 (0x50 → 10240 bytes on this firmware).
    public static let macroAreaDefault = 10240
    public static let macroHeader = 16

    public enum Command: UInt8 {
        case begin = 0x01, end = 0x02, readInfo = 0x03, writeInfo = 0x04, readMem = 0x05, writeMem = 0x06
        case readKeys = 0x07, writeKeys = 0x08, readMacros = 0x09, writeMacros = 0x0A, readDefaultKeys = 0x0F, readLED = 0x10, writeLED = 0x11
    }

    /// Builds a 63-byte payload (report ID excluded) with the vendor checksum.
    public static func packet(_ cmd: Command, data: [UInt8] = [], addr: Int = 0, length: Int? = nil) -> [UInt8] {
        precondition(data.count <= chunk)
        var p = [UInt8](repeating: 0, count: packetLength)          // index 0 is the report ID slot
        p[0] = reportID; p[3] = cmd.rawValue
        p[4] = UInt8(length ?? data.count)
        p[5] = UInt8(addr & 0xFF); p[6] = UInt8((addr >> 8) & 0xFF)
        p.replaceSubrange(8..<8 + data.count, with: data)
        let sum = p[3..<packetLength].reduce(0) { $0 + Int($1) }
        p[1] = UInt8(sum & 0xFF); p[2] = UInt8((sum >> 8) & 0xFF)
        return Array(p.dropFirst())
    }
}

public enum HverLightMode: Int, CaseIterable, Codable, Sendable, Identifiable {
    case rainbowRipple = 1, rainbowEbbAndFlow, rainbowRotation, sevenColourCycle, rainbowBreathing, rainbowFixed,
         rainbowFollowingKeys, rainbowExplosionKeys, rainbowSplitKeys, rainbowFlashKeys, rainbowPulseKeys, fallingRainbow,
         rainbowTwist, rainbowWaves, rainbowRain, rainbowScan, fixedSingleColour, rainbowEruption
    case custom = 20
    public var id: Int { rawValue }
    public var name: String {
        switch self {
        case .rainbowRipple: return "Rainbow Ripple"; case .rainbowEbbAndFlow: return "Rainbow Ebb and Flow"; case .rainbowRotation: return "Rainbow Rotation"
        case .sevenColourCycle: return "7-Colour Cycle"; case .rainbowBreathing: return "Rainbow Breathing"; case .rainbowFixed: return "Rainbow Fixed"
        case .rainbowFollowingKeys: return "Rainbow Following Keys"; case .rainbowExplosionKeys: return "Rainbow Explosion Keys"; case .rainbowSplitKeys: return "Rainbow Split Keys"
        case .rainbowFlashKeys: return "Rainbow Flash Keys"; case .rainbowPulseKeys: return "Rainbow Pulse Keys"; case .fallingRainbow: return "Falling Rainbow"
        case .rainbowTwist: return "Rainbow Twist"; case .rainbowWaves: return "Rainbow Waves"; case .rainbowRain: return "Rainbow Rain"; case .rainbowScan: return "Rainbow Scan"
        case .fixedSingleColour: return "Fixed Single Colour"; case .rainbowEruption: return "Rainbow Eruption"; case .custom: return "Custom (per-key)"
        }
    }
    /// Modes where the vendor UI shows a direction control.
    public var hasDirection: Bool { [.rainbowRipple, .rainbowEbbAndFlow, .rainbowRotation, .fallingRainbow, .rainbowTwist, .rainbowWaves, .rainbowRain, .rainbowScan, .rainbowEruption].contains(self) }
    public var hasSpeed: Bool { ![.rainbowFixed, .fixedSingleColour, .custom].contains(self) }
    public var hasColour: Bool { self != .custom }
}

/// One 42-byte per-profile settings block; unknown bytes are preserved in `raw`.
public struct HverProfile: Equatable, Codable, Sendable {
    public var raw: [UInt8]
    public init(raw: [UInt8]) throws {
        guard raw.count == Hver.profileBlockLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }
    public var mode: HverLightMode {
        get { HverLightMode(rawValue: Int(raw[0])) ?? .rainbowFixed }
        set { raw[0] = UInt8(newValue.rawValue) }
    }
    public var modeRaw: Int { Int(raw[0]) }
    public var brightness: Int { get { Int(raw[1]) } set { raw[1] = UInt8(max(0, min(4, newValue))) } }
    /// Wire speed 0 (fast) … 3 (slow).
    public var speedWire: Int { get { Int(raw[2]) } set { raw[2] = UInt8(max(0, min(3, newValue))) } }
    public var reversed: Bool { get { raw[3] != 0 } set { raw[3] = newValue ? 0xFF : 0 } }
    public var colourful: Bool { get { raw[4] != 0 } set { raw[4] = newValue ? 0x01 : 0x00 } }
    public var colour: RGB {
        get { RGB(raw[5], raw[6], raw[7]) }
        set { raw[5] = newValue.r; raw[6] = newValue.g; raw[7] = newValue.b }
    }
    public var reportRateIndex: Int { get { Int(raw[0x0F]) } set { raw[0x0F] = UInt8(max(0, min(3, newValue))) } }
    /// Which of the three per-key colour sets the "Custom" pattern uses (0–2).
    public var customSet: Int { get { Int(raw[0x12]) } set { raw[0x12] = UInt8(max(0, min(Hver.colourSets - 1, newValue))) } }
}

/// One per-key colour page: 126 RGB triplets in **row-major** matrix order (`row*21 + col`),
/// whereas the key map is column-major (`col*6 + row`). Verified on hardware.
public struct HverColourPage: Equatable, Codable, Sendable {
    public var raw: [UInt8]
    public init(raw: [UInt8]) throws {
        guard raw.count == Hver.colourPageLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }
    public static let black = try! HverColourPage(raw: [UInt8](repeating: 0, count: Hver.colourPageLength))
    public static func ledIndex(col: Int, row: Int) -> Int { row * Hver.columns + col }
    /// Converts a key-map matrix index (column-major) to the LED index (row-major).
    public static func ledIndex(matrixIndex i: Int) -> Int { ledIndex(col: i / Hver.rows, row: i % Hver.rows) }
    public subscript(col col: Int, row row: Int) -> RGB {
        get { let i = Self.ledIndex(col: col, row: row) * 3; return RGB(raw[i], raw[i + 1], raw[i + 2]) }
        set { let i = Self.ledIndex(col: col, row: row) * 3; raw[i] = newValue.r; raw[i + 1] = newValue.g; raw[i + 2] = newValue.b }
    }
    public mutating func fill(_ c: RGB) { for i in stride(from: 0, to: raw.count, by: 3) { raw[i] = c.r; raw[i + 1] = c.g; raw[i + 2] = c.b } }
}

/// The 44-byte info block (cmd 0x03/0x04).
public struct HverInfo: Equatable, Codable, Sendable {
    public var raw: [UInt8]
    public init(raw: [UInt8]) throws {
        guard raw.count == Hver.infoLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }
    public var activeProfile: Int { get { Int(raw[10]) } set { raw[10] = UInt8(max(0, min(2, newValue))) } }
    public var availableModes: [Int] { raw[16..<35].map(Int.init).filter { $0 != 0 } }
}

/// One key-map entry (3 bytes).
public enum HverKey: Equatable, Hashable, Codable, Sendable {
    case none
    case key(usage: UInt8)
    case modifier(bit: UInt8)
    case media(usage: UInt16)          // HID consumer-page usage, e.g. 0xCD play/pause
    case macro(index: Int)             // index into the macro area
    case mouseButton(mask: UInt8)      // 0x01 left, 0x02 right, 0x04 middle
    case mouseWheel(up: Bool)
    case raw(UInt8, UInt8, UInt8)

    public init(bytes b: ArraySlice<UInt8>) {
        let a = Array(b)
        switch (a[0], a[1]) {
        case (0, 0): self = .none
        case (2, 2): self = .key(usage: a[2])
        case (2, 1): self = .modifier(bit: a[2])
        case (3, _): self = .media(usage: UInt16(a[1]) | UInt16(a[2]) << 8)
        case (5, 1): self = .macro(index: Int(a[2]))
        case (1, 1): self = .mouseButton(mask: a[2])
        case (1, 5): self = .mouseWheel(up: a[2] != 0xFF)
        default: self = .raw(a[0], a[1], a[2])
        }
    }
    public var bytes: [UInt8] {
        switch self {
        case .none: return [0, 0, 0]
        case .key(let u): return [2, 2, u]
        case .modifier(let b): return [2, 1, b]
        case .media(let u): return [3, UInt8(u & 0xFF), UInt8(u >> 8)]
        case .macro(let i): return [5, 1, UInt8(clamping: i)]
        case .mouseButton(let m): return [1, 1, m]
        case .mouseWheel(let up): return [1, 5, up ? 0x01 : 0xFF]
        case .raw(let x, let y, let z): return [x, y, z]
        }
    }
    /// HID usage equivalent (modifiers mapped to 0xE0–0xE7) for display.
    public var usage: UInt8? {
        switch self {
        case .key(let u): return u
        case .modifier(let b):
            let left: [UInt8: UInt8] = [0x01: 0xE0, 0x02: 0xE1, 0x04: 0xE2, 0x08: 0xE3, 0x10: 0xE4, 0x20: 0xE5, 0x40: 0xE6, 0x80: 0xE7]
            return left[b]
        default: return nil
        }
    }
    public static func from(usage u: UInt8) -> HverKey {
        if (0xE0...0xE7).contains(u) { return .modifier(bit: 1 << (u - 0xE0)) }
        return .key(usage: u)
    }
    public var name: String {
        switch self {
        case .none: return "—"
        case .media(let u): return HverMediaKey(rawValue: u)?.name ?? String(format: "Consumer 0x%03X", u)
        case .macro(let i): return "Macro \(i + 1)"
        case .mouseButton(let m): return ["Mouse left", "Mouse right", "Mouse middle"].enumerated().filter { m & (1 << $0.offset) != 0 }.map(\.element).joined(separator: "+")
        case .mouseWheel(let up): return up ? "Wheel up" : "Wheel down"
        case .raw(let x, let y, let z): return String(format: "raw %02x %02x %02x", x, y, z)
        default: return usage.map(HIDUsage.name) ?? "?"
        }
    }
}

/// Consumer-page usages the vendor tool offers as "Media" functions (table at 0x652A00 in the tool).
public enum HverMediaKey: UInt16, CaseIterable, Codable, Sendable, Identifiable {
    case mediaPlayer = 0x183, playPause = 0xCD, stop = 0xB7, previous = 0xB6, next = 0xB5, volumeDown = 0xEA, volumeUp = 0xE9, mute = 0xE2
    case home = 0x223, refresh = 0x227, browserStop = 0x226, back = 0x224, forward = 0x225, favorites = 0x22A, search = 0x221
    case explorer = 0x194, calculator = 0x192, email = 0x18A
    public var id: UInt16 { rawValue }
    public var name: String {
        switch self {
        case .mediaPlayer: return "Media player"; case .playPause: return "Play / Pause"; case .stop: return "Stop"; case .previous: return "Previous track"; case .next: return "Next track"
        case .volumeDown: return "Volume down"; case .volumeUp: return "Volume up"; case .mute: return "Mute"; case .home: return "Browser home"; case .refresh: return "Refresh"
        case .browserStop: return "Browser stop"; case .back: return "Browser back"; case .forward: return "Browser forward"; case .favorites: return "Favorites"; case .search: return "Search"
        case .explorer: return "File explorer"; case .calculator: return "Calculator"; case .email: return "E-mail"
        }
    }
}

// MARK: - Macro area (cmd 0x0A / 0x09)

public struct HverMacroEvent: Equatable, Codable, Sendable {
    public enum Kind: Equatable, Codable, Sendable {
        case key(usage: UInt8)          // HID keyboard usage
        case modifier(bit: UInt8)       // 0x01 Ctrl … 0x80 right GUI
        case consumer(usage: UInt16)
        case mouseButton(mask: UInt8)
        case mouseWheel(up: Bool)
        case raw(type: UInt8, payload: UInt16)
    }
    public var kind: Kind
    public var release: Bool
    public var delayMs: Int     // delay before this event, 10 ms resolution, max 40950
    public init(kind: Kind, release: Bool, delayMs: Int) { self.kind = kind; self.release = release; self.delayMs = delayMs }

    /// 4-byte wire form: u16 [15]=release [14:12]=type [11:0]=delay/10, then u16 payload (LE).
    public var words: (UInt16, UInt16) {
        var w0 = UInt16(max(0, min(4095, delayMs / 10)))
        if release { w0 |= 0x8000 }
        let w1: UInt16
        switch kind {
        case .key(let u): w0 |= 0x2000; w1 = 0x0002 | UInt16(u) << 8
        case .modifier(let b): w0 |= 0x2000; w1 = 0x0001 | UInt16(b) << 8
        case .consumer(let u): w0 |= 0x3000; w1 = u
        case .mouseButton(let m): w0 |= 0x1000; w1 = 0x0001 | UInt16(m) << 8
        case .mouseWheel(let up): w0 |= 0x1000; w1 = up ? 0x0105 : 0xFF05
        case .raw(let t, let p): w0 |= UInt16(t & 7) << 12; w1 = p
        }
        return (w0, w1)
    }

    public init(w0: UInt16, w1: UInt16) {
        release = w0 & 0x8000 != 0
        delayMs = Int(w0 & 0x0FFF) * 10
        let type = UInt8((w0 >> 12) & 7)
        switch (type, w1 & 0xFF) {
        case (2, 2): kind = .key(usage: UInt8(w1 >> 8))
        case (2, 1): kind = .modifier(bit: UInt8(w1 >> 8))
        case (3, _): kind = .consumer(usage: w1)
        case (1, 1): kind = .mouseButton(mask: UInt8(w1 >> 8))
        case (1, 5): kind = .mouseWheel(up: (w1 >> 8) != 0xFF)
        default: kind = .raw(type: type, payload: w1)
        }
    }
}

public struct HverMacro: Equatable, Codable, Sendable {
    public var name: String = ""
    public var repeatCount: Int = 1
    public var events: [HverMacroEvent] = []
    public init(name: String = "", repeatCount: Int = 1, events: [HverMacroEvent] = []) { self.name = name; self.repeatCount = repeatCount; self.events = events }
}

/// The macro area: `55 AA | size | count | namesIncluded | 8×0 | u16 offsets… | records`.
/// Record: u16 eventCount, u8 repeat, u8 nameLength(UTF-16 units), events (4 B each), optional UTF-16LE name.
public enum HverMacroArea {
    public static func encode(_ macros: [HverMacro], withNames: Bool = true, capacity: Int = Hver.macroAreaDefault) -> [UInt8]? {
        func build(names: Bool) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: Hver.macroHeader + macros.count * 2)
            for (i, m) in macros.enumerated() {
                let off = out.count
                out[Hver.macroHeader + i * 2] = UInt8(off & 0xFF); out[Hver.macroHeader + i * 2 + 1] = UInt8(off >> 8)
                let nameUnits = names ? Array(m.name.utf16.prefix(255)) : []
                out += [UInt8(m.events.count & 0xFF), UInt8(m.events.count >> 8), UInt8(clamping: m.repeatCount), UInt8(nameUnits.count)]
                for e in m.events { let (a, b) = e.words; out += [UInt8(a & 0xFF), UInt8(a >> 8), UInt8(b & 0xFF), UInt8(b >> 8)] }
                for u in nameUnits { out += [UInt8(u & 0xFF), UInt8(u >> 8)] }
            }
            out[0] = 0xAA; out[1] = 0x55
            out[2] = UInt8(out.count & 0xFF); out[3] = UInt8(out.count >> 8)
            out[4] = UInt8(macros.count & 0xFF); out[5] = UInt8(macros.count >> 8)
            out[6] = names ? 1 : 0; out[7] = 0
            return out
        }
        var bytes = build(names: withNames)
        if bytes.count > capacity { bytes = build(names: false) }
        return bytes.count <= capacity ? bytes : nil
    }

    public static func decode(_ d: [UInt8]) -> [HverMacro]? {
        guard d.count >= Hver.macroHeader, d[0] == 0xAA, d[1] == 0x55 else { return nil }
        let count = Int(d[4]) | Int(d[5]) << 8
        let names = d[6] != 0
        var out: [HverMacro] = []
        for i in 0..<count {
            let oi = Hver.macroHeader + i * 2
            guard oi + 1 < d.count else { return nil }
            var p = Int(d[oi]) | Int(d[oi + 1]) << 8
            guard p + 4 <= d.count else { return nil }
            let n = Int(d[p]) | Int(d[p + 1]) << 8
            var m = HverMacro(); m.repeatCount = Int(d[p + 2]); let nameLen = Int(d[p + 3]); p += 4
            for _ in 0..<n {
                guard p + 4 <= d.count else { return nil }
                m.events.append(HverMacroEvent(w0: UInt16(d[p]) | UInt16(d[p + 1]) << 8, w1: UInt16(d[p + 2]) | UInt16(d[p + 3]) << 8)); p += 4
            }
            if names, nameLen > 0, p + nameLen * 2 <= d.count {
                let units = (0..<nameLen).map { UInt16(d[p + $0 * 2]) | UInt16(d[p + $0 * 2 + 1]) << 8 }
                m.name = String(utf16CodeUnits: units, count: units.count)
            }
            out.append(m)
        }
        return out
    }
}

public struct HverKeyMap: Equatable, Codable, Sendable {
    public var raw: [UInt8]
    public init(raw: [UInt8]) throws {
        guard raw.count == Hver.keyMapLength else { throw HIDError.badReply(raw) }
        self.raw = raw
    }
    public subscript(index: Int) -> HverKey {
        get { HverKey(bytes: raw[index * 3..<index * 3 + 3]) }
        set { raw.replaceSubrange(index * 3..<index * 3 + 3, with: newValue.bytes) }
    }
}

/// High-level access to a connected HVER PRO X.
public final class HverKeyboard {
    public let device: HIDDevice
    public init(device: HIDDevice) { self.device = device }

    private func xfer(_ cmd: Hver.Command, data: [UInt8] = [], addr: Int = 0, length: Int? = nil) throws -> [UInt8] {
        let payload = Hver.packet(cmd, data: data, addr: addr, length: length)
        let reply = try device.exchange(id: Hver.reportID, payload: payload, timeout: 1.0) { r in r.count >= 8 && r[0] == Hver.reportID && r[3] == cmd.rawValue }
        if reply[7] == 0xFF || reply[7] == 0xFE { throw HIDError.badReply(reply) }
        return reply
    }

    private func readChunked(_ cmd: Hver.Command, addr: Int, count: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        while out.count < count {
            let n = min(Hver.chunk, count - out.count)
            let r = try xfer(cmd, addr: addr + out.count, length: n)
            out += r[8..<8 + n]
        }
        return out
    }

    private func writeChunked(_ cmd: Hver.Command, addr: Int, data: [UInt8]) throws {
        var i = 0
        while i < data.count {
            let n = min(Hver.chunk, data.count - i)
            _ = try xfer(cmd, data: Array(data[i..<i + n]), addr: addr + i)
            i += n
        }
    }

    /// Runs `body` inside the vendor's begin/end bracket.
    public func transaction(_ body: () throws -> Void) throws {
        _ = try xfer(.begin)
        defer { Thread.sleep(forTimeInterval: 0.01); _ = try? xfer(.end) }
        try body()
    }

    public func readInfo() throws -> HverInfo { try HverInfo(raw: Array(try xfer(.readInfo, length: Hver.infoLength)[8..<8 + Hver.infoLength])) }
    public func writeInfo(_ info: HverInfo) throws { try transaction { _ = try xfer(.writeInfo, data: info.raw) } }

    public func readProfile(_ p: Int) throws -> HverProfile { try HverProfile(raw: try readChunked(.readMem, addr: p * Hver.profileBlockLength, count: Hver.profileBlockLength)) }
    public func writeProfile(_ profile: HverProfile, index p: Int) throws {
        try transaction { try writeChunked(.writeMem, addr: p * Hver.profileBlockLength, data: profile.raw) }
    }

    public func readKeyMap(profile p: Int) throws -> HverKeyMap { try HverKeyMap(raw: try readChunked(.readKeys, addr: p * Hver.keyMapLength, count: Hver.keyMapLength)) }
    public func readDefaultKeyMap() throws -> HverKeyMap { try HverKeyMap(raw: try readChunked(.readDefaultKeys, addr: 0, count: Hver.keyMapLength)) }
    public func writeKeyMap(_ map: HverKeyMap, profile p: Int) throws {
        try transaction { try writeChunked(.writeKeys, addr: p * Hver.keyMapLength, data: map.raw) }
    }

    /// Reads the raw macro area (up to `count` bytes).
    public func readMacroArea(count: Int = Hver.macroAreaDefault) throws -> [UInt8] {
        let head = try readChunked(.readMacros, addr: 0, count: Hver.macroHeader)
        guard head[0] == 0xAA, head[1] == 0x55 else { return head }
        let size = min(count, max(Hver.macroHeader, Int(head[2]) | Int(head[3]) << 8))
        return head + (size > Hver.macroHeader ? try readChunked(.readMacros, addr: Hver.macroHeader, count: size - Hver.macroHeader) : [])
    }

    public func writeMacroArea(_ bytes: [UInt8]) throws {
        try transaction { try writeChunked(.writeMacros, addr: 0, data: bytes) }
    }

    /// Reads per-key colour set `set` (0–2) of `profile`. Page address = (profile*3 + set) * 0x200.
    public func readColourPage(profile p: Int, set: Int) throws -> HverColourPage {
        let base = (p * Hver.colourSets + set) * Hver.colourPageStride
        var out: [UInt8] = []
        while out.count < Hver.colourPageLength {
            let n = min(Hver.colourChunk, Hver.colourPageLength - out.count)
            let r = try xfer(.readLED, addr: base + out.count, length: n)
            out += r[8..<8 + n]
        }
        return try HverColourPage(raw: out)
    }

    public func writeColourPage(_ page: HverColourPage, profile p: Int, set: Int) throws {
        let base = (p * Hver.colourSets + set) * Hver.colourPageStride
        try transaction {
            var i = 0
            while i < page.raw.count {
                let n = min(Hver.colourChunk, page.raw.count - i)
                _ = try xfer(.writeLED, data: Array(page.raw[i..<i + n]), addr: base + i)
                i += n
            }
        }
    }
}
