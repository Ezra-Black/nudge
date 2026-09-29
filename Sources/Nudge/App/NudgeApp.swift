import AppKit
import Combine
import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var item: NSStatusItem?
    private var subscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--export-theme-preview"),
            ProcessInfo.processInfo.arguments.count > flag + 1
        {
            let path = ProcessInfo.processInfo.arguments[flag + 1]
            try? MascotArt.exportThemePreview(to: URL(fileURLWithPath: path + "-light.png"), dark: false)
            try? MascotArt.exportThemePreview(to: URL(fileURLWithPath: path + "-dark.png"), dark: true)
            NSApp.terminate(nil)
            return
        }
        if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--export-character-sheet"),
            ProcessInfo.processInfo.arguments.count > flag + 1
        {
            try? MascotArt.exportSheet(to: URL(fileURLWithPath: ProcessInfo.processInfo.arguments[flag + 1]))
            NSApp.terminate(nil)
            return
        }
        if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "--export-icon"), ProcessInfo.processInfo.arguments.count > flag + 1
        {
            // Used by scripts/build.sh to draw the app icon from the character.
            do { try MascotArt.exportIcon(to: URL(fileURLWithPath: ProcessInfo.processInfo.arguments[flag + 1])) } catch {
                print("Icon export failed: \(error)")
            }
            NSApp.terminate(nil)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") || ProcessInfo.processInfo.arguments.contains("--model-check") {
            let availability = LocalIntelligence.availability
            print("On-device model ready: \(availability.ready)")
            print(availability.detail)
            print("Accessibility granted: \(ScreenObserver.accessibilityGranted)")
            print("Screen capture granted: \(ScreenObserver.captureGranted)")
            print("Screen capture switched on: \(ScreenObserver.captureSwitchedOn)")
            Task {
                do {
                    let _: Hello = try await controller.engine.call("hello", as: Hello.self)
                    print("Bundled engine: ready")
                    if ProcessInfo.processInfo.arguments.contains("--model-check") {
                        let labels = ["Search", "Inbox", "New message", "Help"]
                        let observation = Observation(
                            app: "Example Mail", bundle: "example.mail", window: "Inbox", window_id: 1,
                            elements: labels.enumerated().map { i, label in
                                ObservedElement(
                                    id: "control-\(i)", label: label, role: "AXButton",
                                    bounds: UnitRect(x: 0.1, y: Double(i) * 0.15, width: 0.2, height: 0.1), source: "ax")
                            })
                        let prepared: Preparation = try await controller.engine.call(
                            "prepare", ["observation": try observation.jsonObject(), "goal": "", "request": "smoke"], as: Preparation.self)
                        let plan = try await LocalIntelligence.generate(prompt: prepared.prompt!)
                        let state: GuideState = try await controller.engine.call(
                            "install", ["request": "smoke", "plan": try plan.jsonObject()], as: GuideState.self)
                        print("Real on-device generation: \(state.plan?.steps.count ?? 0) validated steps; state=\(state.status)")
                        if state.status != "step" { print("Model returned a limited explanation rather than a tour.") }
                    }
                } catch { print("Bundled engine: \(error.localizedDescription)") }
                NSApp.terminate(nil)
            }
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.image = MascotArt.menuBarImage()
        item?.button?.image?.accessibilityDescription = "Nudge"
        let menu = NSMenu()
        add("Nudge this screen", action: #selector(nudge), to: menu)
        add("Explain an Area…", action: #selector(area), to: menu)
        add("Welcome Tour", action: #selector(tour), to: menu)
        add("Pause guidance", action: #selector(pause), to: menu)
        add("Close guide", action: #selector(closeGuide), to: menu)
        menu.addItem(.separator())
        add("Open Nudge…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator())
        add("Quit Nudge", action: #selector(quit), to: menu)
        item?.menu = menu
        subscription = controller.$phase.sink { [weak self] phase in
            let visible = phase != .idle && phase != .paused
            self?.item?.button?.title = visible ? " •" : ""
            self?.item?.button?.toolTip = visible ? "Nudge — guide active" : "Nudge — standing by"
        }
        controller.statusItemFrame = { [weak self] in self?.item?.button?.window?.frame }
        controller.start()
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
    @objc private func nudge() { controller.toggle() }
    @objc private func area() { controller.selectArea() }
    @objc private func tour() { controller.startWelcomeTour() }
    @objc private func pause() { controller.pause() }
    @objc private func closeGuide() { controller.closeGuide() }
    @objc private func openSettings() { controller.showWindow() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showWindow()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
