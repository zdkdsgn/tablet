import AppKit
import ApplicationServices

/// Which gestures are on – stored in UserDefaults.
@MainActor
final class TouchSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "touch.enabled") } }
    @Published var move: Bool { didSet { d.set(move, forKey: "touch.move") } }
    @Published var tap: Bool { didSet { d.set(tap, forKey: "touch.tap") } }
    @Published var rightTap: Bool { didSet { d.set(rightTap, forKey: "touch.rightTap") } }
    @Published var scroll: Bool { didSet { d.set(scroll, forKey: "touch.scroll") } }
    @Published var naturalScroll: Bool { didSet { d.set(naturalScroll, forKey: "touch.natural") } }
    @Published var pinch: Bool { didSet { d.set(pinch, forKey: "touch.pinch") } }
    @Published var swipeSpaces: Bool { didSet { d.set(swipeSpaces, forKey: "touch.swipe") } }
    @Published var missionControl: Bool { didSet { d.set(missionControl, forKey: "touch.mission") } }
    @Published var palmRejection: Bool { didSet { d.set(palmRejection, forKey: "touch.palm") } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "touch.speed") } }
    /// Ignore touch while a contact larger than `palmSize` (the tablet's contact size units) is on the tablet.
    @Published var palmBySize: Bool { didSet { d.set(palmBySize, forKey: "touch.palmBySize") } }
    @Published var palmSize: Double { didSet { d.set(palmSize, forKey: "touch.palmSize") } }

    func isPalm(_ t: TouchPoint) -> Bool { palmBySize && t.size >= palmSize }

    init() {
        d.register(defaults: ["touch.enabled": true, "touch.move": true, "touch.tap": true, "touch.rightTap": true,
                              "touch.scroll": true, "touch.natural": true, "touch.pinch": true, "touch.swipe": true,
                              "touch.mission": true, "touch.palm": true, "touch.speed": 6.0,
                              "touch.palmBySize": false, "touch.palmSize": 12.0])
        enabled = d.bool(forKey: "touch.enabled"); move = d.bool(forKey: "touch.move")
        tap = d.bool(forKey: "touch.tap"); rightTap = d.bool(forKey: "touch.rightTap")
        scroll = d.bool(forKey: "touch.scroll"); naturalScroll = d.bool(forKey: "touch.natural")
        pinch = d.bool(forKey: "touch.pinch"); swipeSpaces = d.bool(forKey: "touch.swipe")
        missionControl = d.bool(forKey: "touch.mission"); palmRejection = d.bool(forKey: "touch.palm")
        speed = d.double(forKey: "touch.speed")
        palmBySize = d.bool(forKey: "touch.palmBySize"); palmSize = d.double(forKey: "touch.palmSize")
    }
}

/// Turns finger positions into cursor movement, clicks, scrolling and gestures – like a trackpad.
@MainActor
final class TouchEngine {
    /// Marks events we post, so palm rejection can tell them apart from the pen.
    static let marker: Int64 = 0x7AB1E7

    private let settings: TouchSettings
    private let source = CGEventSource(stateID: .hidSystemState)

    // Size of one touch unit in millimetres (touch sensor 223.52 × 139.7 mm, 0…4095 each).
    private let mmX = 223.52 / 4095, mmY = 139.7 / 4095

    private enum Mode { case idle, undecided, move, scroll, pinch, swipe, done }
    private var mode: Mode = .idle
    private var palmDown = false
    private var startTime = Date()
    private var maxFingers = 0
    private var travelled = 0.0           // mm, for tap detection
    private var lastCentroid: CGPoint?
    private var lastSpread: Double?
    private var accum = CGPoint.zero      // mm, for swipes / decision
    private var pinchAccum = 0.0
    private var scrollRemainder = CGPoint.zero
    private var penActiveUntil = Date.distantPast
    private var monitor: Any?

    init(settings: TouchSettings) {
        self.settings = settings
        // Pen strokes (posted by OpenTabletDriver) silence touch for a moment – palm rejection.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .tabletPoint, .tabletProximity]) { [weak self] e in
            guard let self else { return }
            if e.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.marker { return }
            MainActor.assumeIsolated { self.penActiveUntil = Date().addingTimeInterval(0.6) }
        }
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func update(_ touches: [TouchPoint]) {
        guard settings.enabled else { reset(); return }
        if settings.palmRejection, Date() < penActiveUntil || touches.count > 4 {
            reset(); mode = touches.isEmpty ? .idle : .done; return
        }
        // a palm (large contact) on the tablet: ignore everything until all fingers are lifted
        if touches.contains(where: settings.isPalm) { palmDown = true }
        if palmDown {
            if touches.isEmpty { palmDown = false; reset(); mode = .idle } else { reset(); mode = .done }
            return
        }
        if touches.isEmpty { finish(); return }

        let c = CGPoint(x: touches.map(\.x).reduce(0, +) / Double(touches.count),
                        y: touches.map(\.y).reduce(0, +) / Double(touches.count))
        let spread = touches.count >= 2 ? hypot((touches[0].x - touches[1].x) * mmX, (touches[0].y - touches[1].y) * mmY) : nil

        if mode == .idle { begin() }
        if touches.count != maxFingers {
            // finger count changed: restart deltas so the cursor does not jump
            maxFingers = max(maxFingers, touches.count)
            lastCentroid = c; lastSpread = spread
            if mode == .move && touches.count > 1 { mode = .undecided }
            return
        }
        guard let last = lastCentroid else { lastCentroid = c; lastSpread = spread; return }
        let d = CGPoint(x: (c.x - last.x) * mmX, y: (c.y - last.y) * mmY)
        lastCentroid = c
        travelled += hypot(d.x, d.y)
        accum.x += d.x; accum.y += d.y

        switch touches.count {
        case 1:
            if mode == .undecided || mode == .move { mode = .move; if settings.move { moveCursor(d) } }
        case 2:
            let ds = (spread ?? 0) - (lastSpread ?? spread ?? 0)
            lastSpread = spread
            if mode == .undecided || mode == .move {
                pinchAccum += ds
                if settings.pinch && abs(pinchAccum) > 4 && abs(pinchAccum) > hypot(accum.x, accum.y) { mode = .pinch; pinchAccum = 0 }
                else if hypot(accum.x, accum.y) > 1.5 { mode = .scroll }
            }
            if mode == .scroll, settings.scroll { postScroll(d) }
            if mode == .pinch { pinchAccum += ds; zoomSteps() }
        case 3:
            if mode != .done { mode = .swipe; swipeCheck() }
        default:
            break
        }
    }

    private func begin() {
        mode = .undecided; startTime = Date(); maxFingers = 0; travelled = 0
        accum = .zero; pinchAccum = 0; scrollRemainder = .zero; lastCentroid = nil; lastSpread = nil
    }

    private func finish() {
        let quick = Date().timeIntervalSince(startTime) < 0.25 && travelled < 1.5
        if quick && mode != .done && mode != .idle {
            if maxFingers == 1, settings.tap { click(.left) }
            else if maxFingers == 2, settings.rightTap { click(.right) }
        }
        reset()
    }

    private func reset() { mode = .idle; lastCentroid = nil; lastSpread = nil }

    // MARK: - Output

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func moveCursor(_ dmm: CGPoint) {
        let v = hypot(dmm.x, dmm.y)
        let gain = (1.5 + settings.speed * 0.9) * (1 + min(v, 6) * 0.35)   // points per mm, with acceleration
        var p = cursor
        p.x += dmm.x * gain
        p.y += dmm.y * gain
        p = clampToScreens(p)
        post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    }

    private func click(_ button: CGMouseButton) {
        let p = cursor
        let (down, up): (CGEventType, CGEventType) = button == .left ? (.leftMouseDown, .leftMouseUp) : (.rightMouseDown, .rightMouseUp)
        post(CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: p, mouseButton: button))
        post(CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: p, mouseButton: button))
    }

    private func postScroll(_ dmm: CGPoint) {
        let k = settings.naturalScroll ? 9.0 : -9.0    // pixels per mm
        scrollRemainder.x += dmm.x * k
        scrollRemainder.y += dmm.y * k
        let dy = Int32(scrollRemainder.y.rounded(.towardZero)), dx = Int32(scrollRemainder.x.rounded(.towardZero))
        guard dx != 0 || dy != 0 else { return }
        scrollRemainder.x -= Double(dx); scrollRemainder.y -= Double(dy)
        let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        e?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        post(e)
    }

    private func zoomSteps() {
        let step = 7.0   // mm of finger spread per zoom step
        // Zoom in uses numeric-keypad "+" (works on every layout; "+" on the Czech number row is read as ⌘1).
        while pinchAccum > step { pinchAccum -= step; key(69, cmd: true) }
        while pinchAccum < -step { pinchAccum += step; key(KeyNames.keyCode(typing: "-") ?? 27, cmd: true) }
    }

    private func swipeCheck() {
        if settings.swipeSpaces, abs(accum.x) > 22, abs(accum.x) > abs(accum.y) {
            key(accum.x < 0 ? 124 : 123, ctrl: true)     // fingers left → next space (like trackpad)
            mode = .done
        } else if settings.missionControl, accum.y < -18, abs(accum.y) > abs(accum.x) {
            key(126, ctrl: true)                          // up → Mission Control
            mode = .done
        } else if settings.missionControl, accum.y > 18, abs(accum.y) > abs(accum.x) {
            key(125, ctrl: true)                          // down → App Exposé
            mode = .done
        }
    }

    private func key(_ code: Int, cmd: Bool = false, ctrl: Bool = false) {
        var flags: CGEventFlags = []
        if cmd { flags.insert(.maskCommand) }
        if ctrl { flags.insert(.maskControl) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            post(e)
        }
    }

    private func post(_ e: CGEvent?) {
        guard let e else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        e.post(tap: .cghidEventTap)
    }

    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        // CG coordinates: origin top-left of the main display.
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        let rects = NSScreen.screens.map { s -> CGRect in
            CGRect(x: s.frame.minX, y: mainH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        if rects.contains(where: { $0.contains(p) }) { return p }
        guard let r = rects.min(by: { dist($0, p) < dist($1, p) }) else { return p }
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}
