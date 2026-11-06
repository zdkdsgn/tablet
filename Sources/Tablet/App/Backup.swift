import AppKit
import UniformTypeIdentifiers

/// Exports / imports everything: the app's settings, OpenTabletDriver's settings.json and the presets.
/// The file is a property list (`.tabletsettings`).
@MainActor
enum Backup {
    static let type = UTType(exportedAs: "local.zdeko.tablet.settings", conformingTo: .propertyList)

    private static var defaultsDomain: String { Bundle.main.bundleIdentifier ?? "local.zdeko.tablet" }

    static func export(store: OTDStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tablet \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-")).tabletsettings"
        panel.allowedContentTypes = [type]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var files: [String: Data] = [:]
        let fm = FileManager.default
        if let data = try? Data(contentsOf: store.settingsURL) { files["settings.json"] = data }
        for name in (try? fm.contentsOfDirectory(atPath: store.presetsDir.path)) ?? [] {
            if let data = try? Data(contentsOf: store.presetsDir.appendingPathComponent(name)) { files["Presets/" + name] = data }
        }
        var prefs = UserDefaults.standard.persistentDomain(forName: defaultsDomain) ?? [:]
        prefs = prefs.filter { !$0.key.hasPrefix("NS") && !$0.key.hasPrefix("com.apple") }
        let plist: [String: Any] = ["format": 1, "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "",
                                    "date": Date(), "defaults": prefs, "files": files]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try data.write(to: url)
        } catch {
            alert(L("Zálohu se nepodařilo uložit."), error.localizedDescription)
        }
    }

    static func importFile(store: OTDStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type, .propertyList]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["format"] as? Int == 1 else {
            alert(L("Tohle není záloha aplikace Tablet."), nil); return
        }
        let a = NSAlert()
        a.messageText = L("Obnovit nastavení ze zálohy?")
        a.informativeText = L("Současné nastavení a předvolby se nahradí. Aplikace se pak sama znovu spustí.")
        a.addButton(withTitle: L("Obnovit ze zálohy"))
        a.addButton(withTitle: L("Zrušit"))
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let fm = FileManager.default
        for (path, content) in plist["files"] as? [String: Data] ?? [:] {
            guard !path.contains("..") else { continue }
            let dest = path == "settings.json" ? store.settingsURL : store.dir.appendingPathComponent(path)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: dest)
        }
        if let prefs = plist["defaults"] as? [String: Any] {
            UserDefaults.standard.setPersistentDomain(prefs, forName: defaultsDomain)
            UserDefaults.standard.synchronize()
        }
        relaunch()
    }

    /// Starts a fresh copy of the app after this one quits.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    private static func alert(_ title: String, _ text: String?) {
        let a = NSAlert()
        a.messageText = title
        if let text { a.informativeText = text }
        a.runModal()
    }
}
