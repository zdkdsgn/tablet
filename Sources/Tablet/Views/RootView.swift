import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case tablet, pen, strokes, touch, lights, area, presets, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tablet: return L("Tablet")
        case .pen: return L("Pero")
        case .strokes: return L("Tahy")
        case .touch: return L("Dotyk")
        case .lights: return L("Světla")
        case .area: return L("Plocha a monitor")
        case .presets: return L("Předvolby aplikací")
        case .general: return L("Obecné")
        }
    }
    var icon: String {
        switch self {
        case .tablet: return "rectangle.inset.filled"
        case .pen: return "pencil.tip"
        case .strokes: return "scribble.variable"
        case .touch: return "hand.point.up.left"
        case .lights: return "lightbulb"
        case .area: return "display"
        case .presets: return "list.bullet.rectangle"
        case .general: return "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .tablet: return L("Klikněte na tlačítko nebo kolečko a nastavte, co dělá")
        case .pen: return L("Grip Pen · tlak 2048 úrovní · náklon")
        case .strokes: return L("Co jste nakreslili – tah po tahu")
        case .touch: return L("Ovládání prsty jako na trackpadu")
        case .lights: return L("Světýlka kolečka a rohů plochy")
        case .area: return L("Kterou část tabletu použít a na kterou obrazovku ji mapovat")
        case .presets: return L("Různé nastavení pro různé aplikace")
        case .general: return L("Aktualizace, záloha, Zkratky a Siri")
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
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
                    Banner(text: e, button: L("Zkusit znovu")) { store.reload(); store.startDaemon() }
                        .padding([.horizontal, .top], 20)
                } else if !device.connected && section != .general {
                    InfoStrip(symbol: "cable.connector.slash", text: L("Tablet není připojený. Nastavení se uloží a použije, jakmile ho připojíte."))
                        .padding([.horizontal, .top], 20)
                }
                Group {
                    switch section {
                    case .tablet: TabletView()
                    case .pen: PenView()
                    case .strokes: StrokesView()
                    case .touch: TouchView()
                    case .lights: LightsView()
                    case .area: AreaView()
                    case .presets: PresetsView()
                    case .general: GeneralView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { UndoToast() }
            }
        }
        .background(Theme.window)
        .font(.system(size: 13))
        .onAppear { model.openMain = { [openWindow] in openWindow(id: "main") } }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model, store: store, device: device, pen: model.penFilters, hover: model.penHover) {
                model.showOnboarding = false
            }
        }
    }
}

struct Sidebar: View {
    @Binding var section: Section
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var device: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                TabletGlyph().environment(\.colorScheme, .dark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.tablet.displayName).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 5) {
                        Circle().fill(device.connected ? Theme.ok : Theme.secondary).frame(width: 7, height: 7)
                        Text("\(store.tablet.model) · \(device.connected || store.daemonRunning ? L("připojeno") : L("nepřipojeno"))")
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    TabletBatteryLabel().font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 30)

            VStack(spacing: 2) {
                ForEach(Section.allCases.filter { store.tablet.enhanced || ($0 != .touch && $0 != .lights) }) { s in
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
                Text("OpenTabletDriver \(store.bundledDriverVersion)")
                if store.daemonRunning {
                    Text("Běží · \(store.daemonSource.lowercased())").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    if store.daemonSource == L("Samostatný OpenTabletDriver") {
                        Button("Použít vestavěný") { store.startDaemon() }.controlSize(.small)
                    }
                } else if store.daemonStarting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Spouští se…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Button("Spustit ovladač") { store.startDaemon() }.controlSize(.small)
                }
                if let r = updater.available {
                    Button { section = .general } label: {
                        Label(String(format: L("Tablet %@ je venku"), r.version), systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0x9CC3FF))
                }
                if let u = store.driverUpdate {
                    Button { NSWorkspace.shared.open(u.url) } label: {
                        Label("Nová verze \(u.version)", systemImage: "arrow.down.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0x9CC3FF))
                    .help("Aktualizujte OTD_VERSION a OTD_SHA256 v make-app.sh a aplikaci sestavte znovu, nebo stáhněte novější vydání aplikace Tablet.")
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
            Menu(store.activePreset ?? L("Bez předvolby")) {
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
