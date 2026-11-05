import Foundation

/// LED brightness on Intuos Pro: three levels (the device's value 3 means off).
enum LEDBrightness: Int, CaseIterable, Identifiable {
    case low = 0, medium = 1, high = 2
    var id: Int { rawValue }
    var title: String {
        switch self { case .low: return "Slabě"; case .medium: return "Středně"; case .high: return "Jasně" }
    }
}

/// One step of a light animation. Brightness 0…2, 3 = off; `corners` nil = keep the user's corner setting.
struct LightFrame {
    var ring: Int
    var ringB: Int
    var corners: Int?
    var t: Double
}

enum LEDAnimation: String, CaseIterable, Identifiable {
    case spin, pingPong, breathe, sparkle, countdown, heartbeat, police
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spin: return "Kolotoč"
        case .pingPong: return "Ping-pong"
        case .breathe: return "Dýchání"
        case .sparkle: return "Jiskření"
        case .countdown: return "Odpočet"
        case .heartbeat: return "Tep"
        case .police: return "Maják"
        }
    }
    var symbol: String {
        switch self {
        case .spin: return "arrow.clockwise.circle"
        case .pingPong: return "arrow.left.and.right.circle"
        case .breathe: return "wind"
        case .sparkle: return "sparkles"
        case .countdown: return "timer"
        case .heartbeat: return "heart"
        case .police: return "light.beacon.max"
        }
    }

    var frames: [LightFrame] {
        func f(_ l: Int, _ b: Int, _ c: Int?, _ t: Double) -> LightFrame { LightFrame(ring: l, ringB: b, corners: c, t: t) }
        switch self {
        case .spin:
            let fast = (0..<16).map { i in f(i % 4, 2, i % 4 == 0 ? 2 : 0, max(0.035, 0.11 - Double(i) * 0.005)) }
            let slow = (0..<8).map { i in f(i % 4, 2, 0, 0.04 + Double(i) * 0.02) }
            return fast + slow + [f(0, 2, 2, 0.15)]
        case .pingPong:
            let path = [0, 1, 2, 3, 2, 1]
            return (0..<4).flatMap { _ in path.map { l in f(l, 2, l == 0 || l == 3 ? 2 : 3, 0.07) } } + [f(0, 2, nil, 0.07)]
        case .breathe:
            let levels = [3, 0, 1, 2, 1, 0]
            return (0..<3).flatMap { _ in levels.map { b in f(0, b, b, b == 2 ? 0.35 : 0.22) } }
        case .sparkle:
            var last = -1
            return (0..<28).map { _ in
                var l = Int.random(in: 0...3)
                if l == last { l = (l + 1) % 4 }
                last = l
                return f(l, Int.random(in: 0...2), Bool.random() ? Int.random(in: 0...2) : 3, Double.random(in: 0.04...0.11))
            }
        case .countdown:
            return [3, 2, 1, 0].flatMap { l in [f(l, 2, 3, 0.45), f(l, 3, 3, 0.12)] }
                + (0..<4).flatMap { _ in [f(0, 2, 2, 0.1), f(0, 3, 3, 0.1)] } + [f(0, 2, 2, 0.3)]
        case .heartbeat:
            let beat = [f(0, 2, 2, 0.12), f(0, 3, 3, 0.1), f(0, 2, 2, 0.12), f(0, 0, 0, 0.55)]
            return (0..<4).flatMap { _ in beat }
        case .police:
            return (0..<8).flatMap { _ in [f(0, 2, 3, 0.09), f(2, 2, 2, 0.09), f(1, 2, 3, 0.09), f(3, 2, 2, 0.09)] }
        }
    }
}

/// Light settings, stored in UserDefaults.
@MainActor
final class LightSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "led.enabled") } }
    @Published var brightness: LEDBrightness { didSet { d.set(brightness.rawValue, forKey: "led.brightness") } }
    @Published var cornersEnabled: Bool { didSet { d.set(cornersEnabled, forKey: "led.corners") } }
    @Published var cornerBrightness: LEDBrightness { didSet { d.set(cornerBrightness.rawValue, forKey: "led.cornerBrightness") } }
    @Published var easterEggUnlocked: Bool { didSet { d.set(easterEggUnlocked, forKey: "led.egg") } }
    /// "random" or an LEDAnimation raw value – what a long press plays.
    @Published var longPressAnimation: String { didSet { d.set(longPressAnimation, forKey: "led.longPress") } }
    /// 0.5 = slow … 2 = fast
    @Published var animationSpeed: Double { didSet { d.set(animationSpeed, forKey: "led.speed") } }
    @Published var animateModeChange: Bool { didSet { d.set(animateModeChange, forKey: "led.modeAnim") } }
    @Published var welcomeAnimation: Bool { didSet { d.set(welcomeAnimation, forKey: "led.welcome") } }
    @Published var breatheCorners: Bool { didSet { d.set(breatheCorners, forKey: "led.breathe") } }

    init() {
        d.register(defaults: ["led.enabled": true, "led.brightness": 2, "led.corners": true, "led.cornerBrightness": 0,
                              "led.egg": false, "led.longPress": "random", "led.speed": 1.0,
                              "led.modeAnim": true, "led.welcome": false, "led.breathe": false])
        enabled = d.bool(forKey: "led.enabled")
        brightness = LEDBrightness(rawValue: d.integer(forKey: "led.brightness")) ?? .high
        cornersEnabled = d.bool(forKey: "led.corners")
        cornerBrightness = LEDBrightness(rawValue: d.integer(forKey: "led.cornerBrightness")) ?? .low
        easterEggUnlocked = d.bool(forKey: "led.egg")
        longPressAnimation = d.string(forKey: "led.longPress") ?? "random"
        animationSpeed = d.double(forKey: "led.speed")
        animateModeChange = d.bool(forKey: "led.modeAnim")
        welcomeAnimation = d.bool(forKey: "led.welcome")
        breatheCorners = d.bool(forKey: "led.breathe")
    }

    var ringValue: Int { enabled ? brightness.rawValue : 3 }
    var cornerValue: Int { cornersEnabled ? cornerBrightness.rawValue : 3 }
}

/// Drives the ring + corner LEDs: the steady state, short effects and the idle "breathing" corners.
@MainActor
final class RingLights {
    private let device: DeviceMonitor
    private let settings: LightSettings
    private var timer: Timer?
    private var idleTimer: Timer?
    private var idleStep = 0
    private var frames: [LightFrame] = []
    private var current = 0
    var restore: (() -> Void)?
    private(set) var playing = false

    init(device: DeviceMonitor, settings: LightSettings) {
        self.device = device
        self.settings = settings
    }

    /// Steady state: ring LED `index` and the corners, with the user's brightness.
    func show(_ index: Int) {
        current = index
        guard !playing else { return }
        device.setRingLED(index, brightness: settings.ringValue, corners: settings.cornerValue)
        updateIdle()
    }

    func play(_ animation: LEDAnimation? = nil) {
        let a: LEDAnimation
        if let animation { a = animation }
        else if let chosen = LEDAnimation(rawValue: settings.longPressAnimation) { a = chosen }
        else { a = LEDAnimation.allCases.randomElement()! }
        run(a.frames)
    }

    /// A quick sweep from the previous LED to the new mode's LED.
    func modeChanged(to index: Int, from old: Int) {
        guard settings.animateModeChange, settings.enabled else { show(index); return }
        current = index
        var seq: [LightFrame] = []
        var l = old
        for _ in 0..<4 {           // one fast lap…
            l = (l + 1) % 4
            seq.append(LightFrame(ring: l, ringB: 2, corners: nil, t: 0.035))
        }
        while l != index {         // …then on to the new mode
            l = (l + 1) % 4
            seq.append(LightFrame(ring: l, ringB: 2, corners: nil, t: 0.05))
        }
        run(seq)
    }

    func welcome() {
        guard settings.welcomeAnimation, settings.enabled || settings.cornersEnabled else { return }
        run(LEDAnimation.spin.frames)
    }

    private func run(_ seq: [LightFrame]) {
        timer?.invalidate()
        idleTimer?.invalidate(); idleTimer = nil
        frames = seq
        playing = true
        next()
    }

    private func next() {
        guard !frames.isEmpty else {
            playing = false
            restore?()
            return
        }
        let fr = frames.removeFirst()
        device.setRingLED(fr.ring, brightness: fr.ringB, corners: fr.corners ?? settings.cornerValue)
        let speed = max(0.25, settings.animationSpeed)
        timer = Timer.scheduledTimer(withTimeInterval: fr.t / speed, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    // MARK: idle breathing corners

    func updateIdle() {
        let want = settings.breatheCorners && settings.cornersEnabled && !playing
        if !want { idleTimer?.invalidate(); idleTimer = nil; return }
        guard idleTimer == nil else { return }
        let t = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.breathe() }
        }
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    private func breathe() {
        guard !playing else { return }
        let levels = [0, 1, 2, 2, 1, 0, 3, 3]   // up, hold, down, rest
        idleStep = (idleStep + 1) % levels.count
        device.setRingLED(current, brightness: settings.ringValue, corners: levels[idleStep])
    }
}
