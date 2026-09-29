import Foundation
import Testing

@testable import Nudge

@Suite("Appearance settings")
struct AppearanceTests {
    @Test("Missing keys fall back to defaults instead of discarding saved choices")
    func partialDecode() throws {
        let saved = Data(#"{"version": 3, "textSize": 24, "cardStyle": "solid", "unknownFutureKey": true}"#.utf8)
        let look = try JSONDecoder().decode(GuideAppearance.self, from: saved)
        #expect(look.textSize == 24)
        #expect(look.cardStyle == .solid)
        #expect(look.highlightColor == GuideAppearance().highlightColor)
        #expect(look.showMascot == GuideAppearance().showMascot)
    }

    @Test("A value that can't be read keeps its default")
    func badValue() throws {
        let saved = Data(#"{"version": 3, "textSize": "huge", "ripple": false}"#.utf8)
        let look = try JSONDecoder().decode(GuideAppearance.self, from: saved)
        #expect(look.textSize == GuideAppearance().textSize)
        #expect(look.ripple == false)
    }

    @Test("Settings saved before the Nudge theme move to it once, with larger text")
    func migration() throws {
        let saved = Data(##"{"textSize": 14, "cardStyle": "solid", "cardColor": "#FFFFFF", "fontFamily": "system"}"##.utf8)
        let look = try JSONDecoder().decode(GuideAppearance.self, from: saved)
        #expect(look.version == 3)
        #expect(look.textSize == 18)
        #expect(look.cardStyle == .glass)
        #expect(look.isNudgeCard)
        #expect(look.fontFamily == "rounded")
    }

    @Test("Settings survive encoding and decoding")
    func roundTrip() throws {
        var look = GuideAppearance()
        look.fontFamily = "serif"
        look.dimStrength = 0.3
        let decoded = try JSONDecoder().decode(GuideAppearance.self, from: JSONEncoder().encode(look))
        #expect(decoded == look)
    }
}
