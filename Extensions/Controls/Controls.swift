import WidgetKit
import SwiftUI
import AppIntents

// Control Center / menu bar controls for Tablet (macOS 26+). Each control opens a tablet:// link,
// which the running app handles (focus goes straight back to the app you were in).

@main
struct TabletControls: WidgetBundle {
    var body: some Widget {
        NextRingModeControl()
        PrecisionControl()
        WindowControl()
        LightsControl()
    }
}

private func link(_ s: String) -> OpenURLIntent { OpenURLIntent(URL(string: s)!) }

struct NextRingModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.zdeko.tablet.ring") {
            ControlWidgetButton(action: link("tablet://ring/next")) {
                Label("Režim kolečka", systemImage: "circle.circle")
            }
        }
        .displayName("Další režim kolečka")
        .description("Přepne Touch Ring na další režim.")
    }
}

struct PrecisionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.zdeko.tablet.precision") {
            ControlWidgetButton(action: link("tablet://precision/toggle")) {
                Label("Přesný režim", systemImage: "scope")
            }
        }
        .displayName("Přesný režim pera")
    }
}

struct WindowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.zdeko.tablet.window") {
            ControlWidgetButton(action: link("tablet://window")) {
                Label("Plocha na okno", systemImage: "macwindow")
            }
        }
        .displayName("Plocha tabletu na okno")
    }
}

struct LightsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "local.zdeko.tablet.lights") {
            ControlWidgetButton(action: link("tablet://lights/toggle")) {
                Label("Světla", systemImage: "lightbulb")
            }
        }
        .displayName("Světla tabletu")
    }
}
