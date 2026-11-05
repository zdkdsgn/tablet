import Foundation

/// User-given names for the 8 ExpressKeys (empty = automatic name from the shortcut).
@MainActor
final class KeyLabels: ObservableObject {
    private let d = UserDefaults.standard
    @Published var names: [String] { didSet { d.set(names, forKey: "keys.names") } }
    @Published var showOnPress: Bool { didSet { d.set(showOnPress, forKey: "keys.showOnPress") } }

    init() {
        d.register(defaults: ["keys.showOnPress": true])
        let saved = d.stringArray(forKey: "keys.names") ?? []
        names = (0..<8).map { saved.indices.contains($0) ? saved[$0] : "" }
        showOnPress = d.bool(forKey: "keys.showOnPress")
    }

    func name(_ i: Int, for action: BindingAction) -> String {
        let n = names[i].trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? Self.autoName(action) : n
    }

    /// A readable name for common shortcuts (Photoshop-style single keys included).
    static func autoName(_ a: BindingAction) -> String {
        switch a {
        case .none: return "Nic"
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
            if key == "Space" && mods.isEmpty { return "Ruka" }
            if mods == ["Application"] {
                let m: [String: String] = ["z": "Zpět", "s": "Uložit", "c": "Kopírovat", "v": "Vložit", "x": "Vyjmout",
                                           "a": "Vybrat vše", "d": "Zrušit výběr", "t": "Transformace", "j": "Duplikovat vrstvu",
                                           "0": "Přizpůsobit oknu", "1": "Zoom 100 %", "e": "Sloučit dolů", "g": "Seskupit",
                                           "o": "Otevřít", "n": "Nový", "w": "Zavřít", "f": "Najít", "r": "Pravítka"]
                if let n = m[ch] { return n }
                if key == "Add" { return "Přiblížit" }
            }
            if mods == ["Application", "Shift"] {
                let m: [String: String] = ["z": "Znovu", "i": "Invertovat výběr", "s": "Uložit jako", "e": "Sloučit viditelné"]
                if let n = m[ch] { return n }
            }
            if mods == ["Application", "Alt"], ch == "z" { return "Krok zpět" }
            if mods.isEmpty {
                let m: [String: String] = ["b": "Štětec", "e": "Guma", "v": "Přesun", "m": "Výběr", "l": "Laso",
                                           "w": "Rychlý výběr", "i": "Kapátko", "t": "Text", "h": "Ruka", "z": "Lupa",
                                           "x": "Prohodit barvy", "d": "Výchozí barvy", "g": "Přechod", "s": "Razítko",
                                           "j": "Retušování", "p": "Pero", "u": "Tvary", "c": "Oříznutí", "r": "Otočit pohled",
                                           "o": "Zesvětlit/ztmavit", "q": "Rychlá maska", "f": "Režim obrazovky"]
                if let n = m[ch] { return n }
                if key == "Escape" { return "Zrušit" }
                if key == "Enter" { return "Potvrdit" }
                if key == "Tab" { return "Skrýt panely" }
            }
            return KeyNames.display(k)
        }
    }
}
