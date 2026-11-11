import AppKit

/// `tablet://` links – for the Shortcuts app ("Open URL"), Siri (run a shortcut by name),
/// automations or the terminal (`open -g tablet://lights/toggle`).
///
///   tablet://preset/Photoshop        switch preset
///   tablet://ring/zoom               ring mode: zoom, brush, history, scroll, rotate, volume, brightness, next
///   tablet://lights/on|off|toggle    ring + corner lights
///   tablet://flash/heartbeat         play a light animation (any name, or nothing = the alert animation)
///   tablet://notify?title=Render%20hotov   lights + on-screen notice
///   tablet://break/reset             start the break timer again
///   tablet://display/next            map the tablet to the next display
///   tablet://window                  map the tablet to the front window (again = whole screen)
///   tablet://precision/on|off|toggle precision mode
///   tablet://open                    open the settings window
@MainActor
enum Commands {
    static let examples: [(String, String)] = [
        ("tablet://preset/Photoshop", "Přepne předvolbu"),
        ("tablet://ring/brush", "Režim kolečka (zoom, brush, history, scroll, rotate, volume, brightness, next)"),
        ("tablet://lights/toggle", "Světla zapnout / vypnout (on, off, toggle)"),
        ("tablet://flash/heartbeat", "Přehraje animaci světel"),
        ("tablet://notify?title=Render%20hotov", "Bliknutí světel a oznámení na obrazovce"),
        ("tablet://window", "Plocha na okno vpředu / zpět celá obrazovka"),
        ("tablet://display/next", "Další monitor"),
        ("tablet://precision/toggle", "Přesný režim"),
        ("tablet://break/reset", "Znovu spustí odpočet přestávky"),
    ]

    /// Handles a link; returns false when it is not understood.
    @discardableResult
    static func handle(_ url: URL, model m: AppModel) -> Bool {
        guard url.scheme?.lowercased() == "tablet" else { return false }
        let head = (url.host ?? "").lowercased()
        let arg = url.pathComponents.dropFirst().first?.removingPercentEncoding ?? ""
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { query.first { $0.name == k }?.value }
        let onOff: (Bool) -> Bool = { cur in
            switch arg.lowercased() { case "on", "1", "true": return true; case "off", "0", "false": return false; default: return !cur }
        }

        switch head {
        case "preset":
            guard let p = m.store.presets.first(where: { $0.caseInsensitiveCompare(arg) == .orderedSame }) else { return false }
            m.store.applyPreset(p)
            m.hud.showMessage(symbol: "list.bullet.rectangle", title: p, subtitle: L("Předvolba"))
        case "ring":
            if arg.lowercased() == "next" { m.ringZoom.nextMode() ; return true }
            let names = ["zoom": RingMode.zoom, "brush": .brush, "history": .history, "scroll": .scroll,
                         "rotate": .rotate, "volume": .volume, "brightness": .brightness]
            guard let mode = names[arg.lowercased()] ?? RingMode(rawValue: Int(arg) ?? -1) else { return false }
            m.setRingMode(mode, notify: true)
        case "lights":
            let on = onOff(m.lightSettings.enabled || m.lightSettings.cornersEnabled)
            m.lightSettings.enabled = on; m.lightSettings.cornersEnabled = on
            m.updateRingLED()
        case "flash":
            m.lights.play(LEDAnimation(rawValue: arg) ?? LEDAnimation.allCases.first { $0.title.caseInsensitiveCompare(arg) == .orderedSame } ?? m.reminderSettings.animation)
        case "notify":
            let anim = LEDAnimation(rawValue: q("animation") ?? "") ?? m.reminderSettings.animation
            m.alert(anim, symbol: q("symbol") ?? "bell", title: q("title") ?? (arg.isEmpty ? L("Tablet") : arg), subtitle: q("text"))
        case "notch":   // tablet://notch?title=…&text=…  – message in the notch island (also a demo without a title)
            if arg == "stats" { m.island.showStats(for: 5) }
            else if arg == "tilt" { m.island.demoTilt() }
            else if let t = q("title") { m.island.message(t, subtitle: q("text")) }
            else { m.island.message(PenOdometer.milestoneText(PenOdometer.milestones.last { $0 * 1000 <= m.odometer.drawn } ?? 1), subtitle: PenOdometer.pencilUsed(m.odometer.drawn)) }
        case "help":    // tablet://help
            m.showMainWindow(); m.showHelp = true
        case "wake":    // tablet://wake – what happens after the Mac wakes up (for testing)
            m.afterWake()
        case "setup":   // tablet://setup – the first-run guide
            m.showMainWindow(); m.showOnboarding = true
        case "break":
            m.reminders.resetBreak()
        case "display":
            m.nextDisplay()
        case "window":
            m.toggleWindowMapping()
        case "precision":
            m.penFilters.precisionActive = onOff(m.penFilters.precisionActive)
            m.hud.showMessage(symbol: "scope", title: L("Přesný režim"), subtitle: m.penFilters.precisionActive ? L("Zapnuto") : L("Vypnuto"))
        case "open", "":
            m.showMainWindow()
            return true
        default:
            return false
        }
        return true
    }
}
