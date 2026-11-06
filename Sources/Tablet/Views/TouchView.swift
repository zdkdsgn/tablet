import SwiftUI

struct TouchView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var device: DeviceMonitor
    @EnvironmentObject var touch: TouchSettings

    var body: some View {
        VStack(spacing: 16) {
            if !device.inputAccess {
                Banner(text: L("Aplikace potřebuje oprávnění Sledování vstupu, aby četla prsty z tabletu."), button: L("Otevřít nastavení")) {
                    AppModel.openPrivacy("Privacy_ListenEvent")
                }
            }
            if !model.accessibility {
                Banner(text: L("Pro pohyb kurzoru a gesta zapněte aplikaci Tablet v Zpřístupnění."), button: L("Otevřít nastavení")) {
                    TouchEngine.requestAccessibility()
                    AppModel.openPrivacy("Privacy_Accessibility")
                }
            }
            HStack(alignment: .top, spacing: 20) {
                Card(title: L("Živý náhled"), trailing: AnyView(Toggle("Dotyk zapnutý", isOn: $touch.enabled).toggleStyle(.switch))) {
                    LiveTouches(touches: device.touches, isPalm: touch.isPalm)
                        .environment(\.colorScheme, .dark)
                        .frame(maxWidth: .infinity, minHeight: 300)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Rychlost kurzoru"); Spacer(); Text(speedName).foregroundStyle(Theme.secondary) }
                        Slider(value: $touch.speed, in: 1...10, step: 1)
                    }
                }
                ScrollView {
                    VStack(spacing: 6) {
                        gesture("Pohyb kurzoru", "1 prst", $touch.move)
                        gesture("Klepnutí", "1 prst · kliknutí", $touch.tap)
                        gesture("Pravé kliknutí", "2 prsty · klepnutí", $touch.rightTap)
                        gesture("Posouvání", "2 prsty · tah", $touch.scroll)
                        gesture("Přirozený směr posouvání", "Obsah jde s prsty, jako na trackpadu", $touch.naturalScroll)
                        gesture("Přiblížení", "2 prsty · roztažení (⌘+ / ⌘−)", $touch.pinch)
                        gesture("Přepnout plochu", "3 prsty · doleva / doprava", $touch.swipeSpaces)
                        gesture("Mission Control", "3 prsty · nahoru (dolů = okna aplikace)", $touch.missionControl)
                        gesture("Ignorovat dotyk při kreslení", "Dlaň na tabletu nehýbe kurzorem", $touch.palmRejection)
                            .padding(.top, 10)
                        gesture("Poznat dlaň podle velikosti", "Velký dotyk (dlaň, hrana ruky) se ignoruje, i když nekreslíte", $touch.palmBySize)
                        if touch.palmBySize {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Dlaň od velikosti")
                                    Spacer()
                                    Text("\(Int(touch.palmSize))" + (largestTouch.map { "  ·  " + String(format: L("teď %d"), Int($0)) } ?? ""))
                                        .monospacedDigit().foregroundStyle(Theme.secondary)
                                }
                                Slider(value: $touch.palmSize, in: 3...40, step: 1)
                                Text("Položte prst a pak dlaň – vlevo uvidíte jejich velikost. Červeně = bere se jako dlaň.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            .padding(12)
                            .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                }
                .frame(width: 400)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            }
        }
        .padding(24)
    }

    private var statusText: String {
        if !device.connected { return L("Tablet není připojený.") }
        if !device.inputAccess { return L("Čekám na oprávnění Sledování vstupu.") }
        if device.touchSwitchOn == false { return L("Dotyk je vypnutý vypínačem na boku tabletu.") }
        if device.touchReportsSeen == 0 { return L("Položte prst na tablet – body se ukážou tady.") }
        return device.touches.isEmpty ? L("Dotyk funguje.") : "Prstů na tabletu: \(device.touches.count)"
    }

    private var largestTouch: Double? { device.touches.map(\.size).max() }

    private var speedName: String {
        switch touch.speed { case ..<4: return L("Pomalu"); case ..<8: return L("Středně rychle"); default: return L("Rychle") }
    }

    private func gesture(_ title: String, _ caption: String, _ on: Binding<Bool>) -> some View {
        SettingRow(title: title, caption: caption) { Toggle("", isOn: on).labelsHidden().toggleStyle(.switch) }
    }
}

struct LiveTouches: View {
    var touches: [TouchPoint]
    var isPalm: (TouchPoint) -> Bool = { _ in false }
    var body: some View {
        GeometryReader { g in
            let ratio = 223.52 / 139.7
            let w = min(g.size.width, g.size.height * ratio), h = w / ratio
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0D0D0E))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x3A3A3E)))
                ForEach(touches, id: \.id) { t in
                    // contact size as the tablet measures it (falls back to a fingertip when not reported)
                    let c = isPalm(t) ? Color(hex: 0xFF453A) : Theme.accent
                    let ew = t.w > 0 ? max(22, t.w * w / 90) : 34, eh = t.h > 0 ? max(22, t.h * w / 90) : 34
                    Ellipse().fill(c.opacity(0.33))
                        .overlay(Ellipse().stroke(c, lineWidth: 2))
                        .frame(width: ew, height: eh)
                        .overlay(Text("\(Int(t.size))").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).opacity(t.size > 0 ? 1 : 0))
                        .position(x: t.x / DeviceMonitor.touchMax * w, y: t.y / DeviceMonitor.touchMax * h)
                }
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("Náhled prstů na tabletu")
    }
}
