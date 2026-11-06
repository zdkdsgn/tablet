import SwiftUI
import AppKit

/// A little "island" that grows out of the MacBook's camera notch: a greeting with the pen's tilt and
/// pressure when the pen comes back to the tablet, and fun messages when the pen passes a distance milestone.
@MainActor
final class NotchIsland {
    final class Model: ObservableObject {
        enum Phase: Equatable { case hidden, ears, message, stats }
        @Published var phase: Phase = .hidden
        @Published var title = ""
        @Published var subtitle: String?
        @Published var penName = L("Pero")
        @Published var distance = ""
        @Published var tiltX = 0.0
        @Published var tiltY = 0.0
        @Published var pressure = 0.0
        /// Stats panel opened by hovering the pen over the notch.
        @Published var stats: [(value: String, label: String, symbol: String)] = []
        @Published var statsFooter: String?
        var notch = CGSize(width: 200, height: 32)
    }

    private let model = Model()
    private var panel: NSPanel?
    private var collapse: DispatchWorkItem?
    private var penAwaySince = Date.distantPast
    private var penInRange = false
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

    /// Every throttled pen sample.
    func pen(_ s: PenSample?, name: String, today: String) {
        model.distance = today
        if model.penName != name { model.penName = name }
        if let s {
            model.tiltX = s.tiltX; model.tiltY = s.tiltY; model.pressure = s.pressure
            if !penInRange {
                penInRange = true
                // greet only when the pen comes back after a while, not between strokes
                if Date().timeIntervalSince(penAwaySince) > 30 { show(.ears, for: 3) }
            }
            checkHover()
        } else if penInRange {
            penInRange = false
            penAwaySince = Date()
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

    /// Pen that leans like the real one, glowing with pressure.
    private var leftEar: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.25 + model.pressure * 0.6)).frame(width: 20, height: 20).blur(radius: 4)
                Image(systemName: "pencil.tip")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .bottom, endPoint: .top))
                    .rotationEffect(.degrees(model.tiltX * 0.9))
            }
            .animation(.easeOut(duration: 0.1), value: model.tiltX)
            Text(model.penName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Today's distance with a tiny pressure meter.
    private var rightEar: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(model.pressure * 4 > Double(i) ? Color.orange : Color.white.opacity(0.2))
                        .frame(width: 3, height: 5 + CGFloat(i) * 3)
                }
            }
            Text(model.distance).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white).lineLimit(1)
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
