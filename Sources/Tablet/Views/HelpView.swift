import SwiftUI

/// Help: what the tablet can do beyond the obvious, keyboard shortcuts, tablet:// links and where the logs are.
struct HelpView: View {
    var done: () -> Void
    @State private var copied: String?

    private let tablet: [(String, String, String)] = [
        ("pencil.tip", "Najeďte perem do výřezu MacBooku", "Ukáže dnešní kilometry, tahy a úspěchy."),
        ("hand.point.up.left", "Položte prst na ExpressKeys", "Vedle obrazovky se ukáže, co které tlačítko dělá (Express View)."),
        ("hand.draw", "Přejeďte prstem po skupině tlačítek", "Funguje jako posuvník – třeba velikost štětce."),
        ("circle.circle", "Podržte střed Touch Ringu", "Přehraje animaci světýlek."),
        ("arrow.up.arrow.down", "Otočte pero gumou dolů", "Aplikace dostane klávesu gumy, po otočení zpět klávesu štětce."),
        ("scope", "ExpressKey s funkcí Přesný režim", "Dokud ji držíte, kurzor se pohybuje jemněji."),
        ("macwindow", "ExpressKey s funkcí Mapovat na okno", "Tablet kreslí jen do okna vpředu, dalším stiskem zpět na celou obrazovku."),
    ]

    private let keys: [(String, String)] = [
        ("⌘Z", "Vrátí poslední větší změnu nastavení"),
        ("⇧⌘Z", "Znovu (v textových polích)"),
        ("⌘?", "Tato nápověda"),
        ("⌘W", "Zavře okno – Tablet dál běží v liště nahoře"),
        ("⌘Q", "Ukončí Tablet i ovladač"),
    ]

    private let links: [(String, String)] = Commands.examples + [
        ("tablet://notch/stats", "Statistiky ve výřezu"),
        ("tablet://setup", "Průvodce nastavením"),
        ("tablet://help", "Tato nápověda"),
        ("tablet://open", "Otevře okno aplikace"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Nápověda", systemImage: "questionmark.circle").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Hotovo", action: done).keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(L("Na tabletu")) {
                        ForEach(tablet, id: \.1) { symbol, title, text in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L(title)).fontWeight(.medium)
                                    Text(L(text)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }
                    section(L("Klávesové zkratky")) {
                        ForEach(keys, id: \.0) { k, what in
                            HStack(spacing: 12) {
                                Text(k).font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Theme.well, in: RoundedRectangle(cornerRadius: 5))
                                    .frame(width: 56, alignment: .leading)
                                Text(L(what)).font(.system(size: 12))
                            }
                        }
                    }
                    section(L("Odkazy pro Zkratky, Siri a Terminál")) {
                        Text("Akce Otevřít URL v aplikaci Zkratky, nebo v Terminálu: open -g odkaz")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        ForEach(links, id: \.0) { url, what in
                            HStack(spacing: 10) {
                                Text(url).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                Spacer(minLength: 8)
                                Text(L(what)).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                    copied = url
                                } label: { Image(systemName: copied == url ? "checkmark" : "doc.on.doc") }
                                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).help(L("Kopírovat"))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.well, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    section(L("Když něco nefunguje")) {
                        Text("Obecné → Pomoc a řešení potíží → Uložit diagnostiku… sbalí logy a nastavení do jednoho souboru, který můžete přiložit k hlášení chyby. Logy jsou v ~/Library/Logs (Tablet*.log).")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button { NSWorkspace.shared.open(AppLog.dir) } label: { Label("Otevřít složku s logy", systemImage: "folder") }
                            Button { NSWorkspace.shared.open(URL(string: "https://github.com/zdkdsgn/tablet/issues")!) } label: {
                                Label("Nahlásit chybu", systemImage: "ladybug")
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 600)
        .background(Theme.window)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
            content()
        }
    }
}
