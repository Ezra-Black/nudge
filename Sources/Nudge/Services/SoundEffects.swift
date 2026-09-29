import AVFoundation

/// Nudge's own bubbly sound effects, synthesized when first needed. No audio files are bundled.
@MainActor final class SoundEffects: NSObject, AVAudioPlayerDelegate {
    enum Effect: CaseIterable { case scan, ready, goodbye, yay, aww }
    static let shared = SoundEffects()
    private static let rate = 44_100.0
    private lazy var clips: [Effect: Data] = Dictionary(uniqueKeysWithValues: Effect.allCases.map { ($0, Self.wav(Self.render($0))) })
    /// Players are kept alive until they finish.
    private var playing: [AVAudioPlayer] = []

    /// `preview` plays even when sound effects are turned off, for the buttons in Settings.
    func play(_ effect: Effect, preview: Bool = false) {
        let prefs = Preferences.shared
        guard preview || prefs.soundEffects, let data = clips[effect], let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = Float(prefs.soundVolume)
        player.delegate = self
        playing.append(player)
        player.play()
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in self.playing.removeAll { ObjectIdentifier($0) == finished } }
    }

    // MARK: Synthesis

    private struct Bubble {
        var at: Double
        var frequency: Double
        var glide: Double
        var length: Double
        var decay: Double
        var gain: Double
    }
    private static func render(_ effect: Effect) -> [Float] {
        let bubbles: [Bubble]
        switch effect {
        case .scan:
            // Bubbles rising while Nudge looks around.
            bubbles = [
                Bubble(at: 0.00, frequency: 480, glide: 1.7, length: 0.12, decay: 0.035, gain: 0.45),
                Bubble(at: 0.075, frequency: 600, glide: 1.7, length: 0.12, decay: 0.035, gain: 0.42),
                Bubble(at: 0.14, frequency: 720, glide: 1.75, length: 0.12, decay: 0.035, gain: 0.40),
                Bubble(at: 0.21, frequency: 900, glide: 1.8, length: 0.14, decay: 0.04, gain: 0.40),
                Bubble(at: 0.27, frequency: 1800, glide: 1.2, length: 0.10, decay: 0.03, gain: 0.12),
            ]
        case .ready:
            // A bright "pop-pop!" with a little sparkle as the first card arrives.
            bubbles = [
                Bubble(at: 0.00, frequency: 560, glide: 1.5, length: 0.14, decay: 0.05, gain: 0.50),
                Bubble(at: 0.09, frequency: 840, glide: 1.5, length: 0.18, decay: 0.07, gain: 0.50),
                Bubble(at: 0.16, frequency: 1680, glide: 1.15, length: 0.20, decay: 0.06, gain: 0.15),
                Bubble(at: 0.20, frequency: 2240, glide: 1.1, length: 0.15, decay: 0.04, gain: 0.08),
            ]
        case .goodbye:
            // Bubbles drifting down, then a soft pop.
            bubbles = [
                Bubble(at: 0.00, frequency: 880, glide: 0.75, length: 0.13, decay: 0.045, gain: 0.45),
                Bubble(at: 0.09, frequency: 700, glide: 0.75, length: 0.13, decay: 0.045, gain: 0.45),
                Bubble(at: 0.18, frequency: 520, glide: 0.7, length: 0.20, decay: 0.07, gain: 0.50),
                Bubble(at: 0.30, frequency: 300, glide: 1.3, length: 0.12, decay: 0.04, gain: 0.25),
            ]
        case .yay:
            // A happy little run up the scale, then sparkles.
            bubbles = [
                Bubble(at: 0.00, frequency: 523, glide: 1.25, length: 0.12, decay: 0.05, gain: 0.45),
                Bubble(at: 0.08, frequency: 659, glide: 1.25, length: 0.12, decay: 0.05, gain: 0.45),
                Bubble(at: 0.16, frequency: 784, glide: 1.25, length: 0.12, decay: 0.05, gain: 0.45),
                Bubble(at: 0.24, frequency: 1047, glide: 1.3, length: 0.22, decay: 0.09, gain: 0.50),
                Bubble(at: 0.32, frequency: 2093, glide: 1.1, length: 0.18, decay: 0.05, gain: 0.14),
                Bubble(at: 0.40, frequency: 2637, glide: 1.1, length: 0.16, decay: 0.05, gain: 0.10),
            ]
        case .aww:
            // A soft, sad "aww", sliding down.
            bubbles = [
                Bubble(at: 0.00, frequency: 660, glide: 0.82, length: 0.24, decay: 0.14, gain: 0.40),
                Bubble(at: 0.22, frequency: 540, glide: 0.62, length: 0.42, decay: 0.22, gain: 0.42),
            ]
        }
        let total = bubbles.map { $0.at + $0.length }.max() ?? 0
        var out = [Float](repeating: 0, count: Int((total + 0.05) * rate))
        for bubble in bubbles { add(bubble, to: &out) }
        // Leave headroom so layered bubbles never clip.
        let peak = out.map(abs).max() ?? 1
        if peak > 0 { out = out.map { $0 / peak * 0.8 } }
        return out
    }
    /// A sine whose pitch glides quickly (up for a "bloop", down for a drop) under a soft pluck envelope.
    private static func add(_ bubble: Bubble, to out: inout [Float]) {
        let first = Int(bubble.at * rate)
        let count = Int(bubble.length * rate)
        var phase = 0.0
        for i in 0..<count where first + i < out.count {
            let t = Double(i) / rate
            let frequency = bubble.frequency * pow(bubble.glide, min(1, t / bubble.length * 1.6))
            phase += 2 * .pi * frequency / rate
            let attack = min(1, t / 0.004)
            let release = min(1, Double(count - i) / (0.01 * rate))
            let envelope = attack * release * exp(-t / bubble.decay)
            out[first + i] += Float(envelope * (sin(phase) + 0.18 * sin(2 * phase)) * bubble.gain)
        }
    }
    /// Mono 16-bit PCM in a WAV container, so AVAudioPlayer can play it from memory.
    private static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        let sampleRate = UInt32(rate)
        data.append(contentsOf: Array("RIFF".utf8))
        u32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        u32(16)
        u16(1)
        u16(1)
        u32(sampleRate)
        u32(sampleRate * 2)
        u16(2)
        u16(16)
        data.append(contentsOf: Array("data".utf8))
        u32(bytes)
        for sample in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32_767))) }
        return data
    }
}
