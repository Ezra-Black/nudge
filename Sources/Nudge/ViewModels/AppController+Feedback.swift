import Foundation

extension AppController {
    private static let cheers = [
        "You just made my whole day! I’m so happy I could help.",
        "That makes me want to do a happy little wiggle! Come find me anytime.",
        "Hooray! Helping you is my very favorite thing.",
        "Thank you! I’ll be right up in the menu bar whenever you need me.",
    ]
    func answer(_ helpful: Bool) {
        guard feedback == .ask else { return }
        if helpful {
            recordFeedback(helpful: true, note: "")
            SoundEffects.shared.play(.yay)
            showFeedback(.happy, title: "Yay!", message: Self.cheers.randomElement() ?? Self.cheers[0], mood: .celebrating)
            overlay.react(.excited, for: 1.6)
        } else {
            feedbackPending = true
            SoundEffects.shared.play(.aww)
            // Sad for a moment, then he hides his eyes while the note box is open.
            showFeedback(
                .note, title: ["Oh no, I’m sorry!", "Oops… I’m so sorry!"].randomElement() ?? "Oh no, I’m sorry!",
                message: "What did I get wrong? Tell me here and I’ll keep your note on this Mac.", mood: .shy)
            overlay.react(.upset, for: 1.3)
        }
    }
    func sendNote(_ note: String) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard feedback == .note, !text.isEmpty else { return }
        recordFeedback(helpful: false, note: text)
        feedbackPending = false
        overlay.model.draft = ""
        SoundEffects.shared.play(.ready)
        showFeedback(
            .sent, title: "Thank you for telling me!", message: "I saved your note on this Mac. Want me to take another look?", mood: .happy
        )
        overlay.react(.cheery, for: 1.2)
    }
    private func showFeedback(_ stage: FeedbackStage, title: String, message: String, mood: MascotMood) {
        feedback = stage
        var content = GuideContent(
            kind: .page, app: targetName, title: title, message: message, page: pageCount, pages: 0, canBack: false, primary: .finish,
            forward: true)
        content.feedback = stage
        overlay.present(
            content, target: nil, window: snapshot?.windowFrame, windowID: snapshot?.observation.window_id, focusRect: areaRegion,
            mood: mood)
        overlay.allowTyping(stage == .note)
        updateSpaceKey()
        announce(title, message)
    }
    /// Explains the same window or area again from scratch, after a "no".
    func lookAgain() {
        overlay.allowTyping(false)
        if feedbackPending { recordFeedback(helpful: false, note: "") }
        feedback = nil
        feedbackPending = false
        overlay.model.draft = ""
        Task {
            let _: GuideState? = try? await engine.call("clear", as: GuideState.self)
            canObserve = true
            refreshCount = 0
            progress = []
            SoundEffects.shared.play(.scan)
            prepare()
        }
    }
    /// Keeps the answer, and what Nudge said, in a file on this Mac only. Nothing is sent anywhere.
    func recordFeedback(helpful: Bool, note: String) {
        let entry = FeedbackEntry(
            date: Date(), app: targetName, guide: areaRegion != nil ? "area" : (sessionGoal.isEmpty ? "tour" : "goal"),
            helpful: helpful, note: note, overview: state?.plan?.introduction ?? "",
            steps: (state?.plan?.steps ?? []).prefix(40).map { FeedbackEntry.Said(title: $0.title, explanation: $0.explanation) })
        try? FeedbackStore.standard.append(entry)
    }
}
