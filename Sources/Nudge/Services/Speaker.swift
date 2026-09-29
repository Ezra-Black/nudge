import AVFoundation
import Combine

/// Reads guide cards aloud with the Mac's on-device voices. The card shows pause and stop while it speaks.
@MainActor final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, speaking, paused }
    static let shared = Speaker()
    @Published private(set) var state = State.idle
    private let synthesizer = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        guard !text.isEmpty else { return }
        let prefs = Preferences.shared
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice =
            AVSpeechSynthesisVoice(identifier: prefs.voice)
            ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = Float(prefs.speechRate)
        synthesizer.speak(utterance)
    }
    func togglePause() {
        if synthesizer.isPaused { synthesizer.continueSpeaking() } else if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    private func sync() { state = synthesizer.isPaused ? .paused : (synthesizer.isSpeaking ? .speaking : .idle) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.sync() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in self.sync() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in self.sync() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.sync() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.sync() }
    }

    /// Voices for the Mac's language, best quality first.
    static var voices: [AVSpeechSynthesisVoice] {
        let language = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name }
    }
}
