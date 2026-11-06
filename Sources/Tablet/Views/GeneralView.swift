import SwiftUI
import AppKit

/// Updates, backup, links for the Shortcuts app / Siri and installation notes.
struct GeneralView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var updater: Updater
    @State private var copied: String?
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue
    @AppStorage("island.enabled") private var island = true

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    Card(title: L("Aktualizace")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tablet \(updater.currentVersion)").fontWeight(.medium)
                                Text("OpenTabletDriver \(store.bundledDriverVersion)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button("Zkontrolovat") { updater.check(manual: true) }.disabled(updater.busy)
                        }
                        if let r = updater.available {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(format: L("Je k dispozici verze %@"), r.version)).fontWeight(.semibold)
                                HStack {
                                    Button(updater.busy ? L("Instaluji…") : L("Nainstalovat a restartovat")) { updater.install() }
                                        .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(updater.busy)
                                    Button("Co je nového") { NSWorkspace.shared.open(r.page) }
                                }
                                Text(r.sha256 == nil ? L("Vydání neuvádí kontrolní součet.") : L("Stažený soubor se ověří kontrolním součtem z popisu vydání."))
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if let s = updater.state { Text(s).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                        Toggle("Hledat aktualizace jednou denně", isOn: $updater.autoCheck).toggleStyle(.checkbox)
                    }
                    Card(title: L("Záloha nastavení")) {
                        Text("Uloží všechno do jednoho souboru: tlačítka, pero, kolečko, světla, plochu i předvolby. Hodí se pro druhý Mac nebo po přeinstalaci.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        HStack {
                            Button { Backup.export(store: store) } label: { Label("Uložit zálohu…", systemImage: "square.and.arrow.down") }
                            Button { Backup.importFile(store: store) } label: { Label("Obnovit ze zálohy…", systemImage: "square.and.arrow.up") }
                        }
                    }
                    Card(title: L("Instalace přes Homebrew")) {
                        Text("Na dalším Macu stačí v Terminálu:").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        copyRow("brew install --cask zdkdsgn/tap/tablet")
                    }
                    SettingRow(title: L("Animace ve výřezu"), caption: L("Dokud je pero nad tabletem, výřez MacBooku živě ukazuje jeho náklon – z boku i shora. Najedete-li perem do výřezu, ukáže statistiky. Ozve se i při milnících a úspěších.")) {
                        HStack(spacing: 8) {
                            Button("Ukázat") { model.island.demoTilt() }
                            .disabled(!island)
                            Toggle("", isOn: $island).labelsHidden().toggleStyle(.switch)
                        }
                    }
                    SettingRow(title: L("Vzhled"), caption: L("Světlý, tmavý, nebo podle nastavení Macu")) {
                        Picker("", selection: $appearance) {
                            ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                        .onChange(of: appearance) { _, v in AppearanceChoice.apply(v) }
                    }
                    SettingRow(title: L("Spouštět po přihlášení"), caption: L("Tablet i ovladač poběží hned po startu Macu")) {
                        Toggle("", isOn: Binding { model.launchAtLogin } set: { model.setLaunchAtLogin($0) })
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                Card(title: L("Zkratky a Siri")) {
                    Text("V aplikaci Zkratky přidejte akci Otevřít URL s odkazem níže. Zkratku pak spustíte Siri („Hej Siri, štětec“), klávesovou zkratkou nebo automatizací. Z Terminálu: open -g odkaz.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    VStack(spacing: 6) {
                        ForEach(Commands.examples, id: \.0) { url, what in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(what)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                copyRow(url)
                            }
                        }
                    }
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) } label: {
                        Label("Otevřít Zkratky", systemImage: "square.2.layers.3d")
                    }
                }
                .frame(width: 440)
            }
            .padding(24)
        }
    }

    private func copyRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = text
            } label: { Image(systemName: copied == text ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                .help(L("Kopírovat"))
                .accessibilityLabel(L("Kopírovat"))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 7))
    }
}
