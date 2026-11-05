import AppKit

/// What sliding a finger along a group of ExpressKeys does.
enum SlideAction: String, CaseIterable, Identifiable {
    case none, brush, history, zoom, scroll, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return L("Nic")
        case .brush: return L("Velikost štětce")
        case .history: return L("Historie")
        case .zoom: return L("Zoom")
        case .scroll: return L("Posouvání")
        case .custom: return L("Vlastní zkratky")
        }
    }
    var caption: String {
        switch self {
        case .none: return ""
        case .brush: return L("Nahoru větší, dolů menší ( ] / [ )")
        case .history: return L("Nahoru Znovu, dolů Zpět")
        case .zoom: return L("Nahoru přiblížit, dolů oddálit")
        case .scroll: return L("Posouvá obsah nahoru a dolů")
        case .custom: return L("Jedna zkratka nahoru, druhá dolů")
        }
    }
}

/// Settings for the two touch strips (keys above / below the Touch Ring), stored in UserDefaults.
@MainActor
final class SliderSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var actions: [SlideAction] { didSet { d.set(actions.map(\.rawValue), forKey: "slide.actions") } }
    @Published var customUp: [[String]] { didSet { d.set(customUp, forKey: "slide.up") } }
    @Published var customDown: [[String]] { didSet { d.set(customDown, forKey: "slide.down") } }
    /// Actions per key travelled (1…3).
    @Published var stepsPerKey: Double { didSet { d.set(stepsPerKey, forKey: "slide.steps") } }
    @Published var invert: Bool { didSet { d.set(invert, forKey: "slide.invert") } }

    init() {
        d.register(defaults: ["slide.steps": 2.0, "slide.invert": false])
        let a = (d.stringArray(forKey: "slide.actions") ?? []).compactMap(SlideAction.init(rawValue:))
        actions = a.count == 2 ? a : [.none, .none]
        customUp = (d.array(forKey: "slide.up") as? [[String]]) ?? [[], []]
        customDown = (d.array(forKey: "slide.down") as? [[String]]) ?? [[], []]
        stepsPerKey = d.double(forKey: "slide.steps")
        invert = d.bool(forKey: "slide.invert")
    }
}

/// Turns a finger sliding along the capacitive ExpressKeys (touched, not pressed) into steps.
@MainActor
final class KeySlider {
    private let settings: SliderSettings
    private let source = CGEventSource(stateID: .hidSystemState)
    private var last: [Double?] = [nil, nil]
    private var acc: [Double] = [0, 0]

    init(settings: SliderSettings) { self.settings = settings }

    /// `groups`: key indices of each strip, top to bottom. `touched` / `pressed`: current key states.
    func update(touched: Set<Int>, pressed: Set<Int>, groups: [[Int]]) {
        for g in 0..<min(2, groups.count) {
            let keys = groups[g]
            let action = settings.actions[g]
            let inGroup = keys.enumerated().filter { touched.contains($0.element) }.map { Double($0.offset) }
            // a press (or nothing touched) ends the slide – pressing a key must not count as sliding
            guard action != .none, !inGroup.isEmpty, keys.allSatisfy({ !pressed.contains($0) }) else {
                last[g] = nil; acc[g] = 0; continue
            }
            let pos = inGroup.reduce(0, +) / Double(inGroup.count)   // between two keys = .5
            defer { last[g] = pos }
            guard let l = last[g] else { continue }
            acc[g] += (pos - l) * settings.stepsPerKey
            while acc[g] >= 1 { acc[g] -= 1; fire(g, up: settings.invert) }     // moving down the strip
            while acc[g] <= -1 { acc[g] += 1; fire(g, up: !settings.invert) }   // moving up the strip
        }
    }

    private func fire(_ g: Int, up: Bool) {
        switch settings.actions[g] {
        case .none: break
        case .brush:
            let code = up ? (KeyNames.keyCode(typing: "]") ?? 30) : (KeyNames.keyCode(typing: "[") ?? 33)
            key(code, [])
        case .history:
            key(KeyNames.keyCode(typing: "z") ?? 6, up ? [.maskCommand, .maskShift] : [.maskCommand])
        case .zoom:
            key(up ? 69 : (KeyNames.keyCode(typing: "-") ?? 27), [.maskCommand])   // ⌘ num+ / ⌘ −
        case .scroll:
            let e = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: up ? 3 : -3, wheel2: 0, wheel3: 0)
            e?.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
            e?.post(tap: .cghidEventTap)
        case .custom:
            let keys = up ? settings.customUp[g] : settings.customDown[g]
            if !keys.isEmpty { RadialMenu.send(keys) }
        }
    }

    private func key(_ code: Int, _ flags: CGEventFlags) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
            e?.post(tap: .cghidEventTap)
        }
    }
}
