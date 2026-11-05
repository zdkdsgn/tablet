import AppKit
import Combine

struct AreaRect: Equatable {
    var width: Double, height: Double, x: Double, y: Double, rotation: Double

    init(width: Double, height: Double, x: Double, y: Double, rotation: Double = 0) {
        self.width = width; self.height = height; self.x = x; self.y = y; self.rotation = rotation
    }
    init(_ d: [String: Any]?) {
        let n = { (k: String) in (d?[k] as? NSNumber)?.doubleValue ?? 0 }
        self.init(width: n("Width"), height: n("Height"), x: n("X"), y: n("Y"), rotation: n("Rotation"))
    }
    var json: [String: Any] { ["Width": width, "Height": height, "X": x, "Y": y, "Rotation": rotation] }
}

/// Reads and writes OpenTabletDriver's settings.json and pushes changes to the running daemon.
@MainActor
final class OTDStore: ObservableObject {
    static let tabletName = "Wacom PTH-651"
    /// Physical active area of the PTH-651 (from the OTD configuration).
    static let fullTablet = (width: 223.52, height: 139.7)

    /// The OpenTabletDriver daemon shipped inside Tablet.app (Contents/Helpers).
    var daemonURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpenTabletDriver.Daemon") }
    /// What the running daemon is: ours, a separately installed OpenTabletDriver.app, or none.
    @Published var daemonSource: String = ""
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OpenTabletDriver")
    var settingsURL: URL { dir.appendingPathComponent("settings.json") }
    var presetsDir: URL { dir.appendingPathComponent("Presets") }

    @Published var loaded = false
    @Published var lastError: String?
    @Published var daemonRunning = false

    @Published var aux: [BindingAction] = Array(repeating: .none, count: 8)
    @Published var wheelCW: BindingAction = .none
    @Published var wheelCCW: BindingAction = .none
    @Published var wheelButton: BindingAction = .none
    @Published var wheelStep: Double = 5
    @Published var penButtons: [BindingAction] = [.adaptive("Button 1"), .adaptive("Button 2")]
    @Published var eraser: BindingAction = .adaptive("Eraser")
    @Published var tipThreshold: Double = 1
    @Published var disablePressure = false
    @Published var disableTilt = false
    @Published var tabletArea = AreaRect(width: 223.52, height: 139.7, x: 111.76, y: 69.85)
    @Published var displayArea = AreaRect(width: 1920, height: 1080, x: 960, y: 540)
    @Published var lockAspect = true

    @Published var presets: [String] = []
    @Published var activePreset: String? = UserDefaults.standard.string(forKey: "activePreset")

    private var root: [String: Any] = [:]
    private var profileIndex = 0
    private var bag = Set<AnyCancellable>()
    private var suppress = false
    private var backedUp = false

    init() {
        reload()
        refreshPresets()
        checkDaemon()
        // Any edit → save + apply (debounced).
        let changes: [AnyPublisher<Void, Never>] = [
            $aux.map { _ in () }.eraseToAnyPublisher(),
            $wheelCW.map { _ in () }.eraseToAnyPublisher(),
            $wheelCCW.map { _ in () }.eraseToAnyPublisher(),
            $wheelButton.map { _ in () }.eraseToAnyPublisher(),
            $wheelStep.map { _ in () }.eraseToAnyPublisher(),
            $penButtons.map { _ in () }.eraseToAnyPublisher(),
            $eraser.map { _ in () }.eraseToAnyPublisher(),
            $tipThreshold.map { _ in () }.eraseToAnyPublisher(),
            $disablePressure.map { _ in () }.eraseToAnyPublisher(),
            $disableTilt.map { _ in () }.eraseToAnyPublisher(),
            $tabletArea.map { _ in () }.eraseToAnyPublisher(),
            $displayArea.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .dropFirst(changes.count)
            .filter { [weak self] in !(self?.suppress ?? true) }
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
            .store(in: &bag)
        Timer.publish(every: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.checkDaemon() }
            .store(in: &bag)
    }

    // MARK: - Load

    func reload() {
        do {
            let data = try Data(contentsOf: settingsURL)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw err("Neplatný soubor nastavení") }
            root = obj
            let profiles = root["Profiles"] as? [[String: Any]] ?? []
            profileIndex = profiles.firstIndex { ($0["Tablet"] as? String) == Self.tabletName } ?? 0
            guard profiles.indices.contains(profileIndex) else { throw err("V nastavení chybí profil tabletu \(Self.tabletName)") }
            apply(profile: profiles[profileIndex])
            loaded = true
            lastError = nil
        } catch {
            lastError = "Nastavení OpenTabletDriveru nejde načíst: \(error.localizedDescription)"
        }
    }

    private func apply(profile p: [String: Any]) {
        suppress = true
        defer { DispatchQueue.main.async { self.suppress = false } }
        let b = p["Bindings"] as? [String: Any] ?? [:]
        let auxRaw = b["AuxButtons"] as? [Any] ?? []
        aux = (0..<8).map { BindingAction(json: auxRaw.indices.contains($0) ? auxRaw[$0] : nil) }
        let wheel = (b["WheelBindings"] as? [[String: Any]])?.first ?? [:]
        wheelCW = BindingAction(json: wheel["ClockwiseRotation"])
        wheelCCW = BindingAction(json: wheel["CounterClockwiseRotation"])
        wheelButton = BindingAction(json: (wheel["WheelButtons"] as? [Any])?.first)
        wheelStep = (wheel["ClockwiseActivationThreshold"] as? NSNumber)?.doubleValue ?? 5
        let pens = b["PenButtons"] as? [Any] ?? []
        penButtons = (0..<2).map { BindingAction(json: pens.indices.contains($0) ? pens[$0] : nil) }
        eraser = BindingAction(json: b["EraserButton"])
        tipThreshold = (b["TipActivationThreshold"] as? NSNumber)?.doubleValue ?? 1
        disablePressure = b["DisablePressure"] as? Bool ?? false
        disableTilt = b["DisableTilt"] as? Bool ?? false
        let abs = p["AbsoluteModeSettings"] as? [String: Any] ?? [:]
        tabletArea = AreaRect(abs["Tablet"] as? [String: Any])
        displayArea = AreaRect(abs["Display"] as? [String: Any])
    }

    // MARK: - Save

    func save() {
        guard loaded, var profiles = root["Profiles"] as? [[String: Any]], profiles.indices.contains(profileIndex) else { return }
        var p = profiles[profileIndex]
        var b = p["Bindings"] as? [String: Any] ?? [:]
        b["AuxButtons"] = aux.map(\.json)
        var wheels = b["WheelBindings"] as? [[String: Any]] ?? [[:]]
        if wheels.isEmpty { wheels = [[:]] }
        wheels[0]["ClockwiseRotation"] = wheelCW.json
        wheels[0]["CounterClockwiseRotation"] = wheelCCW.json
        wheels[0]["WheelButtons"] = [wheelButton.json]
        wheels[0]["ClockwiseActivationThreshold"] = wheelStep
        wheels[0]["CounterClockwiseActivationThreshold"] = wheelStep
        b["WheelBindings"] = wheels
        b["PenButtons"] = penButtons.map(\.json)
        b["EraserButton"] = eraser.json
        b["TipActivationThreshold"] = tipThreshold
        b["DisablePressure"] = disablePressure
        b["DisableTilt"] = disableTilt
        p["Bindings"] = b
        var abs = p["AbsoluteModeSettings"] as? [String: Any] ?? [:]
        abs["Tablet"] = tabletArea.json
        abs["Display"] = displayArea.json
        p["AbsoluteModeSettings"] = abs
        profiles[profileIndex] = p
        root["Profiles"] = profiles
        do {
            if !backedUp {
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                try? FileManager.default.copyItem(at: settingsURL, to: dir.appendingPathComponent("settings.backup-tablet-\(stamp).json"))
                backedUp = true
            }
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
            if let a = activePreset {   // edits made while a preset is active belong to it
                try? data.write(to: presetsDir.appendingPathComponent(a + ".json"), options: .atomic)
            }
            pushToDaemon()
        } catch {
            lastError = "Uložení selhalo: \(error.localizedDescription)"
        }
    }

    /// Tells the running daemon to load settings.json.
    /// Sends the current settings to the running daemon over its JSON-RPC socket.
    func pushToDaemon() {
        let settings = root
        Task.detached {
            let ok = OTDClient.setSettings(settings)
            await MainActor.run { self.lastError = ok ? nil : "Ovladač nastavení nepřevzal – zkuste ho spustit znovu." }
        }
    }

    // MARK: - Daemon

    /// Processes named OpenTabletDriver.Daemon with their executable paths.
    nonisolated static func runningDaemons() -> [(pid: Int32, path: String)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,comm="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(of: " "), t.hasSuffix("OpenTabletDriver.Daemon"), let pid = Int32(t[..<sp]) else { return nil }
            return (pid, t[sp...].trimmingCharacters(in: .whitespaces))
        }
    }

    func checkDaemon() {
        let daemons = Self.runningDaemons()
        daemonRunning = !daemons.isEmpty && OTDClient.isReachable()
        if daemons.isEmpty { daemonSource = "" }
        else if daemons.contains(where: { $0.path == daemonURL.path }) { daemonSource = "Součást aplikace" }
        else { daemonSource = "Samostatný OpenTabletDriver" }
    }

    /// Starts the bundled daemon. A daemon from a separately installed OpenTabletDriver.app is stopped
    /// first, so only one driver talks to the tablet.
    func startDaemon() {
        let mine = daemonURL.path
        let daemons = Self.runningDaemons()
        if daemons.contains(where: { $0.path == mine }) { checkDaemon(); return }
        guard FileManager.default.isExecutableFile(atPath: mine) else {
            lastError = "V aplikaci chybí ovladač (Contents/Helpers/OpenTabletDriver.Daemon). Sestavte ji znovu skriptem make-app.sh."
            return
        }
        for d in daemons { kill(d.pid, SIGTERM) }
        let delay = daemons.isEmpty ? 0 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let p = Process()
            p.executableURL = self.daemonURL
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.checkDaemon(); self.pushToDaemon() }
            } catch {
                self.lastError = "Ovladač nejde spustit: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Presets (whole settings files in OTD's Presets folder)

    func refreshPresets() {
        let files = (try? FileManager.default.contentsOfDirectory(at: presetsDir, includingPropertiesForKeys: nil)) ?? []
        presets = files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    func savePreset(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty else { return }
        save()
        try? FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        let target = presetsDir.appendingPathComponent(clean + ".json")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: settingsURL, to: target)
            setActive(clean)
        } catch { lastError = "Předvolbu nejde uložit: \(error.localizedDescription)" }
        refreshPresets()
    }

    func applyPreset(_ name: String) {
        let src = presetsDir.appendingPathComponent(name + ".json")
        guard FileManager.default.fileExists(atPath: src.path), name != activePreset || !loaded else { return }
        do {
            let data = try Data(contentsOf: src)
            try data.write(to: settingsURL, options: .atomic)
            reload()
            pushToDaemon()
            setActive(name)
        } catch { lastError = "Předvolbu nejde načíst: \(error.localizedDescription)" }
    }

    func deletePreset(_ name: String) {
        try? FileManager.default.removeItem(at: presetsDir.appendingPathComponent(name + ".json"))
        if activePreset == name { setActive(nil) }
        refreshPresets()
    }

    private func setActive(_ name: String?) {
        activePreset = name
        UserDefaults.standard.set(name, forKey: "activePreset")
    }

    private func err(_ s: String) -> NSError { NSError(domain: "Tablet", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
}
