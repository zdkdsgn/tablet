import Foundation
import CoreGraphics

/// Silly achievements unlocked by using the pen. Shown in the Pen screen and announced in the notch.
@MainActor
final class Achievements: ObservableObject {
    struct Def: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        /// Hidden until unlocked ("???").
        var secret = false
    }

    static let all: [Def] = [
        Def(id: "firstStroke", symbol: "pencil.line", title: "První čárka", detail: "Nakreslete první tah. Picasso taky nějak začínal."),
        Def(id: "pencil", symbol: "pencil", title: "Délka tužky", detail: "Nakreslete 17,5 cm."),
        Def(id: "meter", symbol: "ruler", title: "Metr hotový", detail: "Nakreslete 1 metr."),
        Def(id: "bridge", symbol: "building.columns", title: "Přes Karlův most", detail: "Nakreslete 516 m."),
        Def(id: "eiffel", symbol: "triangle", title: "Na Eiffelovku", detail: "Nakreslete 330 m."),
        Def(id: "marathon", symbol: "figure.run", title: "Maratonec", detail: "Nakreslete 42,195 km. Pero potřebuje sprchu."),
        Def(id: "dayHundred", symbol: "flame", title: "Dneska to sype", detail: "100 m za jeden den."),
        Def(id: "longStroke", symbol: "arrow.left.and.right", title: "Jedním tahem", detail: "Jeden tah dlouhý přes 50 cm."),
        Def(id: "strokes1k", symbol: "hand.draw", title: "Tisíc čárek", detail: "1 000 tahů."),
        Def(id: "strokes10k", symbol: "paintpalette", title: "Pracovitý jako Mucha", detail: "10 000 tahů."),
        Def(id: "heavy", symbol: "hammer", title: "Těžká ruka", detail: "Zmáčkněte hrot na 100 %. Tablet to vydrží… snad."),
        Def(id: "feather", symbol: "leaf", title: "Pírko", detail: "Tah přes 5 cm s přítlakem pod 10 %."),
        Def(id: "pisa", symbol: "building", title: "Šikmá věž v Pise", detail: "Nakloňte pero o víc než 55°."),
        Def(id: "hover", symbol: "wind", title: "Vznášedlo", detail: "Urazte 10 m perem ve vzduchu nad tabletem."),
        Def(id: "eraser", symbol: "eraser", title: "Perfekcionista", detail: "Otočte pero gumou dolů 25×."),
        Def(id: "pens", symbol: "pencil.and.outline", title: "Sběratel per", detail: "Připojte dvě různá pera."),
        Def(id: "notch", symbol: "eye", title: "Zvědavec", detail: "Najeďte perem do výřezu displeje."),
        Def(id: "night", symbol: "moon.stars", title: "Noční sova", detail: "Kreslete mezi půlnocí a čtvrtou ráno.", secret: true),
        Def(id: "early", symbol: "sunrise", title: "Ranní ptáče", detail: "Kreslete mezi pátou a šestou ráno.", secret: true),
        Def(id: "weekend", symbol: "beach.umbrella", title: "Víkendový umělec", detail: "Kreslete v sobotu i v neděli.", secret: true),
        Def(id: "precision", symbol: "scope", title: "Chirurg", detail: "Kreslete v přesném režimu.", secret: true),
        Def(id: "spin", symbol: "arrow.triangle.2.circlepath", title: "Kolotoč", detail: "Zatočte perem dokola, ať náklon obkrouží celý kruh.", secret: true),
    ]

    private let d = UserDefaults.standard
    @Published private(set) var unlocked: [String: Date]
    /// New unlock – the app announces it.
    var onUnlock: ((Def) -> Void)?
    /// Asked on each sample (the app's state).
    var precisionActive: (() -> Bool)?

    private var eraserFlips: Int
    private var weekendDays: Set<Int>
    // current stroke
    private var last: CGPoint?
    private var strokeLen = 0.0
    private var strokeMax = 0.0
    private var down = false
    // tilt directions seen while the pen is in range (8 sectors)
    private var sectors = Set<Int>()

    init() {
        unlocked = (d.dictionary(forKey: "ach.unlocked") as? [String: Date]) ?? [:]
        eraserFlips = d.integer(forKey: "ach.eraserFlips")
        weekendDays = Set((d.array(forKey: "ach.weekend") as? [Int]) ?? [])
    }

    var count: Int { unlocked.count }
    func isUnlocked(_ id: String) -> Bool { unlocked[id] != nil }
    var latest: Def? {
        guard let id = unlocked.max(by: { $0.value < $1.value })?.key else { return nil }
        return Self.all.first { $0.id == id }
    }

    func unlock(_ id: String) {
        guard unlocked[id] == nil, let def = Self.all.first(where: { $0.id == id }) else { return }
        unlocked[id] = Date()
        d.set(unlocked, forKey: "ach.unlocked")
        onUnlock?(def)
    }

    func reset() {
        unlocked = [:]; eraserFlips = 0; weekendDays = []
        d.removeObject(forKey: "ach.unlocked"); d.removeObject(forKey: "ach.eraserFlips"); d.removeObject(forKey: "ach.weekend")
    }

    // MARK: events

    /// Every pen report, with the odometer's totals (mm) after it.
    func sample(_ s: PenSample?, odo: PenOdometer) {
        guard let s else { endStroke(); last = nil; sectors.removeAll(); return }
        let isDown = s.pressure > 0.01
        if isDown && !down { strokeLen = 0; strokeMax = 0; timeChecks() }
        if !isDown && down { endStroke() }
        down = isDown
        if isDown, let l = last {
            let step = hypot(s.mm.x - l.x, s.mm.y - l.y)
            if step < 25 { strokeLen += step }
            strokeMax = max(strokeMax, s.pressure)
            if s.pressure >= 0.995 { unlock("heavy") }
            if precisionActive?() == true { unlock("precision") }
        }
        last = s.mm
        let tilt = hypot(s.tiltX, s.tiltY)
        if tilt > 55 { unlock("pisa") }
        if tilt > 25 {
            sectors.insert(Int(((atan2(s.tiltY, s.tiltX) + .pi) / (2 * .pi) * 8).rounded(.down)) % 8)
            if sectors.count == 8 { unlock("spin") }
        }
        totals(odo)
    }

    private func endStroke() {
        guard down else { return }
        down = false
        if strokeLen > 500 { unlock("longStroke") }
        if strokeLen > 50 && strokeMax < 0.10 { unlock("feather") }
    }

    private func totals(_ o: PenOdometer) {
        let m = o.drawn / 1000
        if o.strokes >= 1 { unlock("firstStroke") }
        if m >= 0.175 { unlock("pencil") }
        if m >= 1 { unlock("meter") }
        if m >= 330 { unlock("eiffel") }
        if m >= 516 { unlock("bridge") }
        if m >= 42_195 { unlock("marathon") }
        if o.today >= 100_000 { unlock("dayHundred") }
        if o.strokes >= 1000 { unlock("strokes1k") }
        if o.strokes >= 10_000 { unlock("strokes10k") }
        if o.hovered >= 10_000 { unlock("hover") }
    }

    private func timeChecks() {
        let c = Calendar.current, now = Date()
        let h = c.component(.hour, from: now)
        if h < 4 { unlock("night") }
        if h == 5 { unlock("early") }
        let wd = c.component(.weekday, from: now)   // 1 = Sunday, 7 = Saturday
        if wd == 1 || wd == 7 {
            // a Saturday and the Sunday right after it
            let day = c.ordinality(of: .day, in: .era, for: now) ?? 0
            weekendDays.insert(day)
            d.set(Array(weekendDays.suffix(30)), forKey: "ach.weekend")
            if wd == 1 && weekendDays.contains(day - 1) { unlock("weekend") }
        }
    }

    func eraserFlipped() {
        eraserFlips += 1
        d.set(eraserFlips, forKey: "ach.eraserFlips")
        if eraserFlips >= 25 { unlock("eraser") }
    }

    func pensSeen(_ n: Int) { if n >= 2 { unlock("pens") } }
}
