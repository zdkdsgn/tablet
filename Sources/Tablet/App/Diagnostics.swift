import AppKit
import UniformTypeIdentifiers

/// "Save diagnostics": one .zip with the logs, the driver settings and a short report of the state,
/// for a bug report. Nothing is sent anywhere – the user picks where the file goes.
@MainActor
enum Diagnostics {
    static func save(model: AppModel) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tablet-diagnostika-\(StrokeLog.key(Date())).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let report = summary(model)
        let settings = model.store.settingsURL
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = build(report: report, settings: settings, into: target)
            DispatchQueue.main.async {
                if ok { NSWorkspace.shared.activateFileViewerSelecting([target]) }
                else { model.hud.showMessage(symbol: "exclamationmark.triangle", title: L("Diagnostiku nejde uložit"), subtitle: nil) }
            }
        }
    }

    private nonisolated static func build(report: String, settings: URL, into target: URL) -> Bool {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("Tablet-diagnostika-\(UUID().uuidString)")
        let folder = stage.appendingPathComponent("Tablet-diagnostika")
        defer { try? fm.removeItem(at: stage) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try report.write(to: folder.appendingPathComponent("stav.txt"), atomically: true, encoding: .utf8)
            for f in AppLog.File.allCases {
                for url in [f.url, f.previous] where fm.fileExists(atPath: url.path) {
                    try? fm.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
                }
            }
            try? fm.copyItem(at: settings, to: folder.appendingPathComponent("OpenTabletDriver-settings.json"))
            run("/usr/bin/defaults", ["export", Bundle.main.bundleIdentifier ?? "local.zdeko.tablet",
                                      folder.appendingPathComponent("nastaveni-aplikace.plist").path])
            // recent crash / hang reports of the app and the driver
            let reports = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
            let cutoff = Date().addingTimeInterval(-14 * 86_400)
            for name in (try? fm.contentsOfDirectory(atPath: reports.path)) ?? []
            where name.hasPrefix("Tablet") || name.hasPrefix("OpenTabletDriver") {
                let url = reports.appendingPathComponent(name)
                if let d = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, d > cutoff {
                    try? fm.copyItem(at: url, to: folder.appendingPathComponent(name))
                }
            }
            try? fm.removeItem(at: target)
            return run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noacl", "--keepParent", folder.path, target.path])
        } catch {
            return false
        }
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// What the app knows right now, in plain text.
    private static func summary(_ m: AppModel) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        var model = [CChar](repeating: 0, count: 128)
        var size = model.count
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let screens = NSScreen.screens.map { "\($0.localizedName) \(Int($0.frame.width))×\(Int($0.frame.height))" }
        let d = m.device, s = m.store
        return """
        Tablet \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")), OpenTabletDriver \(s.bundledDriverVersion)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(String(cString: model))
        Datum: \(ISO8601DateFormatter().string(from: Date()))
        Spuštěno: \(Int(ProcessInfo.processInfo.systemUptime / 60)) min od startu Macu

        Tablet: \(s.tablet.displayName) (\(s.tablet.model)), připojený: \(d.connected)
        Baterie: \(d.battery.map { "\($0) %" } ?? "–"), nabíjí: \(d.charging), vypínač dotyku: \(d.touchSwitchOn.map { $0 ? "zap" : "vyp" } ?? "?")
        Ovladač: běží \(s.daemonRunning), \(s.daemonSource), spouští se: \(s.daemonStarting)
        Chyba: \(s.lastError ?? "–")
        Oprávnění: Zpřístupnění \(m.accessibility), Sledování vstupu \(d.inputAccess)
        Filtr pera: \(m.edgeFix.enabled)
        Předvolba: \(s.activePreset ?? "–"), automaticky: \(m.autoPresets)
        Monitory: \(screens.joined(separator: ", "))
        Plocha monitoru: \(s.displayArea), plocha tabletu: \(s.tabletArea)
        """
    }
}
