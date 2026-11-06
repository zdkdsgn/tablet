import Foundation
import CoreGraphics

/// Where the pen is above the tablet right now (mm, native tablet frame), for the live dot in the previews.
/// Updated at most ~60× a second so the views stay cheap.
@MainActor
final class PenHover: ObservableObject {
    @Published private(set) var mm: CGPoint?
    /// 0…1 tip pressure (0 = hovering).
    @Published private(set) var pressure: Double = 0
    private var last = Date.distantPast
    private var timeout: Timer?

    func update(_ p: CGPoint?, pressure: Double) {
        timeout?.invalidate()
        guard let p else { mm = nil; self.pressure = 0; return }
        // the pen can leave range without an "exit" report (e.g. lifted fast) – hide the dot after a pause
        timeout = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.mm = nil; self?.pressure = 0 }
        }
        let now = Date()
        guard now.timeIntervalSince(last) > 1.0 / 60 else { return }
        last = now
        mm = p; self.pressure = pressure
    }
}
