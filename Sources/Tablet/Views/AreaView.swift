import SwiftUI
import AppKit

struct AreaView: View {
    @EnvironmentObject var store: OTDStore
    @AppStorage("area.lockAspect") private var lockAspect = true
    @State private var screens: [ScreenInfo] = ScreenInfo.all()
    @EnvironmentObject var usage: UsageMap
    @EnvironmentObject var model: AppModel
    @State private var showHeat = true
    @State private var previewSuggestion = false
    @State private var editingSize = false

    var body: some View {
        ScrollView { content }
    }

    private var aspect: Double? {
        lockAspect && store.displayArea.height > 0 ? store.displayArea.width / store.displayArea.height : nil
    }

    private var suggestion: AreaRect? {
        guard usage.total >= 400, var a = usage.suggestion(full: store.fullTablet, aspect: aspect) else { return nil }
        a.rotation = store.tabletArea.rotation
        return a
    }

    private var content: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                Card(title: L("Obrazovka"), trailing: screens.count == 1 ? AnyView(Text(screens[0].name).font(.system(size: 12)).foregroundStyle(Theme.secondary)) : nil) {
                    if screens.count > 1 { Picker("Monitor", selection: displayChoice) {
                        ForEach(screens.indices, id: \.self) { i in Text(screens[i].name).tag(i) }
                        if screens.count > 1 { Text("Všechny").tag(-1) }
                    }
                    .pickerStyle(.segmented).labelsHidden() }
                    DisplayPreview(screens: screens, area: store.displayArea, tabletArea: store.tabletArea, pen: model.penHover,
                                   onSelect: { displayChoice.wrappedValue = $0 })
                        .frame(maxWidth: .infinity, minHeight: 290)
                }
                Card(title: L("Plocha tabletu"), trailing: AnyView(Text("Táhněte obdélník nebo rohy · šipky posouvají").font(.system(size: 12)).foregroundStyle(Theme.secondary))) {
                    TabletAreaEditor(area: $store.tabletArea, full: store.fullTablet, heat: showHeat ? usage.cells : nil,
                                     ghost: previewSuggestion ? suggestion : nil, pen: model.penHover,
                                     onEditSize: { editingSize = true })
                        .frame(maxWidth: .infinity, minHeight: 290)
                        .popover(isPresented: $editingSize, arrowEdge: .bottom) {
                            SizeEditor(area: store.tabletArea, full: store.fullTablet, aspect: aspect) { w, h in
                                store.checkpoint(String(format: L("Plocha %.0f × %.0f mm"), w, h))
                                withAnimation(.snappy) { setSize(w, h) }
                                editingSize = false
                            }
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Velikost")
                            Spacer()
                            Button { editingSize = true } label: {
                                HStack(spacing: 4) {
                                    Text(String(format: "%.1f × %.1f mm", store.tabletArea.width, store.tabletArea.height))
                                    Image(systemName: "pencil").font(.system(size: 10))
                                }
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                            .help(L("Zadat přesné rozměry"))
                        }
                        Slider(value: sizeBinding, in: 0.3...1)
                    }
                }
            }
            HStack(spacing: 12) {
                SettingRow(title: L("Zachovat poměr stran"), caption: distortionCaption) {
                    Toggle("", isOn: $lockAspect).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: L("Pro leváky"), caption: L("Otočit tablet o 180°")) {
                    Toggle("", isOn: Binding { store.tabletArea.rotation == 180 } set: { store.tabletArea.rotation = $0 ? 180 : 0 })
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: L("Rychlé nastavení"), caption: L("Celý tablet, nebo skutečná velikost: 1 cm tahu = 1 cm na displeji")) {
                    HStack(spacing: 6) {
                        Button("Celý") {
                            store.checkpoint(L("Celý tablet"))
                            withAnimation(.snappy) { fit(scale: 1, center: true) }
                        }
                        Button("1 : 1") { realSize() }
                            .help(L("Skutečná velikost"))
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                SettingRow(title: L("Kde kreslíte"), caption: usage.total < 400 ? L("Aplikace si pamatuje, kam po tabletu kreslíte. Až bude dost tahů, navrhne menší a přesnější plochu.") : String(format: L("Zaznamenáno %d bodů tahů. Oranžová ukazuje, kam kreslíte nejčastěji."), usage.total)) {
                    HStack(spacing: 8) {
                        Toggle("Ukázat", isOn: $showHeat).toggleStyle(.checkbox)
                        Button("Navrhnout plochu") {
                            if let a = suggestion {
                                previewSuggestion = false
                                store.checkpoint(L("Plocha podle kreslení"))
                                withAnimation(.snappy) { store.tabletArea = a }
                            }
                        }
                        .disabled(suggestion == nil)
                        .onHover { previewSuggestion = $0 }
                        .help(L("Najeďte myší pro náhled navržené plochy"))
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
        .onChange(of: lockAspect) { _, on in if on { withAnimation(.snappy) { fit(scale: currentScale, center: false) } } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in screens = ScreenInfo.all() }
    }

    /// With the aspect lock off: how much a circle drawn on the tablet gets stretched on the screen.
    private var distortionCaption: String {
        let t = store.tabletArea, d = store.displayArea
        guard !lockAspect, t.height > 0, d.height > 0 else { return L("Kruh na tabletu = kruh na obrazovce") }
        let r = (d.width / d.height) / (t.width / t.height) - 1
        if abs(r) < 0.01 { return L("Poměr stran teď sedí – kruh zůstane kruhem") }
        return String(format: r > 0 ? L("Pozor: kruh bude o %d %% širší") : L("Pozor: kruh bude o %d %% užší"), Int((abs(r) * 100).rounded()))
    }

    /// 1 mm of pen movement = 1 mm on the display (physical size from the display's EDID).
    private func realSize() {
        let d = store.displayArea
        let s = screens.first { abs($0.otd.width - d.width) < 1 && abs($0.otd.x - d.x) < 1 && abs($0.otd.y - d.y) < 1 } ?? screens.first
        guard let mmPerPt = s?.mmPerPoint, mmPerPt > 0 else {
            model.hud.showMessage(symbol: "questionmark.circle", title: L("Velikost displeje není známá"), subtitle: nil); return
        }
        let full = store.fullTablet
        var w = d.width * mmPerPt, h = d.height * mmPerPt
        let shrink = min(1, full.width / w, full.height / h)
        w *= shrink; h *= shrink
        store.checkpoint(L("Skutečná velikost 1 : 1"))
        withAnimation(.snappy) { setSize(w, h) }
        if shrink < 0.999 {
            model.hud.showMessage(symbol: "arrow.down.right.and.arrow.up.left", title: L("Displej je větší než tablet"),
                                  subtitle: String(format: L("Použito %d %% skutečné velikosti"), Int(shrink * 100)))
        }
    }

    private func setSize(_ w: Double, _ h: Double) {
        let full = store.fullTablet
        var a = store.tabletArea
        a.width = min(w, full.width); a.height = min(h, full.height)
        a.x = min(max(a.x, a.width / 2), full.width - a.width / 2)
        a.y = min(max(a.y, a.height / 2), full.height - a.height / 2)
        store.tabletArea = a
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
    var builtin = false
    var wallpaper: NSImage?
    /// Physical millimetres per point (0 = unknown).
    var mmPerPoint: Double = 0

    static func all() -> [ScreenInfo] {
        let ss = NSScreen.screens
        guard !ss.isEmpty else { return [] }
        let union = ss.map(\.frame).reduce(ss[0].frame) { $0.union($1) }
        return ss.map { s in
            let f = s.frame
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ScreenInfo(name: s.localizedName.replacingOccurrences(of: "Built-in Retina Display", with: "MacBook"),
                              otd: AreaRect(width: f.width, height: f.height,
                                            x: f.minX - union.minX + f.width / 2,
                                            y: union.maxY - f.maxY + f.height / 2),
                              builtin: CGDisplayIsBuiltin(id) != 0,
                              wallpaper: NSWorkspace.shared.desktopImageURL(for: s).flatMap { thumbnail($0) },
                              mmPerPoint: f.width > 0 ? CGDisplayScreenSize(id).width / f.width : 0)
        }
    }

    /// Small copy of the desktop picture (wallpapers are often huge HEICs).
    private static func thumbnail(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: 640,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func union(_ s: [ScreenInfo]) -> AreaRect {
        guard !s.isEmpty else { return AreaRect(width: 0, height: 0, x: 0, y: 0) }
        let minX = s.map { $0.otd.x - $0.otd.width / 2 }.min()!, maxX = s.map { $0.otd.x + $0.otd.width / 2 }.max()!
        let minY = s.map { $0.otd.y - $0.otd.height / 2 }.min()!, maxY = s.map { $0.otd.y + $0.otd.height / 2 }.max()!
        return AreaRect(width: maxX - minX, height: maxY - minY, x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}

/// The screens drawn as a MacBook / monitors with their wallpapers; the mapped part is outlined.
struct DisplayPreview: View {
    var screens: [ScreenInfo]
    var area: AreaRect
    var tabletArea: AreaRect? = nil
    var pen: PenHover? = nil
    var onSelect: ((Int) -> Void)? = nil
    @State private var hovered: Int?

    var body: some View {
        GeometryReader { g in
            let u = ScreenInfo.union(screens)
            // room below the screens for the MacBook base / monitor stand
            let foot = u.height * 0.16
            let k = min(g.size.width / max(u.width, 1), g.size.height / max(u.height + foot, 1)) * 0.86
            let ox = (g.size.width - u.width * k) / 2 - (u.x - u.width / 2) * k
            let oy = (g.size.height - (u.height + foot) * k) / 2 - (u.y - u.height / 2) * k
            let sel = CGRect(x: ox + (area.x - area.width / 2) * k, y: oy + (area.y - area.height / 2) * k,
                             width: area.width * k, height: area.height * k)

            ZStack(alignment: .topLeading) {
                ForEach(screens.indices, id: \.self) { i in
                    let s = screens[i]
                    let r = CGRect(x: ox + (s.otd.x - s.otd.width / 2) * k, y: oy + (s.otd.y - s.otd.height / 2) * k,
                                   width: s.otd.width * k, height: s.otd.height * k)
                    let mapped = sel.insetBy(dx: -1, dy: -1).contains(r.insetBy(dx: 2, dy: 2)) || r.intersects(sel.insetBy(dx: 2, dy: 2))
                    device(s, rect: r, mapped: mapped, hovered: hovered == i)
                        .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                        .onTapGesture { onSelect?(i) }
                }

                // mapped area
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.10)))
                    .frame(width: sel.width, height: sel.height)
                    .offset(x: sel.minX, y: sel.minY)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                    .allowsHitTesting(false)

                Text(String(format: L("%d × %d bodů"), Int(area.width), Int(area.height)))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .position(x: sel.midX, y: sel.maxY - 14)
                    .allowsHitTesting(false)

                if let pen, let t = tabletArea {
                    PenDot(pen: pen) { mm in
                        let d = PenDot.screenPoint(mm: mm, tablet: t, display: area)
                        return CGPoint(x: ox + d.x * k, y: oy + d.y * k)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .padding(10)
        .background(Theme.stage, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Obrazovka")
    }

    @ViewBuilder
    private func device(_ s: ScreenInfo, rect r: CGRect, mapped: Bool, hovered: Bool) -> some View {
        let bezel = max(3, r.width * 0.018)
        ZStack(alignment: .topLeading) {
            // stand / base (behind)
            if s.builtin {
                // MacBook base: a wide thin wedge under the screen
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(LinearGradient(colors: [Color(hex: 0x4A4A50), Color(hex: 0x2A2A2E)], startPoint: .top, endPoint: .bottom))
                    .frame(width: r.width * 1.16 + bezel * 2, height: max(5, r.height * 0.045))
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                            .fill(Color(hex: 0x1E1E22)).frame(width: r.width * 0.18, height: max(2, r.height * 0.015))
                    }
                    .offset(x: r.minX - bezel - r.width * 0.08, y: r.maxY + bezel)
            } else {
                Path { p in
                    let top = r.maxY + bezel, w = r.width * 0.16, h = r.height * 0.11
                    p.move(to: CGPoint(x: r.midX - w * 0.35, y: top))
                    p.addLine(to: CGPoint(x: r.midX + w * 0.35, y: top))
                    p.addLine(to: CGPoint(x: r.midX + w * 0.45, y: top + h))
                    p.addLine(to: CGPoint(x: r.midX - w * 0.45, y: top + h))
                    p.closeSubpath()
                    p.addRoundedRect(in: CGRect(x: r.midX - w, y: top + h, width: w * 2, height: max(3, h * 0.18)), cornerSize: CGSize(width: 2, height: 2))
                }
                .fill(Color(hex: 0x3A3A40))
            }

            // bezel
            RoundedRectangle(cornerRadius: bezel * 2.2)
                .fill(Color(hex: 0x0A0A0B))
                .overlay(RoundedRectangle(cornerRadius: bezel * 2.2).strokeBorder(Color.white.opacity(hovered ? 0.3 : 0.12), lineWidth: 1))
                .frame(width: r.width + bezel * 2, height: r.height + bezel * 2)
                .offset(x: r.minX - bezel, y: r.minY - bezel)

            // screen content
            ZStack(alignment: .top) {
                if let w = s.wallpaper {
                    Image(nsImage: w).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color(hex: 0x2B3A67), Color(hex: 0x6B4E8A), Color(hex: 0xC97B63)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Rectangle().fill(.black.opacity(0.35)).frame(height: max(3, r.height * 0.035))  // menu bar
                if !mapped { Rectangle().fill(.black.opacity(0.55)) }
            }
            .frame(width: r.width, height: r.height)
            .clipShape(RoundedRectangle(cornerRadius: bezel))
            .offset(x: r.minX, y: r.minY)

            if screens.count > 1 {
                Text(s.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .foregroundStyle(mapped ? Color.primary : Theme.secondary)
                    .frame(width: r.width)
                    .offset(x: r.minX, y: r.maxY + r.height * 0.13 + 8)
            }
        }
        .contentShape(Rectangle().path(in: r.insetBy(dx: -bezel, dy: -bezel)))
        .help(screens.count > 1 ? s.name : "")
    }
}

struct TabletAreaEditor: View {
    @Binding var area: AreaRect
    var full: (width: Double, height: Double)
    /// Usage map cells (UsageMap.cols × rows) drawn over the tablet, nil = hidden.
    var heat: [Int]? = nil
    /// Dashed preview of a proposed area (the "suggest" button is hovered).
    var ghost: AreaRect? = nil
    var pen: PenHover? = nil
    var onEditSize: (() -> Void)? = nil
    @State private var dragStart: AreaRect?
    @State private var hover = false
    @FocusState private var focused: Bool
    /// The ring shows only after the user clicked the area (it gets focus on its own when the page opens).
    @State private var engaged = false

    /// Body around the active area (mm), roughly like the Intuos Pro M; keys on the left (right when rotated).
    private var margins: (l: Double, r: Double, t: Double, b: Double) {
        area.rotation == 180 ? (36, 60, 26, 26) : (60, 36, 26, 26)
    }

    var body: some View {
        GeometryReader { g in
            let full = self.full, m = margins
            let bw = full.width + m.l + m.r, bh = full.height + m.t + m.b
            let k = min(g.size.width / bw, g.size.height / bh) * 0.94
            let bx = (g.size.width - bw * k) / 2, by = (g.size.height - bh * k) / 2
            let ox = bx + m.l * k, oy = by + m.t * k
            let sel = CGRect(x: ox + (area.x - area.width / 2) * k, y: oy + (area.y - area.height / 2) * k,
                             width: area.width * k, height: area.height * k)
            let surface = CGRect(x: ox, y: oy, width: full.width * k, height: full.height * k)

            ZStack(alignment: .topLeading) {
                // body
                RoundedRectangle(cornerRadius: max(10, 16 * k))
                    .fill(LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x1C1C1F)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: max(10, 16 * k)).strokeBorder(Color.white.opacity(0.07)))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                    .frame(width: bw * k, height: bh * k)
                    .offset(x: bx, y: by)
                keyStrip(k: k, x: area.rotation == 180 ? ox + full.width * k + 4 * k : bx, width: (area.rotation == 180 ? m.r : m.l) * k - 4 * k, y: by, height: bh * k)

                // active surface + grid + corner marks
                Canvas { ctx, size in
                    let r = CGRect(origin: .zero, size: size)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Color(hex: 0x111113)))
                    let step = 10 * k
                    var dots = Path()
                    var x = step
                    while x < size.width - 1 {
                        var y = step
                        while y < size.height - 1 { dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)); y += step }
                        x += step
                    }
                    ctx.fill(dots, with: .color(.white.opacity(0.09)))
                    if let heat, let peak = heat.max(), peak > 0 {
                        var layer = ctx
                        layer.clip(to: Path(roundedRect: r, cornerRadius: 4))
                        layer.addFilter(.blur(radius: max(2, size.width / Double(UsageMap.cols) * 0.55)))
                        layer.blendMode = .plusLighter
                        let cw = size.width / Double(UsageMap.cols), ch = size.height / Double(UsageMap.rows)
                        for (i, c) in heat.enumerated() where c > 0 {
                            let v = sqrt(Double(c) / Double(peak))
                            let cell = CGRect(x: Double(i % UsageMap.cols) * cw, y: Double(i / UsageMap.cols) * ch, width: cw, height: ch).insetBy(dx: -cw * 0.15, dy: -ch * 0.15)
                            layer.fill(Path(ellipseIn: cell), with: .color(Self.heatColor(v).opacity(0.12 + v * 0.55)))
                        }
                    }
                    // corner marks of the active area
                    let c = min(14, size.width * 0.05)
                    var marks = Path()
                    for (px, py, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (size.width, 0, -1, 1), (0, size.height, 1, -1), (size.width, size.height, -1, -1)] {
                        marks.move(to: CGPoint(x: px + dx * c, y: py)); marks.addLine(to: CGPoint(x: px, y: py)); marks.addLine(to: CGPoint(x: px, y: py + dy * c))
                    }
                    ctx.stroke(marks, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                }
                .frame(width: surface.width, height: surface.height)
                .offset(x: surface.minX, y: surface.minY)
                .allowsHitTesting(false)

                // dim everything outside the selection
                Path { p in
                    p.addRoundedRect(in: surface, cornerSize: CGSize(width: 4, height: 4))
                    p.addRoundedRect(in: sel, cornerSize: CGSize(width: 4, height: 4))
                }
                .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                // selection
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(hover || dragStart != nil ? 0.14 : 0.08))
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1.5)
                    crosshair
                }
                .frame(width: sel.width, height: sel.height)
                .contentShape(Rectangle())
                .onHover { h in hover = h; if h { NSCursor.openHand.push() } else { NSCursor.pop() } }
                .gesture(DragGesture()
                    .onChanged { v in
                        focused = true; engaged = true
                        let s = dragStart ?? area
                        dragStart = s
                        var a = area
                        a.x = min(max(s.x + v.translation.width / k, a.width / 2), full.width - a.width / 2)
                        a.y = min(max(s.y + v.translation.height / k, a.height / 2), full.height - a.height / 2)
                        area = a
                    }
                    .onEnded { _ in dragStart = nil })
                .offset(x: sel.minX, y: sel.minY)

                // corner handles – resize around the centre, keeping the ratio
                ForEach(0..<4, id: \.self) { i in
                    let p = CGPoint(x: i % 2 == 0 ? sel.minX : sel.maxX, y: i < 2 ? sel.minY : sel.maxY)
                    Circle().fill(.white)
                        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                        .onHover { h in if h { NSCursor.crosshair.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture(coordinateSpace: .named("tablet"))
                            .onChanged { v in resize(to: v.location, origin: CGPoint(x: ox, y: oy), k: k) }
                            .onEnded { _ in dragStart = nil })
                        .position(p)
                }

                if let ghost {
                    let gr = CGRect(x: ox + (ghost.x - ghost.width / 2) * k, y: oy + (ghost.y - ghost.height / 2) * k,
                                    width: ghost.width * k, height: ghost.height * k)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.warn, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.warn.opacity(0.08)))
                        .overlay(alignment: .topLeading) {
                            Text(String(format: L("Návrh %.0f × %.0f mm"), ghost.width, ghost.height))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.warn)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                                .fixedSize().padding(4)
                        }
                        .frame(width: gr.width, height: gr.height)
                        .offset(x: gr.minX, y: gr.minY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let pen {
                    PenDot(pen: pen) { mm in CGPoint(x: ox + mm.x * k, y: oy + mm.y * k) }
                }

                // size label under the selection (inside when there is no room)
                let label = String(format: "%.0f × %.0f mm · %.0f %%", area.width, area.height, area.width * area.height / (full.width * full.height) * 100)
                Text(label)
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .onTapGesture(count: 2) { onEditSize?() }
                    .help(L("Dvojklikem zadáte přesné rozměry"))
                    .position(x: sel.midX, y: sel.maxY + 16 < by + bh * k - 4 ? sel.maxY + 16 : sel.maxY - 14)
            }
            .coordinateSpace(name: "tablet")
            .animation(.easeOut(duration: 0.15), value: ghost)
        }
        .environment(\.colorScheme, .dark)   // the device is dark, like the real one
        .padding(10)
        .background(Theme.stage, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(focused && engaged ? 0.6 : 0), lineWidth: 1.5))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onChange(of: focused) { _, f in if !f { engaged = false } }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let step = press.modifiers.contains(.shift) ? 10.0 : 1.0
            var a = area
            switch press.key {
            case .leftArrow: a.x -= step
            case .rightArrow: a.x += step
            case .upArrow: a.y -= step
            default: a.y += step
            }
            a.x = min(max(a.x, a.width / 2), full.width - a.width / 2)
            a.y = min(max(a.y, a.height / 2), full.height - a.height / 2)
            area = a
            return .handled
        }
        .accessibilityLabel("Plocha tabletu")
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().fill(Theme.accent.opacity(0.7)).frame(width: 14, height: 1)
            Rectangle().fill(Theme.accent.opacity(0.7)).frame(width: 1, height: 14)
        }
    }

    private func keyStrip(k: Double, x: Double, width: Double, y: Double, height: Double) -> some View {
        let key = RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x313136))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.05)))
            .frame(width: 22 * k, height: 11 * k)
        return VStack(spacing: 3 * k) {
            ForEach(0..<4, id: \.self) { _ in key }
            Circle().strokeBorder(Color(hex: 0x3A3A40), lineWidth: 7 * k)
                .frame(width: 36 * k, height: 36 * k).padding(.vertical, 4 * k)
            ForEach(0..<4, id: \.self) { _ in key }
        }
        .frame(width: width, height: height)
        .offset(x: x, y: y)
        .allowsHitTesting(false)
    }

    private func resize(to p: CGPoint, origin: CGPoint, k: Double) {
        let s = dragStart ?? area
        dragStart = s
        let hw = abs((p.x - origin.x) / k - s.x), hh = abs((p.y - origin.y) / k - s.y)
        var r = max(2 * hw / s.width, 2 * hh / s.height)
        r = min(r, full.width / s.width, full.height / s.height)
        r = max(r, 0.3 / max(s.width / full.width, s.height / full.height))  // same minimum as the slider
        var a = area
        a.width = s.width * r; a.height = s.height * r
        a.x = min(max(s.x, a.width / 2), full.width - a.width / 2)
        a.y = min(max(s.y, a.height / 2), full.height - a.height / 2)
        area = a
    }

    /// Deep orange → amber → pale yellow.
    static func heatColor(_ v: Double) -> Color {
        let v = min(max(v, 0), 1)
        return Color(hue: (18 + 32 * v) / 360, saturation: 0.95 - 0.45 * v * v, brightness: 0.85 + 0.15 * v)
    }
}

/// Popover for typing the exact area size in mm.
struct SizeEditor: View {
    var area: AreaRect
    var full: (width: Double, height: Double)
    var aspect: Double?
    var apply: (Double, Double) -> Void
    @State private var w = 0.0
    @State private var h = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Přesná velikost plochy").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                field($w, max: full.width).onChange(of: w) { _, v in if let r = aspect, abs(v / r - h) > 0.05 { h = (v / r * 10).rounded() / 10 } }
                Text("×").foregroundStyle(Theme.secondary)
                field($h, max: full.height).onChange(of: h) { _, v in if let r = aspect, abs(v * r - w) > 0.05 { w = (v * r * 10).rounded() / 10 } }
                Text("mm").foregroundStyle(Theme.secondary)
            }
            Text(String(format: L("Tablet má nejvýš %.1f × %.1f mm"), full.width, full.height) + (aspect != nil ? " · " + L("poměr stran je zamčený") : ""))
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            HStack {
                Spacer()
                Button("Použít") { apply(min(w, full.width), min(h, full.height)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(w < 10 || h < 10)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { w = (area.width * 10).rounded() / 10; h = (area.height * 10).rounded() / 10 }
    }

    private func field(_ v: Binding<Double>, max: Double) -> some View {
        TextField("", value: v, format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder).frame(width: 70).multilineTextAlignment(.trailing)
    }
}

/// Live pen position: a ring that grows with pressure.
struct PenDot: View {
    @ObservedObject var pen: PenHover
    var map: (CGPoint) -> CGPoint

    var body: some View {
        if let smp = pen.sample {
            let p = map(smp.mm), touching = smp.pressure > 0.01
            // halo: bigger when the pen is higher above the surface, stronger with pressure
            let halo = touching ? 18 + smp.pressure * 18 : 14 + smp.distance * 22
            ZStack {
                Circle().fill(Theme.warn.opacity(touching ? 0.35 : 0.22 - smp.distance * 0.12)).frame(width: halo, height: halo)
                // tilt: short line in the direction the pen leans
                Path { q in
                    q.move(to: CGPoint(x: 20, y: 20))
                    q.addLine(to: CGPoint(x: 20 + smp.tiltX / 64 * 18, y: 20 + smp.tiltY / 64 * 18))
                }
                .stroke(Theme.warn.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 40, height: 40)
                Circle().fill(.white).frame(width: touching ? 8 : 6, height: touching ? 8 : 6)
                    .overlay(Circle().strokeBorder(Theme.warn, lineWidth: 1.5))
            }
            .shadow(color: .black.opacity(0.4), radius: 2)
            .position(p)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Tablet mm → display point (OTD display coords), clamped like the cursor.
    static func screenPoint(mm: CGPoint, tablet t: AreaRect, display d: AreaRect) -> CGPoint {
        var u = (mm.x - (t.x - t.width / 2)) / t.width, v = (mm.y - (t.y - t.height / 2)) / t.height
        if t.rotation == 180 { u = 1 - u; v = 1 - v }
        u = min(max(u, 0), 1); v = min(max(v, 0), 1)
        return CGPoint(x: d.x - d.width / 2 + u * d.width, y: d.y - d.height / 2 + v * d.height)
    }
}
