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
                    LiveTouches(touches: device.touches)
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
        if device.touchReportsSeen == 0 { return L("Položte prst na tablet – body se ukážou tady.") }
        return device.touches.isEmpty ? L("Dotyk funguje.") : "Prstů na tabletu: \(device.touches.count)"
    }

    private var speedName: String {
        switch touch.speed { case ..<4: return L("Pomalu"); case ..<8: return L("Středně rychle"); default: return L("Rychle") }
    }

    private func gesture(_ title: String, _ caption: String, _ on: Binding<Bool>) -> some View {
        SettingRow(title: title, caption: caption) { Toggle("", isOn: on).labelsHidden().toggleStyle(.switch) }
    }
}

struct LiveTouches: View {
    var touches: [TouchPoint]
    var body: some View {
        GeometryReader { g in
            let ratio = 223.52 / 139.7
            let w = min(g.size.width, g.size.height * ratio), h = w / ratio
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0D0D0E))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x3A3A3E)))
                ForEach(touches, id: \.id) { t in
                    Circle().fill(Theme.accent.opacity(0.33))
                        .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                        .frame(width: 34, height: 34)
                        .position(x: t.x / DeviceMonitor.touchMax * w, y: t.y / DeviceMonitor.touchMax * h)
                }
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("Náhled prstů na tabletu")
    }
}
