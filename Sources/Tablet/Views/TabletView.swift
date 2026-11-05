import SwiftUI

struct TabletView: View {
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var zoom: ZoomSettings
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var lights: LightSettings
    @EnvironmentObject var labels: KeyLabels
    static let ring = 100
    @State private var selected = 0          // ExpressKey index, or TabletView.ring
    @State private var ringTab = 0           // 0 Režimy, 1 Nastavení, 2 Tlačítko
    @State private var logoTaps = 0

    var body: some View {
        HStack(spacing: 0) {
            TabletStage(selected: $selected, logoTap: logoTapped)
                .background(Theme.stage)
            inspector
                .frame(width: 320)
                .background(Color(hex: 0x1F1F22))
                .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
        }
    }

    private func logoTapped() {
        logoTaps += 1
        if logoTaps >= 5 {
            logoTaps = 0
            lights.easterEggUnlocked = true
            model.lights.play(.spin)
        }
    }

    // MARK: - Inspector

    @ViewBuilder private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if selected == Self.ring { ringInspector } else if selected < store.aux.count { keyInspector } else { Text("Vyberte tlačítko v kresbě tabletu.").foregroundStyle(Theme.secondary) }
            }
            .padding(20)
        }
    }

    @ViewBuilder private var keyInspector: some View {
        header("ExpressKey \(selected + 1)", labels.name(selected, for: store.aux[selected]))
        VStack(alignment: .leading, spacing: 6) {
            Text("Název").foregroundStyle(Color(hex: 0xC7C7CC))
            TextField(KeyLabels.autoName(store.aux[selected]), text: $labels.names[selected])
                .textFieldStyle(.roundedBorder)
            Text("Nechte prázdné a název se vezme ze zkratky.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Co tlačítko dělá").foregroundStyle(Color(hex: 0xC7C7CC))
            Picker("Co tlačítko dělá", selection: appActionBinding) {
                Text("Zkratka nebo myš").tag(AppKeyAction.none)
                Divider()
                ForEach(AppKeyAction.allCases.filter { $0 != .none }) { a in
                    Label(a.title, systemImage: a.symbol).tag(a)
                }
            }
            .labelsHidden()
            if labels.appAction(selected) == .none {
                ActionEditor(action: $store.aux[selected])
            } else {
                Text(labels.appAction(selected).caption).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        if labels.appAction(selected) == .radial {
            VStack(alignment: .leading, spacing: 8) {
                Text("Položky kruhového menu").foregroundStyle(Color(hex: 0xC7C7CC))
                RadialEditor()
                Text("1 je nahoře, dál po směru hodin.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        SettingRow(title: L("Ukázat název při stisku"), caption: L("Krátké oznámení na obrazovce")) {
            Toggle("", isOn: $labels.showOnPress).labelsHidden().toggleStyle(.switch)
        }
        if store.tablet.enhanced {
            SettingRow(title: L("Express View"), caption: L("Při položení prstu na tlačítka ukáže, co dělají")) {
                Toggle("", isOn: $labels.expressView).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    @ViewBuilder private var ringInspector: some View {
        if store.tablet.enhanced {
            header("Touch Ring", zoom.smooth ? zoom.mode.title : ringTitle)
            Picker("Sekce", selection: $ringTab) {
                Text("Režimy").tag(0)
                Text("Nastavení").tag(1)
                Text("Tlačítko").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch ringTab {
            case 0: ringModes
            case 1: ringSettings
            default: ringButton
            }
        } else {
            header("Kolečko", ringTitle)
            otdRingEditors
            VStack(alignment: .leading, spacing: 8) {
                Text("Tlačítko kolečka").foregroundStyle(Color(hex: 0xC7C7CC))
                ActionEditor(action: $store.wheelButton)
            }
        }
    }

    @ViewBuilder private var ringModes: some View {
        SettingRow(title: L("Plynulý zoom a režimy"), caption: L("Kolečko ovládá aplikace Tablet")) {
            Toggle("", isOn: smoothBinding).labelsHidden().toggleStyle(.switch)
        }
        if zoom.smooth {
            VStack(spacing: 6) {
                ForEach(RingMode.allCases) { m in
                    Button { zoom.mode = m; model.updateRingLED() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: m.symbol).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.title)
                                Text(m.caption).font(.system(size: 11)).opacity(0.8)
                            }
                            Spacer()
                            Button { zoom.toggleInCycle(m); model.updateRingLED() } label: {
                                Image(systemName: zoom.cycle.contains(m) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15))
                            }
                            .buttonStyle(.plain)
                            .help("Zařadit do přepínání tlačítkem (nejvýš 4 – kolečko má 4 světýlka)")
                            .accessibilityLabel(zoom.cycle.contains(m) ? L("V cyklu tlačítka") : L("Mimo cyklus tlačítka"))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(zoom.mode == m ? Theme.accent : Theme.well, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(zoom.mode == m ? .white : Color(hex: 0xE4E4E8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(zoom.buttonCycles ? L("Zaškrtnuté režimy (nejvýš 4) střídá tlačítko uprostřed kolečka. Otáčení plátna funguje ve Photoshopu.") : L("Přepínání tlačítkem je vypnuté (záložka Tlačítko)."))
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        } else {
            Text("Kolečko teď posílá zkratky přes OpenTabletDriver – nastavíte je v záložce Nastavení.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder private var ringSettings: some View {
        if zoom.smooth {
            VStack(alignment: .leading, spacing: 8) {
                Text("Klávesa pro zoom").foregroundStyle(Color(hex: 0xC7C7CC))
                Picker("Klávesa pro zoom", selection: $zoom.modifier) {
                    ForEach(["auto", "alt", "cmd", "ctrl", "none"], id: \.self) { Text(ZoomSettings.title($0)).tag($0) }
                }
                .labelsHidden()
                Text("Automaticky: ⌥ v aplikacích Adobe, bez klávesy v Blenderu, jinde ⌘ (Figma, Affinity…).")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Rychlost"); Spacer(); Text("\(Int(zoom.speed))").foregroundStyle(Theme.secondary) }
                Slider(value: $zoom.speed, in: 1...10, step: 1)
                Text("Platí pro zoom i posouvání.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Plynulost"); Spacer(); Text("\(Int(zoom.smoothing))").foregroundStyle(Theme.secondary) }
                Slider(value: $zoom.smoothing, in: 1...10, step: 1)
                Text("Vyšší = víc dobíhá, nižší = reaguje okamžitě.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Toggle("Obrátit směr", isOn: $zoom.invert).toggleStyle(.checkbox)
        } else {
            otdRingEditors
        }
    }

    /// Ring bindings sent by OpenTabletDriver (when this app does not handle the ring itself).
    @ViewBuilder private var otdRingEditors: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("↻ Po směru hodin").foregroundStyle(Color(hex: 0xC7C7CC))
                ActionEditor(action: $store.wheelCW)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("↺ Proti směru").foregroundStyle(Color(hex: 0xC7C7CC))
                ActionEditor(action: $store.wheelCCW)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Citlivost"); Spacer(); Text("1 krok / \(Int(store.wheelStep))°").foregroundStyle(Theme.secondary) }
                Slider(value: $store.wheelStep, in: 1...30, step: 1)
                Text("Menší číslo = víc kroků na jednu otáčku.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Button("Nastavit zoom klávesami") { setKeyZoom() }
    }

    @ViewBuilder private var ringButton: some View {
        if zoom.smooth {
            SettingRow(title: L("Přepíná režim kolečka"), caption: L("Režim ukazují světýlka na kolečku")) {
                Toggle("", isOn: cycleBinding).labelsHidden().toggleStyle(.switch)
            }
        }
        if !(zoom.smooth && zoom.buttonCycles) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Akce tlačítka uprostřed").foregroundStyle(Color(hex: 0xC7C7CC))
                ActionEditor(action: $store.wheelButton)
            }
        }
    }

    // MARK: - Helpers

    /// Choosing an app function hands the key to this app, so OpenTabletDriver must not also act on it.
    private var appActionBinding: Binding<AppKeyAction> {
        Binding { labels.appAction(selected) } set: { a in
            labels.appActions[selected] = a.rawValue
            if a != .none { store.aux[selected] = .none }
        }
    }

    /// Smooth zoom is done by this app, so OpenTabletDriver must stop sending the ring's keys (and vice versa).
    private var smoothBinding: Binding<Bool> {
        Binding { zoom.smooth } set: { on in
            zoom.smooth = on
            if on {
                store.wheelCW = .none; store.wheelCCW = .none
                if zoom.buttonCycles { store.wheelButton = .none }
            } else { setKeyZoom() }
            model.updateRingLED()
        }
    }

    /// While the centre button cycles modes, OpenTabletDriver must not also act on it.
    private var cycleBinding: Binding<Bool> {
        Binding { zoom.buttonCycles } set: { on in
            zoom.buttonCycles = on
            if on { store.wheelButton = .none }
        }
    }

    private func setKeyZoom() {
        store.wheelCW = .keys(["Application", "Add"])
        store.wheelCCW = .keys(["Application", KeyNames.keyName(typing: "-") ?? "Slash"])
    }

    private var ringTitle: String {
        if case .keys(let k) = store.wheelCW, k.contains("Add") { return L("Zoom") }
        return "\(store.wheelCW.title) / \(store.wheelCCW.title)"
    }

    private func header(_ over: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(over.uppercased()).font(.system(size: 11)).tracking(0.6).foregroundStyle(Theme.secondary)
            Text(title).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Tablet drawing

/// The tablet drawn to scale (body ≈ 380 × 251 mm for the Intuos Pro M; others use their active area + margins) with callout labels on the left.
private struct TabletStage: View {
    @Binding var selected: Int
    var logoTap: () -> Void
    @EnvironmentObject var store: OTDStore
    @EnvironmentObject var zoom: ZoomSettings
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var lights: LightSettings
    @EnvironmentObject var labels: KeyLabels

    /// Body proportions: exact for the Intuos Pro M, else derived from the active area and the key strip.
    private var ratio: Double {
        let t = store.tablet
        if t.model == "PTH-651" { return 380.0 / 251.0 }
        let areaFrac = store.aux.isEmpty ? 0.89 : 0.75
        return (t.width / areaFrac) / (t.height / 0.82)
    }
    private let labelWidth = 150.0

    var body: some View {
        GeometryReader { g in
            let availW = g.size.width - labelWidth - 56
            let w = max(300, min(availW, (g.size.height - 64) * ratio))
            let h = w / ratio
            let ox = (g.size.width - (w + labelWidth + 24)) / 2 + labelWidth + 24
            let oy = (g.size.height - h) / 2
            let geo = Geometry(w: w, h: h, ox: ox, oy: oy, keys: store.aux.count, wheel: store.tablet.hasWheel)

            ZStack(alignment: .topLeading) {
                ForEach(0..<store.aux.count, id: \.self) { i in callout(i, geo) }
                if store.tablet.hasWheel { callout(ringAt: geo) }
                body(geo)
                activeArea(geo)
                ForEach(0..<store.aux.count, id: \.self) { i in key(i, geo) }
                if store.tablet.hasWheel { ring(geo) }
            }
        }
    }

    struct Geometry {
        var w, h, ox, oy: Double
        var keys: Int = 8
        var wheel: Bool = true
        // everything in the key column is sized from the height, so it always fits the body
        var ringD: Double { wheel ? h * 0.19 : 0 }
        var gap: Double { h * 0.02 }
        var top: Int { wheel ? (keys + 1) / 2 : keys }      // keys above the ring
        var keyH: Double {
            let n = Double(max(keys, 1))
            return min(h * 0.09, (h * 0.84 - ringD - gap * (n - 2 + (wheel ? 4.4 : 0))) / n)
        }
        var keyW: Double { max(keyH * 1.9, w * 0.072) }
        var stripX: Double { ox + w * 0.035 }
        var ringCenter: CGPoint { CGPoint(x: stripX + keyW / 2, y: oy + h / 2) }
        func keyCenter(_ i: Int) -> CGPoint {
            let x = stripX + keyW / 2
            guard wheel else {   // one centred column
                let total = Double(keys) * keyH + Double(keys - 1) * gap
                return CGPoint(x: x, y: oy + (h - total) / 2 + keyH / 2 + Double(i) * (keyH + gap))
            }
            let ringHalf = ringD / 2 + gap * 2.2
            if i < top {
                let fromRing = Double(top - 1 - i)            // the last top key is nearest the ring
                return CGPoint(x: x, y: oy + h / 2 - ringHalf - keyH / 2 - fromRing * (keyH + gap))
            } else {
                let fromRing = Double(i - top)
                return CGPoint(x: x, y: oy + h / 2 + ringHalf + keyH / 2 + fromRing * (keyH + gap))
            }
        }
        var area: CGRect {
            let left = keys > 0 ? 0.2 : 0.06
            return CGRect(x: ox + w * left, y: oy + h * 0.09, width: w * (0.95 - left), height: h * 0.82)
        }
    }

    private func body(_ g: Geometry) -> some View {
        RoundedRectangle(cornerRadius: g.w * 0.045)
            .fill(LinearGradient(colors: [Color(hex: 0x19191B), Color(hex: 0x0B0B0C)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: g.w * 0.045).stroke(Color(hex: 0x3A3A3E)))
            .overlay(alignment: .top) {   // light edge along the top
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(height: 2).padding(.horizontal, g.w * 0.06).padding(.top, 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .frame(width: g.w, height: g.h)
            .offset(x: g.ox, y: g.oy)
    }

    private func activeArea(_ g: Geometry) -> some View {
        let r = g.area
        let cornerOn = lights.cornersEnabled
        let cornerColor = cornerOn ? Color.white.opacity([0.5, 0.75, 1.0][lights.cornerBrightness.rawValue]) : Color(hex: 0x4A4A4F)
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x111113))
            CornerMarks(color: cornerColor, glow: cornerOn)
            Text("wacom").font(.system(size: max(10, g.w * 0.018), weight: .medium)).tracking(0.5)
                .foregroundStyle(Color(hex: 0x6E6E73))
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture(perform: logoTap)
        }
        .frame(width: r.width, height: r.height)
        .offset(x: r.minX, y: r.minY)
    }

    private func key(_ i: Int, _ g: Geometry) -> some View {
        let c = g.keyCenter(i)
        let on = selected == i
        let pressed = model.pressedKey == i
        return Button { selected = i } label: {
            Text(labels.appAction(i) == .none ? short(store.aux[i]) : labels.appAction(i).title)
                .font(.system(size: max(10, g.w * 0.019), weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .frame(width: g.keyW, height: g.keyH)
                .background(on ? Theme.accent : Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(pressed ? Color.white : (on ? Theme.accent : Color(hex: 0x3F3F44)), lineWidth: pressed ? 2 : 1))
                .foregroundStyle(on ? .white : Color(hex: 0xC7C7CC))
        }
        .buttonStyle(.plain)
        .position(c)
        .accessibilityLabel("ExpressKey \(i + 1): \(labels.name(i, for: store.aux[i]))")
    }

    private func ring(_ g: Geometry) -> some View {
        let c = g.ringCenter
        let on = selected == TabletView.ring
        let lit = lights.enabled ? (zoom.smooth ? zoom.ledIndex : 0) : -1
        let ledOpacity = [0.55, 0.8, 1.0][lights.brightness.rawValue]
        return ZStack {
            Button { selected = TabletView.ring } label: {
                Circle()
                    .fill(Color(hex: 0x141416))
                    .overlay(Circle().stroke(on ? Theme.accent : Color(hex: 0x3F3F44), lineWidth: 3))
                    .overlay(Circle().fill(Color(hex: 0x1D1D20)).overlay(Circle().stroke(Color(hex: 0x4A4A4F))).frame(width: g.ringD * 0.38, height: g.ringD * 0.38))
                    .frame(width: g.ringD, height: g.ringD)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Touch Ring")
            // four status LEDs on an arc to the right of the ring
            ForEach(0..<4, id: \.self) { i in
                let angle = Angle.degrees(-45 + Double(i) * 30)
                let rad = g.ringD / 2 + max(7, g.ringD * 0.16)
                Circle()
                    .fill(i == lit ? Color.white.opacity(ledOpacity) : Color(hex: 0x2E2E32))
                    .shadow(color: i == lit ? .white.opacity(0.7) : .clear, radius: 4)
                    .frame(width: max(5, g.ringD * 0.07), height: max(5, g.ringD * 0.07))
                    .offset(x: cos(angle.radians) * rad, y: sin(angle.radians) * rad)
                    .accessibilityHidden(true)
            }
        }
        .position(c)
    }

    private func callout(_ i: Int, _ g: Geometry) -> some View {
        let c = g.keyCenter(i)
        let app = labels.appAction(i)
        return Callout(title: labels.name(i, for: store.aux[i]), subtitle: app == .none ? store.aux[i].title : L("Funkce aplikace"),
                       selected: selected == i, pressed: model.pressedKey == i,
                       width: labelWidth, lineTo: c.x - g.keyW / 2 - (g.ox - labelWidth - 24) - labelWidth)
            .position(x: g.ox - 24 - labelWidth / 2, y: c.y)
            .onTapGesture { selected = i }
    }

    private func callout(ringAt g: Geometry) -> some View {
        let c = g.ringCenter
        let title = zoom.smooth ? zoom.mode.title : (store.wheelCW == .none ? "Touch Ring" : "Kolečko: \(store.wheelCW.title)")
        let sub = zoom.smooth ? (zoom.buttonCycles ? L("Tlačítko přepíná režim") : zoom.mode.caption) : L("Zkratky přes OpenTabletDriver")
        return Callout(title: title, subtitle: sub, selected: selected == TabletView.ring, pressed: false,
                       width: labelWidth, lineTo: c.x - g.ringD / 2 - (g.ox - labelWidth - 24) - labelWidth)
            .position(x: g.ox - 24 - labelWidth / 2, y: c.y)
            .onTapGesture { selected = TabletView.ring }
    }

    private func short(_ a: BindingAction) -> String {
        switch a {
        case .none: return "—"
        case .keys(let k): return k == ["Space"] ? "␣" : KeyNames.display(k)
        case .mouse(let b): return ["Left": L("Klik"), "Right": L("P. klik"), "Middle": L("Stř.")][b] ?? L("Myš")
        default: return a.title
        }
    }
}

/// Right-aligned label with a leader line running right to the control.
private struct Callout: View {
    var title: String
    var subtitle: String
    var selected: Bool
    var pressed: Bool
    var width: Double
    var lineTo: Double     // length of the leader line beyond the label's right edge

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Circle().fill(selected || pressed ? Theme.accent : Color(hex: 0x4A4A4F)).frame(width: 5, height: 5)
        }
        .foregroundStyle(selected ? .white : Color(hex: 0xD6D6DA))
        .frame(width: width)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(selected || pressed ? Theme.accent.opacity(0.8) : Color(hex: 0x3A3A3E))
                .frame(width: max(0, lineTo - 4), height: 1)
                .offset(x: max(0, lineTo - 4))
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
    }
}

struct CornerMarks: View {
    var color: Color = Color(hex: 0x4A4A4F)
    var glow = false
    var body: some View {
        GeometryReader { g in
            let s: CGFloat = 14, inset: CGFloat = 10
            Path { p in
                p.move(to: CGPoint(x: inset, y: inset + s)); p.addLine(to: CGPoint(x: inset, y: inset)); p.addLine(to: CGPoint(x: inset + s, y: inset))
                p.move(to: CGPoint(x: g.size.width - inset - s, y: inset)); p.addLine(to: CGPoint(x: g.size.width - inset, y: inset)); p.addLine(to: CGPoint(x: g.size.width - inset, y: inset + s))
                p.move(to: CGPoint(x: inset, y: g.size.height - inset - s)); p.addLine(to: CGPoint(x: inset, y: g.size.height - inset)); p.addLine(to: CGPoint(x: inset + s, y: g.size.height - inset))
                p.move(to: CGPoint(x: g.size.width - inset - s, y: g.size.height - inset)); p.addLine(to: CGPoint(x: g.size.width - inset, y: g.size.height - inset)); p.addLine(to: CGPoint(x: g.size.width - inset, y: g.size.height - inset - s))
            }
            .stroke(color, lineWidth: 2)
            .shadow(color: glow ? color.opacity(0.8) : .clear, radius: 4)
        }
        .accessibilityHidden(true)
    }
}
