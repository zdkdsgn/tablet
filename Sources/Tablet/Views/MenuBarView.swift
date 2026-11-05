import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var device: DeviceMonitor
    @EnvironmentObject var touch: TouchSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TabletGlyph()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Intuos Pro M").fontWeight(.semibold)
                    HStack(spacing: 6) {
                        Circle().fill(device.connected && store.daemonRunning ? Theme.ok : Theme.warn).frame(width: 7, height: 7)
                        Text(status).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))

            if !store.presets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PŘEDVOLBA").font(.system(size: 11)).tracking(0.6).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                    ForEach(store.presets, id: \.self) { p in
                        Button { store.applyPreset(p) } label: {
                            HStack {
                                Text(p)
                                Spacer()
                                if store.activePreset == p { Image(systemName: "checkmark") }
                            }
                            .padding(.horizontal, 10).frame(height: 32)
                            .background(store.activePreset == p ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(spacing: 2) {
                Toggle("Dotyk prsty", isOn: $touch.enabled).toggleStyle(.switch)
                Toggle("Přepínat podle aplikace", isOn: $model.autoPresets).toggleStyle(.switch)
                Toggle("Spouštět po přihlášení", isOn: Binding { model.launchAtLogin } set: { model.setLaunchAtLogin($0) })
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 6)

            Divider()
            HStack {
                Button("Otevřít nastavení…") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Ukončit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
        .font(.system(size: 13))
    }

    private var status: String {
        if !device.connected { return "Nepřipojeno" }
        if !store.daemonRunning { return "Ovladač neběží" }
        return "Připojeno přes USB"
    }
}
