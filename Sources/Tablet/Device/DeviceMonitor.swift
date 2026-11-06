import Foundation
import IOKit.hid

struct TouchPoint: Equatable {
    var id: Int
    var x: Double   // 0…4095
    var y: Double   // 0…4095
}

/// Watches for the Intuos Pro M over USB and reads its touch reports.
/// The device is opened *without* seizing it, so OpenTabletDriver keeps working alongside.
@MainActor
final class DeviceMonitor: ObservableObject {
    private(set) var vendorID = 0x056A
    private(set) var productID = 0x0315
    /// Intuos5 / Intuos Pro report format: Touch Ring, LEDs and touch are read by this app.
    private(set) var enhanced = true

    /// Watches another tablet (after OpenTabletDriver detected it).
    func setTarget(_ t: TabletInfo) {
        enhanced = t.enhanced
        guard t.vendorID != 0, t.vendorID != vendorID || t.productID != productID else { return }
        vendorID = t.vendorID; productID = t.productID
        if let m = manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
        devices.removeAll(); penInterface = nil; connected = false
        start()
    }
    static let touchMax = 4095.0
    static let maxPoints = 16

    @Published private(set) var connected = false
    @Published private(set) var inputAccess = true
    @Published private(set) var touches: [TouchPoint] = []
    @Published private(set) var touchReportsSeen = 0

    var onTouches: (([TouchPoint]) -> Void)?
    var onRing: ((Int?) -> Void)?
    var onRingButton: ((Bool) -> Void)?
    var onExpressKeys: (([Bool]) -> Void)?
    var onKeyTouch: (([Bool]) -> Void)?
    /// The pen came into range: true = eraser end, false = tip (from the tool ID in the "enter" report).
    var onTool: ((Bool) -> Void)?
    /// Pen position in mm (nil = out of range) and tip pressure 0…1.
    var onPen: ((CGPoint?, Double) -> Void)?
    /// Called when the tablet (re)appears, e.g. to restore the ring LED.
    var onConnect: (() -> Void)?

    private var penInterface: IOHIDDevice? { didSet { leds.setDevice(penInterface) } }
    /// LED output with software dimming (runs on its own queue).
    let leds = LEDDriver()
    private var ledLogCount = 0

    /// Lights one of the four Touch Ring LEDs (0…3). Same command the Linux wacom driver uses
    /// for Intuos5 / Intuos Pro: feature report 0x20, byte 1 = brightness << 2 | led.
    /// Brightness: 0 = low, 1 = medium, 2 = high, 3 = off. `corners` = the four crop-mark LEDs (all together).
    @discardableResult
    func setRingLED(_ index: Int, brightness: Int = 2, corners: Int = 3) -> Bool {
        guard let dev = penInterface else { return false }
        var buf = [UInt8](repeating: 0, count: 9)
        buf[0] = 0x20
        buf[1] = UInt8(((corners & 0x03) << 4) | ((brightness & 0x03) << 2) | (index & 0x03))
        let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0x20, &buf, buf.count)
        if ledLogCount < 5 { ledLogCount += 1; debug("LED byte 0x\(String(buf[1], radix: 16)) → 0x\(String(UInt32(bitPattern: r), radix: 16))") }
        return r == kIOReturnSuccess
    }

    private var manager: IOHIDManager?
    private var devices = Set<IOHIDDevice>()
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private var slots = [TouchPoint?](repeating: nil, count: 16)

    func start() {
        guard manager == nil else { return }
        inputAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if !inputAccess { inputAccess = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            let me = Unmanaged<DeviceMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.added(device) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            let me = Unmanaged<DeviceMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.removed(device) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    /// Re-checks Input Monitoring (after the user granted it in System Settings).
    func recheckAccess() {
        let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if granted != inputAccess {
            inputAccess = granted
            if granted, let m = manager {   // reopen so reports start flowing
                IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
                manager = nil
                devices.removeAll()
                start()
            }
        }
    }

    // MARK: debug log (~/Library/Logs/Tablet-hid.log), first reports per interface
    private var debugCounts: [String: Int] = [:]
    private func debug(_ s: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tablet-hid.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
    private func describe(_ d: IOHIDDevice) -> String {
        let n = { (k: String) in (IOHIDDeviceGetProperty(d, k as CFString) as? NSNumber)?.intValue ?? -1 }
        return "page=0x\(String(n(kIOHIDPrimaryUsagePageKey), radix: 16)) usage=0x\(String(n(kIOHIDPrimaryUsageKey), radix: 16)) in=\(n(kIOHIDMaxInputReportSizeKey))"
    }

    private func added(_ device: IOHIDDevice) {
        devices.insert(device)
        connected = true
        let maxLen = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        let desc = describe(device)
        let openRes = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        debug("device added \(desc) open=0x\(String(UInt32(bitPattern: openRes), radix: 16))")
        guard maxLen > 0 else { return }
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        if page == 0xFF0D && enhanced {
            penInterface = device
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.onConnect?() }
        }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: maxLen)
        buffers[device] = buf
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, maxLen, { ctx, result, _, _, _, report, length in
            guard result == kIOReturnSuccess else { return }
            let me = Unmanaged<DeviceMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { me.received(bytes, maxLen: length) }
        }, ctx)
    }

    private func received(_ bytes: [UInt8], maxLen: Int) {
        let key = "len\(bytes.count)-id\(bytes.first ?? 0)"
        let c = debugCounts[key, default: 0]
        if c < 40 {
            debugCounts[key] = c + 1
            debug("report \(key): " + bytes.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        // Pad report on the pen interface: [2] = Touch Ring (bit 7 = finger on it, 0…71 position)
        if enhanced, bytes.first == 0x03, bytes.count >= 5 {
            onRingButton?(bytes[3] & 0x01 != 0)
            onExpressKeys?((0..<8).map { bytes[4] & (1 << $0) != 0 })
            // byte 5: ExpressKeys that are only touched (capacitive sensing, Wacom's "Express View")
            if bytes.count > 5 { onKeyTouch?((0..<8).map { bytes[5] & (1 << $0) != 0 }) }
            onRing?(bytes[2] & 0x80 != 0 ? Int(bytes[2] & 0x7F) : nil)
            return
        }
        // Pen report: [1] & 0xFC == 0xC0 is "tool entered proximity" with the tool ID (Linux wacom_intuos_inout).
        // Erasers have bit 3 of the ID set (Pro Pen 0x802 tip / 0x80A eraser).
        if enhanced, bytes.first == 0x02, bytes.count >= 9 {
            if bytes[1] & 0xFC == 0xC0 {
                let id = (Int(bytes[2]) << 4) | (Int(bytes[3]) >> 4) | ((Int(bytes[7]) & 0x0F) << 16) | ((Int(bytes[8]) & 0xF0) << 8)
                debug("pen enter tool 0x\(String(id, radix: 16))")
                onTool?(id & 0x8 != 0)
            } else if bytes.count >= 10, bytes[1] & 0xB8 == 0xA0 {
                // general pen report (Linux wacom_intuos_general): 16-bit + 1 extra bit per axis, 200 lines per mm
                let x = (Int(bytes[2]) << 9) | (Int(bytes[3]) << 1) | ((Int(bytes[9]) >> 1) & 1)
                let y = (Int(bytes[4]) << 9) | (Int(bytes[5]) << 1) | (Int(bytes[9]) & 1)
                let p = (Int(bytes[6]) << 3) | ((Int(bytes[7]) & 0xC0) >> 5) | (Int(bytes[1]) & 1)
                onPen?(CGPoint(x: Double(x) / 200, y: Double(y) / 200), min(1, Double(p) / 2047))
            } else if bytes[1] & 0xFE == 0x80 {
                onPen?(nil, 0)   // left proximity
            }
            return
        }
        if bytes.count >= 10 && bytes.count != 10 && bytes.count != 11 { handle(bytes) }
    }

    private func removed(_ device: IOHIDDevice) {
        devices.remove(device)
        if device == penInterface { penInterface = nil }
        if let b = buffers.removeValue(forKey: device) { b.deallocate() }
        connected = !devices.isEmpty
        if !connected { slots = .init(repeating: nil, count: Self.maxPoints); publish() }
    }

    /// Wacom 64-byte touch report, same layout OpenTabletDriver's WacomTouchReport parses:
    /// [0] report id, [1] chunk count, then 8-byte chunks: id, state, xHi, yHi, xLo|yLo nibble…
    /// A chunk with id 0x80 carries ExpressKeys; [2] == 0x81 is a "which fingers are still down" mask.
    private func handle(_ r: [UInt8]) {
        guard r.count >= 10 else { return }
        if r[2] == 0x81 {
            let mask = Int(r[3]) | (Int(r[4]) << 8)
            for i in 0..<Self.maxPoints where mask & (1 << i) == 0 { slots[i] = nil }
            publish()
            return
        }
        let chunks = Int(r[1])
        var sawTouch = false
        for i in 0..<chunks {
            let o = (i << 3) + 2
            guard o + 4 < r.count else { break }
            let rawID = Int(r[o])
            if rawID == 0x80 { continue }      // ExpressKeys – OpenTabletDriver handles them
            let id = rawID - 2
            guard id >= 0, id < Self.maxPoints else { continue }
            sawTouch = true
            if r[o + 1] == 0x20 {
                slots[id] = nil
            } else {
                let x = (Int(r[o + 2]) << 4) | (Int(r[o + 4]) >> 4)
                let y = (Int(r[o + 3]) << 4) | (Int(r[o + 4]) & 0xF)
                slots[id] = TouchPoint(id: id, x: Double(x), y: Double(y))
            }
        }
        if sawTouch { touchReportsSeen += 1; publish() }
    }

    private func publish() {
        let t = slots.compactMap { $0 }
        touches = t
        onTouches?(t)
    }
}
