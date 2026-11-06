import SwiftUI

/// First-run guide: tablet, permissions, monitor and the pen's tap in five short steps.
/// Shown once on a fresh install; can be opened again from Obecné.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: OTDStore
    @ObservedObject var device: DeviceMonitor
    @ObservedObject var pen: PenFilters
    @ObservedObject var hover: PenHover
    var done: () -> Void

    enum Step: Int, CaseIterable { case welcome, access, display, pen, finish }
    @State private var step = Step.welcome
    @State private var screens: [ScreenInfo] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Theme.accent : Color.primary.opacity(0.15))
                        .frame(width: s == step ? 22 : 8, height: 6)
                }
            }
            .animation(.snappy, value: step)
            .padding(.top, 22)

            Group {
                switch step {
                case .welcome: welcome
                case .access: access
                case .display: display
                case .pen: penStep
                case .finish: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36).padding(.top, 20)
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            HStack {
                if step != .welcome {
                    Button("Předchozí krok") { go(-1) }
                }
                Spacer()
                if step != .finish {
                    Button("Přeskočit průvodce") { done() }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    Button(step == .welcome ? L("Začít") : L("Další")) { go(1) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Hotovo") { done() }.keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 660, height: 540)
        .background(Theme.window)
        .onAppear { screens = ScreenInfo.all() }
    }

    private func go(_ d: Int) {
        withAnimation(.snappy(duration: 0.3)) { step = Step(rawValue: step.rawValue + d) ?? step }
    }

    private func header(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34, weight: .medium)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 22, weight: .bold))
            Text(text).multilineTextAlignment(.center).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    private func status(_ ok: Bool, _ title: String, _ caption: String, button: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 20)).foregroundStyle(ok ? Theme.ok : Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !ok, let button, let action { Button(button, action: action) }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 12) {
            header("pencil.and.scribble", L("Vítejte v aplikaci Tablet"),
                   L("Za minutku nastavíme, co je potřeba: oprávnění, monitor a citlivost pera. Všechno jde později změnit."))
            status(device.connected, device.connected ? store.tablet.displayName : L("Tablet zatím nevidím"),
                   device.connected ? L("Tablet je připojený.") : L("Připojte ho kabelem USB-C nebo zapněte bezdrátovou sadu."))
            status(store.daemonRunning, L("Ovladač"),
                   store.daemonRunning ? "OpenTabletDriver \(store.bundledDriverVersion) " + L("běží.") : L("Ovladač se spouští…"),
                   button: L("Spustit"), action: { store.startDaemon() })
        }
    }

    private var access: some View {
        VStack(spacing: 12) {
            header("lock.shield", L("Dvě oprávnění"),
                   L("macOS se zeptá jen jednou. Bez nich pero hýbe kurzorem, ale nefungují gesta, křivka tlaku ani klidné klepnutí."))
            status(model.accessibility, L("Zpřístupnění"), L("Pro křivku tlaku, vyhlazení, klidné klepnutí a gesta prstů."),
                   button: L("Povolit"), action: { TouchEngine.requestAccessibility(); AppModel.openPrivacy("Privacy_Accessibility") })
            status(device.inputAccess, L("Sledování vstupu"), L("Pro dotyk prstů, ExpressKeys a stav baterie."),
                   button: L("Povolit"), action: { AppModel.openPrivacy("Privacy_ListenEvent") })
            Text("Stav se tu obnoví sám, jakmile oprávnění zapnete.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }

    private var display: some View {
        VStack(spacing: 12) {
            header("display", L("Na který monitor kreslit?"),
                   L("Tablet se namapuje na vybraný monitor. Plochu tabletu a skutečnou velikost 1:1 doladíte v Plocha a monitor."))
            HStack(spacing: 14) {
                ForEach(Array(screens.enumerated()), id: \.offset) { _, s in
                    let selected = abs(store.displayArea.width - s.otd.width) < 1 && abs(store.displayArea.x - s.otd.x) < 1 && abs(store.displayArea.y - s.otd.y) < 1
                    Button {
                        store.displayArea = s.otd
                        if UserDefaults.standard.object(forKey: "area.lockAspect") as? Bool ?? true { store.fitTabletArea() }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                if let w = s.wallpaper { Image(nsImage: w).resizable().aspectRatio(contentMode: .fill) }
                                else { Theme.stage }
                            }
                            .frame(width: 150, height: 150 * s.otd.height / max(1, s.otd.width))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 3 : 1))
                            HStack(spacing: 5) {
                                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                Text(s.name).lineLimit(1)
                            }
                            Text("\(Int(s.otd.width)) × \(Int(s.otd.height))").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        .padding(10)
                        .background(selected ? Theme.accent.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var penStep: some View {
        VStack(spacing: 12) {
            header("pencil.tip", L("Vyzkoušejte ťuknutí"),
                   L("Párkrát ťukněte perem na tablet. Kliká-li vám lehký dotyk, posuňte práh doprava."))
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(hover.sample != nil ? Theme.ok : Theme.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    Text(hover.sample == nil ? L("Přibližte pero k tabletu") : hover.pressure > 0 ? L("Pero se dotýká") : L("Pero je nad tabletem"))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                TipThresholdSetting(threshold: $store.tipThreshold, hover: hover)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Klidné klepnutí")
                    Picker("", selection: $pen.calmTap) {
                        Text("Vypnuto").tag(0); Text("Slabě").tag(1); Text("Středně").tag(2); Text("Silně").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Po dotyku hrotu kurzor chvilku stojí, takže ťuknutí klikne a netáhne.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
    }

    private var finish: some View {
        VStack(spacing: 12) {
            header("checkmark.seal.fill", L("Hotovo, můžete kreslit"), L("Pár věcí, které se hodí vědět:"))
            VStack(alignment: .leading, spacing: 12) {
                tip("rectangle.inset.filled", L("Tlačítka a kolečko"), L("Na obrazovce Tablet klikněte na tlačítko a nastavte, co dělá."))
                tip("macbook", L("Výřez MacBooku"), L("Najeďte perem do výřezu a uvidíte, kolik jste dnes nakreslili."))
                tip("scribble.variable", L("Tahy"), L("Všechno, co dnes nakreslíte, si můžete přehrát a uložit jako obrázek."))
                tip("arrow.uturn.backward", L("Zpět"), L("Každou větší změnu nastavení vrátíte zkratkou ⌘Z."))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func tip(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
