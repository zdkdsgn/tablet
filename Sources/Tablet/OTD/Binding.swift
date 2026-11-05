import Foundation

/// One OpenTabletDriver binding ("Plugin setting store"), simplified to what this app edits.
enum BindingAction: Equatable {
    case none
    case keys([String])          // Multi-Key Binding
    case mouse(String)           // Mouse Button Binding: Left, Middle, Right, Backward, Forward
    case adaptive(String)        // Adaptive Binding: Tip, Eraser, Button 1, Button 2…
    case unknown([String: Any])  // anything else – kept untouched

    static func == (a: BindingAction, b: BindingAction) -> Bool {
        switch (a, b) {
        case (.none, .none): return true
        case let (.keys(x), .keys(y)): return x == y
        case let (.mouse(x), .mouse(y)): return x == y
        case let (.adaptive(x), .adaptive(y)): return x == y
        case let (.unknown(x), .unknown(y)): return NSDictionary(dictionary: x).isEqual(to: y)
        default: return false
        }
    }

    static let keyPath = "OpenTabletDriver.Desktop.Binding.MultiKeyBinding"
    static let mousePath = "OpenTabletDriver.Desktop.Binding.MouseBinding"
    static let adaptivePath = "OpenTabletDriver.Desktop.Binding.AdaptiveBinding"

    init(json: Any?) {
        guard let d = json as? [String: Any], let path = d["Path"] as? String else { self = .none; return }
        let settings = d["Settings"] as? [[String: Any]] ?? []
        func value(_ prop: String) -> String? {
            settings.first { ($0["Property"] as? String) == prop }?["Value"] as? String
        }
        switch path {
        case Self.keyPath:
            let keys = (value("Keys") ?? "").split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            self = keys.isEmpty ? .none : .keys(keys)
        case Self.mousePath:
            self = .mouse(value("Button") ?? "Left")
        case Self.adaptivePath:
            self = .adaptive(value("Binding") ?? "Tip")
        default:
            self = .unknown(d)
        }
    }

    var json: Any {
        func store(_ path: String, _ prop: String, _ value: String) -> [String: Any] {
            ["Path": path, "Settings": [["Property": prop, "Value": value]], "Enable": true]
        }
        switch self {
        case .none: return NSNull()
        case .keys(let k): return store(Self.keyPath, "Keys", k.joined(separator: "+"))
        case .mouse(let b): return store(Self.mousePath, "Button", b)
        case .adaptive(let b): return store(Self.adaptivePath, "Binding", b)
        case .unknown(let d): return d
        }
    }

    var title: String {
        switch self {
        case .none: return "Nic"
        case .keys(let k): return KeyNames.display(k)
        case .mouse(let b): return Self.mouseTitle(b)
        case .adaptive(let b):
            switch b {
            case "Button 1": return "Výchozí (tlačítko 1)"
            case "Button 2": return "Výchozí (tlačítko 2)"
            case "Tip": return "Hrot"
            case "Eraser": return "Guma"
            default: return b
            }
        case .unknown: return "Vlastní"
        }
    }

    static func mouseTitle(_ b: String) -> String {
        switch b {
        case "Left": return "Kliknutí"
        case "Right": return "Pravé kliknutí"
        case "Middle": return "Prostřední kliknutí"
        case "Backward": return "Zpět (myš)"
        case "Forward": return "Vpřed (myš)"
        default: return b
        }
    }

    /// True when every key is a modifier – those are best held while the button is held.
    var isModifierOnly: Bool {
        if case .keys(let k) = self { return !k.isEmpty && k.allSatisfy(KeyNames.isModifier) }
        return false
    }
}
