import SwiftUI
import AppKit

/// A small notice near the bottom of the screen (like the system volume HUD):
/// the Touch Ring mode, or the name of a pressed ExpressKey.
@MainActor
final class ModeHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ mode: RingMode) {
        present(HUDView(symbol: mode.symbol, title: mode.title, subtitle: nil, dots: RingMode.allCases.count, active: mode.rawValue),
                duration: 1.2)
    }

    func showKey(_ index: Int, name: String, shortcut: String) {
        present(HUDView(symbol: "square.grid.2x2", title: name, subtitle: "ExpressKey \(index + 1) · \(shortcut)", dots: 0, active: 0),
                duration: 0.9)
    }

    private func present(_ view: HUDView, duration: Double) {
        let size = NSSize(width: 300, height: 92)
        let p = panel ?? makePanel(size)
        p.contentView = NSHostingView(rootView: view)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 120))
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; self?.panel?.animator().alphaValue = 0 },
                                                 completionHandler: { MainActor.assumeIsolated { self?.panel?.orderOut(nil) } })
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
    }

    private func makePanel(_ size: NSSize) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

private struct HUDView: View {
    var symbol: String
    var title: String
    var subtitle: String?
    var dots: Int
    var active: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium)).frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if let subtitle { Text(subtitle).font(.system(size: 12)).opacity(0.75).lineLimit(1) }
                if dots > 0 {
                    HStack(spacing: 6) {
                        ForEach(0..<dots, id: \.self) { i in
                            Capsule().fill(i == active ? Color.white : Color.white.opacity(0.25)).frame(width: 22, height: 4)
                        }
                    }
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(width: 300, height: 92)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }
}
