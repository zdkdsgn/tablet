import Foundation
import IOKit.hid

/// Sends Touch Ring / corner LED state to the tablet, with software dimming.
///
/// The hardware has only three brightness levels plus off, and it re-applies the LED a little late
/// after every report – fast switching between levels (dithering) shows up as flicker. So fades are
/// sampled from a smooth curve and shown as the nearest real level, with hysteresis, sending a report
/// only when the level changes: gentle, flicker-free steps.
final class LEDDriver: @unchecked Sendable {
    /// What to show at time t (seconds since start): ring LED index, ring and corner brightness 0…1.
    typealias Render = (TimeInterval) -> (led: Int, ring: Double, corners: Double)

    /// Perceived brightness of the hardware levels: off, low, medium, high.
    private static let perceived: [Double] = [0, 0.3, 0.62, 1]
    /// Device values for those levels (3 = off on Intuos Pro).
    private static let raw: [Int] = [3, 0, 1, 2]

    private let queue = DispatchQueue(label: "tablet.leds", qos: .userInteractive)
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var render: Render?
    private var start = Date()
    private var duration: TimeInterval?
    private var onFinish: (() -> Void)?
    private var lastRing = 0, lastCorners = 0
    private var lastByte: UInt8?

    func setDevice(_ d: IOHIDDevice?) {
        queue.async { self.device = d; self.lastByte = nil }
    }

    /// Fixed levels (0…2, 3 = off) – one report, stops any running fade.
    func setStatic(led: Int, ring: Int, corners: Int) {
        queue.async {
            self.stopTimer()
            self.send(led: led, ringRaw: ring, cornersRaw: corners, force: true)
        }
    }

    /// Runs a smooth animation. `duration` nil = until replaced. `finished` runs on the main queue.
    func run(duration: TimeInterval?, _ render: @escaping Render, finished: (() -> Void)? = nil) {
        queue.async {
            self.render = render
            self.start = Date()
            self.duration = duration
            self.onFinish = finished
            if self.timer == nil {
                let t = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)
                t.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
                t.setEventHandler { [weak self] in self?.tick() }
                t.resume()
                self.timer = t
            }
        }
    }

    func stop() { queue.async { self.stopTimer() } }

    private func stopTimer() {
        timer?.cancel(); timer = nil
        render = nil; onFinish = nil
    }

    private func tick() {
        guard let render else { stopTimer(); return }
        let t = Date().timeIntervalSince(start)
        if let d = duration, t >= d {
            let done = onFinish
            stopTimer()
            if let done { DispatchQueue.main.async(execute: done) }
            return
        }
        let f = render(t)
        let r = quantize(f.ring, &lastRing)
        let c = quantize(f.corners, &lastCorners)
        send(led: f.led, ringRaw: r, cornersRaw: c, force: false)
    }

    /// Nearest hardware level for `v`, with hysteresis so a value hovering at a boundary does not toggle.
    private func quantize(_ v: Double, _ last: inout Int) -> Int {
        let p = Self.perceived
        let x = min(max(v, 0), 1)
        var best = 0
        for i in 1..<p.count where abs(p[i] - x) < abs(p[best] - x) { best = i }
        if best != last {
            let mid = (p[best] + p[last]) / 2
            if abs(x - mid) < 0.06 { best = last }      // stay until clearly past the midpoint
        }
        last = best
        return Self.raw[best]
    }

    private func send(led: Int, ringRaw: Int, cornersRaw: Int, force: Bool) {
        guard let dev = device else { return }
        let byte = UInt8(((cornersRaw & 3) << 4) | ((ringRaw & 3) << 2) | (led & 3))
        if !force && byte == lastByte { return }      // nothing changed – save the USB round trip
        lastByte = byte
        var buf = [UInt8](repeating: 0, count: 9)
        buf[0] = 0x20
        buf[1] = byte
        IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0x20, &buf, buf.count)
    }

    /// Perceived 0…1 value of a user brightness setting (0 low, 1 medium, 2 high).
    static func level(_ b: Int) -> Double { perceived[min(max(b, 0), 2) + 1] }
}
