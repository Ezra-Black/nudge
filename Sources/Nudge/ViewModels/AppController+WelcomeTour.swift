import AppKit

extension AppController {
    /// A scripted tour of Nudge's own window, so people learn how to use it and see the guide in action.
    /// It needs no permissions and no model, so it works the moment Nudge is first opened.
    func startWelcomeTour() {
        if touring { return }
        if phase != .idle { closeGuide() }
        showWindow(section: "Start")
        tourStops = [
            TourStop(
                anchor: nil, title: "Hi, I’m Nudge!",
                message:
                    "I help you find your way around any app or website, one step at a time. Let me show you how I work. It only takes a minute."
            ),
            TourStop(
                anchor: "shortcut", title: "Your helping shortcut",
                message:
                    "Open any app or website and press \(shortcutLabel). I’ll look at the window and explain what’s there, one step at a time."
            ),
            TourStop(
                anchor: "area", title: "Just one part?",
                message:
                    "Press \(areaShortcutLabel) and drag a box around anything on screen. I’ll explain only what’s inside it, even plain text or a picture."
            ),
            TourStop(
                anchor: "keys", title: "Moving through a guide",
                message:
                    "Press Space for the next step and Shift-Space to go back, or use the big Back and Next buttons. Esc closes the guide."),
            TourStop(
                anchor: "goal", title: "Tell me what you want to do",
                message: "Type a goal here, like “print this page”, and I’ll guide you to it one action at a time."),
            TourStop(
                anchor: "section-Setup", title: "Setup",
                message: "Here you let me read the screen, and choose your shortcuts. I never click or type for you."),
            TourStop(
                anchor: "section-Reading", title: "Guide",
                message: "Choose how long tours are, whether I read steps aloud, my sounds, and how quickly things move."),
            TourStop(
                anchor: "section-Appearance", title: "Appearance", message: "Make me yours: colors, text size, the glow, and how big I am."),
            TourStop(anchor: "section-Privacy", title: "Privacy", message: "Everything stays on this Mac. No cloud and no uploads."),
            TourStop(
                anchor: "menubar", title: "I live up here",
                message: "Find me in the menu bar whenever you need me. Press \(shortcutLabel) in any app to begin."),
        ]
        tourIndex = 0
        touring = true
        canObserve = false
        targetName = "Nudge"
        // Let the window finish laying out so every control has reported where it is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.touring else { return }
            SoundEffects.shared.play(.ready)
            self.phase = .step
            self.presentTourStop(forward: true)
            self.overlay.react(.cheery)
        }
    }
    /// Called as the settings window's controls report their positions, so the highlight stays on them while scrolling.
    func anchorsChanged(_ frames: [String: CGRect]) {
        let old = tourStops.indices.contains(tourIndex) ? tourStops[tourIndex].anchor.flatMap { anchors[$0] } : nil
        anchors = frames
        guard touring, let id = tourStops[tourIndex].anchor, let now = frames[id], let old else { return }
        if abs(now.minX - old.minX) + abs(now.minY - old.minY) > 1 { presentTourStop(forward: true, quiet: true) }
    }
    func presentTourStop(forward: Bool, quiet: Bool = false) {
        guard touring, let window, tourStops.indices.contains(tourIndex) else { return }
        let stop = tourStops[tourIndex]
        if section != "Start" { section = "Start" }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = CGRect(x: window.frame.minX, y: top - window.frame.maxY, width: window.frame.width, height: window.frame.height)
        var spot: CGRect?
        if stop.anchor == "menubar", let icon = statusItemFrame?() {
            // The menu bar sits above ordinary overlays; lift Nudge's layer so the icon can be highlighted.
            overlay.raised = true
            spot = CGRect(x: icon.minX, y: top - icon.maxY, width: icon.width, height: icon.height)
        } else {
            overlay.raised = false
            spot = stop.anchor.flatMap { anchors[$0] }.map {
                CGRect(x: frame.minX + $0.minX, y: frame.minY + $0.minY, width: $0.width, height: $0.height)
            }
        }
        let last = tourIndex == tourStops.count - 1
        let hint = tourIndex == 0 && preferences.spaceAdvances ? "Press Space or choose Next to begin." : ""
        overlay.model.icon = NSApp.applicationIconImage
        overlay.present(
            GuideContent(
                kind: .page, app: "Welcome to Nudge", title: stop.title, message: stop.message, hint: hint, page: tourIndex,
                pages: tourStops.count, canBack: tourIndex > 0, primary: last ? .finish : .next, forward: forward), target: spot,
            window: frame, windowID: UInt32(window.windowNumber), focusWindow: spot == nil)
        if !quiet { announce(stop.title, stop.message) }
        status = "Showing you around Nudge."
        updateSpaceKey()
    }
    func tourMove(to index: Int) {
        guard touring, tourStops.indices.contains(index), index != tourIndex else { return }
        let forward = index > tourIndex
        tourIndex = index
        presentTourStop(forward: forward)
    }
    func endTour(finished: Bool) {
        guard touring else { return }
        touring = false
        UserDefaults.standard.set(true, forKey: "welcomeTourSeen")
        SoundEffects.shared.play(.goodbye)
        overlay.hide()
        overlay.raised = false
        speaker.stop()
        phase = .idle
        status = "Ready when you need a nudge."
        // Straight on to setup if Nudge can't read the screen yet.
        if finished && !accessibilityReady { section = "Setup" }
    }

}
