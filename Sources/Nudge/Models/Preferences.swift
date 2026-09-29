import Combine
import Foundation

@MainActor final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var appearance: GuideAppearance { didSet { save() } }
    @Published var readingSeconds: Double { didSet { save() } }
    @Published var autoAdvance: Bool { didSet { save() } }
    @Published var transitionSeconds: Double { didSet { save() } }
    /// Speak each step aloud with an on-device voice.
    @Published var speakSteps: Bool { didSet { save() } }
    /// "" uses the system's default voice.
    @Published var voice: String { didSet { save() } }
    @Published var speechRate: Double { didSet { save() } }
    /// Most stops in one tour, and whether similar neighbouring controls share one stop.
    @Published var tourLimit: Double { didSet { save() } }
    @Published var groupSimilar: Bool { didSet { save() } }
    /// In a browser: "ask" each time, or go straight to the page ("web") or the browser's controls ("app").
    @Published var browserScope: String { didSet { save() } }
    /// Space goes to the next step and Shift-Space goes back while a guide card is showing.
    @Published var spaceAdvances: Bool { didSet { save() } }
    /// Nudge's bubbly sounds when a scan starts, the first card appears and the guide closes.
    @Published var soundEffects: Bool { didSet { save() } }
    /// Nudge asks "Did I do good?" when a guide ends.
    @Published var askFeedback: Bool { didSet { save() } }
    @Published var soundVolume: Double { didSet { save() } }
    @Published var recentApps: [String: String] { didSet { save() } }
    @Published var blockedApps: [String: String] { didSet { save() } }
    @Published var useOCR: Bool { didSet { save() } }
    @Published var shortcutKey: UInt32 { didSet { save() } }
    @Published var shortcutModifiers: UInt32 { didSet { save() } }
    /// The shortcut that opens the area selector. Control-Shift-A by default.
    @Published var areaKey: UInt32 { didSet { save() } }
    @Published var areaModifiers: UInt32 { didSet { save() } }
    let trackingInterval = 0.5
    let changeDebounce = 0.9
    /// Fallback re-check while nothing is happening, so a window moved by keyboard is still followed.
    let recheckInterval = 8.0
    let interpretationCooldown = 4.0
    private let defaults = UserDefaults.standard
    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "guideAppearance"), let saved = try? JSONDecoder().decode(GuideAppearance.self, from: data) {
            appearance = saved
        } else {
            // Carry over the text size, glow and dimming chosen before appearance settings existed.
            var initial = GuideAppearance()
            initial.textSize = max(initial.textSize, d.object(forKey: "guideTextSize") as? Double ?? 0)
            initial.glowStrength = d.object(forKey: "glowStrength") as? Double ?? initial.glowStrength
            initial.dimBackground = d.object(forKey: "dimBackground") as? Bool ?? initial.dimBackground
            initial.dimStrength = d.object(forKey: "dimStrength") as? Double ?? initial.dimStrength
            appearance = initial
        }
        readingSeconds = d.object(forKey: "readingSeconds") as? Double ?? 10
        autoAdvance = d.bool(forKey: "autoAdvance")
        transitionSeconds = d.object(forKey: "transitionSeconds") as? Double ?? 0.45
        speakSteps = d.bool(forKey: "speakSteps")
        voice = d.string(forKey: "voice") ?? ""
        speechRate = d.object(forKey: "speechRate") as? Double ?? 0.45
        tourLimit = d.object(forKey: "tourLimit") as? Double ?? 36
        groupSimilar = d.object(forKey: "groupSimilar") as? Bool ?? true
        browserScope = d.string(forKey: "browserScope") ?? "ask"
        spaceAdvances = d.object(forKey: "spaceAdvances") as? Bool ?? true
        soundEffects = d.object(forKey: "soundEffects") as? Bool ?? true
        askFeedback = d.object(forKey: "askFeedback") as? Bool ?? true
        soundVolume = d.object(forKey: "soundVolume") as? Double ?? 0.6
        recentApps = d.dictionary(forKey: "recentApps") as? [String: String] ?? [:]
        blockedApps = d.dictionary(forKey: "blockedApps") as? [String: String] ?? [:]
        useOCR = d.object(forKey: "useOCR") as? Bool ?? true
        shortcutKey = UInt32(d.object(forKey: "shortcutKey") as? Int ?? 49)
        shortcutModifiers = UInt32(d.object(forKey: "shortcutModifiers") as? Int ?? 4608)
        areaKey = UInt32(d.object(forKey: "areaKey") as? Int ?? 0)
        areaModifiers = UInt32(d.object(forKey: "areaModifiers") as? Int ?? 4608)
    }
    private func save() {
        if let data = try? JSONEncoder().encode(appearance) { defaults.set(data, forKey: "guideAppearance") }
        defaults.set(readingSeconds, forKey: "readingSeconds")
        defaults.set(autoAdvance, forKey: "autoAdvance")
        defaults.set(transitionSeconds, forKey: "transitionSeconds")
        defaults.set(speakSteps, forKey: "speakSteps")
        defaults.set(voice, forKey: "voice")
        defaults.set(speechRate, forKey: "speechRate")
        defaults.set(tourLimit, forKey: "tourLimit")
        defaults.set(groupSimilar, forKey: "groupSimilar")
        defaults.set(browserScope, forKey: "browserScope")
        defaults.set(spaceAdvances, forKey: "spaceAdvances")
        defaults.set(soundEffects, forKey: "soundEffects")
        defaults.set(askFeedback, forKey: "askFeedback")
        defaults.set(soundVolume, forKey: "soundVolume")
        defaults.set(recentApps, forKey: "recentApps")
        defaults.set(blockedApps, forKey: "blockedApps")
        defaults.set(useOCR, forKey: "useOCR")
        defaults.set(Int(shortcutKey), forKey: "shortcutKey")
        defaults.set(Int(shortcutModifiers), forKey: "shortcutModifiers")
        defaults.set(Int(areaKey), forKey: "areaKey")
        defaults.set(Int(areaModifiers), forKey: "areaModifiers")
    }
}
