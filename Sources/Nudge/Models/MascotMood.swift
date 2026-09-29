import Foundation

/// Nudge, the guide character: a small, soft, floating blob with big eyes and little arms.
/// Drawn entirely with shapes so it stays crisp from the menu bar to the app icon.
enum MascotMood: String, CaseIterable, Equatable {
    case happy, waving, excited, cheery, thinking, curious, confused, surprised, pointing, celebrating, sleeping, focused, upset, angry, shy
    var name: String { rawValue.capitalized }
}
