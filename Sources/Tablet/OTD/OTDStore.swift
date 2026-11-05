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
    /// The connected tablet as OpenTabletDriver describes it (its configuration: size, buttons, wheel).
    @Published var tablet: TabletInfo = TabletInfo.cached ?? .intuosProM
    /// Called when a different tablet is detected.
    var onTabletChange: ((TabletInfo) -> Void)?
    /// Physical active area of the connected tablet in mm.
    var fullTablet: (width: Double, height: Double) { (tablet.width, tablet.height) }

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
            profileIndex = profiles.firstIndex { ($0["Tablet"] as? String) == tablet.name } ?? 0
            guard profiles.indices.contains(profileIndex) else { throw err("V nastavení chybí profil tabletu \(tablet.name)") }
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
        aux = (0..<max(tablet.auxCount, auxRaw.count)).map { BindingAction(json: auxRaw.indices.contains($0) ? auxRaw[$0] : nil) }
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
            await MainActor.run { self.lastError = ok ? nil : L("Ovladač nastavení nepřevzal – zkuste ho spustit znovu.") }
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

    /// Asks the daemon which tablet is connected; on a change the matching profile is loaded.
    func detectTablet() {
        Task.detached {
            guard let info = OTDClient.tablets().compactMap(TabletInfo.init(otd:)).first else { return }
            await MainActor.run {
                guard info != self.tablet else { return }
                self.tablet = info
                info.cache()
                self.reload()
                self.onTabletChange?(info)
            }
        }
    }

    func checkDaemon() {
        let daemons = Self.runningDaemons()
        daemonRunning = !daemons.isEmpty && OTDClient.isReachable()
        if daemonRunning { detectTablet() }
        if daemons.isEmpty { daemonSource = "" }
        else if daemons.contains(where: { $0.path == daemonURL.path }) { daemonSource = L("Součást aplikace") }
        else { daemonSource = L("Samostatný OpenTabletDriver") }
    }

    /// Starts the bundled daemon. A daemon from a separately installed OpenTabletDriver.app is stopped
    /// first, so only one driver talks to the tablet.
    func startDaemon() {
        let mine = daemonURL.path
        let daemons = Self.runningDaemons()
        if daemons.contains(where: { $0.path == mine }) { checkDaemon(); return }
        guard FileManager.default.isExecutableFile(atPath: mine) else {
            lastError = L("V aplikaci chybí ovladač (Contents/Helpers/OpenTabletDriver.Daemon). Sestavte ji znovu skriptem make-app.sh.")
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

    /// Keeps the tablet area's size and centre but matches the display's aspect ratio.
    func fitTabletArea() {
        let full = fullTablet
        var a = tabletArea
        guard displayArea.height > 0 else { return }
        let r = displayArea.width / displayArea.height
        let scale = max(a.width / full.width, a.height / full.height)
        var w = full.width * scale, h = full.height * scale
        if w / h > r { w = h * r } else { h = w / r }
        a.width = w; a.height = h
        a.x = min(max(a.x, w / 2), full.width - w / 2)
        a.y = min(max(a.y, h / 2), full.height - h / 2)
        tabletArea = a
    }

    // MARK: - Driver updates

    /// OpenTabletDriver version shipped in this app (from Info.plist, written by make-app.sh).
    var bundledDriverVersion: String { Bundle.main.object(forInfoDictionaryKey: "OTDVersion") as? String ?? "?" }
    /// A newer OpenTabletDriver release, when there is one.
    @Published var driverUpdate: (version: String, url: URL)?

    /// Looks up the latest OpenTabletDriver release on GitHub (at most once a day).
    func checkDriverUpdate(force: Bool = false) {
        let d = UserDefaults.standard
        if !force, let last = d.object(forKey: "otd.lastCheck") as? Date, Date().timeIntervalSince(last) < 86_400,
           let v = d.string(forKey: "otd.latest"), let u = d.string(forKey: "otd.latestURL").flatMap(URL.init(string:)) {
            setUpdate(v, u); return
        }
        guard let api = URL(string: "https://api.github.com/repos/OpenTabletDriver/OpenTabletDriver/releases/latest") else { return }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Tablet-macOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String, let page = (j["html_url"] as? String).flatMap(URL.init(string:)) else { return }
            let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                d.set(Date(), forKey: "otd.lastCheck"); d.set(v, forKey: "otd.latest"); d.set(page.absoluteString, forKey: "otd.latestURL")
                self.setUpdate(v, page)
            }
        }.resume()
    }

    private func setUpdate(_ latest: String, _ url: URL) {
        driverUpdate = Self.isNewer(latest, than: bundledDriverVersion) ? (latest, url) : nil
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
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

    private func err(_ s: String) -> NSError { NSError(domain: L("Tablet"), code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
}

/// A tablet as described by OpenTabletDriver's configuration (GetTablets).
struct TabletInfo: Equatable, Codable {
    var name: String
    var width: Double          // mm
    var height: Double
    var auxCount: Int          // ExpressKeys
    var penButtons: Int
    var hasWheel: Bool
    var vendorID: Int
    var productID: Int

    static let intuosProM = TabletInfo(name: "Wacom PTH-651", width: 223.52, height: 139.7, auxCount: 8, penButtons: 2,
                                       hasWheel: true, vendorID: 0x056A, productID: 0x0315)

    /// Models whose Touch Ring, LEDs and touch this app reads itself (Intuos5 / Intuos Pro 2013 report format).
    static let enhancedModels: Set<String> = ["Wacom PTH-451", "Wacom PTH-651", "Wacom PTH-851",
                                              "Wacom PTH-450", "Wacom PTH-650", "Wacom PTH-850",
                                              "Wacom PTK-450", "Wacom PTK-650", "Wacom PTK-850"]
    var enhanced: Bool { Self.enhancedModels.contains(name) }

    /// "Wacom PTH-651" → "Intuos Pro M (PTH-651)" for known models, else the name itself.
    var displayName: String {
        let known: [String: String] = ["PTH-451": "Intuos Pro S", "PTH-651": "Intuos Pro M", "PTH-851": "Intuos Pro L",
                                       "PTH-450": "Intuos5 touch S", "PTH-650": "Intuos5 touch M", "PTH-850": "Intuos5 touch L",
                                       "PTK-450": "Intuos5 S", "PTK-650": "Intuos5 M", "PTK-850": "Intuos5 L",
                                       "PTH-460": "Intuos Pro S", "PTH-660": "Intuos Pro M", "PTH-860": "Intuos Pro L"]
        let model = name.replacingOccurrences(of: "Wacom ", with: "")
        return known[model] ?? name
    }
    var model: String { name.replacingOccurrences(of: "Wacom ", with: "") }

    init(name: String, width: Double, height: Double, auxCount: Int, penButtons: Int, hasWheel: Bool, vendorID: Int, productID: Int) {
        self.name = name; self.width = width; self.height = height; self.auxCount = auxCount
        self.penButtons = penButtons; self.hasWheel = hasWheel; self.vendorID = vendorID; self.productID = productID
    }

    init?(otd t: [String: Any]) {
        guard let props = t["Properties"] as? [String: Any], let name = props["Name"] as? String else { return nil }
        let spec = props["Specifications"] as? [String: Any] ?? [:]
        let dig = spec["Digitizer"] as? [String: Any] ?? [:]
        let num = { (d: [String: Any]?, k: String) in (d?[k] as? NSNumber)?.doubleValue ?? 0 }
        let ids = (props["DigitizerIdentifiers"] as? [[String: Any]])?.first
        self.init(name: name,
                  width: num(dig, "Width"), height: num(dig, "Height"),
                  auxCount: min(16, Int(num(spec["AuxiliaryButtons"] as? [String: Any], "ButtonCount"))),
                  penButtons: Int(num(spec["Pen"] as? [String: Any], "ButtonCount")),
                  hasWheel: !((spec["Wheels"] as? [Any]) ?? []).isEmpty,
                  vendorID: Int(num(ids, "VendorID")), productID: Int(num(ids, "ProductID")))
        if width <= 0 || height <= 0 { return nil }
    }

    static var cached: TabletInfo? {
        guard let d = UserDefaults.standard.data(forKey: "tablet.info") else { return nil }
        return try? JSONDecoder().decode(TabletInfo.self, from: d)
    }
    func cache() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "tablet.info") }
    }
}
