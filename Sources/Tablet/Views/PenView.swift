import SwiftUI
import AppKit

struct PenView: View {
    @EnvironmentObject var store: OTDStore
    @State private var pressure: Double = 0
    @State private var clearToken = 0

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                Card(title: "Vyzkoušet", trailing: AnyView(Button("Vymazat") { clearToken += 1 }.controlSize(.small))) {
                    PressurePad(pressure: $pressure, clearToken: clearToken)
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: 10) {
                        Text("Tlak").foregroundStyle(Color(hex: 0xC7C7CC)).frame(width: 60, alignment: .leading)
                        ProgressView(value: pressure).tint(Theme.accent)
                        Text("\(Int(pressure * 100)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Card(title: "Citlivost hrotu") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Práh dotyku hrotu"); Spacer(); Text("\(Int(store.tipThreshold)) %").foregroundStyle(Theme.secondary) }
                        Slider(value: $store.tipThreshold, in: 0...30, step: 1)
                        Text("Jak silně musíte přitlačit, než pero začne kreslit.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    HStack(spacing: 12) {
                        Toggle("Tlak", isOn: Binding { !store.disablePressure } set: { store.disablePressure = !$0 })
                        Toggle("Náklon", isOn: Binding { !store.disableTilt } set: { store.disableTilt = !$0 })
                    }
                    .toggleStyle(.checkbox)
                }
            }
            ScrollView {
                VStack(spacing: 20) {
                    Card(title: "Horní tlačítko pera") {
                        ActionEditor(action: $store.penButtons[1], defaultAction: .adaptive("Button 2"))
                    }
                    Card(title: "Dolní tlačítko pera") {
                        ActionEditor(action: $store.penButtons[0], defaultAction: .adaptive("Button 1"))
                    }
                    Card(title: "Guma") {
                        ActionEditor(action: $store.eraser, defaultAction: .adaptive("Eraser"), defaultTitle: "Guma")
                    }
                }
            }
            .frame(width: 400)
        }
        .padding(24)
    }
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
                let t = "Kreslete sem perem" as NSString
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
