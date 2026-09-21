import Foundation
import Combine
import KaliberHID

/// Tracks connected Kaliber devices and the Input Monitoring permission state.
@MainActor
final class DeviceMonitor: ObservableObject {
    @Published private(set) var mouse: MouseModel?
    @Published private(set) var keyboard: KeyboardModel?
    @Published private(set) var access: HIDAccess.Status = HIDAccess.status

    private let watcher: HIDWatcher
    private var accessTimer: Timer?

    init() {
        watcher = HIDWatcher(matches: [
            .init(vendorID: Korona.vendorID, productID: Korona.productID),
            .init(vendorID: Hver.vendorID, productID: Hver.productID),
        ])
        watcher.onAdd = { [weak self] dev in Task { @MainActor in self?.added(dev) } }
        watcher.onRemove = { [weak self] dev in Task { @MainActor in self?.removed(dev) } }
        watcher.start()
        // TCC changes are not observable; poll cheaply while the app is open.
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = HIDAccess.status
                if now != self.access { self.access = now; if now == .granted { self.mouse?.reload(); self.keyboard?.reload() } }
            }
        }
    }

    func requestAccess() {
        HIDAccess.request()
        access = HIDAccess.status
    }

    /// Clears this app's Input Monitoring record (stale after the app's signing identity changes) and asks again.
    func resetAccess() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ListenEvent", Bundle.main.bundleIdentifier ?? "com.alexjukl.kaliberconfig"]
        try? p.run(); p.waitUntilExit()
        requestAccess()
    }

    private func added(_ dev: HIDDevice) {
        if dev.vendorID == Korona.vendorID, dev.productID == Korona.productID, dev.hasUsage(page: Korona.vendorUsagePage) {
            if mouse == nil { mouse = MouseModel(device: dev) }
        } else if dev.vendorID == Hver.vendorID, dev.productID == Hver.productID, dev.hasUsage(page: Hver.vendorUsagePage, usage: Hver.vendorUsage) {
            if keyboard == nil { keyboard = KeyboardModel(device: dev) }
        }
    }

    private func removed(_ dev: HIDDevice) {
        if let m = mouse, m.mouse.device == dev { mouse = nil }
        if let k = keyboard, k.keyboard.device == dev { keyboard = nil }
    }
}
