import AppKit

/// Remembers where on the tablet the pen actually draws (a coarse grid over the whole active area)
/// and suggests a smaller tablet area that covers it.
@MainActor
final class UsageMap: ObservableObject {
    static let cols = 48, rows = 30
    private let d = UserDefaults.standard
    @Published private(set) var cells: [Int]
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "usage.enabled") } }
    private var dirty = false
    private var saveTimer: Timer?

    var total: Int { cells.reduce(0, +) }

    init() {
        d.register(defaults: ["usage.enabled": true])
        enabled = d.bool(forKey: "usage.enabled")
        let saved = d.array(forKey: "usage.cells") as? [Int] ?? []
        cells = saved.count == Self.cols * Self.rows ? saved : Array(repeating: 0, count: Self.cols * Self.rows)
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    /// A drawing point in tablet millimetres (0…full width / height).
    func record(mmX: Double, mmY: Double, full: (width: Double, height: Double)) {
        guard enabled, full.width > 0, full.height > 0 else { return }
        let c = Int(mmX / full.width * Double(Self.cols)), r = Int(mmY / full.height * Double(Self.rows))
        guard (0..<Self.cols).contains(c), (0..<Self.rows).contains(r) else { return }
        cells[r * Self.cols + c] += 1
        dirty = true
    }

    func save() {
        guard dirty else { return }
        dirty = false
        d.set(cells, forKey: "usage.cells")
    }

    func reset() {
        cells = Array(repeating: 0, count: Self.cols * Self.rows)
        dirty = true
        save()
    }

    /// The area covering ~98 % of the strokes, with a margin; nil until there is enough data.
    func suggestion(full: (width: Double, height: Double), aspect: Double?) -> AreaRect? {
        let sum = total
        guard sum > 400 else { return nil }
        func bounds(_ counts: [Int]) -> (Int, Int) {
            let cut = Double(sum) * 0.01
            var acc = 0.0, lo = 0, hi = counts.count - 1
            for (i, c) in counts.enumerated() { acc += Double(c); if acc > cut { lo = i; break } }
            acc = 0
            for (i, c) in counts.enumerated().reversed() { acc += Double(c); if acc > cut { hi = i; break } }
            return (lo, hi)
        }
        let colSums = (0..<Self.cols).map { c in (0..<Self.rows).reduce(0) { $0 + cells[$1 * Self.cols + c] } }
        let rowSums = (0..<Self.rows).map { r in cells[(r * Self.cols)..<((r + 1) * Self.cols)].reduce(0, +) }
        let (c0, c1) = bounds(colSums), (r0, r1) = bounds(rowSums)
        let cw = full.width / Double(Self.cols), rh = full.height / Double(Self.rows)
        var minX = Double(c0) * cw, maxX = Double(c1 + 1) * cw
        var minY = Double(r0) * rh, maxY = Double(r1 + 1) * rh
        // margin, minimum size
        let mx = (maxX - minX) * 0.08, my = (maxY - minY) * 0.08
        minX -= mx; maxX += mx; minY -= my; maxY += my
        var w = max(maxX - minX, full.width * 0.3), h = max(maxY - minY, full.height * 0.3)
        if let r = aspect, r > 0 { if w / h > r { h = w / r } else { w = h * r } }
        w = min(w, full.width); h = min(h, full.height)
        if let r = aspect, r > 0 { if w / h > r { w = h * r } else { h = w / r } }
        var x = (minX + maxX) / 2, y = (minY + maxY) / 2
        x = min(max(x, w / 2), full.width - w / 2)
        y = min(max(y, h / 2), full.height - h / 2)
        return AreaRect(width: w, height: h, x: x, y: y)
    }
}

/// Converts between macOS global coordinates (CG: origin top-left of the main display) and
/// OpenTabletDriver's display coordinates (origin top-left of all displays together).
enum ScreenSpace {
    static var unionOriginCG: CGPoint {
        let ss = NSScreen.screens
        guard let main = ss.first else { return .zero }
        let minX = ss.map(\.frame.minX).min() ?? 0
        let maxY = ss.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: minX, y: main.frame.height - maxY)
    }

    static func otd(fromCG p: CGPoint) -> CGPoint {
        let o = unionOriginCG
        return CGPoint(x: p.x - o.x, y: p.y - o.y)
    }

    /// The front window of an app in OTD display coordinates.
    static func frontWindow(pid: pid_t) -> AreaRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  r.width > 200, r.height > 150 else { continue }
            let o = otd(fromCG: r.origin)
            return AreaRect(width: r.width, height: r.height, x: o.x + r.width / 2, y: o.y + r.height / 2)
        }
        return nil
    }
}
