import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case tablet, pen, touch, lights, area, presets
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tablet: return "Tablet"
        case .pen: return "Pero"
        case .touch: return "Dotyk"
        case .lights: return "Světla"
        case .area: return "Plocha a monitor"
        case .presets: return "Předvolby aplikací"
        }
    }
    var icon: String {
        switch self {
        case .tablet: return "rectangle.inset.filled"
        case .pen: return "pencil.tip"
        case .touch: return "hand.point.up.left"
        case .lights: return "lightbulb"
        case .area: return "display"
        case .presets: return "list.bullet.rectangle"
        }
    }
    var subtitle: String {
        switch self {
        case .tablet: return "Klikněte na tlačítko nebo kolečko a nastavte, co dělá"
        case .pen: return "Grip Pen · tlak 2048 úrovní · náklon"
        case .touch: return "Ovládání prsty jako na trackpadu"
        case .lights: return "Světýlka kolečka a rohů plochy"
        case .area: return "Kterou část tabletu použít a na kterou obrazovku ji mapovat"
        case .presets: return "Různé nastavení pro různé aplikace"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var device: DeviceMonitor
    @AppStorage("section") private var section: Section = .tablet

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(section.title).font(.system(size: 15, weight: .semibold))
                    Text(section.subtitle).foregroundStyle(Theme.secondary)
                    Spacer()
                    if section == .tablet || section == .pen { PresetMenu() }
                }
                .padding(.horizontal, 20)
                .frame(height: 52)
                Divider().overlay(Theme.line)
                if let e = store.lastError {
                    Banner(text: e, button: "Zkusit znovu") { store.reload(); store.startDaemon() }
                        .padding([.horizontal, .top], 20)
                }
                Group {
                    switch section {
                    case .tablet: TabletView()
                    case .pen: PenView()
                    case .touch: TouchView()
                    case .lights: LightsView()
                    case .area: AreaView()
                    case .presets: PresetsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.window)
        .font(.system(size: 13))
    }
}

struct Sidebar: View {
    @Binding var section: Section
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var device: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                TabletGlyph()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intuos Pro M").fontWeight(.semibold)
                    HStack(spacing: 5) {
                        Circle().fill(device.connected ? Theme.ok : Theme.secondary).frame(width: 7, height: 7)
                        Text(device.connected ? "PTH-651 · připojeno" : "PTH-651 · nepřipojeno")
                    }
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 30)

            VStack(spacing: 2) {
                ForEach(Section.allCases) { s in
                    Button { section = s } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.icon).frame(width: 18)
                            Text(s.title)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(section == s ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(section == s ? .white : Color(hex: 0xE4E4E8))
                        .fontWeight(section == s ? .medium : .regular)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Ovladač").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text("OpenTabletDriver")
                if store.daemonRunning {
                    Text("Běží · \(store.daemonSource.lowercased())").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if store.daemonSource == "Samostatný OpenTabletDriver" {
                        Button("Použít vestavěný") { store.startDaemon() }.controlSize(.small)
                    }
                } else {
                    Button("Spustit ovladač") { store.startDaemon() }.controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

struct TabletGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(hex: 0x0F0F10))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: 0x4A4A4F)))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x3A3A3E)).frame(width: 6, height: 18).padding(.leading, 4)
            }
            .frame(width: 40, height: 28)
            .accessibilityHidden(true)
    }
}

struct PresetMenu: View {
    @EnvironmentObject var store: OTDStore
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("Předvolba").foregroundStyle(Theme.secondary)
            Menu(store.activePreset ?? "Bez předvolby") {
                ForEach(store.presets, id: \.self) { p in Button(p) { store.applyPreset(p) } }
                if !store.presets.isEmpty { Divider() }
                Button("Uložit současné jako…") { name = ""; naming = true }
            }
            .fixedSize()
        }
        .alert("Nová předvolba", isPresented: $naming) {
            TextField("Název, např. Photoshop", text: $name)
            Button("Uložit") { store.savePreset(named: name) }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Pojmenujte ji jako aplikaci a při automatickém přepínání se zapne sama.")
        }
    }
}
