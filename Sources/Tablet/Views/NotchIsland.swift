import SwiftUI
import AppKit

/// A little "island" that grows out of the MacBook's camera notch: the pen's live tilt (from the side and
/// from above) while the pen is over the tablet, and fun messages when the pen passes a distance milestone.
@MainActor
final class NotchIsland {
    final class Model: ObservableObject {
        enum Phase: Equatable { case hidden, ears, message, stats }
        @Published var phase: Phase = .hidden
        @Published var title = ""
        @Published var subtitle: String?
        @Published var penName = L("Pero")
        @Published var distance = ""
        /// Live pen pose – one value so a sample redraws the island once.
        @Published var pose = Pose()
        /// Stats panel opened by hovering the pen over the notch.
        @Published var stats: [(value: String, label: String, symbol: String)] = []
        @Published var statsFooter: String?
        var notch = CGSize(width: 200, height: 32)
    }

    private let model = Model()
    private var panel: NSPanel?
    private var collapse: DispatchWorkItem?
    private var penInRange = false
    private var lastRefresh = Date.distantPast
    var enabled: Bool { UserDefaults.standard.object(forKey: "island.enabled") as? Bool ?? true }
    /// Values for the stats panel (asked for when it opens).
    var statsProvider: (() -> (items: [(String, String, String)], footer: String?))?
    /// The pen was moved onto the notch (for an achievement).
    var onVisit: (() -> Void)?

    static let earWidth: CGFloat = 118
    static let messageHeight: CGFloat = 58
    static let statsHeight: CGFloat = 104

    /// Screen with a camera housing, and the notch size.
    private static func notchScreen() -> (NSScreen, CGSize)? {
        for s in NSScreen.screens where s.safeAreaInsets.top > 0 {
            let l = s.auxiliaryTopLeftArea?.width ?? 0, r = s.auxiliaryTopRightArea?.width ?? 0
            let w = s.frame.width - l - r
            if w > 50 { return (s, CGSize(width: w, height: s.safeAreaInsets.top)) }
        }
        return nil
    }

    /// The island can be shown (enabled and the Mac has a notch).
    var available: Bool { enabled && Self.notchScreen() != nil }

    /// Every throttled pen sample. `flip`: the tablet is used upside down (left-handed).
    func pen(_ s: PenSample?, name: String, today: String, flip: Bool = false) {
        if model.distance != today { model.distance = today }
        if model.penName != name { model.penName = name }
        if let s {
            let k = flip ? -1.0 : 1.0
            model.pose = Pose(tiltX: s.tiltX * k, tiltY: s.tiltY * k, pressure: s.pressure)
            // the ears stay out while the pen is over the tablet (re-armed a few times a second)
            if !penInRange || Date().timeIntervalSince(lastRefresh) > 0.25 {
                penInRange = true
                lastRefresh = Date()
                show(.ears, for: 1.5)
            }
            checkHover()
        } else if penInRange {
            penInRange = false
            show(.ears, for: 0.8)   // fold away shortly after the pen leaves
        }
    }

    private var demoTimer: Timer?

    /// Shows the tilt ears with a pen that sweeps around once (for the "Show" button and tablet://notch/tilt).
    func demoTilt() {
        demoTimer?.invalidate()
        let start = Date()
        show(.ears, for: 4.5)
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let e = Date().timeIntervalSince(start)
                if e > 4 { t.invalidate(); self.model.pose = Pose(); return }
                let ang = e / 4 * 2 * .pi, lean = 45 * sin(min(1, e / 0.6) * .pi / 2)
                self.model.pose = Pose(tiltX: lean * sin(ang), tiltY: lean * -cos(ang), pressure: 0.5 + 0.5 * sin(ang * 3))
            }
        }
    }

    /// Pen cursor on the notch → open the stats; it stays open while the cursor is over the island.
    private func checkHover() {
        guard enabled, let (screen, notch) = Self.notchScreen() else { return }
        let m = NSEvent.mouseLocation
        let open = model.phase == .stats
        let w = open ? notch.width + Self.earWidth * 2 : notch.width + 40
        let h = open ? notch.height + Self.statsHeight : notch.height + 6
        let zone = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h + 2)
        guard zone.contains(m) else { return }
        if !open { onVisit?() }
        showStats(for: 1.2)
    }

    /// Opens (or keeps open) the stats panel.
    func showStats(for seconds: Double) {
        if model.phase != .stats, let p = statsProvider?() {
            model.stats = p.items.map { (value: $0.0, label: $0.1, symbol: $0.2) }
            model.statsFooter = p.footer
        }
        show(.stats, for: seconds)
    }

    private var queue: [(String, String?, Double)] = []

    func message(_ title: String, subtitle: String?, seconds: Double = 4.5) {
        // one message at a time – the rest wait their turn
        if model.phase == .message { queue.append((title, subtitle, seconds)); return }
        model.title = title; model.subtitle = subtitle
        show(.message, for: seconds)
    }

    private func show(_ phase: Model.Phase, for seconds: Double) {
        guard enabled, let (screen, notch) = Self.notchScreen() else { return }
        model.notch = notch
        let size = NSSize(width: notch.width + Self.earWidth * 2 + 40, height: notch.height + max(Self.messageHeight, Self.statsHeight) + 30)
        let p = panel ?? makePanel()
        p.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: false)
        p.orderFrontRegardless()
        panel = p
        if model.phase == .message && phase != .message { return }   // do not cut a message short
        if model.phase == .stats && phase == .ears { return }
        if model.phase != phase { withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { model.phase = phase } }
        collapse?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { self.model.phase = .hidden }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.model.phase == .hidden else { return }
                if !self.queue.isEmpty {
                    let (t, sub, sec) = self.queue.removeFirst()
                    self.message(t, subtitle: sub, seconds: sec)
                } else {
                    self.panel?.orderOut(nil)
                }
            }
        }
        collapse = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: IslandView(model: model))
        host.sizingOptions = []   // the panel sets the size, not the SwiftUI content
        p.contentView = host
        p.appearance = NSAppearance(named: .darkAqua)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)   // above the menu bar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }
}

struct Pose: Equatable {
    var tiltX = 0.0
    var tiltY = 0.0
    var pressure = 0.0
    /// Angle from upright in degrees, combining both tilt planes.
    var total: Double {
        let a = tan(tiltX * .pi / 180), b = tan(tiltY * .pi / 180)
        return atan(sqrt(a * a + b * b)) * 180 / .pi
    }
}

private struct IslandView: View {
    @ObservedObject var model: NotchIsland.Model

    var body: some View {
        let n = model.notch
        let open = model.phase != .hidden
        let w = open ? n.width + NotchIsland.earWidth * 2 : n.width
        let h = model.phase == .message ? n.height + NotchIsland.messageHeight
            : model.phase == .stats ? n.height + NotchIsland.statsHeight : n.height
        let r: CGFloat = model.phase == .message || model.phase == .stats ? 24 : (open ? 14 : 10)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r)
                    .fill(.black)
                    .frame(width: w, height: h)
                    .shadow(color: .black.opacity(open ? 0.35 : 0), radius: 10, y: 4)

                if open {
                    HStack(spacing: 0) {
                        leftEar.frame(width: NotchIsland.earWidth)
                        Spacer(minLength: n.width)
                        rightEar.frame(width: NotchIsland.earWidth)
                    }
                    .frame(width: w, height: n.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
                if model.phase == .message {
                    VStack(spacing: 3) {
                        Text(model.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        if let s = model.subtitle { Text(s).font(.system(size: 11)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: w - 36)
                    .padding(.top, n.height + 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if model.phase == .stats {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(Array(model.stats.enumerated()), id: \.offset) { _, s in
                                VStack(spacing: 3) {
                                    Image(systemName: s.symbol).font(.system(size: 12)).foregroundStyle(.orange)
                                    Text(s.value).font(.system(size: 13, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                    Text(s.label).font(.system(size: 9)).opacity(0.6).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        if let f = model.statsFooter {
                            Text(f).font(.system(size: 10.5)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: w - 32)
                    .padding(.top, n.height + 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The pen from the side: it leans with the real one around its nib, glowing with pressure.
    private var leftEar: some View {
        HStack(spacing: 8) {
            SidePen(pose: model.pose).frame(width: 34, height: model.notch.height - 4)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(model.pose.total.rounded()))°")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                Text("náklon").font(.system(size: 8.5)).opacity(0.55)
            }
            .foregroundStyle(.white)
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The pen from above: which way it leans, like a spirit level.
    private var rightEar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(model.distance).font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1)
                Text("dnes").font(.system(size: 8.5)).opacity(0.55)
            }
            .foregroundStyle(.white)
            TopLevel(pose: model.pose).frame(width: model.notch.height - 6, height: model.notch.height - 6)
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Side view of the pen standing on the tablet surface.
private struct SidePen: View {
    var pose: Pose
    var body: some View {
        Canvas { ctx, size in
            let base = size.height - 3
            let nib = CGPoint(x: size.width / 2, y: base)
            // tablet surface
            var surface = Path(); surface.move(to: CGPoint(x: 1, y: base + 1)); surface.addLine(to: CGPoint(x: size.width - 1, y: base + 1))
            ctx.stroke(surface, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            // shadow cast along the surface
            let a = pose.tiltX * .pi / 180
            let len = (size.height - 5) * cos(pose.tiltY * .pi / 180)   // leaning towards/away from you shortens it
            let sh = len * sin(a)
            var shadow = Path(); shadow.move(to: nib); shadow.addLine(to: CGPoint(x: nib.x + sh, y: base + 1))
            ctx.stroke(shadow, with: .color(.orange.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // nib glow with pressure
            let g = 4 + pose.pressure * 7
            ctx.fill(Path(ellipseIn: CGRect(x: nib.x - g, y: nib.y - g, width: g * 2, height: g * 2)),
                     with: .radialGradient(Gradient(colors: [.orange.opacity(0.35 + pose.pressure * 0.6), .clear]),
                                           center: nib, startRadius: 0, endRadius: g))
            // the pen, drawn upright and rotated around its nib
            var c = ctx
            c.translateBy(x: nib.x, y: nib.y)
            c.rotate(by: .radians(a))
            let w: CGFloat = 4.6
            var cone = Path(); cone.move(to: .zero); cone.addLine(to: CGPoint(x: -w / 2, y: -5)); cone.addLine(to: CGPoint(x: w / 2, y: -5)); cone.closeSubpath()
            c.fill(cone, with: .color(Color(white: 0.75)))
            let body = Path(roundedRect: CGRect(x: -w / 2, y: -len, width: w, height: len - 5), cornerSize: CGSize(width: 2, height: 2))
            c.fill(body, with: .linearGradient(Gradient(colors: [.orange, .yellow]), startPoint: CGPoint(x: 0, y: -5), endPoint: CGPoint(x: 0, y: -len)))
            // grip band and side switch
            c.fill(Path(CGRect(x: -w / 2, y: -10, width: w, height: 3)), with: .color(.black.opacity(0.35)))
            c.fill(Path(roundedRect: CGRect(x: w / 2 - 1, y: -len * 0.55, width: 1.6, height: 4), cornerSize: CGSize(width: 0.8, height: 0.8)),
                   with: .color(.white.opacity(0.8)))
        }
    }
}

/// Top view: the nib in the middle and a line showing where the pen's top points.
private struct TopLevel: View {
    var pose: Pose
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 1
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(ring, with: .color(.white.opacity(0.06)))
            ctx.stroke(ring, with: .color(.white.opacity(0.25)), lineWidth: 1)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            ctx.stroke(cross, with: .color(.white.opacity(0.12)), lineWidth: 0.7)
            // the pen's top, seen from above (screen down = towards you)
            let a = tan(pose.tiltX * .pi / 180), b = tan(pose.tiltY * .pi / 180)
            let m = sqrt(a * a + b * b)
            let reach = r * min(1, sin(pose.total * .pi / 180) / sin(60 * .pi / 180))
            let end = m > 0.001 ? CGPoint(x: c.x + a / m * reach, y: c.y + b / m * reach) : c
            var pen = Path(); pen.move(to: c); pen.addLine(to: end)
            ctx.stroke(pen, with: .linearGradient(Gradient(colors: [.orange, .yellow]), startPoint: c, endPoint: end),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)), with: .color(.yellow))
            let g = 1.5 + pose.pressure * 2
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)), with: .color(.white))
        }
    }
}
