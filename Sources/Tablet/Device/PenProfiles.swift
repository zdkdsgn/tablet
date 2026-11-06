import Foundation

/// Every Wacom pen has its own serial number, sent when it comes into range.
/// With per-pen settings on, each pen keeps its own pressure curve, smoothing, buttons and eraser behaviour.
@MainActor
final class PenProfiles: ObservableObject {
    struct Pen: Codable, Identifiable, Equatable {
        var serial: String
        var name: String
        var kind: String
        var lastSeen: Date
        /// JSON of the pen-related settings (nil = not saved yet).
        var settings: Data?
        var id: String { serial }
    }

    private let d = UserDefaults.standard
    @Published var perPen: Bool { didSet { d.set(perPen, forKey: "pens.perPen"); if perPen, let c = current { saveInto(c) } } }
    @Published private(set) var pens: [Pen] = []
    /// Serial of the pen in use (also remembered across launches, so edits made to it are not overwritten).
    @Published private(set) var current: String? { didSet { d.set(current, forKey: "pens.current") } }
    /// The pen just switched to – shown briefly.
    var onSwitch: ((Pen) -> Void)?

    private let store: OTDStore
    private let filters: PenFilters
    private let behaviour: KeyBehaviour

    init(store: OTDStore, filters: PenFilters, behaviour: KeyBehaviour) {
        self.store = store; self.filters = filters; self.behaviour = behaviour
        perPen = d.bool(forKey: "pens.perPen")
        current = d.string(forKey: "pens.current")
        if let data = d.data(forKey: "pens.known"), let p = try? JSONDecoder().decode([Pen].self, from: data) { pens = p }
    }

    func penEntered(id: Int, serial: UInt32) {
        guard serial != 0 else { return }
        let key = String(format: "%08X", serial)
        if let i = pens.firstIndex(where: { $0.serial == key }) {
            pens[i].lastSeen = Date()
            let kind = Self.kind(id)
            if pens[i].kind != kind {   // better name known now
                if pens[i].name == pens[i].kind { pens[i].name = kind }
                pens[i].kind = kind
            }
        } else {
            let kind = Self.kind(id)
            let n = pens.filter { $0.kind == kind }.count
            pens.append(Pen(serial: key, name: n == 0 ? kind : "\(kind) \(n + 1)", kind: kind, lastSeen: Date()))
        }
        if key != current {
            if perPen, let c = current { saveInto(c) }
            current = key
            if let pen = pens.first(where: { $0.serial == key }) {
                if perPen {
                    if let s = pen.settings { apply(s) } else { saveInto(key) }   // a new pen starts with the current settings
                    onSwitch?(pen)
                }
            }
        }
        persist()
    }

    func rename(_ serial: String, to name: String) {
        guard let i = pens.firstIndex(where: { $0.serial == serial }) else { return }
        pens[i].name = name.trimmingCharacters(in: .whitespaces).isEmpty ? pens[i].kind : name
        persist()
    }

    func forget(_ serial: String) {
        pens.removeAll { $0.serial == serial }
        if current == serial { current = nil }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pens) { d.set(data, forKey: "pens.known") }
    }

    // MARK: settings snapshot

    private func saveInto(_ serial: String) {
        guard let i = pens.firstIndex(where: { $0.serial == serial }) else { return }
        let dict: [String: Any] = [
            "gamma": filters.gamma, "maxInput": filters.maxInput, "smoothing": filters.smoothing,
            "tipThreshold": store.tipThreshold, "calmTap": filters.calmTap,
            "penButtons": store.penButtons.map(\.json), "eraser": store.eraser.json,
            "eraserSwitch": behaviour.eraserSwitch, "eraserKeys": behaviour.eraserKeys, "penKeys": behaviour.penKeys,
        ]
        pens[i].settings = try? JSONSerialization.data(withJSONObject: dict)
        persist()
    }

    private func apply(_ data: Data) {
        guard let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let v = s["gamma"] as? Double { filters.gamma = v }
        if let v = s["maxInput"] as? Double { filters.maxInput = v }
        if let v = s["smoothing"] as? Double { filters.smoothing = v }
        if let v = s["tipThreshold"] as? Double { store.tipThreshold = v }
        if let v = s["calmTap"] as? Int { filters.calmTap = v }
        if let v = s["penButtons"] as? [Any] { store.penButtons = (0..<store.penButtons.count).map { BindingAction(json: v.indices.contains($0) ? v[$0] : nil) } }
        if let v = s["eraser"] { store.eraser = BindingAction(json: v) }
        if let v = s["eraserSwitch"] as? Bool { behaviour.eraserSwitch = v }
        if let v = s["eraserKeys"] as? [String] { behaviour.eraserKeys = v }
        if let v = s["penKeys"] as? [String] { behaviour.penKeys = v }
    }

    /// Tool ID → pen type (Linux wacom_intuos_get_tool_type; the eraser bit 0x8 is ignored).
    static func kind(_ id: Int) -> String {
        // the low 12 bits name the tool; higher bits differ between tablet generations (0x802, 0x10802, 0x100802…)
        switch id & 0xFF7 {
        case 0x802: return "Grip Pen"
        case 0x842, 0x852: return "Pro Pen"
        case 0x822: return "Classic Pen"
        case 0x812: return "Inking Pen"
        case 0x832: return "Stroke Pen"
        case 0x804: return "Art Pen"
        case 0x902: return "Airbrush"
        default: return L("Pero")
        }
    }
}
