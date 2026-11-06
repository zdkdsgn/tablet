import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// White paper with every stroke of the chosen day, drawn where it was on the tablet. Can replay and export.
struct StrokesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: OTDStore
    @AppStorage("strokes.byTime") private var byTime = false
    @AppStorage("strokes.showArea") private var showArea = true
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var replay: Double?          // 0…1 while replaying
    @State private var timer: Timer?
    @State private var confirmDelete = false

    var body: some View {
        StrokesContent(log: model.strokeLog, day: $day, byTime: $byTime, showArea: $showArea,
                       replay: $replay, confirmDelete: $confirmDelete,
                       full: store.fullTablet, area: store.tabletArea,
                       startReplay: startReplay, stopReplay: stopReplay)
            .onDisappear { stopReplay() }
    }

    private func startReplay(count: Int) {
        stopReplay()
        guard count > 0 else { return }
        let duration = min(14, max(3, Double(count) * 0.03))
        let start = Date()
        replay = 0
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let p = Date().timeIntervalSince(start) / duration
                if p >= 1 { stopReplay() } else { replay = p }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopReplay() { timer?.invalidate(); timer = nil; replay = nil }
}

private struct StrokesContent: View {
    @ObservedObject var log: StrokeLog
    @Binding var day: Date
    @Binding var byTime: Bool
    @Binding var showArea: Bool
    @Binding var replay: Double?
    @Binding var confirmDelete: Bool
    var full: (width: Double, height: Double)
    var area: AreaRect
    var startReplay: (Int) -> Void
    var stopReplay: () -> Void
    /// Past days are read from disk once; today comes live from the log.
    @State private var past: [Stroke] = []

    private var strokes: [Stroke] { Calendar.current.isDateInToday(day) ? log.today : past }

    var body: some View {
        let strokes = self.strokes
        let days = log.days()
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                dayPicker(days)
                Spacer()
                stats(strokes)
            }
            StrokeCanvas(strokes: strokes, full: full, area: showArea ? area : nil, byTime: byTime, progress: replay)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if strokes.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "scribble").font(.system(size: 30)).foregroundStyle(Color(white: 0.75))
                            Text(Calendar.current.isDateInToday(day) ? L("Dnes zatím nic. Vezměte pero a čmárejte!") : L("Tento den nejsou žádné tahy."))
                                .foregroundStyle(Color(white: 0.55))
                        }
                    }
                }
            HStack(spacing: 10) {
                Button { replay == nil ? startReplay(strokes.count) : stopReplay() } label: {
                    Label(replay == nil ? L("Přehrát") : L("Zastavit"), systemImage: replay == nil ? "play.fill" : "stop.fill")
                }
                .disabled(strokes.isEmpty)
                Toggle("Barvy podle času", isOn: $byTime).toggleStyle(.checkbox)
                Toggle("Ukázat plochu", isOn: $showArea).toggleStyle(.checkbox)
                Spacer()
                Toggle("Zaznamenávat tahy", isOn: $log.enabled).toggleStyle(.checkbox)
                Button { export(strokes) } label: { Label("Uložit obrázek…", systemImage: "square.and.arrow.down") }
                    .disabled(strokes.isEmpty)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .disabled(strokes.isEmpty)
                    .help(L("Smazat tahy tohoto dne"))
                    .confirmationDialog(L("Smazat tahy tohoto dne?"), isPresented: $confirmDelete) {
                        Button("Smazat", role: .destructive) { stopReplay(); log.delete(day: day) }
                    }
            }
            Text(String(format: L("Tahy zůstávají jen v tomto Macu a po %d dnech se samy mažou."), StrokeLog.keepDays))
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .onChange(of: day, initial: true) { _, d in past = Calendar.current.isDateInToday(d) ? [] : log.strokes(on: d) }
        .onChange(of: confirmDelete) { _, open in if !open && !Calendar.current.isDateInToday(day) { past = log.strokes(on: day) } }
    }

    private func dayPicker(_ days: [Date]) -> some View {
        let i = days.firstIndex { Calendar.current.isDate($0, inSameDayAs: day) }
        return HStack(spacing: 6) {
            Button { if let i, i + 1 < days.count { stopReplay(); day = days[i + 1] } } label: { Image(systemName: "chevron.left") }
                .disabled(i == nil || i! + 1 >= days.count)
            Text(dayTitle).font(.system(size: 15, weight: .semibold)).frame(minWidth: 150)
            Button { if let i, i > 0 { stopReplay(); day = days[i - 1] } } label: { Image(systemName: "chevron.right") }
                .disabled(i == nil || i! == 0)
            if !Calendar.current.isDateInToday(day) {
                Button("Dnes") { stopReplay(); day = Calendar.current.startOfDay(for: Date()) }
            }
        }
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(day) { return L("Dnes") }
        if Calendar.current.isDateInYesterday(day) { return L("Včera") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func stats(_ s: [Stroke]) -> some View {
        let length = s.reduce(0.0) { acc, st in
            var l = 0.0
            for i in 1..<max(st.points.count, 1) where i < st.points.count {
                let a = st.points[i - 1], b = st.points[i]
                l += Double(hypot(b.x - a.x, b.y - a.y))
            }
            return acc + l
        }
        let first = s.first?.time, last = s.last?.time
        return HStack(spacing: 16) {
            stat("\(s.count)", L("tahů"))
            stat(PenOdometer.format(length), L("délka"))
            if let first, let last {
                stat("\(first.formatted(date: .omitted, time: .shortened))–\(last.formatted(date: .omitted, time: .shortened))", L("čas"))
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(v).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            Text(l).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
    }

    private func export(_ strokes: [Stroke]) {
        let w = 2400.0, h = w * full.height / full.width
        let view = StrokeCanvas(strokes: strokes, full: full, area: nil, byTime: byTime, progress: nil, paperOnly: true)
            .frame(width: w / 2, height: h / 2)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let cg = r.cgImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(format: L("Tahy %@.png"), StrokeLog.key(day))
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// The paper and the strokes. Line width follows pressure; colours optionally go from morning blue to evening orange.
struct StrokeCanvas: View {
    var strokes: [Stroke]
    var full: (width: Double, height: Double)
    var area: AreaRect?
    var byTime: Bool
    var progress: Double?
    var paperOnly = false

    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width / full.width, g.size.height / full.height)
            let pw = full.width * k, ph = full.height * k
            let flip = (area?.rotation ?? 0) == 180
            ZStack {
                RoundedRectangle(cornerRadius: paperOnly ? 0 : 6).fill(Color.white)
                    .shadow(color: .black.opacity(paperOnly ? 0 : 0.25), radius: 10, y: 4)
                Canvas { ctx, size in
                    func pt(_ p: SIMD3<Float>) -> CGPoint {
                        let x = Double(p.x) * k, y = Double(p.y) * k
                        return flip ? CGPoint(x: size.width - x, y: size.height - y) : CGPoint(x: x, y: y)
                    }
                    if let a = area {
                        let r = CGRect(x: (a.x - a.width / 2) * k, y: (a.y - a.height / 2) * k, width: a.width * k, height: a.height * k)
                        let rr = flip ? CGRect(x: size.width - r.maxX, y: size.height - r.maxY, width: r.width, height: r.height) : r
                        ctx.stroke(Path(roundedRect: rr, cornerRadius: 3), with: .color(Color(white: 0.85)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    // replay: whole strokes up to the progress point, then part of the current one
                    let total = strokes.count
                    let shown = progress.map { $0 * Double(total) } ?? Double(total)
                    let t0 = strokes.first?.time.timeIntervalSince1970 ?? 0
                    let span = max(1, (strokes.last?.time.timeIntervalSince1970 ?? 0) - t0)
                    for (i, s) in strokes.enumerated() {
                        if Double(i) >= shown { break }
                        let frac = min(1, shown - Double(i))
                        let n = frac >= 1 ? s.points.count : max(2, Int(Double(s.points.count) * frac))
                        let color: Color = byTime
                            ? Color(hue: 0.62 - 0.55 * (s.time.timeIntervalSince1970 - t0) / span, saturation: 0.75, brightness: 0.8)
                            : Color(white: 0.1)
                        // segments grouped into 6 pressure levels → a few paths per stroke instead of one per segment
                        var buckets = [Path](repeating: Path(), count: 6)
                        for j in 1..<min(n, s.points.count) {
                            let a = s.points[j - 1], b = s.points[j]
                            let lvl = min(5, Int(Double(a.z + b.z) / 2 * 6))
                            buckets[lvl].move(to: pt(a)); buckets[lvl].addLine(to: pt(b))
                        }
                        for (lvl, path) in buckets.enumerated() where !path.isEmpty {
                            let pr = (Double(lvl) + 0.5) / 6
                            ctx.stroke(path, with: .color(color.opacity(0.55 + pr * 0.45)),
                                       style: StrokeStyle(lineWidth: max(0.6, (0.25 + pr * 1.1) * k * 0.9), lineCap: .round, lineJoin: .round))
                        }
                    }
                }
            }
            .frame(width: pw, height: ph)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .accessibilityLabel(L("Nakreslené tahy"))
    }
}
