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

    private func pushConfig() {
        engine.setConfig(.init(gamma: filters.gamma, maxInput: filters.maxInput, smoothing: filters.smoothing,
                               precisionActive: filters.precisionActive, precisionScale: filters.precisionScale,
                               calmTap: filters.calmTap, calmRadius: filters.calmRadius, calmTime: filters.calmTime,
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
    var lastActivity: Date { lock.withLock { _lastActivity } }

    func setConfig(_ c: Config) { lock.withLock { config = c } }
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

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let (cfg, pids, screens, draw) = lock.withLock { (config, daemonPIDs, self.screens, _onDraw) }
        guard pids.contains(event.getIntegerValueField(.eventSourceUnixProcessID)), !screens.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        if !cfg.heldFlags.isEmpty { event.flags.formUnion(cfg.heldFlags) }

        // 1. pressure curve
        if cfg.gamma != 1 || cfg.maxInput < 1 {
            let p = event.getDoubleValueField(.mouseEventPressure)
            if p > 0 {
                let out = PenFilters.curve(p, gamma: cfg.gamma, maxInput: cfg.maxInput)
                event.setDoubleValueField(.mouseEventPressure, value: out)
                event.setDoubleValueField(.tabletEventPointPressure, value: out)
            }
        }
        if type == .tabletPointer { return Unmanaged.passUnretained(event) }

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
        if let l = lastRaw, cfg.precisionActive || cfg.smoothing > 0 {
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

        event.location = p
        event.setDoubleValueField(.mouseEventDeltaX, value: dx)
        event.setDoubleValueField(.mouseEventDeltaY, value: dy)
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
