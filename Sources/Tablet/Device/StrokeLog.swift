import Foundation
import simd

/// One pen stroke (tip down → up): points in tablet mm (native frame) with pressure.
struct Stroke {
    var time: Date
    var points: [SIMD3<Float>]   // x mm, y mm, pressure 0…1
}

/// Logs every stroke of the day to ~/Library/Application Support/Tablet/Strokes/<day>.strokes,
/// so the Strokes screen can show (and replay) what was drawn. Kept for 30 days.
@MainActor
final class StrokeLog: ObservableObject {
    private let d = UserDefaults.standard
    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "strokes.enabled") } }
    /// Today's strokes (live).
    @Published private(set) var today: [Stroke] = []
    private var todayKey: String
    private var current: [SIMD3<Float>] = []
    private var currentStart = Date()

    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tablet/Strokes", isDirectory: true)
    static let keepDays = 30

    init() {
        d.register(defaults: ["strokes.enabled": true])
        enabled = d.bool(forKey: "strokes.enabled")
        todayKey = Self.key(Date())
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        today = Self.read(Self.file(todayKey))
        cleanup()
    }

    // MARK: recording

    /// Every pen report (full rate).
    func add(_ s: PenSample?) {
        guard enabled, let s, s.pressure > 0.01 else { finish(); return }
        let p = SIMD3<Float>(Float(s.mm.x), Float(s.mm.y), Float(s.pressure))
        if current.isEmpty { currentStart = Date(); current.append(p); return }
        // keep the file small: only points that moved ≥ 0.25 mm or changed pressure noticeably
        let l = current[current.count - 1]
        if simd_distance(SIMD2(l.x, l.y), SIMD2(p.x, p.y)) >= 0.25 || abs(l.z - p.z) > 0.06 { current.append(p) }
    }

    private func finish() {
        guard !current.isEmpty else { return }
        defer { current.removeAll(keepingCapacity: true) }
        guard current.count >= 2 else { return }
        let k = Self.key(currentStart)
        if k != todayKey { todayKey = k; today = [] }
        let st = Stroke(time: currentStart, points: current)
        today.append(st)
        Self.append(st, to: Self.file(k))
    }

    // MARK: days

    /// Days that have a log, newest first.
    func days() -> [Date] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.dir.path)) ?? []
        var out = names.compactMap { $0.hasSuffix(".strokes") ? f.date(from: String($0.dropLast(8))) : nil }
        if !out.contains(where: { Calendar.current.isDateInToday($0) }) { out.append(Calendar.current.startOfDay(for: Date())) }
        return out.sorted(by: >)
    }

    func strokes(on day: Date) -> [Stroke] {
        Calendar.current.isDateInToday(day) ? today : Self.read(Self.file(Self.key(day)))
    }

    func delete(day: Date) {
        try? FileManager.default.removeItem(at: Self.file(Self.key(day)))
        if Calendar.current.isDateInToday(day) { today = [] }
        objectWillChange.send()
    }

    private func cleanup() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: Date()) ?? .distantPast
        for day in days() where day < cutoff { try? FileManager.default.removeItem(at: Self.file(Self.key(day))) }
    }

    // MARK: file format: per stroke Float64 time, UInt32 count, count × 3 Float32

    static func key(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    static func file(_ key: String) -> URL { dir.appendingPathComponent(key + ".strokes") }

    private static func append(_ s: Stroke, to url: URL) {
        var data = Data()
        var t = s.time.timeIntervalSince1970
        var n = UInt32(s.points.count)
        withUnsafeBytes(of: &t) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
        for p in s.points { var v = (p.x, p.y, p.z); withUnsafeBytes(of: &v) { data.append(contentsOf: $0.prefix(12)) } }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func read(_ url: URL) -> [Stroke] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var out: [Stroke] = []
        var o = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            while o + 12 <= raw.count {
                let t = raw.loadUnaligned(fromByteOffset: o, as: Double.self)
                let n = Int(raw.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self))
                o += 12
                guard n > 0, o + n * 12 <= raw.count else { break }
                var pts: [SIMD3<Float>] = []
                pts.reserveCapacity(n)
                for i in 0..<n {
                    let b = o + i * 12
                    pts.append(SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self),
                                     raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                                     raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self)))
                }
                o += n * 12
                out.append(Stroke(time: Date(timeIntervalSince1970: t), points: pts))
            }
        }
        return out
    }
}
