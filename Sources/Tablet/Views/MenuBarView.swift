import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var device: DeviceMonitor
    @EnvironmentObject var touch: TouchSettings
    @EnvironmentObject var zoom: ZoomSettings
    @EnvironmentObject var lights: LightSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if zoom.smooth && store.tablet.enhanced {
                section("Touch Ring") {
                    HStack(spacing: 6) {
                        ForEach(RingMode.allCases) { m in
                            Button { zoom.mode = m; model.updateRingLED() } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: m.symbol).font(.system(size: 15))
                                    Text(m.title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(zoom.mode == m ? Theme.accent : Theme.well, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(zoom.mode == m ? .white : Color(hex: 0xD6D6DA))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(m.caption)
                        }
                    }
                }
            }

            if !store.presets.isEmpty {
                section("Předvolba") {
                    VStack(spacing: 2) {
                        ForEach(store.presets, id: \.self) { p in
                            Button { store.applyPreset(p) } label: {
                                HStack {
                                    Text(p)
                                    Spacer()
                                    if store.activePreset == p { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                                }
                                .padding(.horizontal, 10).frame(height: 30)
                                .background(store.activePreset == p ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(store.activePreset == p ? .white : Color(hex: 0xE4E4E8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            section("Rychlé volby") {
                VStack(spacing: 0) {
                    row("lightbulb", "Světla", Binding { lights.enabled || lights.cornersEnabled } set: { on in
                        lights.enabled = on; lights.cornersEnabled = on; model.updateRingLED()
                    })
                    divider
                    row("hand.point.up.left", "Dotyk prsty", $touch.enabled)
                    divider
                    row("arrow.triangle.2.circlepath", "Přepínat podle aplikace", $model.autoPresets)
                    divider
                    row("power", "Spouštět po přihlášení", Binding { model.launchAtLogin } set: { model.setLaunchAtLogin($0) })
                }
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                Button {
                    model.openMain = { [openWindow] in openWindow(id: "main") }
                    model.showMainWindow()
                } label: {
                    Label("Otevřít nastavení", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)

                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .frame(width: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Ukončit Tablet")
                .accessibilityLabel("Ukončit Tablet")
            }
        }
        .padding(14)
        .frame(width: 320)
        .font(.system(size: 13))
    }

    // MARK: - parts

    private var header: some View {
        HStack(spacing: 12) {
            TabletGlyph()
            VStack(alignment: .leading, spacing: 3) {
                Text(store.tablet.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(ok ? Theme.ok : Theme.warn).frame(width: 7, height: 7)
                    Text(status).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            if zoom.smooth {
                Text(zoom.mode.title)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color(hex: 0x9CC3FF))
            }
        }
        .padding(12)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 12))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.7)
                .foregroundStyle(Theme.secondary).padding(.leading, 4)
            content()
        }
    }

    private func row(_ icon: String, _ title: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(Theme.secondary)
            Text(title)
            Spacer(minLength: 8)
            Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12).frame(height: 38)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 40)
    }

    private var ok: Bool { device.connected && store.daemonRunning }

    private var status: String {
        if !device.connected { return L("Nepřipojeno") }
        if !store.daemonRunning { return L("Ovladač neběží") }
        return L("Připojeno přes USB")
    }
}
