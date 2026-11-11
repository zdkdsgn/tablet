import Foundation

/// Decodes the Intuos5 / Intuos Pro HID reports (layouts from the Linux wacom driver).
/// Pure functions, no state – used by the HID thread and by the tests.
enum WacomReport: Equatable {
    /// 0xC0 status: wireless kit, battery 0…100, charging, side touch switch.
    case status(Status)
    /// 0x03 pad: Touch Ring (nil = no finger), ring centre button, ExpressKeys pressed / only touched.
    case pad(ring: Int?, ringButton: Bool, keys: [Bool], keyTouch: [Bool]?, flags: UInt8)
    /// The pen came into range: tool ID and the pen's serial number.
    case penEnter(tool: Int, serial: UInt32)
    case pen(PenSample)
    case penExit
    /// Touch: either a "still down" mask or finger chunks.
    case touch(TouchReport)
    case other

    struct Status: Equatable {
        var wireless: Bool
        var level: Int          // 0…100, raw (jumps around – smoothed by DeviceMonitor)
        var charging: Bool
        var touchSwitchOn: Bool
    }

    enum TouchReport: Equatable {
        case stillDown(mask: Int)
        case chunks([Finger])
    }

    struct Finger: Equatable {
        var id: Int
        var up: Bool
        var x: Double, y: Double, w: Double, h: Double
    }

    static func decode(_ b: [UInt8], enhanced: Bool) -> WacomReport {
        guard let id = b.first else { return .other }
        if id == 0xC0 { return status(b).map { .status($0) } ?? .other }
        if enhanced, id == 0x03, b.count >= 5 {
            return .pad(ring: b[2] & 0x80 != 0 ? Int(b[2] & 0x7F) : nil,
                        ringButton: b[3] & 0x01 != 0,
                        keys: (0..<8).map { b[4] & (1 << $0) != 0 },
                        keyTouch: b.count > 5 ? (0..<8).map { b[5] & (1 << $0) != 0 } : nil,
                        flags: b[1])
        }
        if enhanced, id == 0x02, b.count >= 9 {
            // [1] & 0xFC == 0xC0: tool entered proximity (Linux wacom_intuos_inout)
            if b[1] & 0xFC == 0xC0 {
                let tool = (Int(b[2]) << 4) | (Int(b[3]) >> 4) | ((Int(b[7]) & 0x0F) << 16) | ((Int(b[8]) & 0xF0) << 8)
                let serial = (UInt32(b[3] & 0x0F) << 28) | (UInt32(b[4]) << 20) | (UInt32(b[5]) << 12)
                    | (UInt32(b[6]) << 4) | (UInt32(b[7]) >> 4)
                return .penEnter(tool: tool, serial: serial)
            }
            if b.count >= 10, b[1] & 0xB8 == 0xA0 {
                // general pen report (Linux wacom_intuos_general): 16-bit + 1 extra bit per axis, 200 lines per mm
                let x = (Int(b[2]) << 9) | (Int(b[3]) << 1) | ((Int(b[9]) >> 1) & 1)
                let y = (Int(b[4]) << 9) | (Int(b[5]) << 1) | (Int(b[9]) & 1)
                let p = (Int(b[6]) << 3) | ((Int(b[7]) & 0xC0) >> 5) | (Int(b[1]) & 1)
                let tx = Double(((Int(b[7]) << 1) & 0x7E) | (Int(b[8]) >> 7)) - 64
                let ty = Double(Int(b[8]) & 0x7F) - 64
                let pressure = min(1, Double(p) / 2047)
                return .pen(PenSample(mm: CGPoint(x: Double(x) / 200, y: Double(y) / 200), pressure: pressure,
                                      tiltX: tx, tiltY: ty, distance: pressure > 0 ? 0 : Double(b[9] >> 2) / 63))
            }
            if b[1] & 0xFE == 0x80 { return .penExit }
            return .other
        }
        if b.count > 11 { return touch(b).map { .touch($0) } ?? .other }
        return .other
    }

    /// Linux wacom_status_irq: [9] & 0x02 = wireless module, [8] & 0x3F = level 0…31, [8] & 0x80 = charging.
    /// [8] & 0x40 = touch switch off (as on Intuos HT; still to be confirmed on this model).
    static func status(_ b: [UInt8]) -> Status? {
        guard b.count > 9 else { return nil }
        return Status(wireless: b[9] & 0x02 != 0, level: Int(b[8] & 0x3F) * 100 / 31,
                      charging: b[8] & 0x80 != 0, touchSwitchOn: b[8] & 0x40 == 0)
    }

    /// Wacom 64-byte touch report (as OpenTabletDriver's WacomTouchReport): [1] chunk count, 8-byte chunks
    /// (id, state, xHi, yHi, xLo|yLo, width, height…). Chunk id 0x80 = ExpressKeys; [2] == 0x81 = "still down" mask.
    static func touch(_ r: [UInt8]) -> TouchReport? {
        guard r.count >= 10 else { return nil }
        if r[2] == 0x81 { return .stillDown(mask: Int(r[3]) | (Int(r[4]) << 8)) }
        var out: [Finger] = []
        for i in 0..<Int(r[1]) {
            let o = (i << 3) + 2
            guard o + 4 < r.count else { break }
            let raw = Int(r[o])
            if raw == 0x80 { continue }
            let id = raw - 2
            guard id >= 0, id < 16 else { continue }
            let x = (Int(r[o + 2]) << 4) | (Int(r[o + 4]) >> 4)
            let y = (Int(r[o + 3]) << 4) | (Int(r[o + 4]) & 0xF)
            out.append(Finger(id: id, up: r[o + 1] == 0x20, x: Double(x), y: Double(y),
                              w: o + 5 < r.count ? Double(r[o + 5]) : 0, h: o + 6 < r.count ? Double(r[o + 6]) : 0))
        }
        return out.isEmpty ? nil : .chunks(out)
    }

    /// Status bits worth logging: everything except the battery level, which flickers every few seconds.
    static func statusSignature(_ b: [UInt8]) -> [UInt8] {
        var s = b
        if s.count > 8 { s[8] &= 0xC0 }
        return s
    }
}
