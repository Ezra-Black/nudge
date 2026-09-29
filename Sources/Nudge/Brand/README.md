# Brand

The files in this folder draw **Nudge, the character**: every expression and pose, the app icon and the menu bar icon.

**They are not open source.** They're covered by the [Nudge Brand License](../../../LICENSE-BRAND.md), not the Apache License. You can build and run Nudge with them and send pull requests that improve them. You can't publish them, or a fork that includes them. See [TRADEMARKS.md](../../../TRADEMARKS.md).

## Replacing the brand in a fork

The rest of the app uses only the API below. Put your own implementation in this folder and the app builds as before.

```swift
/// The guide character. `mood` picks the expression; `pointing` is the direction of
/// a pointing arm in radians (0 points right, π/2 points down).
struct MascotView: View {
    init(mood: MascotMood = .happy, size: CGFloat = 64, pointing: Double = 0, animated: Bool = true)
}

enum MascotArt {
    /// The template image shown in the menu bar.
    static func menuBarImage() -> NSImage
    /// Writes AppIcon.iconset into `folder`. `scripts/build.sh` turns it into the app icon.
    @MainActor static func exportIcon(to folder: URL) throws
    /// Writes the README and website header image.
    @MainActor static func exportHero(to file: URL) throws
    /// Writes a PNG of every mood.
    @MainActor static func exportSheet(to file: URL) throws
    /// Writes a PNG of a sample guide card in the default theme.
    @MainActor static func exportThemePreview(to file: URL, dark: Bool) throws
}
```

`MascotMood`, the list of expressions, lives in [`Models/MascotMood.swift`](../Models/MascotMood.swift) and is open source. Your character should have some way to show every mood, even if several look the same. The guide depends on `.pointing`, `.thinking`, `.celebrating`, `.upset` and `.shy` to react to what's happening.
