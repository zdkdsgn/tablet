import SwiftUI

struct LightsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var lights: LightSettings
    @EnvironmentObject var zoom: ZoomSettings
    @EnvironmentObject var rem: ReminderSettings
    @EnvironmentObject var reminders: Reminders

    var body: some View {
        ScrollView { content }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                Card(title: "Touch Ring") {
                    SettingRow(title: L("Světýlka kolečka"), caption: zoom.smooth ? L("Ukazují zvolený režim kolečka") : L("Svítí první světýlko")) {
                        Toggle("", isOn: $lights.enabled).labelsHidden().toggleStyle(.switch)
                    }
                    brightnessPicker($lights.brightness).disabled(!lights.enabled)
                    SettingRow(title: L("Naplno jen při dotyku"), caption: L("V klidu ztlumené, rozsvítí se, když sáhnete na tlačítka nebo kolečko")) {
                        Toggle("", isOn: $lights.dimUntilTouch).labelsHidden().toggleStyle(.switch)
                    }
                    if lights.dimUntilTouch {
                        Picker("V klidu", selection: $lights.dimLevel) {
                            Text("Zhasnuto").tag(3)
                            Text("Slabě").tag(0)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Card(title: L("Rohy plochy")) {
                    SettingRow(title: L("Rohová světýlka"), caption: L("Čtyři značky aktivní plochy – svítí všechny naráz")) {
                        Toggle("", isOn: $lights.cornersEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    brightnessPicker($lights.cornerBrightness).disabled(!lights.cornersEnabled)
                    SettingRow(title: L("Dýchání v klidu"), caption: L("Rohy pomalu pulzují")) {
                        Toggle("", isOn: $lights.breatheCorners).labelsHidden().toggleStyle(.switch)
                    }
                    .disabled(!lights.cornersEnabled)
                }
                LightsPreview()
            }
            VStack(spacing: 20) {
                Card(title: L("Upozornění světly")) {
                    SettingRow(title: L("Slabá baterie"), caption: String(format: L("Bliknou světla, když baterie Macu klesne pod %d %%"), rem.batteryLevel)) {
                        Toggle("", isOn: $rem.batteryAlert).labelsHidden().toggleStyle(.switch)
                    }
                    if rem.batteryAlert {
                        Slider(value: Binding { Double(rem.batteryLevel) } set: { rem.batteryLevel = Int($0) }, in: 5...40, step: 5)
                    }
                    HStack {
                        Text("Animace upozornění")
                        Spacer()
                        Picker("", selection: $rem.alertAnimation) {
                            ForEach(LEDAnimation.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden().fixedSize()
                        Button { model.lights.play(rem.animation) } label: { Image(systemName: "play.fill") }
                            .accessibilityLabel(L("Přehrát"))
                    }
                    Text("Vlastní upozornění (hotový render, zpráva…) pošlete odkazem tablet://notify?title=… ze Zkratek nebo terminálu – viz Obecné.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Card(title: L("Přestávky")) {
                    SettingRow(title: L("Připomínat přestávku"), caption: L("Po dlouhém kreslení bliknou světla a ukáže se oznámení")) {
                        Toggle("", isOn: $rem.breakEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    if rem.breakEnabled {
                        HStack { Text("Kreslit"); Spacer(); Text(String(format: L("%d min"), Int(rem.workMinutes))).foregroundStyle(Theme.secondary) }
                        Slider(value: $rem.workMinutes, in: 15...120, step: 5)
                        HStack { Text("Přestávka"); Spacer(); Text(String(format: L("%d min"), Int(rem.breakMinutes))).foregroundStyle(Theme.secondary) }
                        Slider(value: $rem.breakMinutes, in: 2...30, step: 1)
                        Toggle("Počítat jen čas s perem v ruce", isOn: $rem.countDrawing).toggleStyle(.checkbox)
                        HStack {
                            ProgressView(value: reminders.progress).tint(reminders.breakDue ? Theme.warn : Theme.accent)
                            Text(reminders.breakDue ? L("Čas na pauzu") : String(format: L("ještě %d min"), reminders.remainingMinutes))
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            Button("Začít znovu") { reminders.resetBreak() }.controlSize(.small)
                        }
                        Text("Když od tabletu odejdete na dobu přestávky, odpočet začne znovu sám.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
                Card(title: L("Animace")) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("Rychlost animací"); Spacer(); Text(speedName).foregroundStyle(Theme.secondary) }
                        Slider(value: $lights.animationSpeed, in: 0.5...2, step: 0.25)
                    }
                    SettingRow(title: L("Při přepnutí režimu"), caption: L("Světlo oběhne kolečko a zastaví se na novém režimu")) {
                        Toggle("", isOn: $lights.animateModeChange).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: L("Uvítání po připojení"), caption: L("Kolotoč, když tablet připojíte")) {
                        Toggle("", isOn: $lights.welcomeAnimation).labelsHidden().toggleStyle(.switch)
                    }
                }
                if lights.easterEggUnlocked {
                    Card(title: L("Světelná show"), trailing: AnyView(Image(systemName: "sparkles").foregroundStyle(Theme.accent))) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dlouhý stisk tlačítka uprostřed kolečka").foregroundStyle(Color(hex: 0xC7C7CC))
                            Picker("Dlouhý stisk", selection: $lights.longPressAnimation) {
                                Text("Náhodná animace").tag("random")
                                ForEach(LEDAnimation.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .labelsHidden()
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(LEDAnimation.allCases) { a in
                                Button { model.lights.play(a) } label: {
                                    Label(a.title, systemImage: a.symbol)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Klikněte na animaci a sledujte tablet.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Card(title: L("Světelná show")) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").foregroundStyle(Theme.secondary)
                            Text("Skryté. Zkuste chvíli podržet tlačítko uprostřed kolečka…").foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .frame(width: 420)
        }
        .padding(24)
        .onChange(of: lights.enabled) { _, _ in model.updateRingLED() }
        .onChange(of: lights.brightness) { _, _ in model.updateRingLED() }
        .onChange(of: lights.cornersEnabled) { _, _ in model.updateRingLED() }
        .onChange(of: lights.cornerBrightness) { _, _ in model.updateRingLED() }
        .onChange(of: lights.breatheCorners) { _, _ in model.updateRingLED() }
        .onChange(of: lights.dimUntilTouch) { _, _ in model.updateRingLED() }
        .onChange(of: lights.dimLevel) { _, _ in model.updateRingLED() }
    }

    private var speedName: String {
        switch lights.animationSpeed { case ..<0.8: return L("Pomalu"); case ..<1.3: return L("Normálně"); default: return L("Rychle") }
    }

    private func brightnessPicker(_ b: Binding<LEDBrightness>) -> some View {
        Picker("Intenzita", selection: b) {
            ForEach(LEDBrightness.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Sketch of where the lights are on the tablet, mirroring the current settings.
private struct LightsPreview: View {
    @EnvironmentObject var lights: LightSettings
    @EnvironmentObject var zoom: ZoomSettings

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color(hex: 0x3F3F44), lineWidth: 3).frame(width: 64, height: 64)
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == litRing ? Color.white.opacity(opacity(lights.brightness)) : Color(hex: 0x3A3A3E))
                        .frame(width: 7, height: 7)
                        .offset(y: -42)
                        .rotationEffect(.degrees(-45 + Double(i) * 30))
                }
            }
            .frame(width: 96, height: 96)
            ZStack {
                RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x2B2B2E))
                CornerMarks()
                    .opacity(lights.cornersEnabled ? 1 : 0.25)
                    .colorMultiply(lights.cornersEnabled ? .white.opacity(opacity(lights.cornerBrightness) + 0.3) : .white)
            }
            .frame(height: 96)
        }
        .padding(16)
        .background(Color(hex: 0x0D0D0E), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x3A3A3E)))
        .accessibilityHidden(true)
    }

    private var litRing: Int { lights.enabled ? (zoom.smooth ? zoom.ledIndex : 0) : -1 }
    private func opacity(_ b: LEDBrightness) -> Double { [0.45, 0.7, 1.0][b.rawValue] }
}
