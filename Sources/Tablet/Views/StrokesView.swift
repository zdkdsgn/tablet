import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// White paper with every stroke of the chosen day, drawn where it was on the tablet. Can replay and export.
struct StrokesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: OTDStore
    @AppStorage("strokes.byTime") private var byTime = false
    @AppStorage("strokes.showArea") private var showArea = true
    @AppStorage("strokes.showTaps") private var showTaps = true
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var replay: Double?          // 0…1 while replaying
    @State private var timer: Timer?
    @State private var confirmDelete = false

    var body: some View {
        StrokesContent(log: model.strokeLog, day: $day, byTime: $byTime, showArea: $showArea, showTaps: $showTaps,
                       threshold: store.tipThreshold / 100,
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
    @Binding var showTaps: Bool
    var threshold: Double
    @Binding var replay: Double?
    @Binding var confirmDelete: Bool
    var full: (width: Double, height: Double)
    var area: AreaRect
    var startReplay: (Int) -> Void
    var stopReplay: () -> Void
    /// Past days are read from disk once; today comes live from the log.
    @State private var past: [Stroke] = []
    @State private var pastTaps: [Tap] = []
    @State private var hovered: Tap.ID?

    private var strokes: [Stroke] { Calendar.current.isDateInToday(day) ? log.today : past }
    private var taps: [Tap] { Calendar.current.isDateInToday(day) ? log.todayTaps : pastTaps }

    var body: some View {
        let strokes = self.strokes
        let taps = self.taps
        let days = log.days()
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                dayPicker(days)
                Spacer()
                stats(strokes, taps)
            }
            HStack(alignment: .top, spacing: 16) {
            StrokeCanvas(strokes: strokes, full: full, area: showArea ? area : nil, byTime: byTime, progress: replay,
                         taps: showTaps ? taps : [], highlighted: hovered)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if strokes.isEmpty && taps.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "scribble").font(.system(size: 30)).foregroundStyle(Color(white: 0.75))
                            Text(Calendar.current.isDateInToday(day) ? L("Dnes zatím nic. Vezměte pero a čmárejte!") : L("Tento den nejsou žádné tahy."))
                                .foregroundStyle(Color(white: 0.55))
                        }
                    }
                }
                if showTaps {
                    TapsPanel(taps: taps, threshold: threshold, hovered: $hovered)
                        .frame(width: 300)
                }
            }
            HStack(spacing: 10) {
                Button { replay == nil ? startReplay(strokes.count) : stopReplay() } label: {
                    Label(replay == nil ? L("Přehrát") : L("Zastavit"), systemImage: replay == nil ? "play.fill" : "stop.fill")
                }
                .disabled(strokes.isEmpty)
                Toggle("Barvy podle času", isOn: $byTime).toggleStyle(.checkbox)
                Toggle("Ukázat plochu", isOn: $showArea).toggleStyle(.checkbox)
                Toggle("Ťuky", isOn: $showTaps).toggleStyle(.checkbox)
                Spacer()
                Toggle("Zaznamenávat tahy", isOn: $log.enabled).toggleStyle(.checkbox)
                Button { export(strokes) } label: { Label("Uložit obrázek…", systemImage: "square.and.arrow.down") }
                    .disabled(strokes.isEmpty)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .disabled(strokes.isEmpty && taps.isEmpty)
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
        .onChange(of: day, initial: true) { _, d in
            let today = Calendar.current.isDateInToday(d)
            past = today ? [] : log.strokes(on: d)
            pastTaps = today ? [] : log.taps(on: d)
        }
        .onChange(of: confirmDelete) { _, open in
            if !open && !Calendar.current.isDateInToday(day) { past = log.strokes(on: day); pastTaps = log.taps(on: day) }
        }
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

    private func stats(_ s: [Stroke], _ taps: [Tap]) -> some View {
        let length = s.reduce(0.0) { acc, st in
            var l = 0.0
            for i in 1..<max(st.points.count, 1) where i < st.points.count {
                let a = st.points[i - 1], b = st.points[i]
                l += Double(hypot(b.x - a.x, b.y - a.y))
            }
            return acc + l
        }
        let times = s.map(\.time) + taps.map(\.time)
        let first = times.min(), last = times.max()
        return HStack(spacing: 16) {
            stat("\(s.count)", L("tahů"))
            stat("\(taps.count)", L("ťuků"))
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
    var taps: [Tap] = []
    var highlighted: Tap.ID?

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
                    // taps: a dot sized by pressure – blue = clicked, orange = too light to click
                    let until: Date? = progress.map { _ in
                        let idx = min(total - 1, max(0, Int(shown) - 1))
                        return total > 0 ? strokes[idx].time : .distantFuture
                    }
                    for t in taps {
                        if let until, t.time > until { continue }
                        let c = pt(SIMD3(t.x, t.y, 0))
                        let r = max(2.5, Double(0.5 + t.peak * 1.6) * k)
                        let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        let tint = t.clicked ? Color(red: 0.18, green: 0.44, blue: 0.87) : Color(red: 1, green: 0.58, blue: 0.04)
                        ctx.fill(dot, with: .color(tint.opacity(t.clicked ? 0.45 : 0.15)))
                        ctx.stroke(dot, with: .color(tint), lineWidth: 1)
                        if t.id == highlighted {
                            let R = r + 6
                            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)),
                                       with: .color(tint), lineWidth: 2)
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

/// Taps of the day: how long and how hard, against the click threshold.
private struct TapsPanel: View {
    var taps: [Tap]
    var threshold: Double
    @Binding var hovered: Tap.ID?

    var body: some View {
        let clicks = taps.filter(\.clicked).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ťuky").font(.system(size: 14, weight: .semibold))
                Spacer()
                if !taps.isEmpty {
                    Text(String(format: L("%d kliknutí · %d pod prahem"), clicks, taps.count - clicks))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            if taps.isEmpty {
                Text("Ťuknutí hrotem na místě se tu objeví i s délkou a silou.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                chart.frame(height: 150)
                summary
                Divider().overlay(Theme.line)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(taps.reversed()) { t in row(t) }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    /// Length (x) against strength (y); the dashed line is today's click threshold.
    private var chart: some View {
        let maxDur = max(0.5, min(2, Double(taps.map(\.duration).max() ?? 0.5)))
        return VStack(spacing: 3) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(Theme.well))
                for f in [0.25, 0.5, 0.75] {
                    var g = Path(); g.move(to: CGPoint(x: 0, y: h * f)); g.addLine(to: CGPoint(x: w, y: h * f))
                    ctx.stroke(g, with: .color(.primary.opacity(0.06)), lineWidth: 1)
                }
                let ty = h * (1 - threshold)
                var line = Path(); line.move(to: CGPoint(x: 0, y: ty)); line.addLine(to: CGPoint(x: w, y: ty))
                ctx.stroke(line, with: .color(.primary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                for t in taps {
                    // square-root scale: quick taps (tens of ms) spread out instead of piling up at the left edge
                    let x = min(w - 4, max(4, w * sqrt(min(1, Double(t.duration) / maxDur))))
                    let y = min(h - 4, max(4, h * (1 - Double(t.peak))))
                    let r: CGFloat = t.id == hovered ? 5.5 : 3
                    let c = t.clicked ? Theme.accent : Theme.warn
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(c.opacity(t.id == hovered ? 1 : 0.75)))
                }
            }
            HStack {
                Text("0")
                Spacer()
                Text(Self.duration(Float(maxDur / 4)))
                Spacer()
                Text(Self.duration(Float(maxDur)) + (taps.contains { Double($0.duration) > maxDur } ? "+" : ""))
            }
            .font(.system(size: 9)).foregroundStyle(Theme.secondary).monospacedDigit()
        }
        .overlay(alignment: .topLeading) {
            Text("síla ↑ · délka →").font(.system(size: 9)).foregroundStyle(Theme.secondary).padding(5)
        }
    }

    private var summary: some View {
        let n = Float(taps.count)
        let avgDur = taps.reduce(0) { $0 + $1.duration } / n
        let avgPeak = taps.reduce(0) { $0 + $1.peak } / n
        return HStack(spacing: 14) {
            item(Self.duration(avgDur), L("průměrná délka"))
            item("\(Int((avgPeak * 100).rounded())) %", L("průměrná síla"))
            item("\(Int(((taps.map(\.peak).max() ?? 0) * 100).rounded())) %", L("nejsilnější"))
        }
    }

    private func item(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Text(l).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }

    private func row(_ t: Tap) -> some View {
        HStack(spacing: 8) {
            Text(t.time.formatted(.dateTime.hour().minute().second())).monospacedDigit()
                .foregroundStyle(Theme.secondary).frame(width: 62, alignment: .leading)
            Text(Self.duration(t.duration)).monospacedDigit().frame(width: 52, alignment: .trailing)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.well)
                    Capsule().fill(t.clicked ? Theme.accent : Theme.warn).frame(width: max(4, g.size.width * CGFloat(t.peak)))
                    Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 1.5, height: 10)
                        .offset(x: g.size.width * CGFloat(t.threshold))
                }
                .frame(height: 6).frame(maxHeight: .infinity)
            }
            Text("\(Int((t.peak * 100).rounded())) %").monospacedDigit().frame(width: 38, alignment: .trailing)
            Image(systemName: t.clicked ? "cursorarrow.click" : "minus.circle")
                .foregroundStyle(t.clicked ? Theme.accent : Theme.warn)
                .help(t.clicked ? L("Kliknutí") : L("Pod prahem – bez kliknutí"))
        }
        .font(.system(size: 11))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(hovered == t.id ? Theme.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? t.id : (hovered == t.id ? nil : hovered) }
    }

    static func duration(_ s: Float) -> String {
        s < 1 ? "\(Int((s * 1000).rounded())) ms" : String(format: "%.1f s", s)
    }
}
