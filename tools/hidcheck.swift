import Foundation
import IOKit.hid

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x258A, kIOHIDProductIDKey: 0x1007] as CFDictionary)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
let devs = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
print("access status (listen):", IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue, " (0=granted 1=denied 2=unknown)")
for d in devs {
    let up = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
    let u = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
    let pairs = IOHIDDeviceGetProperty(d, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
    let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
    print("device usage \(up)/\(u) pairs=\(pairs.map { "\($0["DeviceUsagePage"]!)/\($0["DeviceUsage"]!)" }) open=0x\(String(r, radix: 16))")
    if r == kIOReturnSuccess { IOHIDDeviceClose(d, 0) }
}
if CommandLine.arguments.contains("--request") {
    print("requesting access ->", IOHIDRequestAccess(kIOHIDRequestTypeListenEvent))
}
