import AppKit
import SwiftUI

/// A row of color presets plus the system color picker for anything else.
struct ColorSwatches: View {
    @Binding var hex: String
    let presets: [(name: String, hex: String)]
    var fallback: Color
    var body: some View {
        HStack(spacing: 7) {
            ForEach(presets, id: \.hex) { preset in
                Button {
                    hex = preset.hex
                } label: {
                    ZStack {
                        if preset.hex == "nudge" {
                            Circle().fill(
                                LinearGradient(
                                    colors: [Color(hex: "#FFFFFF"), Color(hex: "#D6E1FF"), Color(hex: "#C8B6FF")], startPoint: .topLeading,
                                    endPoint: .bottomTrailing)
                            )
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                        } else if let color = NSColor(hex: preset.hex) {
                            Circle().fill(Color(nsColor: color)).overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                        } else {
                            Image(systemName: "circle.slash").font(.system(size: 17)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(
                            Color.primary.opacity(hex.caseInsensitiveCompare(preset.hex) == .orderedSame ? 0.9 : 0), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(preset.name)
            }
            ColorPicker(
                "Custom color",
                selection: Binding(get: { NSColor(hex: hex).map { Color(nsColor: $0) } ?? fallback }, set: { hex = NSColor($0).hex }),
                supportsOpacity: false
            )
            .labelsHidden()
            .help("Custom color")
        }
    }
}

/// A small stand-in window showing the guide as it will look: highlight, dimming and card.
struct GuidePreview: View {
    @ObservedObject private var prefs = Preferences.shared
    @Environment(\.colorScheme) private var systemScheme
    private let sample = GuideContent(
        kind: .page, app: "Toolbar", title: "Share this page", message: "Sends a link to this page by Mail, Messages or AirDrop.", page: 2,
        pages: 8, canBack: true)
    private let spot = CGRect(x: 8, y: 8, width: 40, height: 36)

    var body: some View {
        let a = prefs.appearance
        let highlight = Color(nsColor: a.highlightNSColor)
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.blue.opacity(0.45), Color.purple.opacity(0.35), Color.orange.opacity(0.25)], startPoint: .topLeading,
                endPoint: .bottomTrailing)
            HStack(spacing: 10) {
                ForEach(["square.and.arrow.up", "plus", "sidebar.left", "magnifyingglass"], id: \.self) { symbol in
                    Image(systemName: symbol).frame(width: 32, height: 28).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(12)
            if a.dimBackground {
                SpotlightShape(hole: spot).fill(Color.black.opacity(a.dimStrength), style: FillStyle(eoFill: true))
            }
            RoundedRectangle(cornerRadius: 9)
                .stroke(highlight, lineWidth: a.highlightWidth)
                .shadow(color: highlight.opacity(a.glowStrength), radius: 9)
                .frame(width: spot.width, height: spot.height)
                .offset(x: spot.minX, y: spot.minY)
            GuideCard(content: sample, icon: NSImage(named: NSImage.applicationIconName))
                .background { CardBackdrop(look: a, embedded: true) }
                .environment(\.colorScheme, a.forcedDark.map { $0 ? .dark : .light } ?? systemScheme)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .offset(x: 12, y: spot.maxY + 14)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 380, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.smooth(duration: 0.25), value: a)
    }
}
private struct SpotlightShape: Shape {
    var hole: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: 9, height: 9))
        return path
    }
}

/// Settings → Appearance.
struct AppearanceSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    private let families = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()

    var body: some View {
        Section {
            GuidePreview().listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
        Section {
            Picker("Style", selection: $prefs.appearance.cardStyle) {
                Text("Glass").tag(GuideAppearance.CardStyle.glass)
                Text("Solid").tag(GuideAppearance.CardStyle.solid)
            }
            .pickerStyle(.segmented)
            LabeledContent("Color") {
                ColorSwatches(hex: $prefs.appearance.cardColor, presets: GuideAppearance.cardPresets, fallback: .gray)
            }
            Picker("Appearance", selection: $prefs.appearance.scheme) {
                Text("Automatic").tag(GuideAppearance.Scheme.system)
                Text("Light").tag(GuideAppearance.Scheme.light)
                Text("Dark").tag(GuideAppearance.Scheme.dark)
            }
            .pickerStyle(.segmented)
            Picker("Size", selection: $prefs.appearance.cardSize) {
                Text("Small").tag(GuideAppearance.CardSize.small)
                Text("Medium").tag(GuideAppearance.CardSize.medium)
                Text("Large").tag(GuideAppearance.CardSize.large)
            }
            .pickerStyle(.segmented)
            Toggle("Show the app’s icon", isOn: $prefs.appearance.showIcon)
            Toggle("Show progress dots", isOn: $prefs.appearance.showDots)
        } header: {
            Text("Guide card")
        } footer: {
            Text(
                "Automatic follows your Mac, and picks light or dark text to suit a card color. The color, font and appearance apply to every Nudge bubble, including “Looking at…”."
            ).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Show Nudge, the guide character", isOn: $prefs.appearance.showMascot)
            Picker("Size", selection: $prefs.appearance.mascotSize) {
                Text("Small").tag(GuideAppearance.CardSize.small)
                Text("Medium").tag(GuideAppearance.CardSize.medium)
                Text("Large").tag(GuideAppearance.CardSize.large)
            }
            .pickerStyle(.segmented)
            .disabled(!prefs.appearance.showMascot)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(
                        [
                            MascotMood.waving, .cheery, .pointing, .thinking, .curious, .surprised, .confused, .celebrating, .upset, .angry,
                            .sleeping,
                        ], id: \.self
                    ) { mood in
                        VStack(spacing: 0) {
                            MascotView(mood: mood, size: 40, pointing: 0)
                            Text(mood.name).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Character")
        } footer: {
            Text("Nudge floats beside each highlight and points at it, thinks while reading, and celebrates when you finish.").font(
                .caption
            ).foregroundStyle(.secondary)
        }
        Section("Text") {
            Picker("Font", selection: $prefs.appearance.fontFamily) {
                ForEach(GuideAppearance.designs, id: \.id) { design in Text(design.name).tag(design.id) }
                Divider()
                ForEach(families, id: \.self) { family in Text(family).tag(family) }
            }
            Picker("Weight", selection: $prefs.appearance.fontWeight) {
                Text("Regular").tag(GuideAppearance.Weight.regular)
                Text("Medium").tag(GuideAppearance.Weight.medium)
                Text("Semibold").tag(GuideAppearance.Weight.semibold)
            }
            .pickerStyle(.segmented)
            LabeledContent("Size") {
                HStack {
                    Slider(value: $prefs.appearance.textSize, in: 14...32, step: 1).frame(width: 200)
                    Text("\(Int(prefs.appearance.textSize)) pt").monospacedDigit().foregroundStyle(.secondary).frame(
                        width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Line spacing") {
                Slider(value: $prefs.appearance.lineSpacing, in: 0...10).frame(width: 248)
            }
        }
        Section {
            LabeledContent("Accent color") {
                ColorSwatches(hex: $prefs.appearance.highlightColor, presets: GuideAppearance.highlightPresets, fallback: .purple)
            }
            LabeledContent("Card glow") {
                Slider(value: $prefs.appearance.cardGlow, in: 0...1).frame(width: 248)
            }
            LabeledContent("Thickness") {
                Slider(value: $prefs.appearance.highlightWidth, in: 2...7, step: 0.5).frame(width: 248)
            }
            LabeledContent("Glow") {
                Slider(value: $prefs.appearance.glowStrength, in: 0...1).frame(width: 248)
            }
            Toggle("Ripple when it moves to something new", isOn: $prefs.appearance.ripple)
            Toggle("Gently pulse the glow", isOn: $prefs.appearance.breathe)
            Toggle("Dim the rest of the screen", isOn: $prefs.appearance.dimBackground)
            if prefs.appearance.dimBackground {
                LabeledContent("Dimming") {
                    Slider(value: $prefs.appearance.dimStrength, in: 0.15...0.75).frame(width: 248)
                }
            }
        } header: {
            Text("Highlight")
        } footer: {
            Text("Clicks still reach the app through the dimming. Motion follows the Reduce Motion setting.").font(.caption)
                .foregroundStyle(.secondary)
        }
        Section {
            HStack {
                Spacer()
                Button("Reset to the Nudge Theme") { prefs.appearance = GuideAppearance() }
                    .disabled(prefs.appearance == GuideAppearance())
            }
        }
    }
}
