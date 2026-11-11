import Foundation
import IOKit.hid

struct TouchPoint: Equatable {
    var id: Int
    var x: Double   // 0…4095
    var y: Double   // 0…4095
    /// Contact width / height as the tablet reports them (bytes 5, 6 of the chunk; bigger = larger contact).
    var w: Double = 0
    var h: Double = 0
    var size: Double { max(w, h) }
}

/// One pen sample beyond position: tilt in degrees (±64) and hover distance 0 (touching) … 1 (edge of range).
struct PenSample: Equatable {
    var mm: CGPoint
    var pressure: Double
    var tiltX: Double
    var tiltY: Double
    var distance: Double
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
        reopen()
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
    /// Pen sample (nil = out of range).
    var onPen: ((PenSample?) -> Void)?
    /// Pen came into range: tool ID and the pen's own serial number.
    var onPenIdentity: ((Int, UInt32) -> Void)?
    /// Touch on/off switch on the tablet's side (nil = not known yet).
    @Published private(set) var touchSwitchOn: Bool?
    /// Wireless kit battery in % (nil = no kit). The raw value jumps around, so the highest reading of the last minute is used.
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    private var batteryReadings: [(Date, Int)] = []
    private var batteryFirst: Date?
    private var lastPadFlags: UInt8?
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

    private let reader = HIDReader()
    private var devices = Set<IOHIDDevice>()
    private var slots = [TouchPoint?](repeating: nil, count: 16)
    private var started = false

    func start() {
        started = true
        reader.deliver = { [weak self] events in MainActor.assumeIsolated { self?.apply(events) } }
        reader.start(vendor: vendorID, product: productID, enhanced: enhanced)
    }

    /// Closes and reopens the tablet (another tablet, permission granted, after sleep).
    func reopen() {
        guard started else { return }
        devices.removeAll(); penInterface = nil; connected = false
        reader.start(vendor: vendorID, product: productID, enhanced: enhanced)
    }

    private var askedForAccess = false

    /// Input Monitoring state, checked in the background by the app (after the user granted it in System Settings
    /// the tablet is reopened so reports start flowing).
    func recheckAccess(granted: Bool) {
        if !granted && !askedForAccess {
            askedForAccess = true
            DispatchQueue.global(qos: .utility).async { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        }
        if granted != inputAccess {
            inputAccess = granted
            if granted { reopen() }
        }
    }

    private func debug(_ s: String) { AppLog.write(s, to: .hid) }

    /// Everything the HID thread decoded since the last batch, in order.
    private func apply(_ events: [HIDReader.Event]) {
        for e in events {
            switch e {
            case .added(let device, let page, let desc, let open):
                devices.insert(device)
                connected = true
                debug("device added \(desc) open=0x\(String(UInt32(bitPattern: open), radix: 16))")
                if page == 0xFF0D && enhanced {
                    penInterface = device
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.onConnect?() }
                }
            case .removed(let device):
                devices.remove(device)
                battery = nil; batteryReadings.removeAll(); batteryFirst = nil; touchSwitchOn = nil
                if device == penInterface { penInterface = nil }
                connected = !devices.isEmpty
                if !connected { slots = .init(repeating: nil, count: Self.maxPoints); publish() }
            case .report(let r):
                handle(r)
            }
        }
    }

    private func handle(_ r: WacomReport) {
        switch r {
        case .status(let st):
            updateStatus(st)
        case .pad(let ring, let button, let keys, let keyTouch, let flags):
            if flags != lastPadFlags { debug("pad flags \(String(format: "%02x", flags))"); lastPadFlags = flags }
            onRingButton?(button)
            onExpressKeys?(keys)
            if let keyTouch { onKeyTouch?(keyTouch) }
            onRing?(ring)
        case .penEnter(let tool, let serial):
            debug("pen enter tool 0x\(String(tool, radix: 16)) serial \(String(format: "%08X", serial))")
            onPenIdentity?(tool, serial)
            onTool?(tool & 0x8 != 0)   // erasers have bit 3 of the ID set (Pro Pen 0x802 tip / 0x80A eraser)
        case .pen(let sample):
            onPen?(sample)
        case .penExit:
            onPen?(nil)
        case .touch(.stillDown(let mask)):
            for i in 0..<Self.maxPoints where mask & (1 << i) == 0 { slots[i] = nil }
            publish()
        case .touch(.chunks(let fingers)):
            for f in fingers {
                slots[f.id] = f.up ? nil : TouchPoint(id: f.id, x: f.x, y: f.y, w: f.w, h: f.h)
            }
            touchReportsSeen += 1
            publish()
        case .other:
            break
        }
    }

    /// Battery (smoothed: highest reading of the last minute, after 20 s) and the touch switch.
    private func updateStatus(_ st: WacomReport.Status) {
        touchSwitchOn = st.touchSwitchOn
        if st.wireless {
            let now = Date()
            batteryReadings.append((now, st.level))
            batteryReadings.removeAll { now.timeIntervalSince($0.0) > 60 }
            batteryFirst = batteryFirst ?? now
            let level = now.timeIntervalSince(batteryFirst!) >= 20 ? batteryReadings.map(\.1).max() : nil
            if level != nil && level != battery { battery = level }
            if charging != st.charging { charging = st.charging }
        } else if battery != nil {
            battery = nil; batteryReadings.removeAll(); batteryFirst = nil
        }
    }

    private func publish() {
        let t = slots.compactMap { $0 }
        touches = t
        onTouches?(t)
    }
}

/// Reads the tablet on its own thread: reports are decoded there and handed to the main thread in batches
/// (about 120 a second), so a busy main thread never holds up the tablet and pen reports don't wake it 200× a second.
final class HIDReader: @unchecked Sendable {
    enum Event {
        case added(IOHIDDevice, page: Int, desc: String, open: IOReturn)
        case removed(IOHIDDevice)
        case report(WacomReport)
    }

    /// Called on the main thread with every batch.
    var deliver: (([Event]) -> Void)?

    private let lock = NSLock()
    private var pending: [Event] = []
    private var flushScheduled = false
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    // HID thread only
    private var manager: IOHIDManager?
    private var enhanced = true
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private var rawCounts: [String: Int] = [:]
    private var lastStatus: [UInt8] = []

    init() {
        let t = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            // keep the run loop alive with no sources yet
            let ctx = CFRunLoopSourceContext()
            var c = ctx
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &c)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            self.ready.signal()
            CFRunLoopRun()
        }
        t.name = "Tablet HID"
        t.qualityOfService = .userInteractive
        t.start()
        ready.wait()
    }

    /// (Re)opens the HID manager for this tablet on the reader thread.
    func start(vendor: Int, product: Int, enhanced: Bool) {
        perform { [self] in
            if let m = manager { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
            for (_, b) in buffers { b.deallocate() }
            buffers.removeAll()
            self.enhanced = enhanced
            let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: product] as CFDictionary)
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
                Unmanaged<HIDReader>.fromOpaque(ctx!).takeUnretainedValue().added(device)
            }, ctx)
            IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
                Unmanaged<HIDReader>.fromOpaque(ctx!).takeUnretainedValue().removed(device)
            }, ctx)
            IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
            manager = m
        }
    }

    private func perform(_ block: @escaping () -> Void) {
        guard let rl = runLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    private func added(_ device: IOHIDDevice) {
        let n = { (k: String) in (IOHIDDeviceGetProperty(device, k as CFString) as? NSNumber)?.intValue ?? -1 }
        let maxLen = max(0, n(kIOHIDMaxInputReportSizeKey))
        let page = n(kIOHIDPrimaryUsagePageKey)
        let desc = "page=0x\(String(page, radix: 16)) usage=0x\(String(n(kIOHIDPrimaryUsageKey), radix: 16)) in=\(maxLen)"
        let open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        enqueue(.added(device, page: page, desc: desc, open: open))
        guard maxLen > 0 else { return }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: maxLen)
        buffers[device] = buf
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, maxLen, { ctx, result, _, _, _, report, length in
            guard result == kIOReturnSuccess else { return }
            Unmanaged<HIDReader>.fromOpaque(ctx!).takeUnretainedValue()
                .received(Array(UnsafeBufferPointer(start: report, count: length)))
        }, ctx)
    }

    private func removed(_ device: IOHIDDevice) {
        if let b = buffers.removeValue(forKey: device) { b.deallocate() }
        enqueue(.removed(device))
    }

    private func received(_ bytes: [UInt8]) {
        // ~/Library/Logs/Tablet-hid.log: the first reports of each kind, and status changes (not battery flicker)
        let key = "len\(bytes.count)-id\(bytes.first ?? 0)"
        let c = rawCounts[key, default: 0]
        if c < 40 {
            rawCounts[key] = c + 1
            AppLog.write("report \(key): " + bytes.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " "), to: .hid)
        }
        if bytes.first == 0xC0 {
            let sig = WacomReport.statusSignature(bytes)
            if sig != lastStatus {
                lastStatus = sig
                AppLog.write("status " + bytes.map { String(format: "%02x", $0) }.joined(separator: " "), to: .hid)
            }
        }
        let r = WacomReport.decode(bytes, enhanced: enhanced)
        if r != .other { enqueue(.report(r)) }
    }

    private func enqueue(_ e: Event) {
        let schedule: Bool = lock.withLock {
            pending.append(e)
            if flushScheduled { return false }
            flushScheduled = true
            return true
        }
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120) { [weak self] in
            guard let self else { return }
            let batch: [Event] = self.lock.withLock {
                let b = self.pending
                self.pending.removeAll(keepingCapacity: true)
                self.flushScheduled = false
                return b
            }
            self.deliver?(batch)
        }
    }
}
