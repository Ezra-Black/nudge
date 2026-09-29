import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var prefs = Preferences.shared
    @State private var recording = false
    @State private var recordingArea = false
    private let sections: [(id: String, title: String, symbol: String)] = [
        ("Start", "Start", "hand.point.up.left"), ("Setup", "Setup", "checkmark.shield"), ("Reading", "Guide", "text.bubble"),
        ("Appearance", "Appearance", "paintpalette"), ("Privacy", "Privacy", "lock.shield"),
    ]
    var body: some View {
        NavigationSplitView {
            List(
                selection: Binding<String?>(
                    get: { controller.section },
                    set: {
                        if let section = $0 {
                            controller.section = section
                            controller.refreshAvailability()
                        }
                    })
            ) {
                ForEach(sections, id: \.0) { item in
                    Label(item.title, systemImage: item.symbol).tag(item.id).tourAnchor("section-" + item.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle().fill(controller.active ? Color.accentColor : Color.green).frame(width: 7, height: 7)
                    Text(controller.active ? "Guide is active" : "Standing by").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(12)
            }
        } detail: {
            Form {
                if let error = controller.error {
                    Section {
                        HStack(alignment: .top) {
                            Label {
                                Text(error)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            Spacer()
                            Button {
                                controller.error = nil
                            } label: {
                                Image(systemName: "xmark")
                            }.buttonStyle(.borderless).help("Dismiss")
                        }
                    }
                }
                switch controller.section {
                case "Setup": setup
                case "Reading": reading
                case "Appearance": AppearanceSettings()
                case "Privacy": privacy
                default: start
                }
            }
            .formStyle(.grouped)
            .navigationTitle(sections.first { $0.id == controller.section }?.title ?? "Nudge")
        }
        .frame(minWidth: 680, minHeight: 480)
        .tint(prefs.appearance.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAvailability()
        }
        .onPreferenceChange(TourAnchorKey.self) { frames in MainActor.assumeIsolated { controller.anchorsChanged(frames) } }
    }
    @ViewBuilder private var start: some View {
        Section {
            NudgeBanner(mood: controller.active ? .pointing : .waving)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shortcut").font(.headline)
                    Text("Open any app or website, then press this to get a tour of that window.").font(.callout).foregroundStyle(
                        .secondary)
                }
                Spacer()
                Text(controller.shortcutLabel).font(.system(.title3, design: .rounded).weight(.medium)).tourAnchor("shortcut")
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Explain an area").font(.headline)
                    Text("Drag a box around any part of the screen to learn about just that part.").font(.callout).foregroundStyle(
                        .secondary)
                }
                Spacer()
                Text(controller.areaShortcutLabel).font(.system(.title3, design: .rounded).weight(.medium)).tourAnchor("area")
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
            LabeledContent("While guiding") { Text("Space for next · Shift-Space to go back · Esc to close").foregroundStyle(.secondary) }
                .tourAnchor("keys")
        }
        Section {
            TextField("Goal", text: $controller.goal, prompt: Text("Optional — for example, print this page")).tourAnchor("goal")
        } footer: {
            Text("Leave blank for a tour of the whole window.").font(.caption).foregroundStyle(.secondary)
        }
        Section {
            HStack(spacing: 10) {
                Label(controller.status, systemImage: "info.circle").foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if controller.phase == .paused { Button("Resume") { controller.resumeFromWindow() } }
                if controller.phase == .complete { Button("Replay") { controller.replay() } }
                Button("Show Me Around") { controller.startWelcomeTour() }
                Button("Nudge This Screen") { controller.beginFromWindow() }.buttonStyle(.borderedProminent)
            }
        }
    }
    @ViewBuilder private var setup: some View {
        Section("Permissions") {
            readiness("On-device intelligence", detail: controller.modelDetail, ready: controller.modelReady, button: "Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
            }
            readiness(
                "Accessibility",
                detail: "Lets Nudge read the buttons and labels in the window you’re using. Nudge never clicks or types for you.",
                ready: controller.accessibilityReady, button: "Allow…"
            ) { controller.requestAccessibility() }
            readiness(
                "Screen Recording",
                detail: controller.captureNeedsRestart
                    ? "Switched on. Reopen Nudge to finish; macOS applies this permission after a restart."
                    : (controller.captureRequested
                        ? "Turn Nudge on in Screen & System Audio Recording. If Nudge isn’t in the list, click + and choose Nudge."
                        : "Optional. Reads visible text and pictures when an app’s controls can’t be read, and lets Explain an Area read what’s in the box. Nothing is recorded or saved."),
                ready: controller.captureReady, button: controller.captureNeedsRestart ? "Open Settings…" : "Allow…",
                extra: (controller.captureRequested || controller.captureNeedsRestart) ? ("Reopen Nudge", { controller.relaunch() }) : nil
            ) { controller.requestCapture() }
        }
        Section {
            Toggle("Open Nudge at login", isOn: Binding(get: { controller.launchAtLogin }, set: { controller.setLogin($0) }))
            LabeledContent("Keyboard shortcut") {
                ShortcutRecorder(recording: $recording, label: controller.shortcutLabel) { key, modifiers in
                    controller.setShortcut(key: key, modifiers: modifiers)
                }.frame(width: 150, height: 24)
            }
            LabeledContent("Explain an area") {
                ShortcutRecorder(recording: $recordingArea, label: controller.areaShortcutLabel) { key, modifiers in
                    controller.setShortcut(key: key, modifiers: modifiers, area: true)
                }.frame(width: 150, height: 24)
            }
        } header: {
            Text("General")
        } footer: {
            Text(
                "Click the shortcut, then press a new combination that includes Control, Option or Command. Nudge stays in the menu bar when this window is closed."
            ).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Button("Check Again") { controller.refreshAvailability() }
        }
    }
    private func readiness(
        _ title: String, detail: String, ready: Bool, button: String, extra: (String, () -> Void)? = nil, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.title3).foregroundStyle(
                ready ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !ready {
                VStack(alignment: .trailing, spacing: 6) {
                    Button(button, action: action)
                    if let extra { Button(extra.0, action: extra.1).buttonStyle(.borderedProminent) }
                }
            }
        }
    }
    @ViewBuilder private var reading: some View {
        Section {
            LabeledContent("Most stops in a tour") {
                HStack {
                    Slider(value: $prefs.tourLimit, in: 10...60, step: 2).frame(width: 200)
                    Text("\(Int(prefs.tourLimit))").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                }
            }
            Toggle("Group similar buttons together", isOn: $prefs.groupSimilar)
            Picker("In web browsers", selection: $prefs.browserScope) {
                Text("Ask each time").tag("ask")
                Text("Explain the web page").tag("web")
                Text("Explain the browser’s controls").tag("app")
            }
        } header: {
            Text("Tours")
        } footer: {
            Text("Grouping explains a keypad’s number keys or a row of tabs as one stop, highlighted together.").font(.caption)
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Move through explanations automatically", isOn: $prefs.autoAdvance)
            if prefs.autoAdvance {
                LabeledContent("Time per step") {
                    HStack {
                        Slider(value: $prefs.readingSeconds, in: 8...30, step: 1).frame(width: 180)
                        Text("\(Int(prefs.readingSeconds)) s").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Transition length") { Slider(value: $prefs.transitionSeconds, in: 0.2...1).frame(width: 220) }
            Toggle("Space bar goes to the next step", isOn: $prefs.spaceAdvances)
        } header: {
            Text("Pace")
        } footer: {
            Text(
                "Shift-Space goes back. Space is left alone on steps that ask you to do something, and as soon as you start typing in the app. Those steps always wait for you."
            ).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Play sound effects", isOn: $prefs.soundEffects)
            LabeledContent("Volume") {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $prefs.soundVolume, in: 0.1...1).frame(width: 180)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            }
            .disabled(!prefs.soundEffects)
            LabeledContent("Listen") {
                HStack(spacing: 8) {
                    Button {
                        SoundEffects.shared.play(.scan, preview: true)
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                    }
                    Button {
                        SoundEffects.shared.play(.ready, preview: true)
                    } label: {
                        Label("Ready", systemImage: "sparkles")
                    }
                    Button {
                        SoundEffects.shared.play(.goodbye, preview: true)
                    } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                }
            }
        } header: {
            Text("Sounds")
        } footer: {
            Text("Bubbly sounds when you press the shortcut, when the first card appears, and when you close the guide.").font(.caption)
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Read each step aloud", isOn: $prefs.speakSteps)
            Picker("Voice", selection: $prefs.voice) {
                Text("System voice").tag("")
                Divider()
                ForEach(Speaker.voices, id: \.identifier) { voice in
                    Text(voice.quality == .default ? voice.name : "\(voice.name) (Enhanced)").tag(voice.identifier)
                }
            }
            LabeledContent("Speed") {
                HStack {
                    Image(systemName: "tortoise").foregroundStyle(.secondary)
                    Slider(value: $prefs.speechRate, in: 0.3...0.6).frame(width: 180)
                    Image(systemName: "hare").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Test Voice") { controller.speaker.say("Here’s where to find the next step.") }
            }
        } header: {
            Text("Read aloud")
        } footer: {
            Text(
                "The speaker button on each card reads it aloud any time. Add more voices in System Settings → Accessibility → Spoken Content."
            ).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var privacy: some View {
        Section {
            Toggle("Use local text recognition when needed", isOn: $prefs.useOCR)
        } footer: {
            Text(
                "Nudge reads the window only while a guide is on screen. Everything stays on this Mac: no cloud AI, no uploads. Password fields are never read; text recognition can’t guarantee other sensitive text is skipped."
            ).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Toggle("Ask “Did I do good?” when a guide ends", isOn: $prefs.askFeedback)
            if FeedbackStore.standard.exists {
                LabeledContent("Your answers and notes") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([FeedbackStore.standard.file]) }
                }
            }
        } header: {
            Text("Feedback")
        } footer: {
            Text("Your answers, notes and what Nudge said are saved in a file on this Mac only. Nothing is sent anywhere.").font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Apps") {
            if prefs.recentApps.isEmpty { Text("Apps you use with Nudge appear here.").foregroundStyle(.secondary) }
            ForEach(prefs.recentApps.keys.sorted(), id: \.self) { bundle in
                LabeledContent(prefs.recentApps[bundle] ?? bundle) {
                    if prefs.blockedApps[bundle] != nil {
                        Button("Allow") { controller.unblock(bundle) }
                    } else {
                        Button("Exclude") { controller.block(bundle) }
                    }
                }
            }
        }
        Section {
            LabeledContent("Guides created this session", value: "\(controller.guideCount)")
        } footer: {
            Text(
                "Nudge uses Apple’s on-device model and can make mistakes. It works best with labeled controls in everyday apps and websites."
            ).font(.caption).foregroundStyle(.secondary)
        }
    }
}
