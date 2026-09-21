import XCTest
@testable import KaliberHID

final class HverCodecTests: XCTestCase {
    func fixture(_ name: String) throws -> [UInt8] {
        let url = Bundle.module.url(forResource: name, withExtension: "hex", subdirectory: "Fixtures")!
        var bytes: [UInt8] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            for tok in line[line.index(after: colon)...].split(separator: " ") { bytes.append(UInt8(tok, radix: 16)!) }
        }
        return bytes
    }

    func testPacketChecksumMatchesVendor() {
        // cmd 0x03 len 0x2c: bytes 3..63 sum = 3 + 0x2c = 0x2f
        let p = Hver.packet(.readInfo, length: 0x2C)
        XCTAssertEqual(p.count, 63)
        XCTAssertEqual(Array(p[0..<7]), [0x2F, 0x00, 0x03, 0x2C, 0x00, 0x00, 0x00])
        let w = Hver.packet(.writeMem, data: [0x11], addr: 0x2A * 2)
        XCTAssertEqual(w[2], 0x06); XCTAssertEqual(w[3], 1); XCTAssertEqual(w[4], 0x54); XCTAssertEqual(w[7], 0x11)
        XCTAssertEqual(Int(w[0]) | Int(w[1]) << 8, 6 + 1 + 0x54 + 0x11)
    }

    func testInfoAndProfiles() throws {
        let info = try HverInfo(raw: try fixture("kb-info"))
        XCTAssertEqual(info.activeProfile, 0)
        XCTAssertEqual(info.availableModes, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 16, 18, 20])
        let all = try fixture("kb-profiles")
        let p0 = try HverProfile(raw: Array(all[0..<0x2A]))
        XCTAssertEqual(p0.mode, .rainbowFixed); XCTAssertEqual(p0.brightness, 4); XCTAssertEqual(p0.speedWire, 3)
        XCTAssertTrue(p0.colourful); XCTAssertEqual(p0.colour, RGB(255, 0, 0))
        let p1 = try HverProfile(raw: Array(all[0x2A..<0x54]))
        XCTAssertEqual(p1.mode, .rainbowEruption); XCTAssertEqual(p1.reportRateIndex, 3)
        var e = p0; e.mode = .fixedSingleColour; e.colourful = false; e.colour = RGB(0, 0, 255)
        XCTAssertEqual(Array(e.raw[0..<8]), [0x11, 0x04, 0x03, 0x00, 0x00, 0x00, 0x00, 0xFF])   // as written on hardware
    }

    func testKeyMapDecodesFactoryLayout() throws {
        let m = try HverKeyMap(raw: try fixture("kb-keys-default"))
        XCTAssertEqual(m[0], .key(usage: 0x29))            // Esc
        XCTAssertEqual(m[4], .modifier(bit: 0x02))         // Left Shift
        XCTAssertEqual(m[5], .modifier(bit: 0x01))         // Left Ctrl
        XCTAssertEqual(m[11], .modifier(bit: 0x08))        // Left GUI
        XCTAssertEqual(m[4].usage, 0xE1)
        var e = m; e[0] = HverKey.from(usage: 0xE3)
        XCTAssertEqual(Array(e.raw[0..<3]), [2, 1, 8])
        e[0] = .none; XCTAssertEqual(Array(e.raw[0..<3]), [0, 0, 0])
        XCTAssertEqual((0..<Hver.keyCount).filter { m[$0] != .none }.count, 126)
    }
}

final class HverColourPageTests: XCTestCase {
    func testLEDIndexIsRowMajorTransposeOfKeyMap() {
        // Verified on hardware: Esc (matrix 0) -> LED 0, F1 (matrix 6 = col 1,row 0) -> LED 1, A (matrix 9 = col 1,row 3) -> LED 64
        XCTAssertEqual(HverColourPage.ledIndex(matrixIndex: 0), 0)
        XCTAssertEqual(HverColourPage.ledIndex(matrixIndex: 6), 1)
        XCTAssertEqual(HverColourPage.ledIndex(matrixIndex: 9), 3 * 21 + 1)
        var p = HverColourPage.black
        p[col: 1, row: 3] = RGB(0, 255, 0)
        XCTAssertEqual(Array(p.raw[64 * 3..<64 * 3 + 3]), [0, 255, 0])
        p.fill(RGB(1, 2, 3)); XCTAssertEqual(p[col: 20, row: 5], RGB(1, 2, 3))
    }
}

final class HverMacroTests: XCTestCase {
    func testMacroAreaMatchesHardwareRoundTrip() throws {
        // Exactly the bytes written to and read back from the keyboard on 2026-09-21 (one macro "kg": K↓ K↑ G↓ G↑, 20 ms).
        let expected: [UInt8] = [0xAA, 0x55, 0x2A, 0x00, 0x01, 0x00, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0x12, 0x00,
                                 0x04, 0x00, 0x01, 0x02, 0x02, 0x20, 0x02, 0x0E, 0x02, 0xA0, 0x02, 0x0E, 0x02, 0x20, 0x02, 0x0A, 0x02, 0xA0, 0x02, 0x0A,
                                 0x6B, 0x00, 0x67, 0x00]
        var m = HverMacro(name: "kg")
        for (u, r) in [(0x0E, false), (0x0E, true), (0x0A, false), (0x0A, true)] as [(UInt8, Bool)] { m.events.append(HverMacroEvent(kind: .key(usage: u), release: r, delayMs: 20)) }
        XCTAssertEqual(HverMacroArea.encode([m]), expected)
        XCTAssertEqual(HverMacroArea.decode(expected), [m])
        XCTAssertNil(HverMacroArea.encode([m], capacity: 20))
    }

    func testMacroEventEncodings() {
        XCTAssertEqual(HverMacroEvent(kind: .modifier(bit: 0x02), release: false, delayMs: 100).words.0, 0x200A)
        XCTAssertEqual(HverMacroEvent(kind: .modifier(bit: 0x02), release: false, delayMs: 100).words.1, 0x0201)
        XCTAssertEqual(HverMacroEvent(kind: .consumer(usage: 0xCD), release: true, delayMs: 0).words.0, 0xB000)
        XCTAssertEqual(HverMacroEvent(kind: .mouseWheel(up: false), release: false, delayMs: 10).words.1, 0xFF05)
        let e = HverMacroEvent(w0: 0x1005, w1: 0x0401)
        XCTAssertEqual(e.kind, .mouseButton(mask: 4)); XCTAssertEqual(e.delayMs, 50)
    }

    func testKeyEntriesForMediaMacroMouse() {
        XCTAssertEqual(HverKey.media(usage: 0xCD).bytes, [3, 0xCD, 0x00])
        XCTAssertEqual(HverKey(bytes: [3, 0x23, 0x02][...]), .media(usage: 0x223))
        XCTAssertEqual(HverKey.macro(index: 2).bytes, [5, 1, 2])
        XCTAssertEqual(HverKey(bytes: [1, 5, 0xFF][...]), .mouseWheel(up: false))
        XCTAssertEqual(HverKey(bytes: [1, 1, 2][...]).name, "Mouse right")
    }
}
