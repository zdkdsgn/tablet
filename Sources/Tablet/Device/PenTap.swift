import AppKit

/// Rewrites the pen events OpenTabletDriver posts, before macOS handles them.
///
/// – Pressure curve (gamma + "full pressure at") on every pen event.
/// – Stroke smoothing: exponential smoothing of the position.
/// – Precision mode: movement scaled down around the point where it was switched on.
/// – Screen edges: OTD puts the cursor one point past the bottom edge (macOS pulls it back → flicker)
///   and a pen resting at an edge reports no movement, so the auto-hidden Dock never sees the pointer
///   pushing. The location is kept inside the screen and at outer edges a small outward delta is added.
@MainActor
final class PenTap {
    private let filters: PenFilters
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var daemonPIDs = Set<Int64>()
    private var screens: [CGRect] = []
    private var refresh: Timer?

    // smoothing / precision state
    private var smoothed: CGPoint?
    private var lastEventTime = Date.distantPast
    private var precisionAnchor: (raw: CGPoint, out: CGPoint)?
    private var lastRaw: CGPoint?

    var enabled: Bool { tap != nil }

    init(filters: PenFilters) { self.filters = filters }

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .tabletPointer]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            let me = Unmanaged<PenTap>.fromOpaque(ctx!).takeUnretainedValue()
            return MainActor.assumeIsolated { me.handle(type, event) }
        }, userInfo: ctx) else { return }      // needs Accessibility; retried by the caller
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        update()
        refresh = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        daemonPIDs = Set(OTDStore.runningDaemons().map { Int64($0.pid) })
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        screens = NSScreen.screens.map { s in   // CG coordinates: origin top-left of the main display
            CGRect(x: s.frame.minX, y: mainH - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard daemonPIDs.contains(event.getIntegerValueField(.eventSourceUnixProcessID)), !screens.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        // 1. pressure curve
        if filters.gamma != 1 || filters.maxInput < 1 {
            let p = event.getDoubleValueField(.mouseEventPressure)
            if p > 0 {
                let out = PenFilters.curve(p, gamma: filters.gamma, maxInput: filters.maxInput)
                event.setDoubleValueField(.mouseEventPressure, value: out)
                event.setDoubleValueField(.tabletEventPointPressure, value: out)
            }
        }
        if type == .tabletPointer { return Unmanaged.passUnretained(event) }

        let now = Date()
        let gap = now.timeIntervalSince(lastEventTime)
        lastEventTime = now
        let raw = event.location
        var p = raw

        // 2. precision mode: scale movement around the anchor
        if filters.precisionActive {
            if precisionAnchor == nil { precisionAnchor = (raw, smoothed ?? raw) }
            let a = precisionAnchor!
            p = CGPoint(x: a.out.x + (raw.x - a.raw.x) * filters.precisionScale,
                        y: a.out.y + (raw.y - a.raw.y) * filters.precisionScale)
        } else {
            precisionAnchor = nil
        }

        // 3. smoothing (reset after a pause, e.g. pen lifted out of range)
        if filters.smoothing > 0 {
            let alpha = max(0.08, 1 - filters.smoothing * 0.09)
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
        if let l = lastRaw, filters.precisionActive || filters.smoothing > 0 {
            dx = (raw.x - l.x) * (filters.precisionActive ? filters.precisionScale : 1)
            dy = (raw.y - l.y) * (filters.precisionActive ? filters.precisionScale : 1)
        }
        lastRaw = raw
        let push = 3.0
        if p.y >= maxY { p.y = maxY; if !hasNeighbour(r, below: true) { dy = max(dy, push) } }
        if p.y <= r.minY { p.y = r.minY; if !hasNeighbour(r, below: false) { dy = min(dy, -push) } }
        if p.x >= maxX { p.x = maxX; if !hasNeighbour(r, right: true) { dx = max(dx, push) } }
        if p.x <= r.minX { p.x = r.minX; if !hasNeighbour(r, right: false) { dx = min(dx, -push) } }

        event.location = p
        event.setDoubleValueField(.mouseEventDeltaX, value: dx)
        event.setDoubleValueField(.mouseEventDeltaY, value: dy)
        return Unmanaged.passUnretained(event)
    }

    private func hasNeighbour(_ r: CGRect, below: Bool) -> Bool {
        screens.contains { s in s != r && s.minX < r.maxX && s.maxX > r.minX && (below ? abs(s.minY - r.maxY) < 2 : abs(s.maxY - r.minY) < 2) }
    }

    private func hasNeighbour(_ r: CGRect, right: Bool) -> Bool {
        screens.contains { s in s != r && s.minY < r.maxY && s.maxY > r.minY && (right ? abs(s.minX - r.maxX) < 2 : abs(s.maxX - r.minX) < 2) }
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> Double {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
