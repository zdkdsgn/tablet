import SwiftUI
import AppKit

/// Localized UI text: Czech is the source language, English comes from en.lproj/Localizable.strings.
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

enum Theme {
    static let window = Color(hex: 0x1B1B1D)
    static let sidebar = Color(hex: 0x232326)
    static let card = Color(hex: 0x1F1F22)
    static let well = Color(hex: 0x26262A)
    static let control = Color(hex: 0x2C2C30)
    static let stage = Color(hex: 0x161618)
    static let border = Color(hex: 0x2F2F33)
    static let line = Color(hex: 0x333336)
    static let secondary = Color(hex: 0xA8A8AD)
    static let accent = Color(hex: 0x2F6FDE)
    static let ok = Color(hex: 0x34C759)
    static let warn = Color(hex: 0xFF9F0A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { Text(title).font(.system(size: 14, weight: .semibold)) }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

/// A row with a label + caption on the left and a control on the right.
struct SettingRow<Trailing: View>: View {
    var title: String
    var caption: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption { Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(12)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Banner: View {
    var text: String
    var button: String
    var action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(button, action: action)
        }
        .padding(12)
        .background(Theme.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warn.opacity(0.4)))
    }
}

// MARK: - Shortcut recorder

/// Click, then press a shortcut. Records physical keys (what OpenTabletDriver sends),
/// so it works with any keyboard layout. A modifier pressed alone (⌥, ⇧…) records just that.
struct ShortcutRecorder: View {
    @Binding var keys: [String]
    @State private var recording = false
    @State private var monitor: Any?
    @State private var peakMods: [String] = []

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? (peakMods.isEmpty ? L("Stiskněte zkratku…") : KeyNames.display(peakMods) + "…")
                           : (keys.isEmpty ? L("Klikněte a nahrajte") : KeyNames.display(keys)))
                .font(.system(size: recording ? 15 : 26, weight: .medium))
                .tracking(recording ? 0 : 2)
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(recording ? Theme.accent : Color(hex: 0x5A5A60), style: StrokeStyle(lineWidth: 1.5, dash: recording ? [] : [5, 4])))
        .accessibilityLabel("Klávesová zkratka \(KeyNames.display(keys)). Kliknutím nahrajete novou.")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        peakMods = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if e.type == .keyDown {
                if e.keyCode == 53 && e.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { stop(); return nil } // esc = cancel
                guard let name = KeyNames.codeToName[Int(e.keyCode)] else { NSSound.beep(); return nil }
                keys = KeyNames.modifierNames(from: e.modifierFlags) + [name]
                stop()
                return nil
            }
            let mods = KeyNames.modifierNames(from: e.modifierFlags)
            if mods.count > peakMods.count { peakMods = mods }
            if mods.isEmpty && !peakMods.isEmpty { keys = peakMods; stop() }
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}

// MARK: - Action editor

/// Edits one BindingAction: keyboard shortcut, mouse button, the pen's default, or nothing.
struct ActionEditor: View {
    @Binding var action: BindingAction
    var defaultAction: BindingAction? = nil   // e.g. .adaptive("Button 1") for pen buttons
    var defaultTitle = L("Výchozí")

    private enum Kind: Hashable { case keys, mouse, standard, none, other }

    private var kind: Binding<Kind> {
        Binding {
            switch action {
            case .keys: return .keys
            case .mouse: return .mouse
            case .adaptive: return .standard
            case .none: return .none
            case .unknown: return .other
            }
        } set: { k in
            switch k {
            case .keys: if case .keys = action {} else { action = .keys([]) }
            case .mouse: if case .mouse = action {} else { action = .mouse("Right") }
            case .standard: action = defaultAction ?? .none
            case .none: action = .none
            case .other: break
            }
        }
    }

    private var keys: Binding<[String]> {
        Binding { if case .keys(let k) = action { return k }; return [] } set: { action = .keys($0) }
    }
    private var mouse: Binding<String> {
        Binding { if case .mouse(let b) = action { return b }; return "Left" } set: { action = .mouse($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Typ akce", selection: kind) {
                Text("Zkratka").tag(Kind.keys)
                Text("Myš").tag(Kind.mouse)
                if defaultAction != nil { Text(defaultTitle).tag(Kind.standard) }
                Text("Nic").tag(Kind.none)
                if case .unknown = action { Text("Vlastní").tag(Kind.other) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch action {
            case .keys(let k):
                ShortcutRecorder(keys: keys)
                Text(k.isEmpty ? L("Klikněte a stiskněte zkratku. Esc zruší nahrávání.")
                     : (action.isModifierOnly ? L("Klávesa se drží, dokud držíte tlačítko.") : L("Klikněte do pole a stiskněte novou zkratku.")))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            case .mouse:
                Picker("Tlačítko myši", selection: mouse) {
                    ForEach(["Left", "Right", "Middle", "Backward", "Forward"], id: \.self) { Text(BindingAction.mouseTitle($0)).tag($0) }
                }
                .labelsHidden()
            case .adaptive:
                Text("Chová se jako běžné tlačítko pera.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            case .none:
                Text("Tlačítko nic nedělá.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            case .unknown:
                Text("Nastaveno v OpenTabletDriveru jiným typem akce – nechávám beze změny.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
