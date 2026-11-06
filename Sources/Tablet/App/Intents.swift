import AppIntents
import AppKit

// Actions for the Shortcuts app and Siri. They need the App Intents metadata that Xcode's build
// generates (make-app.sh builds with xcodebuild when Xcode is installed); tablet:// links work always.

enum RingModeOption: String, AppEnum {
    case zoom, brush, history, scroll, rotate, volume, brightness

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Režim kolečka"
    static var caseDisplayRepresentations: [RingModeOption: DisplayRepresentation] = [
        .zoom: "Zoom", .brush: "Velikost štětce", .history: "Historie", .scroll: "Posouvání",
        .rotate: "Otáčení plátna", .volume: "Hlasitost", .brightness: "Jas obrazovky",
    ]
    var mode: RingMode {
        switch self {
        case .zoom: return .zoom
        case .brush: return .brush
        case .history: return .history
        case .scroll: return .scroll
        case .rotate: return .rotate
        case .volume: return .volume
        case .brightness: return .brightness
        }
    }
}

enum LightAnimationOption: String, AppEnum {
    case spin, pingPong, breathe, wave, sparkle, countdown, heartbeat, police

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Animace světel"
    static var caseDisplayRepresentations: [LightAnimationOption: DisplayRepresentation] = [
        .spin: "Kolotoč", .pingPong: "Ping-pong", .breathe: "Dýchání", .wave: "Vlna",
        .sparkle: "Jiskření", .countdown: "Odpočet", .heartbeat: "Tep", .police: "Maják",
    ]
}

struct SetRingModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Nastavit režim kolečka"
    static var description = IntentDescription("Přepne Touch Ring tabletu do zvoleného režimu.")
    @Parameter(title: "Režim") var mode: RingModeOption

    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared?.setRingMode(mode.mode, notify: true)
        return .result()
    }
}

struct NextRingModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Další režim kolečka"
    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared?.ringZoom.nextMode()
        return .result()
    }
}

struct SwitchPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Přepnout předvolbu tabletu"
    @Parameter(title: "Předvolba") var preset: String

    @MainActor func perform() async throws -> some IntentResult {
        guard let m = AppModel.shared, let url = URL(string: "tablet://preset/" + (preset.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? preset)) else { return .result() }
        Commands.handle(url, model: m)
        return .result()
    }
}

struct ToggleLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Zapnout nebo vypnout světla tabletu"
    @Parameter(title: "Zapnout", default: true) var on: Bool

    @MainActor func perform() async throws -> some IntentResult {
        guard let m = AppModel.shared else { return .result() }
        m.lightSettings.enabled = on; m.lightSettings.cornersEnabled = on
        m.updateRingLED()
        return .result()
    }
}

struct FlashLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Bliknout světly tabletu"
    static var description = IntentDescription("Přehraje animaci na světlech tabletu a volitelně ukáže oznámení – třeba když doběhne render.")
    @Parameter(title: "Animace", default: .heartbeat) var animation: LightAnimationOption
    @Parameter(title: "Oznámení") var message: String?

    @MainActor func perform() async throws -> some IntentResult {
        guard let m = AppModel.shared else { return .result() }
        let a = LEDAnimation(rawValue: animation.rawValue) ?? .heartbeat
        if let message, !message.isEmpty { m.alert(a, symbol: "bell", title: message, subtitle: nil) } else { m.lights.play(a) }
        return .result()
    }
}

struct PrecisionModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Přepnout přesný režim pera"
    @MainActor func perform() async throws -> some IntentResult {
        guard let m = AppModel.shared, let url = URL(string: "tablet://precision/toggle") else { return .result() }
        Commands.handle(url, model: m)
        return .result()
    }
}

struct WindowMappingIntent: AppIntent {
    static var title: LocalizedStringResource = "Plocha tabletu na okno"
    static var description = IntentDescription("Namapuje tablet na okno vpředu, nebo zpět na celou obrazovku.")
    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared?.toggleWindowMappingFromMenu()
        return .result()
    }
}

struct TabletShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextRingModeIntent(), phrases: ["Další režim kolečka v \(.applicationName)", "Next ring mode in \(.applicationName)"],
                    shortTitle: "Další režim kolečka", systemImageName: "circle.circle")
        AppShortcut(intent: SetRingModeIntent(), phrases: ["Nastav kolečko v \(.applicationName)", "Set the ring mode in \(.applicationName)"],
                    shortTitle: "Režim kolečka", systemImageName: "dial.medium")
        AppShortcut(intent: PrecisionModeIntent(), phrases: ["Přesný režim v \(.applicationName)", "Precision mode in \(.applicationName)"],
                    shortTitle: "Přesný režim", systemImageName: "scope")
        AppShortcut(intent: WindowMappingIntent(), phrases: ["Plocha na okno v \(.applicationName)", "Map \(.applicationName) to the window"],
                    shortTitle: "Plocha na okno", systemImageName: "macwindow")
        AppShortcut(intent: FlashLightsIntent(), phrases: ["Blikni světly v \(.applicationName)", "Flash the lights in \(.applicationName)"],
                    shortTitle: "Bliknout světly", systemImageName: "lightbulb")
    }
}
