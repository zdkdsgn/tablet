import SwiftUI
import IOKit.hid
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    let store = OTDStore()
    let device = DeviceMonitor()
    let touch = TouchSettings()
    private(set) lazy var engine = TouchEngine(settings: touch)
    let zoom = ZoomSettings()
    let hud = ModeHUD()
    let lightSettings = LightSettings()
    private(set) lazy var lights = RingLights(device: device, settings: lightSettings)

    /// LED shows the ring mode while this app controls the ring, else the first LED (or nothing when lights are off).
    func updateRingLED() {
        lights.show(zoom.smooth ? zoom.mode.rawValue : 0)
    }
    private(set) lazy var ringZoom = RingZoom(settings: zoom)
    let keyLabels = KeyLabels()
    /// Keeps the pen cursor inside the screen and lets it push the auto-hidden Dock out.
    let edgeFix = EdgeFix()
    /// Last pressed ExpressKey – the Tablet screen highlights it.
    @Published var pressedKey: Int?
    private var keysDown = [Bool](repeating: false, count: 8)

    private func expressKeys(_ down: [Bool]) {
        for i in 0..<min(8, down.count) where down[i] != keysDown[i] {
            if down[i] {
                pressedKey = i
                if keyLabels.showOnPress {
                    let a = store.aux[i]
                    hud.showKey(i, name: keyLabels.name(i, for: a), shortcut: a.title)
                }
            } else if pressedKey == i {
                pressedKey = nil
            }
        }
        keysDown = Array(down.prefix(8))
    }

    @Published var accessibility = TouchEngine.accessibilityGranted
    @Published var autoPresets: Bool = UserDefaults.standard.bool(forKey: "autoPresets") {
        didSet { UserDefaults.standard.set(autoPresets, forKey: "autoPresets") }
    }
    private var timer: Timer?

    /// Start Tablet (and with it the OpenTabletDriver daemon) when the user logs in.
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginItemError: String?

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = "Nejde nastavit: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginItemError = "Povolte Tablet v Nastavení systému → Obecné → Položky otevírané při přihlášení."
        }
    }

    init() {
        device.onTouches = { [weak self] t in self?.engine.update(t) }
        device.onRing = { [weak self] p in self?.ringZoom.ring(p) }
        device.onRingButton = { [weak self] b in self?.ringZoom.button(b) }
        device.onConnect = { [weak self] in
            self?.updateRingLED()
            self?.lights.welcome()
        }
        ringZoom.onModeChange = { [weak self] m in
            guard let self else { return }
            let count = RingMode.allCases.count
            self.lights.modeChanged(to: m.rawValue, from: (m.rawValue + count - 1) % count)
            self.hud.show(m)
        }
        lights.restore = { [weak self] in self?.updateRingLED() }
        device.onExpressKeys = { [weak self] down in self?.expressKeys(down) }
        ringZoom.onLongPress = { [weak self] in
            guard let self else { return }
            self.lights.play()
            if !self.lightSettings.easterEggUnlocked { self.lightSettings.easterEggUnlocked = true }
        }
        device.start()
        // first run: start at login by default (the user can turn it off in Předvolby)
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
            setLaunchAtLogin(true)
        }
        if !accessibility { TouchEngine.requestAccessibility() }
        store.startDaemon()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.accessibility = TouchEngine.accessibilityGranted
                self.device.recheckAccess()
                self.logStatus()
                if self.accessibility && !self.edgeFix.enabled { self.edgeFix.start() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.appActivated(app) }
        }
    }

    private var lastStatus = ""
    /// Writes permission / device state changes to ~/Library/Logs/Tablet.log (for troubleshooting).
    private func logStatus() {
        let hid = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let s = "ax=\(accessibility) hidAccess=\(hid.rawValue) connected=\(device.connected) touchReports=\(device.touchReportsSeen) touches=\(device.touches.count) edgeFix=\(edgeFix.enabled) bundle=\(Bundle.main.bundlePath)"
        guard s != lastStatus else { return }
        lastStatus = s
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tablet.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// Switches to the preset named like the app in front (e.g. "Photoshop"), else to "Výchozí".
    private func appActivated(_ app: NSRunningApplication?) {
        guard autoPresets, let name = app?.localizedName, app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let match = store.presets.first { name.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(name) }
        if let m = match { store.applyPreset(m) }
        else if store.presets.contains("Výchozí") { store.applyPreset("Výchozí") }
    }

    static func openPrivacy(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }
}

@main
struct TabletMain: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Tablet", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.device)
                .environmentObject(model.touch)
                .environmentObject(model.zoom)
                .environmentObject(model.lightSettings)
                .environmentObject(model.keyLabels)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 760)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.device)
                .environmentObject(model.touch)
                .environmentObject(model.zoom)
                .environmentObject(model.lightSettings)
                .environmentObject(model.keyLabels)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: "pencil.and.scribble")
        }
        .menuBarExtraStyle(.window)
    }
}
