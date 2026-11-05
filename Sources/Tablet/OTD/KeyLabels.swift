import Foundation

/// User-given names for the 8 ExpressKeys (empty = automatic name from the shortcut).
@MainActor
final class KeyLabels: ObservableObject {
    private let d = UserDefaults.standard
    @Published var names: [String] { didSet { d.set(names, forKey: "keys.names") } }
    @Published var showOnPress: Bool { didSet { d.set(showOnPress, forKey: "keys.showOnPress") } }
    /// Functions handled by this app instead of OpenTabletDriver ("" = none), see AppKeyAction.
    @Published var appActions: [String] { didSet { d.set(appActions, forKey: "keys.appActions") } }

    init() {
        d.register(defaults: ["keys.showOnPress": true])
        let saved = d.stringArray(forKey: "keys.names") ?? []
        names = (0..<16).map { saved.indices.contains($0) ? saved[$0] : "" }
        showOnPress = d.bool(forKey: "keys.showOnPress")
        let acts = d.stringArray(forKey: "keys.appActions") ?? []
        appActions = (0..<16).map { acts.indices.contains($0) ? acts[$0] : "" }
    }

    func appAction(_ i: Int) -> AppKeyAction { AppKeyAction(rawValue: appActions[i]) ?? .none }

    func name(_ i: Int, for action: BindingAction) -> String {
        let n = names[i].trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        let app = appAction(i)
        return app == .none ? Self.autoName(action) : app.title
    }


    /// A readable name for common shortcuts (Photoshop-style single keys included).
    static func autoName(_ a: BindingAction) -> String {
        switch a {
        case .none: return L("Nic")
        case .mouse(let b): return BindingAction.mouseTitle(b)
        case .adaptive, .unknown: return a.title
        case .keys(let k):
            let mods = Set(k.compactMap(KeyNames.normalizedModifier))
            let rest = k.filter { KeyNames.normalizedModifier($0) == nil }
            if rest.isEmpty {
                if mods == ["Alt"] { return "Option" }
                if mods == ["Shift"] { return "Shift" }
                if mods == ["Application"] { return "Command" }
                if mods == ["Control"] { return "Control" }
                return KeyNames.display(k)
            }
            guard rest.count == 1, let key = rest.first else { return KeyNames.display(k) }
            // what the key types on the current layout, e.g. physical "Y" types "z" on Czech QWERTZ
            let ch = KeyNames.glyph(forKeyName: key).lowercased()
            if key == "Space" && mods.isEmpty { return L("Ruka") }
            if mods == ["Application"] {
                let m: [String: String] = ["z": L("Zpět"), "s": L("Uložit"), "c": L("Kopírovat"), "v": L("Vložit"), "x": L("Vyjmout"),
                                           "a": L("Vybrat vše"), "d": L("Zrušit výběr"), "t": L("Transformace"), "j": L("Duplikovat vrstvu"),
                                           "0": L("Přizpůsobit oknu"), "1": "Zoom 100 %", "e": L("Sloučit dolů"), "g": L("Seskupit"),
                                           "o": L("Otevřít"), "n": L("Nový"), "w": L("Zavřít"), "f": L("Najít"), "r": L("Pravítka")]
                if let n = m[ch] { return n }
                if key == "Add" { return L("Přiblížit") }
            }
            if mods == ["Application", "Shift"] {
                let m: [String: String] = ["z": L("Znovu"), "i": L("Invertovat výběr"), "s": L("Uložit jako"), "e": L("Sloučit viditelné")]
                if let n = m[ch] { return n }
            }
            if mods == ["Application", "Alt"], ch == "z" { return L("Krok zpět") }
            if mods.isEmpty {
                let m: [String: String] = ["b": L("Štětec"), "e": L("Guma"), "v": L("Přesun"), "m": L("Výběr"), "l": L("Laso"),
                                           "w": L("Rychlý výběr"), "i": L("Kapátko"), "t": L("Text"), "h": L("Ruka"), "z": L("Lupa"),
                                           "x": L("Prohodit barvy"), "d": L("Výchozí barvy"), "g": L("Přechod"), "s": L("Razítko"),
                                           "j": L("Retušování"), "p": L("Pero"), "u": L("Tvary"), "c": L("Oříznutí"), "r": L("Otočit pohled"),
                                           "o": L("Zesvětlit/ztmavit"), "q": L("Rychlá maska"), "f": L("Režim obrazovky")]
                if let n = m[ch] { return n }
                if key == "Escape" { return L("Zrušit") }
                if key == "Enter" { return L("Potvrdit") }
                if key == "Tab" { return L("Skrýt panely") }
            }
            return KeyNames.display(k)
        }
    }
}

/// ExpressKey functions implemented by this app (OpenTabletDriver's binding is set to nothing).
enum AppKeyAction: String, CaseIterable, Identifiable {
    case none = "", precision, display, radial
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return L("Žádná")
        case .precision: return L("Přesný režim")
        case .display: return L("Další monitor")
        case .radial: return L("Kruhové menu")
        }
    }
    var caption: String {
        switch self {
        case .none: return ""
        case .precision: return L("Dokud tlačítko držíte, pero se pohybuje jemněji.")
        case .display: return L("Přepne, na který monitor se tablet mapuje.")
        case .radial: return L("Podržte, perem vyberte akci a tlačítko pusťte.")
        }
    }
    var symbol: String {
        switch self {
        case .none: return "circle.slash"
        case .precision: return "scope"
        case .display: return "display.2"
        case .radial: return "circle.grid.cross"
        }
    }
}
