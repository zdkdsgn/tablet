import SwiftUI
import AppKit

struct RadialItem: Codable, Equatable {
    var name: String
    var keys: [String]
}

/// The 8 actions of the radial menu, stored in UserDefaults.
@MainActor
final class RadialSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var items: [RadialItem] { didSet { save() } }

    static let defaults: [RadialItem] = [
        RadialItem(name: L("Zpět"), keys: ["Application", "Y"]),
        RadialItem(name: L("Znovu"), keys: ["Application", "Shift", "Y"]),
        RadialItem(name: L("Štětec"), keys: ["B"]),
        RadialItem(name: L("Guma"), keys: ["E"]),
        RadialItem(name: L("Kapátko"), keys: ["I"]),
        RadialItem(name: L("Ruka"), keys: ["H"]),
        RadialItem(name: L("Přiblížit"), keys: ["Application", "Add"]),
        RadialItem(name: L("Přizpůsobit"), keys: ["Application", "D0"]),
    ]

    init() {
        if let data = d.data(forKey: "radial.items"), let saved = try? JSONDecoder().decode([RadialItem].self, from: data), saved.count == 8 {
            items = saved
        } else {
            items = Self.layoutDefaults()
        }
    }

    /// Defaults adjusted to the keyboard layout: ⌘Z is on the physical Y key on QWERTZ.
    static func layoutDefaults() -> [RadialItem] {
        var def = defaults
        let z = KeyNames.keyName(typing: "z") ?? "Z"
        def[0].keys = ["Application", z]
        def[1].keys = ["Application", "Shift", z]
        return def
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { d.set(data, forKey: "radial.items") }
    }
}

/// A pie menu that opens at the cursor while an ExpressKey is held; the pen picks a slice.
@MainActor
final class RadialMenu {
    private let settings: RadialSettings
    private var panel: NSPanel?
    private var timer: Timer?
    private var center: CGPoint = .zero      // screen coordinates (Cocoa, bottom-left origin)
    private let model = RadialModel()
    private let size: CGFloat = 300

    init(settings: RadialSettings) { self.settings = settings }

    var isOpen: Bool { panel?.isVisible == true }

    func open() {
        center = NSEvent.mouseLocation
        model.items = settings.items
        model.selected = nil
        let p = panel ?? makePanel()
        p.contentView = NSHostingView(rootView: RadialView(model: model, size: size) { [weak self] i in
            self?.model.selected = i
            self?.close(perform: true)
        })
        p.setFrame(NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
    }

    /// Closes the menu; with `perform` the highlighted action is sent to the app in front.
    func close(perform: Bool) {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
        if perform, let i = model.selected, settings.items.indices.contains(i) {
            Self.send(settings.items[i].keys)
        }
        model.selected = nil
    }

    private func track() {
        let m = NSEvent.mouseLocation
        let dx = m.x - center.x, dy = m.y - center.y
        if hypot(dx, dy) < 34 { model.selected = nil; return }
        // slice 0 at the top, clockwise
        var a = atan2(dx, dy) * 180 / .pi
        if a < 0 { a += 360 }
        model.selected = Int((a + 22.5) / 45) % 8
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.appearance = NSAppearance(named: .darkAqua)   // on-screen overlays stay dark in light mode too
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return p
    }

    /// Presses a shortcut given as OpenTabletDriver key names (modifiers + key).
    static func send(_ keys: [String]) {
        let src = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        for k in keys {
            switch KeyNames.normalizedModifier(k) {
            case "Application": flags.insert(.maskCommand)
            case "Shift": flags.insert(.maskShift)
            case "Alt": flags.insert(.maskAlternate)
            case "Control": flags.insert(.maskControl)
            default: break
            }
        }
        guard let main = keys.last(where: { KeyNames.normalizedModifier($0) == nil }), let code = KeyNames.nameToCode[main] else { return }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: TouchEngine.marker)
            e?.post(tap: .cghidEventTap)
        }
    }
}

final class RadialModel: ObservableObject {
    @Published var items: [RadialItem] = []
    @Published var selected: Int?
}

private struct RadialView: View {
    @ObservedObject var model: RadialModel
    var size: CGFloat
    var pick: (Int) -> Void

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            Circle().fill(Color.black.opacity(0.35))
            ForEach(0..<8, id: \.self) { i in
                Slice(index: i)
                    .fill(model.selected == i ? Theme.accent : Color.white.opacity(0.0001))
                    .onTapGesture { pick(i) }
                let angle = (Double(i) * 45 - 90) * .pi / 180
                let r = size * 0.36
                VStack(spacing: 2) {
                    Text(model.items.indices.contains(i) ? model.items[i].name : "")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.items.indices.contains(i) ? KeyNames.display(model.items[i].keys) : "")
                        .font(.system(size: 10)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .frame(width: 84)
                .offset(x: cos(angle) * r, y: sin(angle) * r)
                .allowsHitTesting(false)
            }
            ForEach(0..<8, id: \.self) { i in   // separators
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: size / 2 - 40)
                    .offset(y: -(size / 4 + 20))
                    .rotationEffect(.degrees(Double(i) * 45 + 22.5))
            }
            Circle().fill(Color(hex: 0x1B1B1D)).frame(width: 64, height: 64)
                .overlay(Circle().stroke(Color.white.opacity(0.15)))
                .overlay(Image(systemName: "xmark").foregroundStyle(.white.opacity(0.6)))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.4), radius: 16)
    }
}

/// One 45° ring segment, slice 0 centred at the top.
private struct Slice: Shape {
    var index: Int
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width / 2, inner: CGFloat = 32
        let start = Angle.degrees(Double(index) * 45 - 90 - 22.5), end = Angle.degrees(Double(index) * 45 - 90 + 22.5)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Editor for the 8 radial menu items.
struct RadialEditor: View {
    @EnvironmentObject var radial: RadialSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(.system(size: 11)).foregroundStyle(Theme.secondary).frame(width: 14)
                    TextField("Název", text: $radial.items[i].name).textFieldStyle(.roundedBorder).frame(width: 110)
                    CompactRecorder(keys: $radial.items[i].keys)
                }
            }
            Button("Obnovit výchozí") { radial.items = RadialSettings.layoutDefaults() }
                .controlSize(.small)
        }
    }
}

/// A small one-line shortcut recorder (click, press keys).
struct CompactRecorder: View {
    @Binding var keys: [String]
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? L("Stiskněte…") : (keys.isEmpty ? "—" : KeyNames.display(keys)))
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(recording ? Theme.accent : Color(hex: 0x45454A)))
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
            if e.keyCode == 53 { stop(); return nil }
            if let name = KeyNames.codeToName[Int(e.keyCode)] {
                keys = KeyNames.modifierNames(from: e.modifierFlags) + [name]
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}
