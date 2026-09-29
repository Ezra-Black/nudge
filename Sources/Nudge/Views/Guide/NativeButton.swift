import SwiftUI

/// System glass buttons on macOS 26, standard bordered buttons before it.
struct NativeButton: ViewModifier {
    var prominent: Bool
    var shape: ButtonBorderShape
    var size: ControlSize = .large
    func body(content: Content) -> some View {
        let shaped = content.buttonBorderShape(shape).controlSize(size)
        // Only the main action takes the theme's accent, so it's always the one that stands out.
        let accent = Preferences.shared.appearance.accent
        if #available(macOS 26.0, *) {
            if prominent { shaped.buttonStyle(.glassProminent).tint(accent) } else { shaped.buttonStyle(.glass) }
        } else {
            if prominent { shaped.buttonStyle(.borderedProminent).tint(accent) } else { shaped.buttonStyle(.bordered) }
        }
    }
}
