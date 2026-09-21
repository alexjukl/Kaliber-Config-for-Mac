import XCTest
@testable import KaliberHID

final class KoronaCodecTests: XCTestCase {
    /// Loads a `tools/probe_mouse.py` hex dump (first byte is the report ID) and strips the ID.
    func fixture(_ name: String) throws -> [UInt8] {
        let url = Bundle.module.url(forResource: name, withExtension: "hex", subdirectory: "Fixtures")!
        let text = try String(contentsOf: url, encoding: .utf8)
        var bytes: [UInt8] = []
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            for tok in line[line.index(after: colon)...].split(separator: " ") { bytes.append(UInt8(tok, radix: 16)!) }
        }
        return Array(bytes.dropFirst())
    }

    func testGeneralDecodesPristineDump() throws {
        let g = try KoronaGeneral(raw: try fixture("pristine-r04"))
        XCTAssertEqual(g.firmware, "XCQ501")
        XCTAssertEqual(g.sensorCode, 0xB)
        XCTAssertFalse(g.xyIndependent)
        XCTAssertEqual(g.stages.map(\.dpi).prefix(5), [400, 800, 1600, 3200, 5000])
        XCTAssertEqual(g.stages.map(\.enabled), [true, true, true, true, true, false, false, false])
        XCTAssertEqual(g.stages.map(\.color).prefix(5), [.red, .yellow, .green, .blue, .magenta])
        XCTAssertEqual(g.ledMode, .colorfulStreaming)
        XCTAssertEqual(g.ledParam, 2)
        XCTAssertFalse(g.ledOff)
        XCTAssertEqual(g.ledColors[0], RGB(255, 0, 0))
        XCTAssertEqual(g.ledColors[1], RGB(0, 0, 255))
        XCTAssertEqual(g.flags, 0x20)
    }

    func testGeneralRoundTripIsByteExact() throws {
        let raw = try fixture("pristine-r04")
        var g = try KoronaGeneral(raw: raw)
        g.stages = g.stages          // re-encode
        g.ledMode = g.ledMode
        g.ledColors = g.ledColors
        XCTAssertEqual(g.raw, raw)
    }

    func testStageEditEncodesLikeHardwareTest() throws {
        var g = try KoronaGeneral(raw: try fixture("pristine-r04"))
        var s = g.stages; s[0].dpi = 800; g.stages = s
        XCTAssertEqual(g.raw[4], 0x07)                 // verified on hardware
        s[5] = DPIStage(dpi: 1200, enabled: true, color: .cyan); g.stages = s
        XCTAssertEqual(g.raw[9], 11)                   // 1200 -> code 11
        XCTAssertEqual(g.raw[1] & 0x0F, 6)             // six enabled stages
        XCTAssertEqual(g.raw[48], DPIColor.cyan.rawValue)
    }

    func testLEDEditMatchesHardwareTest() throws {
        var g = try KoronaGeneral(raw: try fixture("pristine-r04"))
        g.ledMode = .off
        XCTAssertEqual(g.raw[20], 0x02); XCTAssertEqual(g.raw[51], 0x22)
        g.ledMode = .steady; g.ledParam = 8; g.ledColors = [RGB(255, 0, 0)]
        XCTAssertEqual(Array(g.raw[20..<25]), [0x28, 0x00, 0xFF, 0x00, 0x00])
        XCTAssertEqual(g.raw[51], 0x20)
    }

    func testModeReport() throws {
        var m = try KoronaMode(raw: try fixture("pristine-r08"))
        XCTAssertEqual(m.activeMode, 1)
        XCTAssertEqual(m.rate(mode: 1), .hz500)
        XCTAssertEqual(m.liveDPILevel, 4)
        m.setRate(.hz1000, mode: 1)
        XCTAssertEqual(m.writePayload, [1, 4, 3, 3, 0, 0, 0, 0])
    }

    func testMatrixDecodesFactoryMapping() throws {
        let mx = try KoronaMatrix(raw: try fixture("pristine-r06"))
        let mode1 = (1...7).map { mx.action(mode: 1, button: $0) }
        XCTAssertEqual(mode1, [.leftClick, .rightClick, .middleClick, .back, .forward, .dpiUp, .dpiDown])
        XCTAssertEqual(mx.action(mode: 2, button: 1), .disabled)
        XCTAssertNil(mx.macro(slot: 1))
    }

    func testMatrixSetEncodesButtonIndexInLowNibble() throws {
        var mx = try KoronaMatrix(raw: try fixture("pristine-r06"))
        mx.set(.dpiLoop, mode: 1, button: 7)
        XCTAssertEqual(mx.code(mode: 1, button: 7), 0x47)        // verified on hardware
        mx.set(.rgbToggle, mode: 1, button: 7)
        XCTAssertEqual(mx.code(mode: 1, button: 7), 0x257)       // verified on hardware
        mx.set(.key(usage: 0x04, modifiers: 0x02), mode: 1, button: 6)
        XCTAssertEqual(mx.action(mode: 1, button: 6), .key(usage: 0x04, modifiers: 0x02))
        mx.set(.media(.volumeUp), mode: 1, button: 6)
        XCTAssertEqual(mx.action(mode: 1, button: 6), .media(.volumeUp))
        mx.set(.macro(slot: 3, repeatMode: .untilReleased), mode: 1, button: 6)
        XCTAssertEqual(mx.code(mode: 1, button: 6), 0x3296)
        XCTAssertEqual(mx.action(mode: 1, button: 6), .macro(slot: 3, repeatMode: .untilReleased))
    }

    func testMacroRoundTrip() throws {
        var m = Macro(); m.repeatCount = 3
        m.events = [MacroEvent(usage: 0xE1, release: false, delayMs: 10), MacroEvent(usage: 0x04, release: false, delayMs: 250),
                    MacroEvent(usage: 0x04, release: true, delayMs: 5), MacroEvent(usage: 0xE1, release: true, delayMs: 1)]
        let bytes = try XCTUnwrap(m.encode())
        XCTAssertEqual(Array(bytes[0..<12]), [0x00, 0x03, 0x0A, 0xE1, 0x32, 0x04, 0x02, 0x03, 0x85, 0x04, 0x81, 0xE1])
        XCTAssertEqual(Macro.decode(bytes), m)
        var mx = try KoronaMatrix(raw: try fixture("pristine-r06"))
        XCTAssertTrue(mx.setMacro(m, slot: 2))
        XCTAssertEqual(mx.macro(slot: 2), m)
        XCTAssertNil(mx.macro(slot: 1))
    }

    func testDPITable() {
        XCTAssertEqual(Korona.dpiCode(for: 200), 1)
        XCTAssertEqual(Korona.dpiCode(for: 5000), 49)
        XCTAssertEqual(Korona.dpiCode(for: 10000), 59)
        XCTAssertEqual(Korona.dpi(forCode: 0x1F), 3200)
        XCTAssertEqual(Korona.dpi(forCode: 0x80 | 0x07), 800)
    }
}
