import AppKit
import CryptoKit

/// Updates Tablet itself from GitHub Releases (zdkdsgn/tablet): checks once a day, downloads the DMG,
/// verifies its SHA-256 (from the release notes), replaces the app and starts the new version.
@MainActor
final class Updater: ObservableObject {
    static let repo = "zdkdsgn/tablet"
    struct Release { var version: String; var dmg: URL; var sha256: String?; var page: URL; var notes: String }

    @Published private(set) var available: Release?
    @Published private(set) var state: String?
    @Published private(set) var busy = false
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "update.auto") } }

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    init() {
        UserDefaults.standard.register(defaults: ["update.auto": true])
        autoCheck = UserDefaults.standard.bool(forKey: "update.auto")
    }

    func checkIfDue() {
        guard autoCheck else { return }
        if let last = UserDefaults.standard.object(forKey: "update.lastCheck") as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        check()
    }

    func check(manual: Bool = false) {
        guard let api = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Tablet-macOS", forHTTPHeaderField: "User-Agent")
        if manual { state = L("Hledám…") }
        URLSession.shared.dataTask(with: req) { data, _, error in
            let parsed: Release? = {
                guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = j["tag_name"] as? String,
                      let page = (j["html_url"] as? String).flatMap(URL.init(string:)),
                      let assets = j["assets"] as? [[String: Any]],
                      let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })?["browser_download_url"] as? String,
                      let dmgURL = URL(string: dmg) else { return nil }
                let body = j["body"] as? String ?? ""
                let sha = body.range(of: "[0-9a-f]{64}", options: .regularExpression).map { String(body[$0]) }
                return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, dmg: dmgURL, sha256: sha, page: page, notes: body)
            }()
            let failed = error != nil
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date(), forKey: "update.lastCheck")
                if let r = parsed, OTDStore.isNewer(r.version, than: self.currentVersion) {
                    self.available = r
                    self.state = nil
                } else {
                    self.available = nil
                    if manual { self.state = failed ? L("GitHub teď není dostupný.") : L("Máte nejnovější verzi.") }
                }
            }
        }.resume()
    }

    /// Downloads, verifies and installs the available release, then relaunches.
    func install() {
        guard let r = available, !busy else { return }
        busy = true
        state = L("Stahuji…")
        URLSession.shared.downloadTask(with: r.dmg) { tmp, _, error in
            guard let tmp, error == nil, let data = try? Data(contentsOf: tmp) else {
                DispatchQueue.main.async { self.fail(L("Stažení se nepodařilo.")) }; return
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Tablet-update-\(r.version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            try? data.write(to: dmg)
            DispatchQueue.main.async {
                if let expected = r.sha256, expected != digest {
                    self.fail(L("Kontrolní součet nesedí – aktualizace se neinstaluje.")); return
                }
                self.state = L("Instaluji…")
                self.replace(with: dmg)
            }
        }.resume()
    }

    private func replace(with dmg: URL) {
        let target = Bundle.main.bundlePath
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpenTabletDriver.Daemon").path
        // runs after this app quits: mount, swap the bundle, unmount, start the new version
        let script = """
        set -e
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        pkill -f '\(helper)' || true
        MNT=$(mktemp -d)
        hdiutil attach -nobrowse -readonly -mountpoint "$MNT" '\(dmg.path)' >/dev/null
        APP=$(find "$MNT" -maxdepth 1 -name '*.app' | head -1)
        STAGE=$(mktemp -d)
        ditto "$APP" "$STAGE/Tablet.app"
        hdiutil detach "$MNT" >/dev/null || true
        xattr -cr "$STAGE/Tablet.app" || true
        rm -rf '\(target)'
        ditto "$STAGE/Tablet.app" '\(target)'
        rm -rf "$STAGE" '\(dmg.path)'
        open '\(target)'
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tablet-update.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: log) { p.standardOutput = h; p.standardError = h }
        do {
            try p.run()
            NSApp.terminate(nil)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ s: String) {
        busy = false
        state = s
    }
}
