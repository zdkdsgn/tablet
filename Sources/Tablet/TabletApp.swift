import SwiftUI
import IOKit.hid
import ServiceManagement
import Combine

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
    let penHover = PenHover()
    let odometer = PenOdometer()
    let island = NotchIsland()
    let achievements = Achievements()
    let strokeLog = StrokeLog()
    private var bag = Set<AnyCancellable>()
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
    let expressView = ExpressView()
    let keyBehaviour = KeyBehaviour()
    private(set) lazy var keyEngine = KeyPressEngine(settings: keyBehaviour)
    private(set) lazy var penProfiles = PenProfiles(store: store, filters: penFilters, behaviour: keyBehaviour)
    let usage = UsageMap()
    let reminderSettings = ReminderSettings()
    private(set) lazy var reminders = Reminders(settings: reminderSettings)
    let updater = Updater()
    /// The app in front before Tablet was activated (by a tablet:// link) – focus goes back to it.
    private var lastOtherApp: NSRunningApplication?
    /// Display + tablet area before "map to window", restored on the next press.
    @Published private(set) var windowMapping: (display: AreaRect, tablet: AreaRect)?
    private var penIsEraser = false

    /// Name of the pen in hand (from its serial), "Pen" until one is seen.
    var currentPenName: String {
        if let c = penProfiles.current, let p = penProfiles.pens.first(where: { $0.serial == c }) { return p.name }
        return L("Pero")
    }

    /// Finger resting on ExpressKeys → overlay with every key's function (the touched one highlighted).
    let sliderSettings = SliderSettings()
    private(set) lazy var slider = KeySlider(settings: sliderSettings)

    /// The two touch strips: keys above and below the ring (one strip without a ring).
    var keyGroups: [[Int]] {
        let n = store.aux.count
        let half = store.tablet.hasWheel ? (n + 1) / 2 : n
        return store.tablet.hasWheel ? [Array(0..<half), Array(half..<n)] : [Array(0..<n)]
    }

    private func keysTouched(_ touched: [Bool]) {
        let t = Set(touched.indices.filter { touched[$0] })
        let p = Set(keysDown.indices.filter { keysDown[$0] && $0 < store.aux.count })
        if !t.isEmpty { lights.wake() }
        slider.update(touched: t, pressed: p, groups: keyGroups)
        guard keyLabels.expressView else { return }
        expressView.update(touched: t, pressed: p) {
            let rows = (0..<store.aux.count).map { i -> ExpressViewModel.Row in
                let app = keyLabels.appAction(i)
                return .init(id: i, name: keyLabels.name(i, for: store.aux[i]),
                             detail: app == .none ? store.aux[i].title
                                : app == .tapHold ? KeyNames.display(keyBehaviour.tapKeys[i]) + (keyBehaviour.holdKeys[i].isEmpty ? "" : " · " + L("držet") + " " + KeyNames.display(keyBehaviour.holdKeys[i]))
                                : app.title, symbol: nil)
            }
            let half = store.tablet.hasWheel ? (rows.count + 1) / 2 : rows.count
            let ring: ExpressViewModel.Row? = store.tablet.hasWheel
                ? .init(id: 100, name: zoom.smooth ? zoom.mode.title : L("Touch Ring"),
                        detail: zoom.smooth ? zoom.mode.caption : store.wheelCW.title, symbol: zoom.smooth ? zoom.mode.symbol : nil)
                : nil
            return (Array(rows.prefix(half)), Array(rows.dropFirst(half)), ring)
        }
    }

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
                case .window: toggleWindowMapping()
                case .tapHold: keyEngine.press(i)
                case .none:
                    if keyLabels.showOnPress && !expressView.visible {
                        let a = store.aux[i]
                        hud.showKey(i, name: keyLabels.name(i, for: a), shortcut: a.title)
                    }
                }
            } else {
                if pressedKey == i { pressedKey = nil }
                switch app {
                case .precision: penFilters.precisionActive = false
                case .radial: radial.close(perform: true)
                case .tapHold: keyEngine.release(i, wasDown: true)
                default: break
                }
            }
        }
        keysDown = down + Array(repeating: false, count: max(0, 16 - down.count))
        if expressView.visible {
            expressView.model.pressed = Set(keysDown.indices.filter { keysDown[$0] && $0 < store.aux.count })
        }
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
        device.onRing = { [weak self] p in
            if p != nil { self?.lights.wake() }
            self?.ringZoom.ring(p)
        }
        device.onRingButton = { [weak self] b in self?.ringZoom.button(b) }
        device.onConnect = { [weak self] in
            self?.updateRingLED()
            self?.lights.welcome()
        }
        keyEngine.onHeldFlagsChange = { [weak self] f in self?.edgeFix.heldFlags = f }
        keyEngine.onFire = { [weak self] i, shortcut in
            guard let self, self.keyLabels.showOnPress, !self.expressView.visible else { return }
            self.hud.showKey(i, name: self.keyLabels.name(i, for: self.store.aux[i]), shortcut: shortcut)
        }
        device.onTool = { [weak self] eraser in self?.toolChanged(eraser: eraser) }
        device.onPen = { [weak self] s in
            guard let self else { return }
            self.penHover.update(s); self.odometer.add(s); self.achievements.sample(s, odo: self.odometer)
            self.strokeLog.add(s)
        }
        achievements.precisionActive = { [weak self] in self?.penFilters.precisionActive ?? false }
        achievements.onUnlock = { [weak self] a in
            guard let self else { return }
            if self.island.available { self.island.message("🏆 " + L(a.title), subtitle: L(a.detail), seconds: 5.5) }
            else { self.hud.showMessage(symbol: "trophy.fill", title: L(a.title), subtitle: L(a.detail)) }
            self.lights.play(.sparkle)
        }
        island.onVisit = { [weak self] in self?.achievements.unlock("notch") }
        island.statsProvider = { [weak self] in
            guard let self else { return ([], nil) }
            let o = self.odometer, a = self.achievements
            let items = [(PenOdometer.format(o.today), L("dnes"), "calendar"),
                         (PenOdometer.format(o.drawn), L("celkem"), "scribble.variable"),
                         (o.strokes.formatted(), L("tahů"), "hand.draw"),
                         ("\(a.count)/\(Achievements.all.count)", L("úspěchů"), "trophy.fill")]
            let footer = a.latest.map { "🏆 " + L($0.title) } ?? PenOdometer.comparison(o.drawn).map { String(format: L("To je jako %@."), $0) }
            return (items, footer)
        }
        odometer.currentPen = { [weak self] in self?.penProfiles.current }
        odometer.onMilestone = { [weak self] m in
            guard let self else { return }
            self.island.message(PenOdometer.milestoneText(m), subtitle: PenOdometer.pencilUsed(self.odometer.drawn))
        }
        penHover.$sample
            .sink { [weak self] s in
                guard let self else { return }
                self.island.pen(s, name: self.currentPenName, today: PenOdometer.format(self.odometer.today))
            }
            .store(in: &bag)
        device.onPenIdentity = { [weak self] id, serial in
            guard let self else { return }
            self.penProfiles.penEntered(id: id, serial: serial)
            self.achievements.pensSeen(self.penProfiles.pens.count)
        }
        penProfiles.onSwitch = { [weak self] pen in self?.hud.showMessage(symbol: "pencil.tip", title: pen.name, subtitle: L("Nastavení tohoto pera")) }
        edgeFix.onDraw = { [weak self] p in self?.recordDraw(p) }
        reminders.lastActivity = { [weak self] in self?.edgeFix.lastActivity ?? .distantPast }
        reminders.alert = { [weak self] anim, symbol, title, text in self?.alert(anim, symbol: symbol, title: title, subtitle: text) }
        updater.checkIfDue()
        ringZoom.onModeChange = { [weak self] m in
            guard let self else { return }
            let n = max(1, self.zoom.cycle.count)
            let idx = self.zoom.ledIndex
            self.lights.modeChanged(to: idx, from: (idx + n - 1) % n)
            self.hud.show(m, dots: n, active: idx)
        }
        lights.restore = { [weak self] in self?.updateRingLED() }
        device.onExpressKeys = { [weak self] down in self?.expressKeys(down) }
        device.onKeyTouch = { [weak self] t in self?.keysTouched(t) }
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
    /// Also sets the ring mode chosen for that app.
    private func appActivated(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastOtherApp = app
        if zoom.smooth, let raw = zoom.appModes[app.bundleIdentifier ?? ""] ?? zoom.appModes["*"],
           let m = RingMode(rawValue: raw), m != zoom.mode {
            setRingMode(m, notify: false)
        }
        guard autoPresets, let name = app.localizedName else { return }
        let match = store.presets.first { name.localizedCaseInsensitiveContains($0) || $0.localizedCaseInsensitiveContains(name) }
        if let m = match { store.applyPreset(m, undoable: false) }
        else if store.presets.contains("Výchozí") { store.applyPreset("Výchozí", undoable: false) }
    }

    // MARK: - New functions (1.2)

    /// Sets the ring mode (from a link or the app in front); updates LEDs, optionally shows the notice.
    func setRingMode(_ m: RingMode, notify: Bool) {
        if !zoom.cycle.contains(m) && notify { zoom.mode = m; updateRingLED(); hud.show(m, dots: max(1, zoom.cycle.count), active: zoom.ledIndex); return }
        if notify { ringZoom.setMode(m) } else { zoom.mode = m; updateRingLED() }
    }

    /// Lights + on-screen notice (battery, break, links).
    func alert(_ animation: LEDAnimation, symbol: String, title: String, subtitle: String?) {
        lights.play(animation)
        hud.showMessage(symbol: symbol, title: title, subtitle: subtitle)
    }

    /// Maps the tablet to the front window of the app in front; the next call restores the previous mapping.
    func toggleWindowMapping() {
        if let saved = windowMapping {
            windowMapping = nil
            store.displayArea = saved.display
            store.tabletArea = saved.tablet
            hud.showMessage(symbol: "display", title: L("Celá obrazovka"), subtitle: L("Tablet se mapuje sem"))
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let win = ScreenSpace.frontWindow(pid: app.processIdentifier) else {
            hud.showMessage(symbol: "macwindow", title: L("Žádné okno"), subtitle: L("Přepněte se do aplikace, ve které kreslíte"))
            return
        }
        windowMapping = (store.displayArea, store.tabletArea)
        store.displayArea = win
        if UserDefaults.standard.object(forKey: "area.lockAspect") as? Bool ?? true { store.fitTabletArea() }
        hud.showMessage(symbol: "macwindow", title: app.localizedName ?? L("Okno"), subtitle: L("Tablet se mapuje jen na toto okno"))
    }

    /// From the menu bar the front app is the one under the menu: use the last app the user worked in.
    func toggleWindowMappingFromMenu() {
        if windowMapping == nil, let app = lastOtherApp, let win = ScreenSpace.frontWindow(pid: app.processIdentifier) {
            windowMapping = (store.displayArea, store.tabletArea)
            store.displayArea = win
            if UserDefaults.standard.object(forKey: "area.lockAspect") as? Bool ?? true { store.fitTabletArea() }
            hud.showMessage(symbol: "macwindow", title: app.localizedName ?? L("Okno"), subtitle: L("Tablet se mapuje jen na toto okno"))
        } else {
            toggleWindowMapping()
        }
    }

    /// Pen flipped: eraser end → eraser tool key, tip → pen tool key (only on a change).
    private func toolChanged(eraser: Bool) {
        defer { penIsEraser = eraser }
        if eraser && !penIsEraser { achievements.eraserFlipped() }
        guard keyBehaviour.eraserSwitch, eraser != penIsEraser else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        KeySender.tap(eraser ? keyBehaviour.eraserKeys : keyBehaviour.penKeys)
    }

    /// A drawing point (CG coordinates) → tablet millimetres → usage map.
    private func recordDraw(_ p: CGPoint) {
        guard usage.enabled else { return }
        let o = ScreenSpace.otd(fromCG: p)
        let disp = store.displayArea, tab = store.tabletArea
        guard disp.width > 0, disp.height > 0 else { return }
        var u = (o.x - (disp.x - disp.width / 2)) / disp.width
        var v = (o.y - (disp.y - disp.height / 2)) / disp.height
        guard (0...1).contains(u), (0...1).contains(v) else { return }
        if tab.rotation == 180 { u = 1 - u; v = 1 - v }
        usage.record(mmX: tab.x - tab.width / 2 + u * tab.width, mmY: tab.y - tab.height / 2 + v * tab.height, full: store.fullTablet)
    }

    /// A tablet:// link; focus goes back to the app that was in front unless the link opens the window.
    func handleLink(_ url: URL) {
        let ok = Commands.handle(url, model: self)
        let opensWindow = (url.host ?? "").isEmpty || url.host == "open"
        if !opensWindow, let prev = lastOtherApp, NSApp.isActive,
           !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "main" }) {
            prev.activate()
        }
        if !ok { hud.showMessage(symbol: "questionmark.circle", title: L("Neznámý odkaz"), subtitle: url.absoluteString) }
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
                .environmentObject(model.sliderSettings)
                .environmentObject(model.keyBehaviour)
                .environmentObject(model.usage)
                .environmentObject(model.reminderSettings)
                .environmentObject(model.reminders)
                .environmentObject(model.updater)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(L("Zpět")) {
                    // text fields keep their own undo; everything else undoes the last bigger settings change
                    if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.undoManager?.canUndo == true { tv.undoManager?.undo() }
                    else { withAnimation(.snappy) { model.store.undo() } }
                }
                .keyboardShortcut("z")
                Button(L("Znovu")) {
                    if let tv = NSApp.keyWindow?.firstResponder as? NSTextView { tv.undoManager?.redo() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }

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
                .environmentObject(model.sliderSettings)
                .environmentObject(model.keyBehaviour)
                .environmentObject(model.usage)
                .environmentObject(model.reminderSettings)
                .environmentObject(model.reminders)
                .environmentObject(model.updater)
        } label: {
            Image(systemName: "pencil.and.scribble")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Clicking the Dock icon while the window is closed opens it again
/// (the app keeps running in the background and in the menu bar).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceChoice.apply(UserDefaults.standard.string(forKey: "appearance") ?? "system")
        // tablet:// links (Shortcuts, Siri, automations) – handled here so SwiftUI does not open a window for them
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        MainActor.assumeIsolated {
            if let m = AppModel.shared { m.handleLink(url) } else { pendingLinks.append(url) }
        }
    }

    /// Links that arrived before the model existed.
    var pendingLinks: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            for u in pendingLinks { AppModel.shared?.handleLink(u) }
            pendingLinks = []
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppModel.shared?.showMainWindow() } }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
