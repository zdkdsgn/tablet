import Foundation
import CoreGraphics

/// The pen above the tablet right now (position in mm in the native tablet frame, pressure, tilt, height),
/// for the live dot in the previews and the pen check. Updated at most ~60× a second so the views stay cheap.
@MainActor
final class PenHover: ObservableObject {
    @Published private(set) var sample: PenSample?
    var mm: CGPoint? { sample?.mm }
    var pressure: Double { sample?.pressure ?? 0 }
    /// Highest pressure of the last touch of the tip, published when the tip lifts (for tuning the tap threshold).
    @Published private(set) var lastPeak: Double?
    private var peak = 0.0
    private var last = Date.distantPast
    private var timeout: Timer?

    func update(_ s: PenSample?) {
        timeout?.invalidate()
        // every report, not just the throttled ones – a quick tap lasts only a few reports
        let p = s?.pressure ?? 0
        if p > 0 { peak = max(peak, p) } else if peak > 0 { lastPeak = peak; peak = 0 }
        guard let s else { sample = nil; return }
        // the pen can leave range without an "exit" report (e.g. lifted fast) – hide the dot after a pause
        timeout = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample = nil }
        }
        let now = Date()
        guard now.timeIntervalSince(last) > 1.0 / 60 else { return }
        last = now
        sample = s
    }
}
