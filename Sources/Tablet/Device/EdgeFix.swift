import AppKit

/// Fixes pen cursor behaviour at screen edges.
///
/// OpenTabletDriver positions the cursor absolutely. At the bottom of the tablet area it puts the
/// cursor exactly on the screen border (one point outside the screen), so macOS pulls it back and
/// the cursor flickers. And the auto-hidden Dock only appears when the pointer keeps *pushing*
/// against the edge, like a mouse or trackpad does, while a pen resting at the edge reports no
/// movement. This event tap rewrites the daemon's mouse events before macOS handles them:
/// – keeps the location inside the screen;
/// – at an outer edge (no other display beyond it) adds a small outward delta, which reveals the Dock
///   (and auto-hidden menu bar) and triggers hot corners like a real mouse would.
@MainActor
final class EdgeFix {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var daemonPIDs = Set<Int64>()
    private var screens: [CGRect] = []
    private var refresh: Timer?

    var enabled: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            let me = Unmanaged<EdgeFix>.fromOpaque(ctx!).takeUnretainedValue()
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
        var p = event.location
        // the screen the point is on, or the nearest one
        let r = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(p) })
            ?? screens.min(by: { dist($0, p) < dist($1, p) })!
        let maxX = r.maxX - 1, maxY = r.maxY - 1
        var dx = event.getDoubleValueField(.mouseEventDeltaX)
        var dy = event.getDoubleValueField(.mouseEventDeltaY)
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
