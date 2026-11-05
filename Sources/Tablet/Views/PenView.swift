import SwiftUI
import AppKit

struct PenView: View {
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var pen: PenFilters
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("Práh dotyku hrotu"); Spacer(); Text("\(Int(store.tipThreshold)) %").foregroundStyle(Theme.secondary) }
                            Slider(value: $store.tipThreshold, in: 0...30, step: 1)
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
