import SwiftUI

/// System glass buttons on macOS 26, standard bordered buttons before it.
struct NativeButton: ViewModifier {
    var prominent: Bool
    var shape: ButtonBorderShape
    var size: ControlSize = .large
    @Environment(\.isSnapshot) private var isSnapshot
    func body(content: Content) -> some View {
        let shaped = content.buttonBorderShape(shape).controlSize(size)
        // Only the main action takes the theme's accent, so it's always the one that stands out.
        let accent = Preferences.shared.appearance.accent
        if isSnapshot {
            shaped.buttonStyle(SnapshotButtonStyle(prominent: prominent, shape: shape, size: size, accent: accent))
        } else if #available(macOS 26.0, *) {
            if prominent { shaped.buttonStyle(.glassProminent).tint(accent) } else { shaped.buttonStyle(.glass) }
        } else {
            if prominent { shaped.buttonStyle(.borderedProminent).tint(accent) } else { shaped.buttonStyle(.bordered) }
        }
    }
}

extension EnvironmentValues {
    /// True while a view is drawn into an image (for the README and website), where system button styles don't render.
    @Entry var isSnapshot = false
}

/// A plain drawing of the system buttons, used only when drawing images.
private struct SnapshotButtonStyle: ButtonStyle {
    var prominent: Bool
    var shape: ButtonBorderShape
    var size: ControlSize
    var accent: Color
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let large = size == .extraLarge || size == .large
        let plain = scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.85)
        return configuration.label
            .padding(.horizontal, shape == .circle ? 7 : (large ? 16 : 11))
            .padding(.vertical, shape == .circle ? 7 : (large ? 10 : 6))
            .foregroundStyle(prominent ? Color(white: 0.1) : Color.primary)
            .background(prominent ? accent : plain, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(prominent ? 0 : 0.08)))
    }
}
