import SwiftUI
import AppKit

/// What the Express View overlay shows: the keys in tablet order, which one is touched or pressed.
final class ExpressViewModel: ObservableObject {
    struct Row: Identifiable {
        var id: Int
        var name: String
        var detail: String
        var symbol: String?
    }
    @Published var top: [Row] = []
    @Published var bottom: [Row] = []
    @Published var ring: Row?
    @Published var touched = Set<Int>()
    @Published var pressed = Set<Int>()
}

/// Wacom-style "Express View": resting a finger on an ExpressKey shows what the keys do,
/// next to the left edge of the screen (where the keys are on the tablet).
@MainActor
final class ExpressView {
    let model = ExpressViewModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private(set) var visible = false

    func update(touched: Set<Int>, pressed: Set<Int>, rows: () -> (top: [ExpressViewModel.Row], bottom: [ExpressViewModel.Row], ring: ExpressViewModel.Row?)) {
        model.touched = touched
        model.pressed = pressed
        if touched.isEmpty && pressed.isEmpty {
            scheduleHide()
            return
        }
        hideWork?.cancel()
        guard !visible else { return }
        let r = rows()
        model.top = r.top; model.bottom = r.bottom; model.ring = r.ring
        show()
    }

    private func show() {
        let p = panel ?? makePanel()
        p.contentView = NSHostingView(rootView: ExpressOverlay(model: model))
        let size = p.contentView?.fittingSize ?? NSSize(width: 300, height: 420)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrame(NSRect(x: f.minX + 24, y: f.midY - size.height / 2, width: size.width, height: size.height), display: true)
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        panel = p
        visible = true
    }

    private func scheduleHide() {
        guard visible, hideWork == nil || hideWork!.isCancelled else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self, let p = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; p.animator().alphaValue = 0 },
                                                 completionHandler: { MainActor.assumeIsolated { p.orderOut(nil); self.visible = false } })
            self.hideWork = nil
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 420), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.appearance = NSAppearance(named: .darkAqua)   // on-screen overlays stay dark in light mode too
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

private struct ExpressOverlay: View {
    @ObservedObject var model: ExpressViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ExpressKeys").font(.system(size: 11, weight: .semibold)).tracking(0.6).opacity(0.6)
                .padding(.leading, 6).padding(.bottom, 2)
            ForEach(model.top) { row($0) }
            if let r = model.ring {
                HStack(spacing: 10) {
                    Image(systemName: r.symbol ?? "circle.circle").frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(r.detail).font(.system(size: 11)).opacity(0.65).lineLimit(1)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15)))
                .padding(.vertical, 4)
            }
            ForEach(model.bottom) { row($0) }
        }
        .padding(12)
        .frame(width: 280)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, .dark)
    }

    private func row(_ r: ExpressViewModel.Row) -> some View {
        let touched = model.touched.contains(r.id), pressed = model.pressed.contains(r.id)
        return HStack(spacing: 10) {
            Text("\(r.id + 1)").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(touched || pressed ? 0.25 : 0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(r.detail).font(.system(size: 11)).opacity(0.65).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(pressed ? Theme.accent : (touched ? Theme.accent.opacity(0.45) : Color.clear)))
        .animation(.easeOut(duration: 0.12), value: touched)
    }
}
