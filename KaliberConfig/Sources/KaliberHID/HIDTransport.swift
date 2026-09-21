import Foundation
import IOKit
import IOKit.hid

public enum HIDError: Error, LocalizedError {
    case notPermitted
    case openFailed(IOReturn)
    case transferFailed(IOReturn)
    case badReply([UInt8])
    case deviceGone

    public var errorDescription: String? {
        switch self {
        case .notPermitted: return "macOS denied access to the device (Input Monitoring permission)."
        case .openFailed(let r): return String(format: "Could not open device (IOReturn 0x%08x).", UInt32(bitPattern: r))
        case .transferFailed(let r): return String(format: "USB transfer failed (IOReturn 0x%08x).", UInt32(bitPattern: r))
        case .badReply(let b): return "Unexpected reply from device: \(b.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))"
        case .deviceGone: return "The device was disconnected."
        }
    }
}

/// Input Monitoring (TCC "ListenEvent") access, required to open HID devices that macOS
/// classifies as keyboards — which includes the vendor collections of both Kaliber devices.
public enum HIDAccess {
    public enum Status { case granted, denied, unknown }

    public static var status: Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    /// Shows the system prompt when the status is `.unknown`; returns the new grant state.
    @discardableResult
    public static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
}

/// A single IOHIDDevice (one USB interface / top-level collection group) with feature-report helpers.
public final class HIDDevice: Hashable, @unchecked Sendable {
    public let device: IOHIDDevice
    public let vendorID: Int
    public let productID: Int
    public let product: String
    public let locationID: Int
    public let usagePairs: [(page: Int, usage: Int)]
    private var isOpen = false
    private let lock = NSLock()
    /// Delay after every transfer; the vendor tools sleep 20 ms and the KORONA garbles reads without it.
    public var settleTime: TimeInterval = 0.03

    init(_ device: IOHIDDevice) {
        self.device = device
        func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? Int) ?? 0 }
        vendorID = int(kIOHIDVendorIDKey)
        productID = int(kIOHIDProductIDKey)
        product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        locationID = int(kIOHIDLocationIDKey)
        let pairs = (IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]]) ?? []
        usagePairs = pairs.compactMap { p in
            guard let page = p[kIOHIDDeviceUsagePageKey], let usage = p[kIOHIDDeviceUsageKey] else { return nil }
            return (page, usage)
        }
    }

    public func hasUsage(page: Int, usage: Int? = nil) -> Bool {
        usagePairs.contains { $0.page == page && (usage == nil || $0.usage == usage) }
    }

    public func open() throws {
        lock.lock(); defer { lock.unlock() }
        guard !isOpen else { return }
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnNotPermitted { throw HIDError.notPermitted }
        guard r == kIOReturnSuccess else { throw HIDError.openFailed(r) }
        isOpen = true
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return }
        if listening {
            IOHIDDeviceUnscheduleFromRunLoop(device, HIDRunLoop.shared.runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device, inputBuffer!, inputBufferSize, nil, nil)
            listening = false
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    /// Reads a feature report; returns the payload without the report ID.
    public func getFeature(id: UInt8, length: Int, retries: Int = 4) throws -> [UInt8] {
        try open()
        var lastBad: [UInt8] = []
        for _ in 0...retries {
            var buf = [UInt8](repeating: 0, count: length + 1)
            buf[0] = id
            var len = CFIndex(buf.count)
            let r = buf.withUnsafeMutableBufferPointer { p in
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), p.baseAddress!, &len)
            }
            Thread.sleep(forTimeInterval: settleTime)
            guard r == kIOReturnSuccess else { throw HIDError.transferFailed(r) }
            if len == length + 1, buf[0] == id { return Array(buf[1...]) }
            lastBad = Array(buf.prefix(Int(len)))
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw HIDError.badReply(lastBad)
    }

    /// Writes a feature report; `payload` excludes the report ID.
    public func setFeature(id: UInt8, payload: [UInt8], retries: Int = 2) throws {
        try open()
        let buf = [id] + payload
        var last: IOReturn = kIOReturnError
        for _ in 0...retries {
            last = buf.withUnsafeBufferPointer { p in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(id), p.baseAddress!, CFIndex(buf.count))
            }
            Thread.sleep(forTimeInterval: settleTime)
            if last == kIOReturnSuccess { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw HIDError.transferFailed(last)
    }

    // MARK: Output reports + input-report replies (used by the SONiX keyboard protocol)

    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var inputBufferSize = 0
    private var listening = false
    private let replyLock = NSCondition()
    private var pendingReplies: [[UInt8]] = []

    /// Starts receiving input reports on a background run loop (idempotent).
    public func startListening() throws {
        try open()
        lock.lock(); defer { lock.unlock() }
        guard !listening else { return }
        let size = max(64, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64)
        inputBufferSize = size
        inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer!, size, { ctx, _, _, _, id, report, length in
            let me = Unmanaged<HIDDevice>.fromOpaque(ctx!).takeUnretainedValue()
            // IOKit hands us the raw report; when the device uses report IDs the ID is byte 0 already.
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            if id != 0, bytes.first != UInt8(id) { bytes.insert(UInt8(id), at: 0) }
            me.replyLock.lock(); me.pendingReplies.append(bytes); if me.pendingReplies.count > 32 { me.pendingReplies.removeFirst() }
            me.replyLock.broadcast(); me.replyLock.unlock()
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, HIDRunLoop.shared.runLoop, CFRunLoopMode.defaultMode.rawValue)
        listening = true
    }

    /// Sends an output report (`payload` excludes the report ID).
    public func sendOutput(id: UInt8, payload: [UInt8]) throws {
        try open()
        let buf = [id] + payload
        let r = buf.withUnsafeBufferPointer { p in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(id), p.baseAddress!, CFIndex(buf.count))
        }
        guard r == kIOReturnSuccess else { throw HIDError.transferFailed(r) }
    }

    /// Sends an output report and waits for an input report accepted by `matches` (bytes include the report ID).
    public func exchange(id: UInt8, payload: [UInt8], timeout: TimeInterval = 1.0, matches: ([UInt8]) -> Bool) throws -> [UInt8] {
        try startListening()
        replyLock.lock(); pendingReplies.removeAll(); replyLock.unlock()
        try sendOutput(id: id, payload: payload)
        let deadline = Date().addingTimeInterval(timeout)
        replyLock.lock(); defer { replyLock.unlock() }
        while true {
            if let i = pendingReplies.firstIndex(where: matches) {
                let r = pendingReplies[i]; pendingReplies.removeSubrange(0...i); return r
            }
            if !replyLock.wait(until: deadline) { throw HIDError.badReply([]) }
        }
    }

    public static func == (a: HIDDevice, b: HIDDevice) -> Bool { a.device == b.device }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(device)) }
}

/// Watches for HID devices matching `(vendorID, productID)` pairs and reports arrivals/removals on the main thread.
public final class HIDWatcher {
    public struct Match: Hashable { public let vendorID: Int; public let productID: Int
        public init(vendorID: Int, productID: Int) { self.vendorID = vendorID; self.productID = productID } }

    private let manager: IOHIDManager
    private var devices: [IOHIDDevice: HIDDevice] = [:]
    public var onAdd: ((HIDDevice) -> Void)?
    public var onRemove: ((HIDDevice) -> Void)?

    public init(matches: [Match]) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let dicts = matches.map { [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(manager, dicts as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            let d = HIDDevice(dev)
            me.devices[dev] = d
            me.onAdd?(d)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            if let d = me.devices.removeValue(forKey: dev) { d.close(); me.onRemove?(d) }
        }, ctx)
    }

    /// Starts delivering callbacks on the main run loop. Does not open devices.
    public func start() {
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public var current: [HIDDevice] { Array(devices.values) }
}

/// A background thread whose run loop services input-report callbacks for all devices.
final class HIDRunLoop {
    static let shared = HIDRunLoop()
    private(set) var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)
    private init() {
        let t = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            // Keep the loop alive with a port that never fires.
            let port = NSMachPort()
            RunLoop.current.add(port, forMode: .default)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "KaliberHID.runloop"; t.qualityOfService = .userInitiated
        t.start()
        ready.wait()
    }
}
