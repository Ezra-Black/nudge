import AppKit

extension AppController {
    /// Lets the person drag out part of the screen, then explains only what's inside it.
    func selectArea() {
        if areaSelector.isActive {
            areaSelector.cancel()
            return
        }
        if active { pause() }
        areaSelector.begin { [weak self] region in
            guard let self, let region else { return }
            // Explain the app whose window is under the middle of the area.
            guard let app = ScreenObserver.app(at: CGPoint(x: region.midX, y: region.midY)) ?? self.lastExternal else { return }
            // Keep the chosen box outlined from the moment it's confirmed until it has been explained.
            self.overlay.model.icon = NSRunningApplication(processIdentifier: app.pid)?.icon
            self.overlay.present(
                GuideContent(kind: .loading, app: app.name, title: "Looking at this area…"), target: nil,
                window: ScreenObserver.frontWindowFrame(app.pid), focusRect: region)
            NSRunningApplication(processIdentifier: app.pid)?.activate(options: [])
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                self.begin(app, region: region)
            }
        }
    }
    func toggle() {
        if areaSelector.isActive {
            areaSelector.cancel()
            return
        }
        if active {
            pause()
            return
        }
        let current = NSWorkspace.shared.frontmostApplication.flatMap(TargetApp.init) ?? lastExternal
        guard let current else {
            showWindow()
            return
        }
        if phase == .paused, target?.pid == current.pid, state != nil {
            resume()
            return
        }
        begin(current)
    }
    func begin(_ candidate: TargetApp, region: CGRect? = nil) {
        refreshAvailability()
        error = nil
        let frame = ScreenObserver.frontWindowFrame(candidate.pid)
        guard modelReady else {
            showSetupNeeded(modelDetail, window: frame)
            return
        }
        guard preferences.blockedApps[candidate.bundle] == nil else {
            showSetupNeeded("This app is excluded from guidance. You can allow it again in Nudge’s Privacy settings.", window: frame)
            return
        }
        guard accessibilityReady || (captureReady && preferences.useOCR) else {
            showSetupNeeded(
                "Allow Nudge in System Settings → Privacy & Security → Accessibility. If it’s already listed, remove it and add this build again.",
                window: frame)
            return
        }
        if let previous = target, previous.pid != candidate.pid { observer.release(previous.pid) }
        preferences.recentApps[candidate.bundle] = candidate.name
        target = candidate
        targetName = candidate.name
        sessionGoal = goal
        progress = []
        refreshCount = 0
        canObserve = true
        state = nil
        snapshot = nil
        overlay.model.icon = NSRunningApplication(processIdentifier: candidate.pid)?.icon
        SoundEffects.shared.play(.scan)
        scope = "all"
        areaRegion = region
        if region != nil { sessionGoal = "" }
        if sessionGoal.isEmpty && candidate.isBrowser && region == nil {
            if preferences.browserScope == "ask" {
                askScope(candidate)
                return
            }
            scope = preferences.browserScope
        }
        prepare()
    }
    /// In a browser, ask first whether to explain the web page or the browser around it.
    private func askScope(_ app: TargetApp) {
        canObserve = false
        phase = .choosing
        status = "Choose what you’d like to learn about."
        overlay.present(
            GuideContent(
                kind: .choice, app: app.name, title: "What would you like to learn about?", message: "",
                choices: [
                    GuideChoice(
                        id: "web", title: "This web page", detail: "What’s on the page, and where its links and buttons go", symbol: "globe"
                    ),
                    GuideChoice(
                        id: "app", title: "\(app.name)’s controls", detail: "Tabs, the address bar and toolbar buttons", symbol: "macwindow"
                    ),
                ]), target: nil, window: ScreenObserver.frontWindowFrame(app.pid), focusWindow: true)
        announce("What would you like to learn about?", "This web page, or \(app.name)’s controls.")
    }
    func block(_ bundle: String) {
        preferences.blockedApps[bundle] = preferences.recentApps[bundle] ?? bundle
        if target?.bundle == bundle { closeGuide() }
    }
    func unblock(_ bundle: String) { preferences.blockedApps.removeValue(forKey: bundle) }
    private func showSetupNeeded(_ message: String, window: CGRect?) {
        canObserve = false
        phase = .paused
        error = message
        status = message
        notice(title: "One setting needs attention", message: message, primary: .setup, window: window)
        try? escapeHotkey.register(key: 53, modifiers: 0)
    }
    func notice(
        title: String, message: String, primary: GuidePrimary, window: CGRect?, windowID: UInt32? = nil, mood: MascotMood? = nil
    ) {
        overlay.present(
            GuideContent(kind: .notice, app: targetName.isEmpty ? "Nudge" : targetName, title: title, message: message, primary: primary),
            target: nil, window: window, windowID: windowID, mood: mood)
    }
    func pause(message: String = "Take your time. Press the shortcut to continue.") {
        if touring {
            endTour(finished: false)
            return
        }
        canObserve = false
        operation?.cancel()
        operation = nil
        cancelCheck()
        autoTask?.cancel()
        requestID = UUID()
        overlay.hide()
        speaker.stop()
        phase = .paused
        status = message
    }
    func closeGuide() {
        if touring {
            endTour(finished: tourIndex == tourStops.count - 1)
            return
        }
        if phase != .idle { SoundEffects.shared.play(.goodbye) }
        if feedbackPending { recordFeedback(helpful: false, note: "") }
        feedback = nil
        feedbackPending = false
        overlay.model.draft = ""
        pause()
        explainTask?.cancel()
        phase = .idle
        state = nil
        snapshot = nil
        onIntro = false
        areaRegion = nil
        status = "Ready when you need a nudge."
        if let target { observer.release(target.pid) }
        Task { let _: GuideState? = try? await engine.call("clear", as: GuideState.self) }
    }
    func cancelCheck() {
        checkTask?.cancel()
        checkTask = nil
        checkToken = UUID()
    }
    private func resume() {
        guard let target, preferences.blockedApps[target.bundle] == nil else {
            closeGuide()
            return
        }
        canObserve = true
        if onIntro {
            showIntro(forward: true)
            return
        }
        let includeOCR = state?.target_source == "ocr"
        let goalMode = !sessionGoal.isEmpty
        operation = Task {
            do {
                let current = try await observer.read(target, includeOCR: includeOCR, includeMenuBar: goalMode)
                try Task.checkCancellation()
                let updated: GuideState = try await engine.call(
                    "observe", ["observation": try current.observation.jsonObject()], as: GuideState.self)
                try Task.checkCancellation()
                snapshot = current
                state = updated
                lastCheck = Date()
                if updated.status == "step" {
                    targetLost = false
                    showStep(forward: true)
                } else if updated.status == "missing" {
                    targetLost = true
                    showStep(forward: true)
                } else if updated.status == "complete" {
                    showCompletion(forward: true)
                } else {
                    prepare()
                }
            } catch is CancellationError {} catch { fail(error) }
        }
    }
    func prepare() {
        guard let target, canObserve else { return }
        cancelCheck()
        operation?.cancel()
        autoTask?.cancel()
        explainTask?.cancel()
        requestID = UUID()
        let id = requestID
        phase = .reading
        status = "Reading \(target.name) on your Mac…"
        lastInterpretation = Date()
        onIntro = false
        targetLost = false
        typing = false
        // The hotkey is the complete request. A small status pill shows while the window is read.
        overlay.hideRing()
        overlay.present(
            GuideContent(
                kind: .loading, app: target.name, title: areaRegion == nil ? "Looking at \(target.name)…" : "Looking at this area…"),
            target: nil, window: ScreenObserver.frontWindowFrame(target.pid) ?? snapshot?.windowFrame, focusRect: areaRegion)
        let goalMode = !sessionGoal.isEmpty
        operation = Task {
            do {
                var current = try await observer.read(target, includeOCR: false, includeMenuBar: goalMode)
                // A chosen area is always looked at closely: its text is read and its picture described.
                if let area = areaRegion {
                    current = try await observer.inspectArea(area, in: current)
                } else if preferences.useOCR && captureReady && current.sparse {
                    current = try await observer.addingText(to: current)
                }
                try Task.checkCancellation()
                guard requestID == id, canObserve else { return }
                snapshot = current
                var fields: [String: Any] = [
                    "observation": try current.observation.jsonObject(), "goal": sessionGoal,
                    "progress": progress.suffix(3).joined(separator: "; "), "request": id.uuidString, "scope": scope,
                    "limit": Int(preferences.tourLimit), "group": preferences.groupSimilar,
                ]
                if let area = areaRegion {
                    let inside = area.intersection(current.frame)
                    guard !inside.isNull, inside.width > 4, inside.height > 4 else {
                        throw NudgeError(
                            "That area isn’t part of \(target.name)’s front window. Click the window you mean, then choose the area again.")
                    }
                    fields["region"] = try UnitRect(inside, in: current.frame).jsonObject()
                }
                let preparation: Preparation = try await engine.call("prepare", fields, as: Preparation.self)
                let result: GuideState
                if preparation.cached, let cached = preparation.state {
                    result = cached
                } else if let batches = preparation.batches {
                    // Tour: the overview comes first; each control's explanation is written while you read.
                    // Without an overview the tour still runs; it just starts at the first control.
                    // A chosen area goes straight to the things inside it; it's only summed up when there's nothing to point at.
                    var overview = GuidePlan(
                        title: areaRegion == nil ? target.name : "", introduction: "", conclusion: "", steps: [], continues: false)
                    if areaRegion == nil || batches.isEmpty {
                        do {
                            overview =
                                areaRegion == nil
                                ? try await LocalIntelligence.overview(prompt: preparation.prompt ?? "")
                                : try await LocalIntelligence.describeArea(prompt: preparation.prompt ?? "")
                        } catch is CancellationError { throw CancellationError() } catch {}
                    }
                    try Task.checkCancellation()
                    guard requestID == id, canObserve else { return }
                    result = try await engine.call(
                        "install", ["request": id.uuidString, "plan": try overview.jsonObject()], as: GuideState.self)
                    guideCount += 1
                    explain(batches, request: id.uuidString, about: overview.introduction)
                } else {
                    let plan = try await LocalIntelligence.generate(prompt: preparation.prompt ?? "")
                    try Task.checkCancellation()
                    guard requestID == id, canObserve else { return }
                    result = try await engine.call(
                        "install", ["request": id.uuidString, "plan": try plan.jsonObject()], as: GuideState.self)
                    guideCount += 1
                }
                try Task.checkCancellation()
                guard requestID == id, canObserve else { return }
                // Re-read after model latency. Never draw coordinates from a screen that changed meanwhile.
                var fresh = try await observer.read(target, includeOCR: false, includeMenuBar: goalMode)
                if result.target_source == "ocr" { fresh = try await observer.addingText(to: fresh) }
                try Task.checkCancellation()
                guard requestID == id, canObserve else { return }
                let verified: GuideState = try await engine.call(
                    "observe", ["observation": try fresh.observation.jsonObject()], as: GuideState.self)
                snapshot = fresh
                state = verified
                lastCheck = Date()
                if verified.status == "changed" {
                    showChanged()
                    return
                }
                SoundEffects.shared.play(.ready)
                failures = 0
                guard let plan = verified.plan ?? result.plan, !plan.steps.isEmpty else {
                    hasIntro = false
                    showCompletion(forward: true)
                    return
                }
                hasIntro = !plan.introduction.isEmpty && progress.isEmpty
                targetLost = verified.status == "missing"
                phase = .step
                if hasIntro {
                    onIntro = true
                    showIntro(forward: true)
                } else {
                    showStep(forward: true)
                }
                overlay.react(.cheery)
            } catch is CancellationError {} catch { if requestID == id { fail(error) } }
        }
    }
    func explain(_ prompts: [String], request: String, about overview: String) {
        explainTask?.cancel()
        // Each batch knows what the whole window is for, so its controls are explained in that light.
        let area = areaRegion != nil
        let context = overview.isEmpty ? "" : (area ? "About this selection: \(overview)\n" : "About this window: \(overview)\n")
        explainTask = Task {
            for (batch, prompt) in prompts.enumerated() {
                // A failed batch still reports in; the engine describes those controls from what it observed.
                let steps = (try? await LocalIntelligence.explain(prompt: context + prompt, area: area)) ?? []
                guard !Task.isCancelled else { return }
                let payload = (try? steps.jsonObject()) ?? [Any]()
                guard
                    let updated: GuideState = try? await engine.call(
                        "explain", ["request": request, "batch": batch, "steps": payload], as: GuideState.self), !Task.isCancelled
                else { continue }
                // Only the plan changes here; navigation may have moved the index meanwhile.
                guard var current = state, let plan = updated.plan else { continue }
                current.plan = plan
                state = current
                if awaitingExplanation, phase == .step, !onIntro, showingPage, state?.step?.ready == true {
                    showStep(forward: true)
                    overlay.react(.cheery, for: 0.9)
                }
            }
        }
    }
    private func pageContent(
        caption: String? = nil, title: String, message: String, hint: String = "", position: Int, forward: Bool,
        primary: GuidePrimary = .next, canBack: Bool, canSkip: Bool = false, busy: Bool = false
    ) -> GuideContent {
        GuideContent(
            kind: .page, app: caption ?? targetName, title: title, message: message, hint: hint, page: position, pages: pageCount,
            canBack: canBack, primary: primary, canSkip: canSkip, forward: forward, busy: busy)
    }
    private func showIntro(forward: Bool) {
        guard let plan = state?.plan else { return }
        autoTask?.cancel()
        cancelCheck()
        onIntro = true
        canObserve = true
        phase = .step
        awaitingExplanation = false
        let hint = preferences.spaceAdvances ? "Press Space or choose Next to begin." : ""
        overlay.present(
            pageContent(
                title: plan.title.isEmpty ? targetName : plan.title, message: plan.introduction, hint: hint, position: 0, forward: forward,
                canBack: false), target: nil, window: snapshot?.windowFrame, windowID: snapshot?.observation.window_id, focusWindow: true,
            focusRect: areaRegion)
        announce(plan.title, plan.introduction)
        status = "Guiding you through \(targetName)."
        updateSpaceKey()
    }
    private func showStep(forward: Bool, restartTimer: Bool = true) {
        guard let step = state?.step, let index = state?.index, let snapshot else {
            showChanged()
            return
        }
        canObserve = true
        phase = .step
        let hint: String
        if targetLost {
            hint =
                step.action
                ? "The screen changed. If you finished this step, choose Done."
                : "I can’t see this right now. It may be scrolled out of view."
        } else {
            hint = step.action ? "Try it in the app, then choose Done." : ""
        }
        awaitingExplanation = !step.ready
        let content = pageContent(
            caption: step.area.isEmpty ? nil : step.area, title: step.title,
            message: step.ready ? step.explanation : "Getting this one ready…", hint: step.ready ? hint : "",
            position: index + (hasIntro ? 1 : 0), forward: forward, primary: step.action ? .confirm : .next, canBack: index > 0 || hasIntro,
            canSkip: step.action, busy: !step.ready)
        let spot = targetLost ? nil : state?.bounds.map { $0.screenRect(in: snapshot.frame) }
        // Can't see the control right now: a puzzled look rather than pointing at nothing.
        // In a chosen area, the area stays framed while each thing inside it is highlighted in turn.
        overlay.present(
            content, target: spot, window: snapshot.windowFrame, windowID: snapshot.observation.window_id, focusRect: areaRegion,
            mood: targetLost ? .confused : nil)
        status = "Guiding you through \(targetName)."
        updateSpaceKey()
        guard restartTimer else { return }
        if step.ready { announce(step.title, step.explanation) }
        autoTask?.cancel()
        if preferences.autoAdvance && !step.action && step.ready {
            let seconds =
                max(preferences.readingSeconds, Double(step.explanation.split(separator: " ").count) / 2.2) + preferences.transitionSeconds
                + 0.3
            autoTask = Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, phase == .step, !onIntro else { return }
                next()
            }
        }
    }
    func next(skipped: Bool = false) {
        autoTask?.cancel()
        if touring {
            if tourIndex == tourStops.count - 1 { endTour(finished: true) } else { tourMove(to: tourIndex + 1) }
            return
        }
        if phase == .complete {
            closeGuide()
            return
        }
        guard phase == .step, showingPage, !changingStep else { return }
        if onIntro {
            onIntro = false
            guard state?.step != nil else {
                showCompletion(forward: true)
                return
            }
            typing = false
            showStep(forward: true)
            return
        }
        guard let old = state?.step else { return }
        if old.action && !sessionGoal.isEmpty && state?.plan?.continues == true {
            if skipped {
                pause(message: "Step skipped. Change your goal or resume when you’re ready.")
                return
            }
            progress.append("User confirmed: \(old.title)")
            overlay.react(.celebrating, for: 1.2)
            prepare()
            return
        }
        move("next", forward: true)
    }
    func back() {
        if touring {
            tourMove(to: tourIndex - 1)
            return
        }
        // Once "Did I do good?" is answered, the guide is over.
        if let feedback, feedback != .ask { return }
        guard !changingStep, showingPage else { return }
        autoTask?.cancel()
        if phase == .complete {
            if stepCount > 0 { move("back", forward: false) }
            return
        }
        guard phase == .step, !onIntro else { return }
        if (state?.index ?? 0) == 0 {
            if hasIntro { showIntro(forward: false) }
            return
        }
        move("back", forward: false)
    }
    /// Jumps to a page from the progress dots. Page 0 is the overview when the tour has one.
    func jump(to page: Int) {
        if touring {
            tourMove(to: page)
            return
        }
        guard !changingStep, showingPage, phase == .step || phase == .complete else { return }
        autoTask?.cancel()
        let index = page - (hasIntro ? 1 : 0)
        let current = onIntro ? -1 : (phase == .complete ? stepCount : (state?.index ?? 0))
        guard index != current else { return }
        if index < 0 {
            showIntro(forward: false)
            return
        }
        move("goto", ["index": index], forward: index > current)
    }
    func move(_ command: String, _ fields: [String: Any] = [:], forward: Bool) {
        changingStep = true
        cancelCheck()
        onIntro = false
        targetLost = false
        typing = false
        feedback = nil
        operation = Task {
            defer { changingStep = false }
            do {
                let updated: GuideState = try await engine.call(command, fields, as: GuideState.self)
                try Task.checkCancellation()
                if updated.status == "complete" {
                    state = updated
                    showCompletion(forward: forward)
                    return
                }
                // The engine answers from the latest read of the window, so moving on needs no new scan.
                apply(updated, forward: forward, restartTimer: true)
            } catch is CancellationError {} catch { fail(error) }
        }
    }
    private func showCompletion(forward: Bool) {
        phase = .complete
        canObserve = false
        onIntro = false
        autoTask?.cancel()
        cancelCheck()
        let empty = stepCount == 0
        let title =
            empty
            ? (areaRegion != nil
                ? (state?.plan?.title.isEmpty == false ? state!.plan!.title : "Here’s what’s in this area") : "Here’s what I found")
            : (sessionGoal.isEmpty
                ? (["All done!", "Ta-da! That’s everything!", "That’s the whole tour!"].randomElement() ?? "All done!")
                : "That’s everything for now")
        // A window with nothing to click still gets its overview.
        let conclusion = (empty && sessionGoal.isEmpty ? state?.plan?.introduction : state?.plan?.conclusion) ?? ""
        let message = conclusion.isEmpty ? "Press \(shortcutLabel) whenever you want another nudge." : conclusion
        // Nudge ends every guide by asking how he did.
        feedback = preferences.askFeedback ? .ask : nil
        var content = GuideContent(
            kind: .page, app: targetName, title: title, message: message, page: pageCount, pages: empty ? 0 : pageCount, canBack: !empty,
            primary: .finish, forward: forward)
        content.feedback = feedback
        overlay.present(
            content, target: nil, window: snapshot?.windowFrame, windowID: snapshot?.observation.window_id, focusRect: areaRegion,
            mood: feedback == nil ? nil : .cheery)
        status = "Guide finished."
        updateSpaceKey()
        announce(title, feedback == nil ? conclusion : [conclusion, "Did I do good?"].filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Reads a card aloud when that setting is on. Re-checks of the same step stay quiet.
    func announce(_ title: String, _ message: String) {
        guard preferences.speakSteps else {
            speaker.stop()
            return
        }
        speaker.say([title, message].filter { !$0.isEmpty }.joined(separator: ". "))
    }
    private func showChanged() {
        autoTask?.cancel()
        cancelCheck()
        phase = .step
        onIntro = false
        notice(
            title: "The screen changed", message: "I’ll take a fresh look before pointing at anything.", primary: .rescan,
            window: snapshot?.windowFrame, windowID: snapshot?.observation.window_id, mood: .surprised)
        status = "Waiting to read the changed screen."
        canObserve = false
        updateSpaceKey()
    }
    func screenInput(_ type: NSEvent.EventType) {
        inputAt = Date()
        needsCheck = true
        autoTask?.cancel()
        cancelCheck()
        if type == .keyDown && !typing {
            typing = true
            updateSpaceKey()
        }
        // What's under the highlight may be moving. It returns once things settle.
        // Scrolling moves what's under the highlight; it returns once things settle. Clicks and typing leave it be.
        if type == .scrollWheel && phase == .step && !onIntro { overlay.hideRing() }
    }
    func tick() {
        if !active, window?.isVisible == true, Date().timeIntervalSince(lastReadinessCheck) > 2 {
            lastReadinessCheck = Date()
            refreshAvailability()
        }
        guard canObserve, phase == .step, !onIntro, !changingStep, checkTask == nil, let target else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier == target.pid || front.bundleIdentifier == Bundle.main.bundleIdentifier
        else {
            pause(message: "Paused while you’re in another app.")
            return
        }
        // Full reads only after the person's input settles, plus an occasional check while idle.
        guard Date().timeIntervalSince(inputAt) > preferences.changeDebounce,
            needsCheck || Date().timeIntervalSince(lastCheck) > preferences.recheckInterval
        else { return }
        runCheck()
    }
    /// Re-reads the window and follows the current step's control, or reacts if it's gone.
    private func runCheck(delay: Double = 0) {
        guard canObserve, phase == .step, !onIntro, let target else { return }
        cancelCheck()
        needsCheck = false
        let token = UUID()
        checkToken = token
        let id = requestID
        let index = state?.index
        let includeOCR = state?.target_source == "ocr"
        let goalMode = !sessionGoal.isEmpty
        func current() -> Bool {
            canObserve && requestID == id && !changingStep && phase == .step && !onIntro && showingPage && state?.index == index
        }
        checkTask = Task {
            defer { if checkToken == token { checkTask = nil } }
            do {
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                let fresh = try await observer.read(target, includeOCR: includeOCR, includeMenuBar: goalMode)
                try Task.checkCancellation()
                guard current() else { return }
                let result: GuideState = try await engine.call(
                    "observe", ["observation": try fresh.observation.jsonObject()], as: GuideState.self)
                try Task.checkCancellation()
                guard current() else { return }
                snapshot = fresh
                lastCheck = Date()
                apply(result)
            } catch is CancellationError {} catch { pause(message: "The window is no longer available. Press the shortcut to try again.") }
        }
    }
    private func apply(_ result: GuideState, forward: Bool = true, restartTimer: Bool = false) {
        switch result.status {
        case "step" where result.bounds != nil:
            state = result
            targetLost = false
            showStep(forward: forward, restartTimer: restartTimer)
        case "missing":
            state = result
            targetLost = true
            autoTask?.cancel()
            showStep(forward: forward, restartTimer: restartTimer)
        default:
            autoTask?.cancel()
            if result.step?.action == true || state?.step?.action == true {
                // No completion is inferred from a click, timer or navigation. The person confirms.
                if result.plan != nil { state = result }
                targetLost = true
                showStep(forward: forward, restartTimer: restartTimer)
            } else if Date().timeIntervalSince(lastInterpretation) > preferences.interpretationCooldown && refreshCount < 2 {
                refreshCount += 1
                prepare()
            } else {
                showChanged()
            }
        }
    }
    private func fail(_ problem: Error) {
        pause()
        error = problem.localizedDescription
        status = "Nudge needs a moment."
        failures += 1
        notice(
            title: "I couldn’t read this screen yet", message: problem.localizedDescription, primary: .retry,
            window: snapshot?.windowFrame ?? target.flatMap { ScreenObserver.frontWindowFrame($0.pid) },
            windowID: snapshot?.observation.window_id, mood: failures >= 2 ? .angry : .upset)
        try? escapeHotkey.register(key: 53, modifiers: 0)
    }
    func retryChanged() {
        SoundEffects.shared.play(.scan)
        canObserve = true
        prepare()
    }
    func replay() {
        guard state?.plan != nil, let target, preferences.blockedApps[target.bundle] == nil else {
            toggle()
            return
        }
        window?.orderOut(nil)
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
        canObserve = true
        operation = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                state = try await engine.call("replay", as: GuideState.self)
                try Task.checkCancellation()
                targetLost = false
                if hasIntro {
                    showIntro(forward: false)
                } else if stepCount > 0 {
                    showStep(forward: false)
                    needsCheck = true
                } else {
                    showCompletion(forward: false)
                }
            } catch is CancellationError {} catch { fail(error) }
        }
    }

}
