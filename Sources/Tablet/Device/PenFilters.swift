import Foundation

/// Pen processing done by this app on top of OpenTabletDriver (pressure curve, smoothing, precision).
@MainActor
final class PenFilters: ObservableObject {
    private let d = UserDefaults.standard
    /// Pressure curve: output = input ^ gamma (1 = linear, < 1 soft, > 1 firm).
    @Published var gamma: Double { didSet { d.set(gamma, forKey: "pen.gamma") } }
    /// Pressure needed for full output (0.5…1): lower = reach full pressure with a lighter hand.
    @Published var maxInput: Double { didSet { d.set(maxInput, forKey: "pen.maxInput") } }
    /// Stroke smoothing 0 (off) … 10.
    @Published var smoothing: Double { didSet { d.set(smoothing, forKey: "pen.smoothing") } }
    /// Precision mode: how much finer the movement is (0.15…0.6 of normal).
    @Published var precisionScale: Double { didSet { d.set(precisionScale, forKey: "pen.precisionScale") } }
    /// Precision mode is active (held ExpressKey or toggled).
    @Published var precisionActive = false

    init() {
        d.register(defaults: ["pen.gamma": 1.0, "pen.maxInput": 1.0, "pen.smoothing": 0.0, "pen.precisionScale": 0.3])
        gamma = d.double(forKey: "pen.gamma")
        maxInput = d.double(forKey: "pen.maxInput")
        smoothing = d.double(forKey: "pen.smoothing")
        precisionScale = d.double(forKey: "pen.precisionScale")
    }

    nonisolated static func curve(_ p: Double, gamma: Double, maxInput: Double) -> Double {
        let x = min(max(p / max(maxInput, 0.05), 0), 1)
        return pow(x, gamma)
    }

    static let presets: [(String, Double)] = [("Měkký", 0.55), ("Lineární", 1.0), ("Tvrdý", 1.8)]
}
