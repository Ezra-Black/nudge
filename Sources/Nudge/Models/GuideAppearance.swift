import AppKit
import SwiftUI

/// Everything about how the guide looks. Stored as one value so new options never disturb saved ones.
struct GuideAppearance: Codable, Equatable {
    enum CardStyle: String, Codable, CaseIterable { case glass, solid }
    enum Scheme: String, Codable, CaseIterable { case system, light, dark }
    enum CardSize: String, Codable, CaseIterable { case small, medium, large }
    enum Weight: String, Codable, CaseIterable { case regular, medium, semibold }

    var cardStyle = CardStyle.glass
    /// "nudge" is the theme's frosted periwinkle (indigo in Dark Mode); "" is no color; otherwise a hex color.
    var cardColor = "nudge"
    /// The violet halo around every Nudge card and bubble, from 0 (off) to 1.
    var cardGlow = 0.6
    var scheme = Scheme.system
    var cardSize = CardSize.medium
    var showIcon = true
    var showDots = true
    /// "system", "rounded", "serif", "mono", or an installed font family.
    var fontFamily = "rounded"
    var fontWeight = Weight.regular
    var textSize = 18.0
    var lineSpacing = 2.0
    /// The accent: highlight, card glow, buttons and progress dots.
    var highlightColor = "#A98BFF"
    var highlightWidth = 3.0
    var glowStrength = 0.7
    var ripple = true
    var breathe = true
    var dimBackground = true
    var dimStrength = 0.45
    /// Nudge, the guide character, floating beside what's being explained.
    var showMascot = true
    var mascotSize = CardSize.medium
    /// Bumped when a default changes enough that saved settings should follow it once.
    var version = 3
}
extension GuideAppearance {
    /// Missing or unreadable keys fall back to their defaults instead of discarding every saved choice.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        cardStyle = read(.cardStyle, cardStyle)
        cardColor = read(.cardColor, cardColor)
        scheme = read(.scheme, scheme)
        cardSize = read(.cardSize, cardSize)
        showIcon = read(.showIcon, showIcon)
        showDots = read(.showDots, showDots)
        fontFamily = read(.fontFamily, fontFamily)
        fontWeight = read(.fontWeight, fontWeight)
        textSize = read(.textSize, textSize)
        lineSpacing = read(.lineSpacing, lineSpacing)
        highlightColor = read(.highlightColor, highlightColor)
        highlightWidth = read(.highlightWidth, highlightWidth)
        glowStrength = read(.glowStrength, glowStrength)
        ripple = read(.ripple, ripple)
        breathe = read(.breathe, breathe)
        dimBackground = read(.dimBackground, dimBackground)
        dimStrength = read(.dimStrength, dimStrength)
        showMascot = read(.showMascot, showMascot)
        mascotSize = read(.mascotSize, mascotSize)
        version = read(.version, 1)
        // Version 2 made the guide larger for easier reading.
        if version < 2 {
            textSize = max(textSize, 18)
            version = 2
        }
        cardGlow = read(.cardGlow, cardGlow)
        // Version 3 introduced the Nudge theme to match the character.
        if version < 3 {
            cardStyle = .glass
            cardColor = "nudge"
            highlightColor = "#A98BFF"
            if fontFamily == "system" { fontFamily = "rounded" }
            version = 3
        }
    }

    var cardNSColor: NSColor? { cardColor == "nudge" ? .nudgeCard : NSColor(hex: cardColor) }
    var isNudgeCard: Bool { cardColor == "nudge" }
    var accent: Color { Color(nsColor: highlightNSColor) }
    var highlightNSColor: NSColor { NSColor(hex: highlightColor) ?? .systemYellow }
    /// A colored card picks light or dark text so it stays readable; otherwise the chosen appearance applies.
    var forcedDark: Bool? {
        switch scheme {
        case .light: return false
        case .dark: return true
        // Automatic follows the Mac, unless a card color needs light or dark text to stay readable.
        // The Nudge color adapts on its own.
        case .system: return isNudgeCard ? nil : cardNSColor.map { $0.luminance < 0.55 }
        }
    }
    var mascotPoints: CGFloat {
        switch mascotSize {
        case .small: 44
        case .medium: 60
        case .large: 80
        }
    }
    /// Wider cards for larger text, so lines don't get cramped.
    var cardWidth: CGFloat {
        let base: CGFloat =
            switch cardSize {
            case .small: 340
            case .medium: 390
            case .large: 450
            }
        return base + max(0, CGFloat(textSize) - 18) * 11
    }
    var bodyWeight: Font.Weight {
        switch fontWeight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
    var titleWeight: Font.Weight { fontWeight == .semibold ? .bold : .semibold }
    func font(_ size: Double, weight: Font.Weight? = nil) -> Font {
        let size = CGFloat(size)
        let weight = weight ?? bodyWeight
        switch fontFamily {
        case "system": return .system(size: size, weight: weight)
        case "rounded": return .system(size: size, weight: weight, design: .rounded)
        case "serif": return .system(size: size, weight: weight, design: .serif)
        case "mono": return .system(size: size, weight: weight, design: .monospaced)
        default: return .custom(fontFamily, size: size).weight(weight)
        }
    }

    static let highlightPresets: [(name: String, hex: String)] = [
        ("Nudge violet", "#A98BFF"), ("Yellow", "#FFD60A"), ("Orange", "#FF9F0A"), ("Red", "#FF453A"), ("Pink", "#FF375F"),
        ("Blue", "#0A84FF"),
        ("Mint", "#63E6E2"), ("Green", "#30D158"), ("White", "#FFFFFF"),
    ]
    static let cardPresets: [(name: String, hex: String)] = [
        ("Nudge", "nudge"), ("None", ""), ("Graphite", "#3A3A3C"), ("Midnight", "#1C2B4A"), ("Blue", "#0A84FF"), ("Purple", "#8E5BD9"),
        ("Pink", "#E0527A"), ("Orange", "#E8872A"), ("Yellow", "#F5D04C"), ("Green", "#34A853"), ("Cream", "#F5EEDC"),
    ]
    static let designs: [(name: String, id: String)] = [
        ("System", "system"), ("Rounded", "rounded"), ("Serif", "serif"), ("Monospaced", "mono"),
    ]
}

extension NSColor {
    /// The theme's card color: frosted periwinkle in Light Mode, deep indigo in Dark Mode.
    static let nudgeCard = NSColor(name: "nudgeCard") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.15, green: 0.16, blue: 0.31, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.945, blue: 1, alpha: 1)
    }
    convenience init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255,
            alpha: 1)
    }
    var hex: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}
