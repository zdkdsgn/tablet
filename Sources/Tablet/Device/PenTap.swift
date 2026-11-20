import AppKit
import Combine

/// Rewrites the pen events OpenTabletDriver posts, before macOS handles them.
///
/// – Pressure curve (gamma + "full pressure at") on every pen event.
/// – Stroke smoothing: exponential smoothing of the position.
/// – Precision mode: movement scaled down around the point where it was switched on.
/// – Calm tap: the cursor holds still for a moment after the tip touches down.
/// – Screen edges: OTD puts the cursor one point past the bottom edge (macOS pulls it back → flicker)
///   and a pen resting at an edge reports no movement, so the auto-hidden Dock never sees the pointer
///   pushing. The location is kept inside the screen and at outer edges a small outward delta is added.
///
/// The event tap runs on its own thread: every mouse and pen event in the system waits for it, so it must
/// never wait for the main thread (which can be busy for seconds right after login).
@MainActor
final class PenTap {
    private let filters: PenFilters
    private let engine = PenTapEngine()
    private var refresh: Timer?
    private var bag = Set<AnyCancellable>()

    var enabled: Bool { engine.running }
    /// Raw pen location (CG) of every drawing event (pressure > 0) – for the usage map. Called on the main thread.
    var onDraw: ((CGPoint) -> Void)? {
        didSet {
            let cb = onDraw
            engine.onDraw = cb.map { cb in { p in DispatchQueue.main.async { cb(p) } } }
        }
    }
    /// Last time the pen did anything (for the break reminder).
    var lastActivity: Date { engine.lastActivity }
    /// Modifiers held by an ExpressKey: added to pen events so e.g. ⌥-click works with the pen.
    var heldFlags: CGEventFlags = [] { didSet { pushConfig() } }

    init(filters: PenFilters) {
        self.filters = filters
        // objectWillChange fires before the new value is stored – read it on the next turn of the run loop
        filters.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.pushConfig() }
            .store(in: &bag)
        pushConfig()
    }

    func start() {
        guard !engine.running else { return }
        update()
        guard engine.start() else { return }   // needs Accessibility; retried by the caller
        refresh = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Writes every pen event (what OpenTabletDriver sent and what this filter made of it) to
    /// ~/Library/Logs/Tablet-pen.log for the next `seconds` – for chasing cursor problems.
    func trace(seconds: Double) { engine.trace(until: Date().addingTimeInterval(seconds)) }

    /// How high the pen hovers right now (0 = touching … 1 = edge of range; nil = out of range), from the tablet.
    /// The higher it is, the weaker the signal and the noisier the position – the stabiliser works harder.
    func setHover(_ distance: Double?) { engine.setHover(distance ?? 0) }

    /// macOS can switch an event tap off (sleep, a slow moment) – switch it back on.
    func reenable() { engine.reenable() }

    private func pushConfig() {
        engine.setConfig(.init(gamma: filters.gamma, maxInput: filters.maxInput, smoothing: filters.smoothing,
                               precisionActive: filters.precisionActive, precisionScale: filters.precisionScale,
                               calmTap: filters.calmTap, calmRadius: filters.calmRadius, calmTime: filters.calmTime,
                               stabilize: filters.stabilize, stabilizeCutoff: filters.stabilizeParams.minCutoff,
                               stabilizeBeta: filters.stabilizeParams.beta,
                               heldFlags: heldFlags))
    }

    private func update() {
        let pids = Set(OTDStore.runningDaemons().map { Int64($0.pid) })
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { s in   // CG coordinates: origin top-left of the main display
            CGRect(x: s.frame.minX, y: mainH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        engine.setEnvironment(daemonPIDs: pids, screens: screens)
    }
}

/// The part of PenTap that runs on the event tap's own thread. Settings come in through `setConfig` /
/// `setEnvironment` (under a lock); the filter state is touched only by the tap thread.
final class PenTapEngine: @unchecked Sendable {
    struct Config {
        var gamma = 1.0, maxInput = 1.0, smoothing = 0.0
        var precisionActive = false, precisionScale = 0.3
        var calmTap = 0, calmRadius = 0.0, calmTime = 0.0
        var stabilize = 0, stabilizeCutoff = 0.0, stabilizeBeta = 0.0
        var heldFlags: CGEventFlags = []
    }

    private let lock = NSLock()
    private var config = Config()
    private var daemonPIDs = Set<Int64>()
    private var screens: [CGRect] = []
    private var _lastActivity = Date.distantPast
    private var _running = false
    var onDraw: ((CGPoint) -> Void)? {
        get { lock.withLock { _onDraw } }
        set { lock.withLock { _onDraw = newValue } }
    }
    private var _onDraw: ((CGPoint) -> Void)?

    var running: Bool { lock.withLock { _running } }
    private var traceUntil = Date.distantPast
    private var traceStart = Date()
    func trace(until: Date) {
        lock.withLock { traceUntil = until; traceStart = Date() }
        AppLog.write("trace start", to: .pen)
    }
    var lastActivity: Date { lock.withLock { _lastActivity } }

    func setConfig(_ c: Config) { lock.withLock { config = c } }
    private var hover = 0.0
    func setHover(_ d: Double) { lock.withLock { hover = d } }
    func setEnvironment(daemonPIDs: Set<Int64>, screens: [CGRect]) {
        lock.withLock { self.daemonPIDs = daemonPIDs; self.screens = screens }
    }

    // tap thread only
    private var tap: CFMachPort?
    private var smoothed: CGPoint?
    private var lastEventTime = Date.distantPast
    private var precisionAnchor: (raw: CGPoint, out: CGPoint)?
    private var lastRaw: CGPoint?
    private var calm: (p: CGPoint, t: Date)?
    private var stabilizer = OneEuro2D()
    private var lastOut: CGPoint?

    /// Creates the tap and starts its thread. False when macOS refuses the tap (no Accessibility yet).
    func start() -> Bool {
        guard !running else { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .tabletPointer]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            Unmanaged<PenTapEngine>.fromOpaque(ctx!).takeUnretainedValue().handle(type, event)
        }, userInfo: ctx) else { return false }
        tap = t
        lock.withLock { _running = true }
        let thread = Thread { [t] in
            let source = CFMachPortCreateRunLoopSource(nil, t, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Tablet pen filter"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func reenable() {
        guard let t = tap, !CGEvent.tapIsEnabled(tap: t) else { return }
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let (cfg, pids, screens, draw, height) = lock.withLock { (config, daemonPIDs, self.screens, _onDraw, hover) }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard pids.contains(pid), !screens.isEmpty else {
            // while tracing, also note pointer events from anything else (e.g. the tablet's own mouse interface)
            let (until, t0) = lock.withLock { (traceUntil, traceStart) }
            if Date() < until {
                AppLog.write(String(format: "%6d t%-2d OTHER pid%lld at %.2f,%.2f d%.2f,%.2f",
                                    Int(Date().timeIntervalSince(t0) * 1000), Int(type.rawValue), pid,
                                    event.location.x, event.location.y,
                                    event.getDoubleValueField(.mouseEventDeltaX), event.getDoubleValueField(.mouseEventDeltaY)), to: .pen)
            }
            return Unmanaged.passUnretained(event)
        }

        if !cfg.heldFlags.isEmpty { event.flags.formUnion(cfg.heldFlags) }
        let (until, t0) = lock.withLock { (traceUntil, traceStart) }
        let tracing = Date() < until
        let inLoc = event.location
        let inDX = event.getDoubleValueField(.mouseEventDeltaX), inDY = event.getDoubleValueField(.mouseEventDeltaY)
        func trace(_ out: CGPoint, _ dx: Double, _ dy: Double) {
            guard tracing else { return }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let sub = event.getIntegerValueField(.mouseEventSubtype)
            let tx = event.getIntegerValueField(.tabletEventPointX), ty = event.getIntegerValueField(.tabletEventPointY)
            AppLog.write(String(format: "%6d t%-2d sub%lld in %.2f,%.2f d%.2f,%.2f → out %.2f,%.2f d%.2f,%.2f  tab %lld,%lld p%.3f",
                                ms, Int(type.rawValue), sub, inLoc.x, inLoc.y, inDX, inDY, out.x, out.y, dx, dy, tx, ty,
                                event.getDoubleValueField(.mouseEventPressure)), to: .pen)
        }

        // 1. pressure curve
        if cfg.gamma != 1 || cfg.maxInput < 1 {
            let p = event.getDoubleValueField(.mouseEventPressure)
            if p > 0 {
                let out = PenFilters.curve(p, gamma: cfg.gamma, maxInput: cfg.maxInput)
                event.setDoubleValueField(.mouseEventPressure, value: out)
                event.setDoubleValueField(.tabletEventPointPressure, value: out)
            }
        }
        if type == .tabletPointer { trace(inLoc, inDX, inDY); return Unmanaged.passUnretained(event) }

        let now = Date()
        let gap = now.timeIntervalSince(lastEventTime)
        lastEventTime = now
        lock.withLock { _lastActivity = now }
        if type == .leftMouseDragged, let draw { draw(event.location) }
        let raw = event.location
        var p = raw

        // 2. precision mode: scale movement around the anchor
        if cfg.precisionActive {
            if precisionAnchor == nil { precisionAnchor = (raw, smoothed ?? raw) }
            let a = precisionAnchor!
            p = CGPoint(x: a.out.x + (raw.x - a.raw.x) * cfg.precisionScale,
                        y: a.out.y + (raw.y - a.raw.y) * cfg.precisionScale)
        } else {
            precisionAnchor = nil
        }

        // 2b. stabiliser: the sensor's jitter (±0.25 pt at 200 Hz) is removed while the pen is still or slow
        if cfg.stabilize > 0 {
            if gap > 0.12 { stabilizer.reset() }
            // hovering high above the tablet: much heavier smoothing (the signal is weak up there)
            let h = type == .mouseMoved ? min(max(height, 0), 1) : 0
            p = stabilizer.filter(p, dt: min(max(gap, 0.001), 0.05),
                                  minCutoff: cfg.stabilizeCutoff / (1 + 3 * h), beta: cfg.stabilizeBeta / (1 + 6 * h))
        } else {
            stabilizer.reset()
        }

        // 3. smoothing (reset after a pause, e.g. pen lifted out of range)
        if cfg.smoothing > 0 {
            let alpha = max(0.08, 1 - cfg.smoothing * 0.09)
            if let s = smoothed, gap < 0.12 {
                p = CGPoint(x: s.x + (p.x - s.x) * alpha, y: s.y + (p.y - s.y) * alpha)
            }
            smoothed = p
        } else {
            smoothed = p
        }

        // 4. screen edges
        let r = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(p) })
            ?? screens.min(by: { dist($0, p) < dist($1, p) })!
        let maxX = r.maxX - 1, maxY = r.maxY - 1
        var dx = event.getDoubleValueField(.mouseEventDeltaX)
        var dy = event.getDoubleValueField(.mouseEventDeltaY)
        if cfg.stabilize > 0, let o = lastOut, gap < 0.12 {
            dx = p.x - o.x; dy = p.y - o.y      // movement of the filtered cursor, not the jittery raw one
        } else if let l = lastRaw, cfg.precisionActive || cfg.smoothing > 0 {
            dx = (raw.x - l.x) * (cfg.precisionActive ? cfg.precisionScale : 1)
            dy = (raw.y - l.y) * (cfg.precisionActive ? cfg.precisionScale : 1)
        }
        lastRaw = raw
        let push = 3.0
        if p.y >= maxY { p.y = maxY; if !hasNeighbour(screens, r, below: true) { dy = max(dy, push) } }
        if p.y <= r.minY { p.y = r.minY; if !hasNeighbour(screens, r, below: false) { dy = min(dy, -push) } }
        if p.x >= maxX { p.x = maxX; if !hasNeighbour(screens, r, right: true) { dx = max(dx, push) } }
        if p.x <= r.minX { p.x = r.minX; if !hasNeighbour(screens, r, right: false) { dx = min(dx, -push) } }

        // 5. calm tap: hold the cursor where the tip touched down until it really moves or a moment passes
        if cfg.calmTap > 0 {
            switch type {
            case .leftMouseDown:
                calm = (p, now)
            case .leftMouseDragged:
                if let c = calm {
                    if hypot(p.x - c.p.x, p.y - c.p.y) <= cfg.calmRadius && now.timeIntervalSince(c.t) < cfg.calmTime {
                        p = c.p; dx = 0; dy = 0
                    } else {
                        calm = nil   // a real stroke – let go (the cursor catches up from here)
                    }
                }
            case .leftMouseUp:
                if let c = calm, hypot(p.x - c.p.x, p.y - c.p.y) <= cfg.calmRadius * 1.5 { p = c.p; dx = 0; dy = 0 }
                calm = nil
            default:
                calm = nil
            }
        } else {
            calm = nil
        }

        lastOut = p
        event.location = p
        event.setDoubleValueField(.mouseEventDeltaX, value: dx)
        event.setDoubleValueField(.mouseEventDeltaY, value: dy)
        trace(p, dx, dy)
        return Unmanaged.passUnretained(event)
    }

    private func hasNeighbour(_ screens: [CGRect], _ r: CGRect, below: Bool) -> Bool {
        screens.contains { s in s != r && s.minX < r.maxX && s.maxX > r.minX && (below ? abs(s.minY - r.maxY) < 2 : abs(s.maxY - r.minY) < 2) }
    }

    private func hasNeighbour(_ screens: [CGRect], _ r: CGRect, right: Bool) -> Bool {
        screens.contains { s in s != r && s.minY < r.maxY && s.maxY > r.minY && (right ? abs(s.minX - r.maxX) < 2 : abs(s.maxX - r.minX) < 2) }
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> Double {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}

/// One Euro filter (Casiez et al. 2012) for a 2D point: a low-pass whose cutoff rises with speed –
/// a still pen gets heavy smoothing (no jitter), a fast stroke almost none (no lag).
struct OneEuro2D {
    private var x: CGPoint?
    private var speed: CGPoint = .zero
    private var last: CGPoint?

    mutating func reset() { x = nil; last = nil; speed = .zero }

    mutating func filter(_ p: CGPoint, dt: Double, minCutoff: Double, beta: Double, dCutoff: Double = 1) -> CGPoint {
        func alpha(_ fc: Double) -> Double { let tau = 1 / (2 * .pi * fc); return 1 / (1 + tau / dt) }
        guard let prev = x, let l = last else { x = p; last = p; return p }
        let ad = alpha(dCutoff)
        speed = CGPoint(x: speed.x + ad * ((p.x - l.x) / dt - speed.x), y: speed.y + ad * ((p.y - l.y) / dt - speed.y))
        let a = alpha(minCutoff + beta * hypot(speed.x, speed.y))
        let out = CGPoint(x: prev.x + a * (p.x - prev.x), y: prev.y + a * (p.y - prev.y))
        x = out; last = p
        return out
    }
}
