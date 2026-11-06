import AppKit
import IOKit.ps

/// Light notifications and the break reminder – settings stored in UserDefaults.
@MainActor
final class ReminderSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var batteryAlert: Bool { didSet { d.set(batteryAlert, forKey: "alert.battery") } }
    @Published var batteryLevel: Int { didSet { d.set(batteryLevel, forKey: "alert.batteryLevel") } }
    @Published var alertAnimation: String { didSet { d.set(alertAnimation, forKey: "alert.animation") } }
    @Published var breakEnabled: Bool { didSet { d.set(breakEnabled, forKey: "break.enabled") } }
    @Published var workMinutes: Double { didSet { d.set(workMinutes, forKey: "break.work") } }
    @Published var breakMinutes: Double { didSet { d.set(breakMinutes, forKey: "break.length") } }
    /// Count only the time the pen is actually used (otherwise wall-clock time).
    @Published var countDrawing: Bool { didSet { d.set(countDrawing, forKey: "break.countDrawing") } }

    init() {
        d.register(defaults: ["alert.battery": false, "alert.batteryLevel": 15, "alert.animation": LEDAnimation.heartbeat.rawValue,
                              "break.enabled": false, "break.work": 50.0, "break.length": 5.0, "break.countDrawing": true])
        batteryAlert = d.bool(forKey: "alert.battery")
        batteryLevel = d.integer(forKey: "alert.batteryLevel")
        alertAnimation = d.string(forKey: "alert.animation") ?? LEDAnimation.heartbeat.rawValue
        breakEnabled = d.bool(forKey: "break.enabled")
        workMinutes = d.double(forKey: "break.work")
        breakMinutes = d.double(forKey: "break.length")
        countDrawing = d.bool(forKey: "break.countDrawing")
    }

    var animation: LEDAnimation { LEDAnimation(rawValue: alertAnimation) ?? .heartbeat }
}

/// Watches the battery and the drawing time and signals with the tablet's lights + an on-screen notice.
@MainActor
final class Reminders: ObservableObject {
    private let settings: ReminderSettings
    /// Plays an animation and shows a notice (set by the app model).
    var alert: ((LEDAnimation, String, String, String?) -> Void)?
    /// Last pen activity (set by the app model).
    var lastActivity: () -> Date = { .distantPast }

    /// Drawing time since the last break, in seconds.
    @Published private(set) var worked: TimeInterval = 0
    @Published private(set) var breakDue = false
    private var idleSince: Date?
    private var lastNag = Date.distantPast
    private var batteryWarned = false
    private var timer: Timer?
    private let tick: TimeInterval = 5

    init(settings: ReminderSettings) {
        self.settings = settings
        timer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    var progress: Double { min(1, worked / max(60, settings.workMinutes * 60)) }
    var remainingMinutes: Int { max(0, Int(ceil((settings.workMinutes * 60 - worked) / 60))) }

    func resetBreak() {
        worked = 0; breakDue = false; idleSince = nil
    }

    private func step() {
        checkBattery()
        guard settings.breakEnabled else { worked = 0; breakDue = false; return }
        let active = Date().timeIntervalSince(lastActivity()) < 45
        if active {
            idleSince = nil
            worked += tick
        } else {
            if idleSince == nil { idleSince = Date() }
            if !settings.countDrawing { worked += tick }
            // away from the tablet for a break's length = the break happened
            if let s = idleSince, Date().timeIntervalSince(s) >= settings.breakMinutes * 60 { resetBreak() }
        }
        if worked >= settings.workMinutes * 60 {
            breakDue = true
            // remind now and then every 10 minutes while drawing goes on
            if active, Date().timeIntervalSince(lastNag) > 600 {
                lastNag = Date()
                alert?(.countdown, "cup.and.saucer", L("Čas na přestávku"),
                       String(format: L("Kreslíte %d minut. Protáhněte se a odpočiňte si oči."), Int(worked / 60)))
            }
        }
    }

    private func checkBattery() {
        guard settings.batteryAlert, let (level, charging) = Self.battery() else { batteryWarned = false; return }
        if charging || level > settings.batteryLevel + 3 { batteryWarned = false; return }
        if level <= settings.batteryLevel && !batteryWarned {
            batteryWarned = true
            alert?(settings.animation, "battery.25", L("Slabá baterie"), String(format: L("Baterie Macu má %d %%."), level))
        }
    }

    /// Internal battery: level in % and whether it is on power; nil on Macs without a battery.
    static func battery() -> (Int, Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (cur * 100 / max, charging)
        }
        return nil
    }
}
