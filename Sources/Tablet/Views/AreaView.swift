import SwiftUI
import AppKit

struct AreaView: View {
    @EnvironmentObject var store: OTDStore
    @AppStorage("area.lockAspect") private var lockAspect = true
    @State private var screens: [ScreenInfo] = ScreenInfo.all()
    @EnvironmentObject var usage: UsageMap
    @EnvironmentObject var model: AppModel
    @State private var showHeat = true

    var body: some View {
        ScrollView { content }
    }

    private var content: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Card(title: L("Obrazovka")) {
                    Picker("Monitor", selection: displayChoice) {
                        ForEach(screens.indices, id: \.self) { i in Text(screens[i].name).tag(i) }
                        if screens.count > 1 { Text("Všechny").tag(-1) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    DisplayPreview(screens: screens, area: store.displayArea)
                        .frame(maxWidth: .infinity, minHeight: 240)
                    Text("\(Int(store.displayArea.width)) × \(Int(store.displayArea.height)) bodů")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Card(title: L("Plocha tabletu"), trailing: AnyView(Text("Táhněte obdélník").font(.system(size: 12)).foregroundStyle(Theme.secondary))) {
                    TabletAreaEditor(area: $store.tabletArea, full: store.fullTablet, heat: showHeat ? usage.cells : nil)
                        .frame(maxWidth: .infinity, minHeight: 240)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Velikost")
                            Spacer()
                            Text(String(format: "%.1f × %.1f mm", store.tabletArea.width, store.tabletArea.height)).foregroundStyle(Theme.secondary)
                        }
                        Slider(value: sizeBinding, in: 0.3...1)
                    }
                }
            }
            HStack(spacing: 12) {
                SettingRow(title: L("Zachovat poměr stran"), caption: L("Kruh na tabletu = kruh na obrazovce")) {
                    Toggle("", isOn: $lockAspect).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: L("Pro leváky"), caption: L("Otočit tablet o 180°")) {
                    Toggle("", isOn: Binding { store.tabletArea.rotation == 180 } set: { store.tabletArea.rotation = $0 ? 180 : 0 })
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: L("Celý tablet"), caption: L("Použít největší plochu")) {
                    Button("Obnovit") { fit(scale: 1, center: true) }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                SettingRow(title: L("Kde kreslíte"), caption: usage.total < 400 ? L("Aplikace si pamatuje, kam po tabletu kreslíte. Až bude dost tahů, navrhne menší a přesnější plochu.") : String(format: L("Zaznamenáno %d bodů tahů. Oranžová ukazuje, kam kreslíte nejčastěji."), usage.total)) {
                    HStack(spacing: 8) {
                        Toggle("Ukázat", isOn: $showHeat).toggleStyle(.checkbox)
                        Button("Navrhnout plochu") {
                            if let a = usage.suggestion(full: store.fullTablet, aspect: lockAspect && store.displayArea.height > 0 ? store.displayArea.width / store.displayArea.height : nil) {
                                var n = a; n.rotation = store.tabletArea.rotation
                                store.tabletArea = n
                            }
                        }
                        .disabled(usage.total < 400)
                        Menu {
                            Toggle("Zaznamenávat", isOn: $usage.enabled)
                            Button("Vymazat záznam", role: .destructive) { usage.reset() }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                }
            }
            if model.windowMapping != nil {
                Banner(text: L("Tablet je teď namapovaný jen na okno. Dalším stiskem tlačítka Plocha na okno se vrátí celá obrazovka."), button: L("Vrátit")) {
                    model.toggleWindowMapping()
                }
            }
        }
        .padding(24)
        .onChange(of: lockAspect) { _, on in if on { fit(scale: currentScale, center: false) } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = ScreenInfo.all() }
    }

    // MARK: display

    private var displayChoice: Binding<Int> {
        Binding {
            let a = store.displayArea
            return screens.firstIndex { abs($0.otd.width - a.width) < 1 && abs($0.otd.x - a.x) < 1 && abs($0.otd.y - a.y) < 1 } ?? -1
        } set: { i in
            store.displayArea = i >= 0 ? screens[i].otd : ScreenInfo.union(screens)
            if lockAspect { fit(scale: currentScale, center: false) }
        }
    }

    // MARK: tablet area

    private var currentScale: Double {
        let full = store.fullTablet
        return max(store.tabletArea.width / full.width, store.tabletArea.height / full.height)
    }

    private var sizeBinding: Binding<Double> {
        Binding { currentScale } set: { fit(scale: $0, center: false) }
    }

    /// Sets the largest area with the right aspect ratio at `scale`, keeping it inside the tablet.
    private func fit(scale: Double, center: Bool) {
        let full = store.fullTablet
        var a = store.tabletArea
        var w = full.width * scale, h = full.height * scale
        if lockAspect, store.displayArea.height > 0 {
            let r = store.displayArea.width / store.displayArea.height
            if w / h > r { w = h * r } else { h = w / r }
        }
        a.width = w; a.height = h
        if center { a.x = full.width / 2; a.y = full.height / 2 }
        a.x = min(max(a.x, w / 2), full.width - w / 2)
        a.y = min(max(a.y, h / 2), full.height - h / 2)
        store.tabletArea = a
    }
}

struct ScreenInfo {
    var name: String
    var otd: AreaRect   // OTD display area: size + centre in points, origin top-left of all screens

    static func all() -> [ScreenInfo] {
        let ss = NSScreen.screens
        guard !ss.isEmpty else { return [] }
        let union = ss.map(\.frame).reduce(ss[0].frame) { $0.union($1) }
        return ss.map { s in
            let f = s.frame
            return ScreenInfo(name: s.localizedName.replacingOccurrences(of: "Built-in Retina Display", with: "MacBook"),
                              otd: AreaRect(width: f.width, height: f.height,
                                            x: f.minX - union.minX + f.width / 2,
                                            y: union.maxY - f.maxY + f.height / 2))
        }
    }

    static func union(_ s: [ScreenInfo]) -> AreaRect {
        guard !s.isEmpty else { return AreaRect(width: 0, height: 0, x: 0, y: 0) }
        let minX = s.map { $0.otd.x - $0.otd.width / 2 }.min()!, maxX = s.map { $0.otd.x + $0.otd.width / 2 }.max()!
        let minY = s.map { $0.otd.y - $0.otd.height / 2 }.min()!, maxY = s.map { $0.otd.y + $0.otd.height / 2 }.max()!
        return AreaRect(width: maxX - minX, height: maxY - minY, x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}

struct DisplayPreview: View {
    var screens: [ScreenInfo]
    var area: AreaRect
    var body: some View {
        GeometryReader { g in
            let u = ScreenInfo.union(screens)
            let k = min(g.size.width / max(u.width, 1), g.size.height / max(u.height, 1)) * 0.9
            let ox = (g.size.width - u.width * k) / 2 - (u.x - u.width / 2) * k
            let oy = (g.size.height - u.height * k) / 2 - (u.y - u.height / 2) * k
            ZStack(alignment: .topLeading) {
                ForEach(screens.indices, id: \.self) { i in
                    let s = screens[i].otd
                    RoundedRectangle(cornerRadius: 6).fill(Theme.well)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0x4A4A4F), lineWidth: 2))
                        .frame(width: s.width * k, height: s.height * k)
                        .position(x: ox + s.x * k, y: oy + s.y * k)
                }
                RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, lineWidth: 2))
                    .frame(width: area.width * k, height: area.height * k)
                    .position(x: ox + area.x * k, y: oy + area.y * k)
            }
        }
        .padding(10)
        .background(Theme.stage, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TabletAreaEditor: View {
    @Binding var area: AreaRect
    var full: (width: Double, height: Double)
    /// Usage map cells (UsageMap.cols × rows) drawn over the tablet, nil = hidden.
    var heat: [Int]? = nil
    @State private var dragStart: AreaRect?

    var body: some View {
        GeometryReader { g in
            let full = self.full
            let k = min(g.size.width / full.width, g.size.height / full.height) * 0.92
            let ox = (g.size.width - full.width * k) / 2, oy = (g.size.height - full.height * k) / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0D0D0E))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x5A5A60), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: full.width * k, height: full.height * k)
                    .offset(x: ox, y: oy)
                if let heat, let peak = heat.max(), peak > 0 {
                    Canvas { ctx, size in
                        let cw = size.width / Double(UsageMap.cols), ch = size.height / Double(UsageMap.rows)
                        for (i, c) in heat.enumerated() where c > 0 {
                            let v = sqrt(Double(c) / Double(peak))
                            let r = CGRect(x: Double(i % UsageMap.cols) * cw, y: Double(i / UsageMap.cols) * ch, width: cw + 0.5, height: ch + 0.5)
                            ctx.fill(Path(r), with: .color(Color(hex: 0xFF9F0A).opacity(0.15 + v * 0.7)))
                        }
                    }
                    .frame(width: full.width * k, height: full.height * k)
                    .offset(x: ox, y: oy)
                    .allowsHitTesting(false)
                }
                RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 2))
                    .overlay(Text(String(format: "%.1f × %.1f mm", area.width, area.height)).fontWeight(.semibold))
                    .frame(width: area.width * k, height: area.height * k)
                    .position(x: ox + area.x * k, y: oy + area.y * k)
                    .gesture(DragGesture()
                        .onChanged { v in
                            let s = dragStart ?? area
                            dragStart = s
                            var a = area
                            a.x = min(max(s.x + v.translation.width / k, a.width / 2), full.width - a.width / 2)
                            a.y = min(max(s.y + v.translation.height / k, a.height / 2), full.height - a.height / 2)
                            area = a
                        }
                        .onEnded { _ in dragStart = nil })
            }
        }
        .padding(10)
        .background(Theme.stage, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Plocha tabletu")
    }
}
