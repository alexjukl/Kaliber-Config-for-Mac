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

    public enum Command: UInt8 {
        case begin = 0x01, end = 0x02, readInfo = 0x03, writeInfo = 0x04, readMem = 0x05, writeMem = 0x06
        case readKeys = 0x07, writeKeys = 0x08, writeMacros = 0x0A, readDefaultKeys = 0x0F, readLED = 0x10, writeLED = 0x11
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
    case raw(UInt8, UInt8, UInt8)

    public init(bytes b: ArraySlice<UInt8>) {
        let a = Array(b)
        switch (a[0], a[1]) {
        case (0, 0): self = .none
        case (2, 2): self = .key(usage: a[2])
        case (2, 1): self = .modifier(bit: a[2])
        default: self = .raw(a[0], a[1], a[2])
        }
    }
    public var bytes: [UInt8] {
        switch self {
        case .none: return [0, 0, 0]
        case .key(let u): return [2, 2, u]
        case .modifier(let b): return [2, 1, b]
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
        case .raw(let x, let y, let z): return String(format: "raw %02x %02x %02x", x, y, z)
        default: return usage.map(HIDUsage.name) ?? "?"
        }
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
