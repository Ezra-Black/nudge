import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@MainActor final class AppController: ObservableObject {
    enum Phase: String { case idle, reading, choosing, step, paused, complete }
    @Published var phase: Phase = .idle
    @Published var status = "Ready when you need a nudge."
    @Published var error: String?
    @Published var targetName = ""
    @Published var goal = ""
    @Published var modelReady = false
    @Published var modelDetail = ""
    @Published var accessibilityReady = false
    @Published var captureReady = false
    /// Screen Recording was requested this session. macOS applies it only after Nudge is reopened.
    @Published var captureRequested = false
    /// Switched on in System Settings but not yet in effect: Nudge needs reopening.
    @Published var captureNeedsRestart = false
    @Published var guideCount = 0
    @Published var launchAtLogin = false
    @Published var shortcutLabel = "⌃ ⇧ Space"
    @Published var areaShortcutLabel = "⌃ ⇧ A"
    let areaSelector = AreaSelector()
    let areaHotkey = Hotkey(identifier: 7)
    /// The part of the screen chosen with the area selector (top-left origin), or nil for the whole window.
    var areaRegion: CGRect?
    @Published var section = "Start"
    let preferences = Preferences.shared
    let engine = EngineBridge()
    let observer = ScreenObserver()
    let overlay = Overlay()
    let hotkey = Hotkey()
    let speaker = Speaker.shared
    let escapeHotkey = Hotkey(identifier: 2)
    private let backHotkey = Hotkey(identifier: 3)
    private let forwardHotkey = Hotkey(identifier: 4)
    private let spaceHotkey = Hotkey(identifier: 5)
    private let shiftSpaceHotkey = Hotkey(identifier: 6)
    /// The person is typing in the app, so Space belongs to them until the guide moves on.
    var typing = false
    private var activitySubscription: AnyCancellable?
    var window: NSWindow?
    var lastExternal: TargetApp?
    var target: TargetApp?
    var snapshot: ScreenObservation?
    var state: GuideState?
    var operation: Task<Void, Never>?
    var checkTask: Task<Void, Never>?
    var checkToken = UUID()
    var timer: Timer?
    var autoTask: Task<Void, Never>?
    /// Writes a tour's step explanations in the background, a few controls at a time.
    var explainTask: Task<Void, Never>?
    private var workspaceToken: NSObjectProtocol?
    private var spaceToken: NSObjectProtocol?
    private var eventMonitor: Any?
    private var localMonitor: Any?
    var requestID = UUID()
    var inputAt = Date.distantPast
    var lastInterpretation = Date.distantPast
    var lastReadinessCheck = Date.distantPast
    var lastCheck = Date.distantPast
    var needsCheck = false
    var progress: [String] = []
    var sessionGoal = ""
    var canObserve = false
    var changingStep = false
    var refreshCount = 0
    /// A tour opens on an overview card before the first highlighted step.
    var hasIntro = false
    var onIntro = false
    /// The current step's control isn't on screen right now (scrolled away, or hidden by the person's action).
    var targetLost = false
    /// The step on screen is highlighted but its explanation hasn't arrived yet.
    var awaitingExplanation = false
    /// Failures in a row. Nudge is upset after one and cross after two; any success resets it.
    var failures = 0
    /// Where the "Did I do good?" exchange is on the last card, and whether a "no" still needs saving.
    var feedback: FeedbackStage?
    var feedbackPending = false
    var active: Bool { [.reading, .choosing, .step].contains(phase) }
    /// What a browser tour covers: "web" (the page), "app" (the browser's own controls) or "all".
    var scope = "all"
    var stepCount: Int { state?.plan?.steps.count ?? 0 }
    var pageCount: Int { stepCount + (hasIntro ? 1 : 0) }
    var showingPage: Bool { overlay.model.content.kind == .page }

    func start() {
        refreshAvailability()
        lastExternal = NSWorkspace.shared.frontmostApplication.flatMap(TargetApp.init)
        hotkey.action = { [weak self] in self?.toggle() }
        escapeHotkey.action = { [weak self] in self?.closeGuide() }
        backHotkey.action = { [weak self] in self?.back() }
        forwardHotkey.action = { [weak self] in self?.next() }
        spaceHotkey.action = { [weak self] in self?.advanceWithSpace() }
        shiftSpaceHotkey.action = { [weak self] in self?.back() }
        overlay.model.perform = { [weak self] action in self?.handle(action) }
        // A resized window moves controls around; read it again once the resizing stops.
        overlay.onWindowResized = { [weak self] in
            guard let self else { return }
            if self.touring {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.presentTourStop(forward: true) }
                return
            }
            self.needsCheck = true
            self.inputAt = Date()
        }
        activitySubscription = $phase.removeDuplicates().sink { [weak self] phase in self?.updateGuideKeys(phase) }
        do { try hotkey.register(key: preferences.shortcutKey, modifiers: preferences.shortcutModifiers) } catch {
            self.error = error.localizedDescription
        }
        shortcutLabel = Self.shortcutName(key: preferences.shortcutKey, modifiers: preferences.shortcutModifiers)
        areaHotkey.action = { [weak self] in self?.selectArea() }
        try? areaHotkey.register(key: preferences.areaKey, modifiers: preferences.areaModifiers)
        areaShortcutLabel = Self.shortcutName(key: preferences.areaKey, modifiers: preferences.areaModifiers)
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let external = TargetApp(app)
                else { return }
                self.lastExternal = external
                guard external.pid != self.target?.pid else { return }
                // Nudge's cards belong to the app they explain; they never follow you elsewhere.
                if self.active { self.pause(message: "Paused while you’re in another app.") } else { self.overlay.hide() }
            }
        }
        spaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.active { self.pause(message: "Paused while you’re in another Space.") } else { self.overlay.hide() }
            }
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) {
            [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                if event.type == .keyDown && event.keyCode == 53 {
                    self.closeGuide()
                    return
                }
                self.screenInput(event.type)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.closeGuide() }
                return nil
            }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: preferences.trackingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Closing settings never exits the utility. First run shows the getting-started screen.
        let loginLaunch =
            NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
        if !loginLaunch {
            showWindow(section: (!accessibilityReady && !captureReady) ? "Setup" : "Start")
            // The very first time, Nudge shows people around his own app.
            if !UserDefaults.standard.bool(forKey: "welcomeTourSeen") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.startWelcomeTour() }
            }
        }
    }
    private func updateGuideKeys(_ phase: Phase) {
        if phase == .idle || phase == .paused { escapeHotkey.unregister() } else { try? escapeHotkey.register(key: 53, modifiers: 0) }
        // ⌃⇧← and ⌃⇧→ page through the guide only while it's on screen.
        if phase == .step || phase == .complete {
            try? backHotkey.register(key: 123, modifiers: UInt32(controlKey | shiftKey))
            try? forwardHotkey.register(key: 124, modifiers: UInt32(controlKey | shiftKey))
        } else {
            backHotkey.unregister()
            forwardHotkey.unregister()
        }
        updateSpaceKey(phase)
    }
    /// Space moves on, Shift-Space goes back, but never on a step that asks the person to type or click in the app.
    func updateSpaceKey(_ phase: Phase? = nil) {
        let phase = phase ?? self.phase
        let actionStep = phase == .step && !onIntro && state?.step?.action == true && overlay.model.content.kind == .page
        if preferences.spaceAdvances && !typing && feedback != .note && (phase == .step || phase == .complete) && !actionStep {
            try? spaceHotkey.register(key: 49, modifiers: 0)
            try? shiftSpaceHotkey.register(key: 49, modifiers: UInt32(shiftKey))
        } else {
            spaceHotkey.unregister()
            shiftSpaceHotkey.unregister()
        }
    }
    private func advanceWithSpace() {
        switch overlay.model.content.kind {
        case .page: next()
        case .notice: handle(.primary)
        default: break
        }
    }
    func handle(_ action: GuideAction) {
        switch action {
        case .back: back()
        case .forward: next()
        case .jump(let page): jump(to: page)
        case .skip: next(skipped: true)
        case .pause: pause()
        case .close: closeGuide()
        case .answer(let helpful): answer(helpful)
        case .send(let note): sendNote(note)
        case .lookAgain: lookAgain()
        case .speak:
            let card = overlay.model.content
            speaker.say([card.title, card.message, card.hint].filter { !$0.isEmpty }.joined(separator: ". "))
        case .choose(let choice):
            guard phase == .choosing else { return }
            scope = choice
            canObserve = true
            prepare()
        case .primary:
            switch overlay.model.content.primary {
            case .next, .confirm: next()
            case .finish: closeGuide()
            case .rescan:
                refreshCount = 0
                retryChanged()
            case .retry: retryChanged()
            case .setup:
                overlay.hide()
                showWindow(section: "Setup")
            }
        }
    }
    func refreshAvailability() {
        let a = LocalIntelligence.availability
        modelReady = a.ready
        modelDetail = a.detail
        accessibilityReady = ScreenObserver.accessibilityGranted
        captureReady = ScreenObserver.captureGranted
        captureNeedsRestart = !captureReady && ScreenObserver.captureSwitchedOn
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    func showWindow(section: String? = nil) {
        if active { pause() }
        if let section { self.section = section }
        refreshAvailability()
        if window == nil {
            let content = MainView(controller: self)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Nudge"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 680, height: 480)
            w.contentView = NSHostingView(rootView: content)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func beginFromWindow() {
        window?.orderOut(nil)
        guard let lastExternal else {
            status = "Open the app you want help with, then press \(shortcutLabel)."
            return
        }
        NSRunningApplication(processIdentifier: lastExternal.pid)?.activate(options: [])
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            self.begin(lastExternal)
        }
    }
    func resumeFromWindow() {
        window?.orderOut(nil)
        guard let target else { return }
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            self.toggle()
        }
    }
    /// Where Nudge's own controls are in the settings window, reported by the views (window coordinates, top-left origin).
    var anchors: [String: CGRect] = [:]
    /// The menu bar icon's frame, supplied by the app delegate.
    var statusItemFrame: (() -> CGRect?)?
    struct TourStop {
        var anchor: String?
        var title: String
        var message: String
    }
    var tourStops: [TourStop] = []
    var tourIndex = 0
    var touring = false

    func shutdown() {
        operation?.cancel()
        cancelCheck()
        autoTask?.cancel()
        explainTask?.cancel()
        timer?.invalidate()
        overlay.hide()
        if let target { observer.release(target.pid) }
        engine.shutdown()
    }
}
