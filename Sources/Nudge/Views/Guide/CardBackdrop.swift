import AppKit
import SwiftUI

/// The card with its backdrop and colors, as it appears on screen.
struct StyledCard: View {
    @ObservedObject var model: GuideModel
    @ObservedObject private var prefs = Preferences.shared
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        let look = prefs.appearance
        GuideCard(content: model.content, icon: model.icon, draft: $model.draft) { model.perform?($0) }
            .background { CardBackdrop(look: look) }
            .environment(\.colorScheme, look.forcedDark.map { $0 ? .dark : .light } ?? systemScheme)
    }
}
/// The backdrop of every Nudge surface: a soft violet halo that gently breathes, a drop shadow, glass or a solid
/// fill in the card color, and a white-to-accent edge. `embedded` draws the glass for use inside an ordinary window.
struct CardBackdrop: View {
    let look: GuideAppearance
    var embedded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let color = look.cardNSColor.map { Color(nsColor: $0) }
        ZStack {
            if look.cardGlow > 0 {
                shape.fill(look.accent.opacity(0.6 * look.cardGlow))
                    .padding(-3)
                    .blur(radius: 20)
                    .opacity(glowing ? 1 : 0.65)
            }
            shape.fill(Color.black.opacity(0.16)).blur(radius: 12).offset(y: 6)
            if look.cardStyle == .solid {
                shape.fill(color ?? Color(nsColor: .windowBackgroundColor))
            } else {
                ZStack {
                    if embedded {
                        if #available(macOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) } else { shape.fill(.regularMaterial) }
                    } else {
                        GlassBackdrop()
                    }
                    if let color { color.opacity(look.isNudgeCard ? 0.74 : 0.5) }
                }
                .clipShape(shape)
            }
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.75), look.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
        }
        .onAppear {
            guard look.breathe, !reduceMotion, look.cardGlow > 0 else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { glowing = true }
        }
    }
}
/// The system's glass (macOS 26) or behind-window blur, sampling whatever is under the card.
struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 20
        blur.layer?.masksToBounds = true
        return blur
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
