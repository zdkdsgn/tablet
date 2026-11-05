import SwiftUI

struct PresetsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: OTDStore
    @State private var name = ""

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Card(title: L("Předvolby")) {
                if store.presets.isEmpty {
                    Text("Zatím žádné. Nastavte tablet a uložte ho jako předvolbu.").foregroundStyle(Theme.secondary)
                }
                ForEach(store.presets, id: \.self) { p in
                    HStack {
                        Image(systemName: store.activePreset == p ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.activePreset == p ? Theme.accent : Theme.secondary)
                        Text(p)
                        Spacer()
                        Button("Použít") { store.applyPreset(p) }.disabled(store.activePreset == p)
                        Button("Smazat", role: .destructive) { store.deletePreset(p) }
                    }
                    .padding(10)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    TextField("Název nové předvolby, např. Photoshop", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveNew)
                    Button("Uložit současné", action: saveNew).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            VStack(spacing: 12) {
                SettingRow(title: L("Spouštět po přihlášení"), caption: L("Tablet i ovladač poběží hned po startu Macu")) {
                    Toggle("", isOn: Binding { model.launchAtLogin } set: { model.setLaunchAtLogin($0) })
                        .labelsHidden().toggleStyle(.switch)
                }
                if let e = model.loginItemError {
                    Text(e).font(.system(size: 12)).foregroundStyle(Theme.warn).frame(maxWidth: .infinity, alignment: .leading)
                }
                SettingRow(title: L("Přepínat podle aplikace"), caption: L("Předvolba pojmenovaná jako aplikace se zapne sama, když ji otevřete. Jinak se použije „Výchozí“.")) {
                    Toggle("", isOn: $model.autoPresets).labelsHidden().toggleStyle(.switch)
                }
                Text("Úpravy v Tablet a Pero se ukládají do právě zapnuté předvolby.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 380)
        }
        .padding(24)
    }

    private func saveNew() {
        store.savePreset(named: name)
        name = ""
    }
}
