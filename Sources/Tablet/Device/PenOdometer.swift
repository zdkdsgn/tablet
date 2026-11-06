import Foundation
import CoreGraphics

/// How far the pen has travelled on the tablet – drawing (tip down) and hovering – with fun comparisons.
@MainActor
final class PenOdometer: ObservableObject {
    private let d = UserDefaults.standard
    /// Millimetres drawn with the tip down, all time / today; hover = moved above the surface.
    @Published private(set) var drawn: Double
    @Published private(set) var hovered: Double
    @Published private(set) var today: Double
    @Published private(set) var strokes: Int
    /// Per pen serial → mm drawn.
    @Published private(set) var perPen: [String: Double]
    /// A distance milestone was just passed (metres) – the notch shows a message.
    var onMilestone: ((Double) -> Void)?
    var currentPen: (() -> String?)?

    private var todayKey: String
    private var last: CGPoint?
    private var wasDown = false
    private var dirty = false
    private var timer: Timer?

    static let milestones: [Double] = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000, 10_000, 21_097, 42_195, 100_000, 205_000, 500_000, 1_000_000]

    init() {
        drawn = d.double(forKey: "odo.drawn"); hovered = d.double(forKey: "odo.hovered")
        strokes = d.integer(forKey: "odo.strokes")
        perPen = (d.dictionary(forKey: "odo.perPen") as? [String: Double]) ?? [:]
        todayKey = Self.dayKey()
        today = d.string(forKey: "odo.todayKey") == todayKey ? d.double(forKey: "odo.today") : 0
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    /// Every pen report (full rate, not throttled).
    func add(_ s: PenSample?) {
        guard let s else { last = nil; wasDown = false; return }
        let down = s.pressure > 0.01
        if down && !wasDown { strokes += 1 }
        wasDown = down
        defer { last = s.mm }
        guard let l = last else { return }
        let step = hypot(s.mm.x - l.x, s.mm.y - l.y)
        guard step < 25 else { return }        // re-entry jump, not movement
        if down {
            let before = drawn
            drawn += step; today += step
            if let p = currentPen?() { perPen[p, default: 0] += step }
            if let m = Self.milestones.first(where: { before / 1000 < $0 && drawn / 1000 >= $0 }) { onMilestone?(m) }
        } else {
            hovered += step
        }
        dirty = true
    }

    func reset() {
        drawn = 0; hovered = 0; today = 0; strokes = 0; perPen = [:]; dirty = true; save()
    }

    func save() {
        let k = Self.dayKey()
        if k != todayKey { todayKey = k; today = 0; dirty = true }
        guard dirty else { return }
        dirty = false
        d.set(drawn, forKey: "odo.drawn"); d.set(hovered, forKey: "odo.hovered"); d.set(strokes, forKey: "odo.strokes")
        d.set(perPen, forKey: "odo.perPen"); d.set(today, forKey: "odo.today"); d.set(todayKey, forKey: "odo.todayKey")
    }

    private static func dayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: formatting

    /// mm → "34 cm", "12,4 m", "1,25 km".
    static func format(_ mm: Double) -> String {
        let f = NumberFormatter(); f.locale = Locale.current; f.numberStyle = .decimal
        let m = mm / 1000
        if m < 1 { f.maximumFractionDigits = 0; return (f.string(from: NSNumber(value: mm / 10)) ?? "0") + " cm" }
        if m < 1000 { f.maximumFractionDigits = m < 100 ? 1 : 0; return (f.string(from: NSNumber(value: m)) ?? "0") + " m" }
        f.maximumFractionDigits = m < 10_000 ? 2 : 1
        return (f.string(from: NSNumber(value: m / 1000)) ?? "0") + " km"
    }

    /// Lengths to compare with, in metres.
    static let things: [(String, Double)] = [
        ("tužka", 0.175), ("pravítko", 0.3), ("kytara", 1.0), ("gauč", 2.2), ("Fiat 500", 3.57), ("žirafa", 5.5),
        ("autobus", 12), ("tenisový kurt", 23.8), ("plavecký bazén", 50), ("Boeing 747", 70.7), ("fotbalové hřiště", 105),
        ("Eiffelova věž", 330), ("Karlův most", 516), ("Burdž Chalífa", 828), ("Sněžka (výška)", 1603),
        ("půlmaraton", 21_097), ("maraton", 42_195), ("Praha → Brno", 205_000),
    ]

    /// "= 2,3× Karlův most"
    static func comparison(_ mm: Double) -> String? {
        let m = mm / 1000
        guard let t = things.last(where: { $0.1 <= m }) else { return nil }
        let x = m / t.1
        let f = NumberFormatter(); f.locale = Locale.current; f.maximumFractionDigits = x < 10 ? 1 : 0
        return (x < 1.05 ? "" : (f.string(from: NSNumber(value: x)) ?? "") + "× ") + L(t.0)
    }

    /// A regular pencil draws a line about 56 km long.
    static func pencilUsed(_ mm: Double) -> String {
        let p = mm / 56_000_000 * 100
        return String(format: L("Obyčejná tužka by už byla vypsaná z %@ %%"), p < 0.1 ? String(format: "%.3f", p) : String(format: "%.1f", p))
    }

    static func milestoneText(_ m: Double) -> String {
        let s = format(m * 1000)
        switch m {
        case 1: return String(format: L("První metr! %@ za námi."), s)
        case 42_195: return L("Maraton! Pero uběhlo 42,195 km.")
        case 21_097: return L("Půlmaraton! Pero si zaslouží medaili.")
        default:
            if let c = comparison(m * 1000) { return String(format: L("%@ nakresleno – to je %@"), s, c) }
            return String(format: L("%@ nakresleno"), s)
        }
    }
}
