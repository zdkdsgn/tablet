import SwiftUI
import IOKit.hid
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    /// The one model, for the app delegate (Dock icon clicks).
    static weak var shared: AppModel?

    /// Opens the settings window; set from a view, which has SwiftUI's openWindow action.
    var openMain: (() -> Void)?

    /// Brings the settings window to the front, re-creating it when it was closed.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == L("Tablet") }), w.canBecomeKey {
            w.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
    }

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
        lights.show(zoom.smooth ? zoom.ledIndex : 0)
    }
    private(set) lazy var ringZoom = RingZoom(settings: zoom)
    let keyLabels = KeyLabels()
    /// Keeps the pen cursor inside the screen and lets it push the auto-hidden Dock out.
    let penFilters = PenFilters()
    let radialSettings = RadialSettings()
    private(set) lazy var radial = RadialMenu(settings: radialSettings)
    private(set) lazy var edgeFix = PenTap(filters: penFilters)
    /// Last pressed ExpressKey – the Tablet screen highlights it.
    @Published var pressedKey: Int?
    private var keysDown = [Bool](repeating: false, count: 16)

    /// Maps the tablet to the next monitor (then all monitors), keeping the tablet area's proportions.
    func nextDisplay() {
        let screens = ScreenInfo.all()
        guard !screens.isEmpty else { return }
        var options = screens.map { ($0.name, $0.otd) }
        if screens.count > 1 { options.append(("Všechny monitory", ScreenInfo.union(screens))) }
        let cur = store.displayArea
        let i = options.firstIndex { abs($0.1.width - cur.width) < 1 && abs($0.1.x - cur.x) < 1 && abs($0.1.y - cur.y) < 1 } ?? -1
        let next = options[(i + 1) % options.count]
        store.displayArea = next.1
        if UserDefaults.standard.object(forKey: "area.lockAspect") as? Bool ?? true {
            store.fitTabletArea()
        }
        hud.showMessage(symbol: "display", title: next.0, subtitle: L("Tablet se mapuje sem"))
    }

    private func expressKeys(_ down: [Bool]) {
        for i in 0..<min(store.aux.count, down.count) where down[i] != keysDown[i] {
            let app = keyLabels.appAction(i)
            if down[i] {
                pressedKey = i
                switch app {
                case .precision: penFilters.precisionActive = true
                case .display: nextDisplay()
                case .radial: radial.open()
                case .none:
                    if keyLabels.showOnPress {
                        let a = store.aux[i]
                        hud.showKey(i, name: keyLabels.name(i, for: a), shortcut: a.title)
                    }
                }
            } else {
                if pressedKey == i { pressedKey = nil }
                switch app {
                case .precision: penFilters.precisionActive = false
                case .radial: radial.close(perform: true)
                default: break
                }
            }
        }
        keysDown = down + Array(repeating: false, count: max(0, 16 - down.count))
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
            loginItemError = L("Povolte Tablet v Nastavení systému → Obecné → Položky otevírané při přihlášení.")
        }
    }

    init() {
        Self.shared = self
        device.onTouches = { [weak self] t in self?.engine.update(t) }
        device.onRing = { [weak self] p in self?.ringZoom.ring(p) }
        device.onRingButton = { [weak self] b in self?.ringZoom.button(b) }
        device.onConnect = { [weak self] in
            self?.updateRingLED()
            self?.lights.welcome()
        }
        ringZoom.onModeChange = { [weak self] m in
            guard let self else { return }
            let n = max(1, self.zoom.cycle.count)
            let idx = self.zoom.ledIndex
            self.lights.modeChanged(to: idx, from: (idx + n - 1) % n)
            self.hud.show(m, dots: n, active: idx)
        }
        lights.restore = { [weak self] in self?.updateRingLED() }
        device.onExpressKeys = { [weak self] down in self?.expressKeys(down) }
        ringZoom.onLongPress = { [weak self] in
            guard let self else { return }
            self.lights.play()
            if !self.lightSettings.easterEggUnlocked { self.lightSettings.easterEggUnlocked = true }
        }
        device.setTarget(store.tablet)
        store.onTabletChange = { [weak self] t in self?.device.setTarget(t) }
        device.start()
        // first run: start at login by default (the user can turn it off in Předvolby)
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
            setLaunchAtLogin(true)
        }
        if !accessibility { TouchEngine.requestAccessibility() }
        store.startDaemon()
        store.checkDriverUpdate()
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
                .environmentObject(model.penFilters)
                .environmentObject(model.radialSettings)
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
                .environmentObject(model.penFilters)
                .environmentObject(model.radialSettings)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: "pencil.and.scribble")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Clicking the Dock icon while the window is closed opens it again
/// (the app keeps running in the background and in the menu bar).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppModel.shared?.showMainWindow() } }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
