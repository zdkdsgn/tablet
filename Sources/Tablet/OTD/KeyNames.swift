import AppKit
import Carbon.HIToolbox

/// Mapping between macOS virtual key codes and the key names OpenTabletDriver's
/// macOS keyboard understands (MacOSVirtualKeyboard.EtoKeysymToVK, v0.6.8.1).
/// OTD sends *physical* keys, so recording by key code makes any keyboard layout
/// (e.g. Czech QWERTZ) work without manual translation.
enum KeyNames {
    static let nameToCode: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
        "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
        "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
        "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
        "Z": kVK_ANSI_Z,
        "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
        "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
        "D0": kVK_ANSI_0, "D1": kVK_ANSI_1, "D2": kVK_ANSI_2, "D3": kVK_ANSI_3, "D4": kVK_ANSI_4,
        "D5": kVK_ANSI_5, "D6": kVK_ANSI_6, "D7": kVK_ANSI_7, "D8": kVK_ANSI_8, "D9": kVK_ANSI_9,
        "Minus": kVK_ANSI_Minus, "Grave": kVK_ANSI_Grave, "Home": kVK_Home, "PageUp": kVK_PageUp,
        "PageDown": kVK_PageDown, "Delete": kVK_ForwardDelete, "End": kVK_End,
        "Divide": kVK_ANSI_KeypadDivide, "Decimal": kVK_ANSI_KeypadDecimal, "Backspace": kVK_Delete,
        "Up": kVK_UpArrow, "Down": kVK_DownArrow, "Left": kVK_LeftArrow, "Right": kVK_RightArrow,
        "Tab": kVK_Tab, "Space": kVK_Space, "Enter": kVK_Return, "Escape": kVK_Escape,
        "Multiply": kVK_ANSI_KeypadMultiply, "Add": kVK_ANSI_KeypadPlus, "Help": kVK_Help,
        "Clear": kVK_ANSI_KeypadClear, "KeypadEqual": kVK_ANSI_KeypadEquals,
        "Backslash": kVK_ANSI_Backslash, "Equal": kVK_ANSI_Equal, "Semicolon": kVK_ANSI_Semicolon,
        "Quote": kVK_ANSI_Quote, "Comma": kVK_ANSI_Comma, "Period": kVK_ANSI_Period,
        "Slash": kVK_ANSI_Slash, "RightBracket": kVK_ANSI_RightBracket, "LeftBracket": kVK_ANSI_LeftBracket,
        "Keypad0": kVK_ANSI_Keypad0, "Keypad1": kVK_ANSI_Keypad1, "Keypad2": kVK_ANSI_Keypad2,
        "Keypad3": kVK_ANSI_Keypad3, "Keypad4": kVK_ANSI_Keypad4, "Keypad5": kVK_ANSI_Keypad5,
        "Keypad6": kVK_ANSI_Keypad6, "Keypad7": kVK_ANSI_Keypad7, "Keypad8": kVK_ANSI_Keypad8,
        "Keypad9": kVK_ANSI_Keypad9,
        "Shift": kVK_Shift, "Alt": kVK_Option, "Control": kVK_Control, "Application": kVK_Command,
        "LeftShift": kVK_Shift, "RightShift": kVK_RightShift, "LeftControl": kVK_Control,
        "RightControl": kVK_RightControl, "LeftAlt": kVK_Option, "RightAlt": kVK_RightOption,
        "LeftApplication": kVK_Command, "RightApplication": kVK_RightCommand,
        "Mute": kVK_Mute, "VolumeDown": kVK_VolumeDown, "VolumeUp": kVK_VolumeUp,
    ]

    /// Preferred name per key code (first, unprefixed modifiers win).
    static let codeToName: [Int: String] = {
        var m: [Int: String] = [:]
        let preferred = ["Shift", "Alt", "Control", "Application", "Add", "Slash"]
        for n in preferred { if let c = nameToCode[n] { m[c] = n } }
        for (n, c) in nameToCode where m[c] == nil { m[c] = n }
        return m
    }()

    static let modifierOrder = ["Control", "Alt", "Shift", "Application"]
    static let modifierGlyph = ["Control": "⌃", "Alt": "⌥", "Shift": "⇧", "Application": "⌘"]

    static func isModifier(_ name: String) -> Bool { normalizedModifier(name) != nil }

    static func normalizedModifier(_ name: String) -> String? {
        switch name {
        case "Shift", "LeftShift", "RightShift": return "Shift"
        case "Alt", "LeftAlt", "RightAlt": return "Alt"
        case "Control", "LeftControl", "RightControl": return "Control"
        case "Application", "LeftApplication", "RightApplication": return "Application"
        default: return nil
        }
    }

    private static let specialGlyph: [String: String] = [
        "Space": "Mezerník", "Enter": "↩", "Escape": "esc", "Tab": "⇥", "Backspace": "⌫",
        "Delete": "⌦", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Home": "↖",
        "End": "↘", "PageUp": "⇞", "PageDown": "⇟", "Add": "num +", "Multiply": "num ×",
        "Divide": "num ÷", "Decimal": "num ,", "KeypadEqual": "num =", "Clear": "⌧",
        "Mute": "Ztlumit", "VolumeUp": "Hlasitost +", "VolumeDown": "Hlasitost −", "Help": "Nápověda",
    ]

    /// What the key prints with the *current* keyboard layout (so "Y" shows "Z" on Czech QWERTZ).
    static func glyph(forKeyName name: String) -> String {
        if let s = specialGlyph[name] { return s }
        if name.hasPrefix("F"), Int(name.dropFirst()) != nil { return name }
        if name.hasPrefix("Keypad") { return "num " + name.dropFirst(6) }
        if let mod = normalizedModifier(name) { return modifierGlyph[mod]! }
        guard let code = nameToCode[name], let ch = character(forKeyCode: code), !ch.isEmpty else { return name }
        return ch.uppercased()
    }

    static func character(forKeyCode code: Int) -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var dead: UInt32 = 0
            var len = 0
            var buf = [UniChar](repeating: 0, count: 4)
            let st = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &dead, 4, &len, &buf)
            return st == noErr ? String(utf16CodeUnits: buf, count: len) : nil
        }
    }

    /// Finds the physical key that types `char` on the current layout (no modifiers).
    static func keyCode(typing char: String) -> Int? {
        for code in 0..<128 where character(forKeyCode: code) == char { return code }
        return nil
    }

    static func keyName(typing char: String) -> String? {
        keyCode(typing: char).flatMap { codeToName[$0] }
    }

    /// Human readable shortcut for a list of OTD key names, e.g. ["Application","Y"] → "⌘Z" on Czech layout.
    static func display(_ keys: [String]) -> String {
        let mods = keys.compactMap(normalizedModifier)
        let rest = keys.filter { normalizedModifier($0) == nil }
        let modStr = modifierOrder.filter(mods.contains).compactMap { modifierGlyph[$0] }.joined()
        let restStr = rest.map(glyph(forKeyName:)).joined(separator: " ")
        if restStr.isEmpty { return modStr }
        return modStr + restStr
    }

    static func modifierNames(from flags: NSEvent.ModifierFlags) -> [String] {
        var r: [String] = []
        if flags.contains(.control) { r.append("Control") }
        if flags.contains(.option) { r.append("Alt") }
        if flags.contains(.shift) { r.append("Shift") }
        if flags.contains(.command) { r.append("Application") }
        return r
    }
}
