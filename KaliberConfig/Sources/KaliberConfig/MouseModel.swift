import Foundation
import Combine
import KaliberHID

/// Editable state for one connected KORONA mouse: the three device reports, plus the last-read copies
/// so we know what is dirty. Unknown bytes always round-trip untouched.
@MainActor
final class MouseModel: ObservableObject {
    let mouse: KoronaMouse

    @Published var general: KoronaGeneral?
    @Published var mode: KoronaMode?
    @Published var matrix: KoronaMatrix?
    @Published private(set) var savedGeneral: KoronaGeneral?
    @Published private(set) var savedMode: KoronaMode?
    @Published private(set) var savedMatrix: KoronaMatrix?

    @Published private(set) var liveDPILevel: Int = 0
    @Published private(set) var status: String = ""
    @Published var lastError: String?
    @Published private(set) var busy = false

    private var pollTimer: Timer?

    init(device: HIDDevice) {
        mouse = KoronaMouse(device: device)
        reload()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollLive() }
        }
    }

    /// Stops background polling; called when the mouse is unplugged.
    func stop() { pollTimer?.invalidate(); pollTimer = nil }

    var isDirty: Bool {
        general != savedGeneral || (mode?.writePayload != savedMode?.writePayload) || matrix != savedMatrix
    }

    var firmware: String { general?.firmware ?? "" }

    func reload() {
        do {
            let g = try mouse.readGeneral()
            let m = try mouse.readMode()
            let x = try mouse.readMatrix()
            general = g; savedGeneral = g
            mode = m; savedMode = m
            matrix = x; savedMatrix = x
            liveDPILevel = m.liveDPILevel
            lastError = nil
            status = "Read from mouse (firmware \(g.firmware))"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func revert() {
        general = savedGeneral; mode = savedMode; matrix = savedMatrix
        status = "Changes discarded"
    }

    /// Writes only the reports that changed, in the vendor's order: general → mode → matrix.
    func apply() {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            if let g = general, g != savedGeneral { try mouse.write(g); savedGeneral = g }
            if let m = mode, m.writePayload != savedMode?.writePayload { try mouse.write(m); savedMode = try mouse.readMode() }
            if let x = matrix, x != savedMatrix { try mouse.write(x); savedMatrix = x }
            // Confirm what the device actually stored.
            let g2 = try mouse.readGeneral()
            if let g = general, g2 != g { general = g2; savedGeneral = g2; status = "Applied; device adjusted some values" }
            else { status = "Applied to mouse" }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func pollLive() {
        guard !busy, general != nil else { return }
        if let m = try? mouse.readMode() {
            if m.liveDPILevel != liveDPILevel { liveDPILevel = m.liveDPILevel }
        }
    }

    // MARK: Backup / restore

    struct Backup: Codable {
        var version = 1
        var firmware: String
        var date: Date
        var general: [UInt8]
        var mode: [UInt8]
        var matrix: [UInt8]
    }

    func backupData() throws -> Data {
        guard let g = savedGeneral, let m = savedMode, let x = savedMatrix else { throw HIDError.deviceGone }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        return try enc.encode(Backup(firmware: g.firmware, date: Date(), general: g.raw, mode: m.raw, matrix: x.raw))
    }

    /// Loads a backup into the editable state (not written until Apply).
    func loadBackup(_ data: Data) throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(Backup.self, from: data)
        var g = try KoronaGeneral(raw: b.general)
        if let cur = general { g.raw.replaceSubrange(52..<58, with: cur.raw[52..<58]) }   // keep this unit's firmware string
        general = g
        mode = try KoronaMode(raw: b.mode)
        matrix = try KoronaMatrix(raw: b.matrix)
        status = "Backup loaded — press Apply to write it to the mouse"
    }

    /// Factory defaults from IOGEAR's Cfg.ini (DPI 400/800/1600/3200/5000, Colorful Streaming, factory buttons).
    func loadFactoryDefaults() {
        guard var g = general, var x = matrix, var m = mode else { return }
        g.stages = [DPIStage(dpi: 400, enabled: true, color: .red), DPIStage(dpi: 800, enabled: true, color: .green),
                    DPIStage(dpi: 1600, enabled: true, color: .blue), DPIStage(dpi: 3200, enabled: true, color: .yellow),
                    DPIStage(dpi: 5000, enabled: true, color: .magenta)] + Array(repeating: DPIStage(dpi: 400, enabled: false, color: .off), count: 3)
        g.ledMode = .colorfulStreaming; g.ledParam = 2; g.ledAux = 0
        g.ledColors = [RGB(255, 0, 0), RGB(0, 0, 255), RGB(0, 255, 0), RGB(128, 0, 255), RGB(250, 198, 3), RGB(250, 3, 106), RGB(250, 0, 250)]
        let factory: [ButtonAction] = [.leftClick, .rightClick, .middleClick, .back, .forward, .dpiUp, .dpiDown]
        for (i, a) in factory.enumerated() { x.set(a, mode: 1, button: i + 1) }
        for b in 8...Korona.matrixButtons { x.set(.disabled, mode: 1, button: b) }
        for mode in 1...3 { m.setRate(.hz500, mode: mode) }
        m.activeMode = 1
        general = g; matrix = x; self.mode = m
        status = "Factory defaults loaded — press Apply to write them"
    }
}
