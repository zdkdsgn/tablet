import AppKit

/// What the Touch Ring does when this app controls it.
enum RingMode: Int, CaseIterable, Identifiable {
    case zoom, brush, history, scroll
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .zoom: return "Zoom"
        case .brush: return "Velikost štětce"
        case .history: return "Historie"
        case .scroll: return "Posouvání"
        }
    }
    var caption: String {
        switch self {
        case .zoom: return "Plynule ke kurzoru"
        case .brush: return "Klávesy [ a ]"
        case .history: return "Zpět ⌘Z / Znovu ⇧⌘Z"
        case .scroll: return "Plynulé posouvání obsahu"
        }
    }
    var symbol: String {
        switch self {
        case .zoom: return "plus.magnifyingglass"
        case .brush: return "paintbrush.pointed"
        case .history: return "clock.arrow.circlepath"
        case .scroll: return "arrow.up.and.down"
        }
    }
}

/// Settings for the app-controlled Touch Ring – stored in UserDefaults.
@MainActor
final class ZoomSettings: ObservableObject {
    private let d = UserDefaults.standard
    /// true = this app handles the ring (smooth zoom + modes); false = OpenTabletDriver's key bindings.
    @Published var smooth: Bool { didSet { d.set(smooth, forKey: "zoom.smooth") } }
    /// "auto", "alt", "cmd", "ctrl", "none"
    @Published var modifier: String { didSet { d.set(modifier, forKey: "zoom.modifier") } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "zoom.speed") } }
    @Published var smoothing: Double { didSet { d.set(smoothing, forKey: "zoom.smoothing") } }
    @Published var invert: Bool { didSet { d.set(invert, forKey: "zoom.invert") } }
    /// Centre button cycles the ring modes.
    @Published var buttonCycles: Bool { didSet { d.set(buttonCycles, forKey: "ring.buttonCycles") } }
    @Published var mode: RingMode { didSet { d.set(mode.rawValue, forKey: "ring.mode") } }

    init() {
        d.register(defaults: ["zoom.smooth": false, "zoom.modifier": "auto", "zoom.speed": 5.0,
                              "zoom.smoothing": 5.0, "zoom.invert": false, "ring.buttonCycles": true, "ring.mode": 0])
        smooth = d.bool(forKey: "zoom.smooth")
        modifier = d.string(forKey: "zoom.modifier") ?? "auto"
        speed = d.double(forKey: "zoom.speed")
        smoothing = d.double(forKey: "zoom.smoothing")
        invert = d.bool(forKey: "zoom.invert")
        buttonCycles = d.bool(forKey: "ring.buttonCycles")
        mode = RingMode(rawValue: d.integer(forKey: "ring.mode")) ?? .zoom
    }

    /// Which key zooms with the scroll wheel in the app in front.
    static func autoModifier(for bundleID: String?) -> String {
        let id = (bundleID ?? "").lowercased()
        if id.hasPrefix("com.adobe.") { return "alt" }          // Photoshop, Illustrator, InDesign, Bridge…
        if id.contains("blender") { return "none" }              // Blender zooms with the plain wheel
        return "cmd"                                             // Figma, Affinity, Sketch, Pixelmator, Krita…
    }

    static func title(_ m: String) -> String {
        switch m {
        case "alt": return "⌥ Option"
        case "cmd": return "⌘ Command"
        case "ctrl": return "⌃ Control"
        case "none": return "Bez klávesy"
        default: return "Automaticky"
        }
    }
}

/// Handles the Touch Ring when the app controls it:
/// – zoom / scroll: a stream of small continuous (trackpad-like) scroll events, eased out over time;
/// – brush size / history: one key press per few degrees of rotation;
/// – centre button: next mode (LEDs + on-screen notice).
@MainActor
final class RingZoom {
    private let settings: ZoomSettings
    private let source = CGEventSource(stateID: .hidSystemState)
    private let steps = 72            // ring positions per revolution (0…71)

    /// Called when the mode changes (to update LEDs / show the notice).
    var onModeChange: ((RingMode) -> Void)?

    private var lastPos: Int?
    private var stepAccum = 0
    private var pending = 0.0         // pixels still to scroll
    private var fraction = 0.0
    private var lastInput = Date.distantPast
    private var timer: Timer?
    private var active = false
    private var heldKey: CGKeyCode?
    private var flags: CGEventFlags = []
    private var buttonDown = false

    init(settings: ZoomSettings) { self.settings = settings }

    /// Long press (≈1.5 s) on the centre button – the light show easter egg.
    var onLongPress: (() -> Void)?
    private var longPressTimer: Timer?
    private var longPressFired = false

    /// Centre button state from every pad report. Short press = next mode (on release), long press = easter egg.
    func button(_ pressed: Bool) {
        defer { buttonDown = pressed }
        guard pressed != buttonDown else { return }
        if pressed {
            longPressFired = false
            longPressTimer?.invalidate()
            let t = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.buttonDown else { return }
                    self.longPressFired = true
                    self.onLongPress?()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            longPressTimer = t
            return
        }
        longPressTimer?.invalidate()
        guard !longPressFired, settings.smooth, settings.buttonCycles else { return }
        let all = RingMode.allCases
        settings.mode = all[(settings.mode.rawValue + 1) % all.count]
        finish()
        stepAccum = 0
        onModeChange?(settings.mode)
    }

    /// Called for every pad report: `position` is 0…71 while a finger is on the ring, nil when lifted.
    func ring(_ position: Int?) {
        guard settings.smooth, let p = position else { lastPos = nil; stepAccum = 0; return }
        defer { lastPos = p }
        guard let l = lastPos else { return }
        var d = p - l
        if d > steps / 2 { d -= steps }
        if d < -steps / 2 { d += steps }
        guard d != 0 else { return }
        if settings.invert { d = -d }   // clockwise (positive) = zoom in / bigger / redo / down

        switch settings.mode {
        case .zoom:
            enqueue(Double(d) * (0.5 + settings.speed * 1.1))
        case .scroll:
            enqueue(Double(-d) * (1 + settings.speed * 2))
        case .brush:
            keySteps(d, every: 3) { up in
                let code = up ? (KeyNames.keyCode(typing: "]") ?? 30) : (KeyNames.keyCode(typing: "[") ?? 33)
                self.tapKey(CGKeyCode(code), flags: [])
            }
        case .history:
            keySteps(d, every: 5) { up in
                self.tapKey(CGKeyCode(KeyNames.keyCode(typing: "z") ?? 6), flags: up ? [.maskCommand, .maskShift] : [.maskCommand])
            }
        }
    }

    // MARK: key-step modes

    private func keySteps(_ d: Int, every n: Int, _ fire: (Bool) -> Void) {
        if (stepAccum > 0) != (d > 0) && stepAccum != 0 { stepAccum = 0 }   // direction change
        stepAccum += d
        while stepAccum >= n { stepAccum -= n; fire(true) }
        while stepAccum <= -n { stepAccum += n; fire(false) }
    }

    private func tapKey(_ code: CGKeyCode, flags f: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = f
            e.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: smooth scroll modes

    private func enqueue(_ px: Double) {
        pending += px
        lastInput = Date()
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        if abs(pending) >= 0.5 {
            // ease out: emit a share of what is left each frame (more smoothing = smaller share)
            let share = 0.42 - settings.smoothing * 0.035          // 0.39 … 0.07
            var chunk = pending * share
            if abs(chunk) < 1 { chunk = pending > 0 ? min(1, pending) : max(-1, pending) }
            pending -= chunk
            emit(chunk)
        } else if Date().timeIntervalSince(lastInput) > 0.18 {
            finish()
        }
    }

    private func emit(_ px: Double) {
        fraction += px
        let whole = Int32(fraction.rounded(.towardZero))
        guard whole != 0 else { return }
        fraction -= Double(whole)
        if !active { begin() }
        post(scroll: whole, phase: 2)
    }

    private func begin() {
        var m = settings.mode == .zoom ? settings.modifier : "none"
        if m == "auto" { m = ZoomSettings.autoModifier(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) }
        switch m {
        case "alt": heldKey = 58; flags = .maskAlternate
        case "cmd": heldKey = 55; flags = .maskCommand
        case "ctrl": heldKey = 59; flags = .maskControl
        default: heldKey = nil; flags = []
        }
        if let k = heldKey { postKey(k, down: true) }
        post(scroll: 0, phase: 1)   // scroll began
        active = true
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        pending = 0; fraction = 0
        guard active else { return }
        post(scroll: 0, phase: 4)   // scroll ended
        if let k = heldKey { postKey(k, down: false) }
        heldKey = nil; flags = []
        active = false
    }

    private func post(scroll dy: Int32, phase: Int64) {
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
        e.post(tap: .cghidEventTap)
    }

    private func postKey(_ code: CGKeyCode, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = down ? flags : []
        e.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
        e.post(tap: .cghidEventTap)
    }
}
