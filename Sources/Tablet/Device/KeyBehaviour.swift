import AppKit

/// Posts key presses for OpenTabletDriver-style key names (physical keys, e.g. ["Application", "Y"]).
/// Modifiers are pressed as real keys, so a held modifier behaves like one held on the keyboard.
@MainActor
enum KeySender {
    private static let source = CGEventSource(stateID: .hidSystemState)

    static func modifier(_ name: String) -> (code: CGKeyCode, flag: CGEventFlags)? {
        switch KeyNames.normalizedModifier(name) {
        case "Application": return (55, .maskCommand)
        case "Shift": return (56, .maskShift)
        case "Alt": return (58, .maskAlternate)
        case "Control": return (59, .maskControl)
        default: return nil
        }
    }

    static func flags(_ keys: [String]) -> CGEventFlags {
        keys.compactMap(modifier).reduce(into: CGEventFlags()) { $0.insert($1.flag) }
    }

    static func press(_ keys: [String], down: Bool) {
        let mods = keys.compactMap(modifier)
        let main = keys.filter { modifier($0) == nil }.compactMap { KeyNames.nameToCode[$0] }.map { CGKeyCode($0) }
        var f: CGEventFlags = []
        if down {
            for m in mods { f.insert(m.flag); post(m.code, true, f) }
            for c in main { post(c, true, f) }
        } else {
            f = flags(keys)
            for c in main.reversed() { post(c, false, f) }
            for m in mods.reversed() { f.remove(m.flag); post(m.code, false, f) }
        }
    }

    static func tap(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        press(keys, down: true)
        press(keys, down: false)
    }

    private static func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
        e.post(tap: .cghidEventTap)
    }

    /// Volume / brightness keys (NX_KEYTYPE_*), with the system's on-screen indicator.
    static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA00 : 0xB00
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                                        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                        data1: (key << 16) | state, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    static let soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3
}

/// Tap / hold shortcuts and two-key combinations for ExpressKeys handled by this app,
/// plus automatic tool switching when the pen is flipped to the eraser.
@MainActor
final class KeyBehaviour: ObservableObject {
    private let d = UserDefaults.standard
    /// Shortcut sent on a short press (key released before the hold delay).
    @Published var tapKeys: [[String]] { didSet { d.set(tapKeys, forKey: "keys.tap") } }
    /// Keys held down for as long as the ExpressKey is held (e.g. ⌥ for the eyedropper, Space for the hand).
    @Published var holdKeys: [[String]] { didSet { d.set(holdKeys, forKey: "keys.hold") } }
    /// Seconds before a press counts as a hold.
    @Published var holdDelay: Double { didSet { d.set(holdDelay, forKey: "keys.holdDelay") } }
    /// Two keys pressed together: "a+b" (a < b, zero-based) → shortcut.
    @Published var combos: [String: [String]] { didSet { d.set(combos, forKey: "keys.combos") } }

    /// Flip the pen → eraser tool key, flip back → pen tool key.
    @Published var eraserSwitch: Bool { didSet { d.set(eraserSwitch, forKey: "pen.eraserSwitch") } }
    @Published var eraserKeys: [String] { didSet { d.set(eraserKeys, forKey: "pen.eraserKeys") } }
    @Published var penKeys: [String] { didSet { d.set(penKeys, forKey: "pen.penKeys") } }

    init() {
        d.register(defaults: ["keys.holdDelay": 0.3, "pen.eraserSwitch": false])
        let ud = UserDefaults.standard
        func keys(_ k: String) -> [[String]] {
            let a = (ud.array(forKey: k) as? [[String]]) ?? []
            return (0..<16).map { a.indices.contains($0) ? a[$0] : [] }
        }
        tapKeys = keys("keys.tap")
        holdKeys = keys("keys.hold")
        holdDelay = d.double(forKey: "keys.holdDelay")
        combos = (d.dictionary(forKey: "keys.combos") as? [String: [String]]) ?? [:]
        eraserSwitch = d.bool(forKey: "pen.eraserSwitch")
        eraserKeys = d.stringArray(forKey: "pen.eraserKeys") ?? [KeyNames.keyName(typing: "e") ?? "E"]
        penKeys = d.stringArray(forKey: "pen.penKeys") ?? [KeyNames.keyName(typing: "b") ?? "B"]
    }

    static func comboKey(_ a: Int, _ b: Int) -> String { "\(min(a, b))+\(max(a, b))" }

    func combo(_ a: Int, _ b: Int) -> [String] { combos[Self.comboKey(a, b)] ?? [] }

    func setCombo(_ a: Int, _ b: Int, _ keys: [String]) {
        if keys.isEmpty { combos.removeValue(forKey: Self.comboKey(a, b)) } else { combos[Self.comboKey(a, b)] = keys }
    }

    /// Combinations that include key `i`: partner index → shortcut.
    func combos(with i: Int) -> [(partner: Int, keys: [String])] {
        combos.compactMap { k, v in
            let p = k.split(separator: "+").compactMap { Int($0) }
            guard p.count == 2, p.contains(i) else { return nil }
            return (p[0] == i ? p[1] : p[0], v)
        }.sorted { $0.partner < $1.partner }
    }
}

/// Runs tap / hold / combo keys. Keys with the "tap / hold" function are fully handled here.
@MainActor
final class KeyPressEngine {
    private let settings: KeyBehaviour
    /// Modifiers currently held by a key – added to the pen's clicks (PenTap) so ⌥-click works with the pen.
    private(set) var heldFlags: CGEventFlags = []
    var onHeldFlagsChange: ((CGEventFlags) -> Void)?
    /// Shows what happened (name of the shortcut) – set by the app model.
    var onFire: ((Int, String) -> Void)?

    private var timers: [Int: Timer] = [:]
    private var holding: [Int: [String]] = [:]
    private var consumed = Set<Int>()
    private var down = Set<Int>()

    init(settings: KeyBehaviour) { self.settings = settings }

    func press(_ i: Int) {
        down.insert(i)
        // another tap/hold key already down + a combination defined → the combination wins
        if let other = down.first(where: { $0 != i && !consumed.contains($0) && !settings.combo($0, i).isEmpty }) {
            let keys = settings.combo(other, i)
            for k in [other, i] { timers[k]?.invalidate(); timers[k] = nil; consumed.insert(k); release(k) }
            KeySender.tap(keys)
            onFire?(i, KeyNames.display(keys))
            return
        }
        let t = Timer(timeInterval: settings.holdDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginHold(i) }
        }
        RunLoop.main.add(t, forMode: .common)
        timers[i] = t
    }

    func release(_ i: Int, wasDown: Bool = false) {
        if wasDown { down.remove(i) }
        timers[i]?.invalidate(); timers[i] = nil
        if let keys = holding.removeValue(forKey: i) {
            KeySender.press(keys, down: false)
            updateFlags()
        } else if wasDown, !consumed.contains(i) {
            let keys = settings.tapKeys[i]
            KeySender.tap(keys)
            if !keys.isEmpty { onFire?(i, KeyNames.display(keys)) }
        }
        if wasDown { consumed.remove(i) }
    }

    private func beginHold(_ i: Int) {
        timers[i] = nil
        guard down.contains(i), !consumed.contains(i) else { return }
        let keys = settings.holdKeys[i]
        guard !keys.isEmpty else {
            // no hold shortcut: a long press is still a tap
            return
        }
        consumed.insert(i)
        holding[i] = keys
        KeySender.press(keys, down: true)
        updateFlags()
    }

    private func updateFlags() {
        heldFlags = holding.values.reduce(into: CGEventFlags()) { $0.formUnion(KeySender.flags($1)) }
        onHeldFlagsChange?(heldFlags)
    }

    /// Releases everything (e.g. when the tablet disconnects).
    func reset() {
        for i in Array(holding.keys) { release(i) }
        down.removeAll(); consumed.removeAll()
    }
}
