import SwiftUI
import AppKit

struct PenView: View {
    @EnvironmentObject var behaviour: KeyBehaviour
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var pen: PenFilters
    @EnvironmentObject var model: AppModel
    @State private var pressure: Double = 0
    @State private var clearToken = 0

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(spacing: 20) {
                    Card(title: L("Křivka tlaku"), trailing: AnyView(presetButtons)) {
                        PressureCurveEditor(gamma: $pen.gamma, maxInput: pen.maxInput, live: pressure)
                            .frame(height: 220)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Plný tlak při"); Spacer(); Text("\(Int(pen.maxInput * 100)) % přítlaku").foregroundStyle(Theme.secondary) }
                            Slider(value: $pen.maxInput, in: 0.5...1, step: 0.05)
                            Text("Táhněte bod v grafu. Nahoru = měkčí pero, dolů = tvrdší.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                    }
                    Card(title: L("Vyzkoušet"), trailing: AnyView(Button("Vymazat") { clearToken += 1 }.controlSize(.small))) {
                        PressurePad(pressure: $pressure, clearToken: clearToken)
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        HStack(spacing: 10) {
                            Text("Tlak").foregroundStyle(Color(hex: 0xC7C7CC)).frame(width: 60, alignment: .leading)
                            ProgressView(value: pressure).tint(Theme.accent)
                            Text("\(Int(pressure * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                    PenCheckCard(hover: model.penHover, profiles: model.penProfiles)
                    OdometerCard(odo: model.odometer)
                    AchievementsCard(ach: model.achievements)
                    PensCard(profiles: model.penProfiles, odo: model.odometer)
                }
            }
            ScrollView {
                VStack(spacing: 20) {
                    Card(title: L("Tah")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Vyhlazení"); Spacer(); Text(pen.smoothing == 0 ? L("Vypnuto") : "\(Int(pen.smoothing))").foregroundStyle(Theme.secondary) }
                            Slider(value: $pen.smoothing, in: 0...10, step: 1)
                            Text("Tlumí chvění ruky. Vyšší hodnota = klidnější, ale lehce opožděná čára.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Přesný režim"); Spacer(); Text("\(Int((1 / pen.precisionScale).rounded()))× jemnější").foregroundStyle(Theme.secondary) }
                            Slider(value: Binding { 1 - pen.precisionScale } set: { pen.precisionScale = 1 - $0 }, in: 0.4...0.85)
                            Text("Zapnete ho podržením ExpressKey s funkcí Přesný režim (obrazovka Tablet).").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        TipThresholdSetting(threshold: $store.tipThreshold, hover: model.penHover)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Klidné klepnutí"); Spacer() }
                            Picker("", selection: $pen.calmTap) {
                                Text("Vypnuto").tag(0); Text("Slabě").tag(1); Text("Středně").tag(2); Text("Silně").tag(3)
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            Text("Po dotyku hrotu kurzor chvilku stojí, takže ťuknutí klikne a netáhne. Silněji = klidnější klikání, ale začátek čáry se o kousek opozdí.")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        HStack(spacing: 12) {
                            Toggle("Tlak", isOn: Binding { !store.disablePressure } set: { store.disablePressure = !$0 })
                            Toggle("Náklon", isOn: Binding { !store.disableTilt } set: { store.disableTilt = !$0 })
                        }
                        .toggleStyle(.checkbox)
                    }
                    Card(title: L("Horní tlačítko pera")) {
                        ActionEditor(action: $store.penButtons[1], defaultAction: .adaptive("Button 2"))
                    }
                    Card(title: L("Dolní tlačítko pera")) {
                        ActionEditor(action: $store.penButtons[0], defaultAction: .adaptive("Button 1"))
                    }
                    Card(title: L("Guma")) {
                        ActionEditor(action: $store.eraser, defaultAction: .adaptive("Eraser"), defaultTitle: L("Guma"))
                        SettingRow(title: L("Přepínat nástroj"), caption: L("Otočíte pero gumou dolů a aplikace dostane klávesu gumy, otočíte zpět a dostane klávesu štětce")) {
                            Toggle("", isOn: $behaviour.eraserSwitch).labelsHidden().toggleStyle(.switch)
                        }
                        if behaviour.eraserSwitch {
                            HStack { Text("Guma").frame(width: 70, alignment: .leading); CompactRecorder(keys: $behaviour.eraserKeys) }
                            HStack { Text("Hrot").frame(width: 70, alignment: .leading); CompactRecorder(keys: $behaviour.penKeys) }
                        }
                    }
                }
            }
            .frame(width: 400)
        }
        .padding(24)
    }

    private var presetButtons: some View {
        HStack(spacing: 2) {
            ForEach(PenFilters.presets, id: \.0) { name, g in
                Button(L(name)) { pen.gamma = g }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(abs(pen.gamma - g) < 0.01 ? Color(hex: 0x47474D) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .font(.system(size: 12))
            }
        }
        .padding(2)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// How hard the tip must press before it counts as a click, with a live check of the last tap.
struct TipThresholdSetting: View {
    @Binding var threshold: Double
    @ObservedObject var hover: PenHover
    @State private var shownPeak: Double?
    @State private var fade: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Citlivost klepnutí hrotem")
                Spacer()
                Text(levelName + " · " + "\(Int(threshold)) %").monospacedDigit().foregroundStyle(Theme.secondary)
            }
            Slider(value: Binding { threshold } set: { threshold = $0.rounded() }, in: 0...60) {
                EmptyView()
            } minimumValueLabel: {
                Text("Citlivé").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } maximumValueLabel: {
                Text("Pevné").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            // meter: the last tap's strongest pressure against the threshold
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.well)
                    if let p = shownPeak {
                        Capsule().fill(p * 100 > threshold ? Theme.ok : Color(hex: 0xFF9F0A))
                            .frame(width: max(6, w * p))
                    }
                    Rectangle().fill(Color.primary.opacity(0.8)).frame(width: 2, height: 14)
                        .offset(x: w * threshold / 100 - 1)
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            .animation(.snappy(duration: 0.2), value: shownPeak)
            .animation(.snappy(duration: 0.2), value: threshold)
            Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .onReceive(hover.$lastPeak.compactMap { $0 }) { p in
            shownPeak = p
            fade?.cancel()
            let w = DispatchWorkItem { shownPeak = nil }
            fade = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
        }
    }

    private var levelName: String {
        switch threshold { case ..<3: return L("Velmi citlivé"); case ..<10: return L("Citlivé"); case ..<25: return L("Střední"); default: return L("Pevné") }
    }

    private var caption: String {
        guard let p = shownPeak else {
            return L("Jak silně musíte hrotem přitlačit, aby to bylo kliknutí. Ťukněte perem na tablet a uvidíte, jestli ťuk projde (čárka = práh).")
        }
        return p * 100 > threshold
            ? String(format: L("Ťuk %d %% – kliknutí ✓. Má-li lehký dotyk neklikat, posuňte práh nad něj."), Int(p * 100))
            : String(format: L("Ťuk %d %% – pod prahem, žádné kliknutí."), Int(p * 100))
    }
}

/// Graph of output = (input / maxInput)^gamma with a draggable midpoint and the live pressure.
struct PressureCurveEditor: View {
    @Binding var gamma: Double
    var maxInput: Double
    var live: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let pt = { (x: Double, y: Double) in CGPoint(x: x * w, y: (1 - y) * h) }
            let midY = PenFilters.curve(0.5 * maxInput, gamma: gamma, maxInput: maxInput)
            ZStack {
                Path { p in
                    for i in 1..<4 {
                        let f = Double(i) / 4
                        p.move(to: pt(f, 0)); p.addLine(to: pt(f, 1))
                        p.move(to: pt(0, f)); p.addLine(to: pt(1, f))
                    }
                }
                .stroke(Theme.border, lineWidth: 1)
                Path { p in p.move(to: pt(0, 0)); p.addLine(to: pt(1, 1)) }
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Path { p in
                    p.move(to: pt(0, 0))
                    for i in 1...80 {
                        let x = Double(i) / 80
                        p.addLine(to: pt(x, PenFilters.curve(x, gamma: gamma, maxInput: maxInput)))
                    }
                }
                .stroke(Theme.accent, lineWidth: 3)
                if live > 0 {   // where the pen is right now (output pressure)
                    Circle().fill(Color.white).frame(width: 8, height: 8)
                        .position(pt(curveInverse(live), live))
                }
                Circle().fill(Theme.window).overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                    .frame(width: 18, height: 18)
                    .position(pt(0.5 * maxInput, midY))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let y = min(max(1 - v.location.y / h, 0.05), 0.95)
                        gamma = min(max(log(y) / log(0.5), 0.25), 4)
                    })
            }
            .background(Theme.stage, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Křivka tlaku")
    }

    private func curveInverse(_ out: Double) -> Double { pow(out, 1 / gamma) * maxInput }
}

/// A sketch pad that shows the pressure macOS receives from the pen.
struct PressurePad: NSViewRepresentable {
    @Binding var pressure: Double
    var clearToken: Int

    func makeNSView(context: Context) -> PadView {
        let v = PadView()
        v.onPressure = { pressure = $0 }
        return v
    }
    func updateNSView(_ v: PadView, context: Context) {
        if v.clearToken != clearToken { v.clearToken = clearToken; v.strokes.removeAll(); v.needsDisplay = true }
    }

    final class PadView: NSView {
        var onPressure: ((Double) -> Void)?
        var clearToken = 0
        var strokes: [[(CGPoint, CGFloat)]] = []
        override var isFlipped: Bool { true }
        override func draw(_ r: NSRect) {
            NSColor(red: 0.957, green: 0.957, blue: 0.945, alpha: 1).setFill()
            bounds.fill()
            NSColor(red: 0.106, green: 0.106, blue: 0.114, alpha: 1).setStroke()
            for s in strokes where s.count > 1 {
                for i in 1..<s.count {
                    let p = NSBezierPath()
                    p.lineCapStyle = .round
                    p.lineWidth = 0.5 + s[i].1 * 12
                    p.move(to: s[i - 1].0); p.line(to: s[i].0); p.stroke()
                }
            }
            if strokes.isEmpty {
                let t = L("Kreslete sem perem") as NSString
                let a: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.gray, .font: NSFont.systemFont(ofSize: 13)]
                let sz = t.size(withAttributes: a)
                t.draw(at: CGPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2), withAttributes: a)
            }
        }
        override func mouseDown(with e: NSEvent) { strokes.append([]); add(e) }
        override func mouseDragged(with e: NSEvent) { add(e) }
        override func mouseUp(with e: NSEvent) { onPressure?(0) }
        private func add(_ e: NSEvent) {
            let p = convert(e.locationInWindow, from: nil)
            let pr = CGFloat(e.subtype == .tabletPoint || e.pressure > 0 ? e.pressure : 1)
            strokes[strokes.count - 1].append((p, pr))
            onPressure?(Double(pr))
            needsDisplay = true
        }
    }
}

/// Live pen check straight from the tablet: height above the surface, tilt, pressure.
struct PenCheckCard: View {
    @ObservedObject var hover: PenHover
    @ObservedObject var profiles: PenProfiles

    var body: some View {
        Card(title: L("Kontrola pera"), trailing: AnyView(Text(penName).font(.system(size: 12)).foregroundStyle(Theme.secondary))) {
            HStack(alignment: .center, spacing: 24) {
                tiltGauge.frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 12) {
                    meter(L("Výška nad tabletem"), value: hover.sample.map { 1 - $0.distance } ?? 0,
                          text: hover.sample.map { $0.pressure > 0 ? L("dotýká se") : String(format: L("%d %% dosahu"), Int(($0.distance * 100).rounded())) } ?? "–")
                    meter(L("Přítlak"), value: hover.pressure, text: hover.sample == nil ? "–" : "\(Int(hover.pressure * 100)) %")
                    meter(L("Náklon"), value: tiltAmount / 60,
                          text: hover.sample == nil ? "–" : String(format: "%.0f°", tiltAmount))
                }
            }
            Text(hover.sample == nil ? L("Přiložte pero nad tablet – ukáže se, co tablet právě měří.") : L("Hodnoty přímo z tabletu. Výška je přibližná, tablet pero cítí asi do 1 cm."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }

    private var penName: String {
        guard let c = profiles.current, let p = profiles.pens.first(where: { $0.serial == c }) else { return "" }
        return p.name
    }

    private var tiltAmount: Double {
        guard let s = hover.sample else { return 0 }
        return min(60, hypot(s.tiltX, s.tiltY))
    }

    /// Top view: the dot moves the way the pen leans.
    private var tiltGauge: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            let s = hover.sample
            let p = CGPoint(x: r + (s?.tiltX ?? 0) / 64 * r * 0.9, y: r + (s?.tiltY ?? 0) / 64 * r * 0.9)
            ZStack {
                Circle().fill(Theme.well)
                Circle().strokeBorder(Theme.line, lineWidth: 1).padding(r * 0.33)
                Circle().strokeBorder(Theme.line, lineWidth: 1)
                Path { $0.move(to: CGPoint(x: r, y: 4)); $0.addLine(to: CGPoint(x: r, y: 2 * r - 4)); $0.move(to: CGPoint(x: 4, y: r)); $0.addLine(to: CGPoint(x: 2 * r - 4, y: r)) }
                    .stroke(Theme.line, lineWidth: 1)
                if s != nil {
                    Path { $0.move(to: CGPoint(x: r, y: r)); $0.addLine(to: p) }.stroke(Theme.warn, lineWidth: 2)
                    Circle().fill(Theme.warn).frame(width: 12, height: 12).position(p)
                }
                Circle().fill(Theme.secondary).frame(width: 5, height: 5)
            }
            .frame(width: 2 * r, height: 2 * r)
            .animation(.linear(duration: 0.05), value: s?.tiltX)
        }
        .accessibilityLabel(L("Náklon pera"))
    }

    private func meter(_ title: String, value: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(text).monospacedDigit().foregroundStyle(Theme.secondary) }
            ProgressView(value: min(max(value, 0), 1)).tint(Theme.warn)
        }
    }
}

/// Pens the tablet has seen (by serial number) and the per-pen settings switch.
struct PensCard: View {
    @ObservedObject var profiles: PenProfiles
    @ObservedObject var odo: PenOdometer
    @State private var editing: String?
    @State private var draft = ""

    var body: some View {
        Card(title: L("Moje pera")) {
            SettingRow(title: L("Nastavení pro každé pero zvlášť"), caption: L("Křivka tlaku, vyhlazení, tlačítka a guma se pamatují pro každé pero podle jeho sériového čísla")) {
                Toggle("", isOn: $profiles.perPen).labelsHidden().toggleStyle(.switch)
            }
            if profiles.pens.isEmpty {
                Text("Zatím žádné pero. Přiložte pero k tabletu.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach(profiles.pens.sorted { $0.lastSeen > $1.lastSeen }) { p in
                HStack(spacing: 10) {
                    Image(systemName: "pencil.tip").foregroundStyle(p.serial == profiles.current ? Theme.accent : Theme.secondary).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        if editing == p.serial {
                            TextField("", text: $draft).textFieldStyle(.roundedBorder)
                                .onSubmit { profiles.rename(p.serial, to: draft); editing = nil }
                        } else {
                            Text(p.name).fontWeight(.medium)
                        }
                        Text("\(p.kind) · č. \(p.serial)" + (odo.perPen[p.serial].map { " · " + PenOdometer.format($0) } ?? ""))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if p.serial == profiles.current {
                        Text("V ruce").font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.18), in: Capsule()).foregroundStyle(Theme.accent)
                    }
                    Menu {
                        Button("Přejmenovat") { draft = p.name; editing = p.serial }
                        Button("Zapomenout", role: .destructive) { profiles.forget(p.serial) }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// How far the pen has travelled, with silly comparisons.
struct OdometerCard: View {
    @ObservedObject var odo: PenOdometer
    @State private var confirmReset = false

    var body: some View {
        Card(title: L("Počítadlo pera"), trailing: AnyView(
            Button("Vynulovat") { confirmReset = true }.controlSize(.small)
                .confirmationDialog(L("Vynulovat počítadlo pera?"), isPresented: $confirmReset) {
                    Button("Vynulovat", role: .destructive) { odo.reset() }
                })) {
            HStack(alignment: .top, spacing: 12) {
                stat(L("Dnes nakresleno"), PenOdometer.format(odo.today), "calendar")
                stat(L("Celkem nakresleno"), PenOdometer.format(odo.drawn), "scribble.variable")
            }
            HStack(alignment: .top, spacing: 12) {
                stat(L("Tahů"), odo.strokes.formatted(), "hand.draw")
                stat(L("Nad tabletem ve vzduchu"), PenOdometer.format(odo.hovered), "wind")
            }
            VStack(alignment: .leading, spacing: 4) {
                if let c = PenOdometer.comparison(odo.drawn) {
                    Text(String(format: L("To je jako %@."), c)).fontWeight(.medium)
                } else {
                    Text("Zatím ani délka tužky. Do toho!").fontWeight(.medium)
                }
                Text(PenOdometer.pencilUsed(odo.drawn)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.warn).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Unlocked / locked achievements.
struct AchievementsCard: View {
    @ObservedObject var ach: Achievements
    @State private var confirmReset = false

    var body: some View {
        Card(title: L("Úspěchy"), trailing: AnyView(
            HStack(spacing: 8) {
                Text("\(ach.count) / \(Achievements.all.count)").monospacedDigit().foregroundStyle(Theme.secondary)
                Menu {
                    Button("Začít znovu", role: .destructive) { confirmReset = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .confirmationDialog(L("Smazat všechny úspěchy?"), isPresented: $confirmReset) {
                Button("Smazat", role: .destructive) { ach.reset() }
            })) {
            ProgressView(value: Double(ach.count), total: Double(Achievements.all.count)).tint(Theme.warn)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(Achievements.all) { a in tile(a) }
            }
        }
    }

    private func tile(_ a: Achievements.Def) -> some View {
        let on = ach.isUnlocked(a.id)
        let hidden = a.secret && !on
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                ZStack {
                    Circle().fill(on ? Theme.warn.opacity(0.2) : Theme.control).frame(width: 30, height: 30)
                    Image(systemName: hidden ? "questionmark" : a.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Theme.warn : Theme.secondary)
                }
                Spacer()
                if let d = ach.unlocked[a.id] {
                    Text(d.formatted(date: .numeric, time: .omitted)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                } else {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.secondary.opacity(0.6))
                }
            }
            Text(hidden ? "???" : L(a.title)).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(hidden ? L("Tajný úspěch – přijdete na něj sami.") : L(a.detail))
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.warn.opacity(0.45) : .clear))
        .opacity(on ? 1 : 0.75)
        .help(hidden ? "" : L(a.detail))
    }
}
