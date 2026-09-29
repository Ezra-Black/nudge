import AppKit
import Carbon
import ServiceManagement

extension AppController {
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openPrivacy("Privacy_Accessibility")
    }
    /// Screen Recording, with one system prompt. A record left by an earlier build of Nudge (signed differently) can sit
    /// in the list switched on without applying to this copy, so Nudge first clears its own record, then asks again:
    /// the prompt puts this copy in the list and offers to open System Settings.
    func requestCapture() {
        captureRequested = true
        // Already switched on and only waiting for a restart: don't undo it, just show the list.
        if captureNeedsRestart {
            openPrivacy("Privacy_ScreenCapture")
            return
        }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "com.ezrablack.nudge"]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        let cleared =
            (try? reset.run()).map {
                reset.waitUntilExit()
                return reset.terminationStatus == 0
            } ?? false
        if CGRequestScreenCaptureAccess() {
            refreshAvailability()
            return
        }
        // If the old record couldn't be cleared, the prompt may not appear; open the list instead.
        if !cleared { openPrivacy("Privacy_ScreenCapture") }
    }
    /// Opens a Privacy & Security list. Current macOS uses the extension link; the older one only reaches the pane.
    private func openPrivacy(_ anchor: String) {
        for link in [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        ] {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
    }
    /// Quits and opens Nudge again, which macOS requires before a new Screen Recording permission takes effect.
    func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? reopen.run()
        NSApp.terminate(nil)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshAvailability()
        } catch {
            self.error = error.localizedDescription
            refreshAvailability()
        }
    }
    func setShortcut(key: UInt32, modifiers: UInt32, area: Bool = false) {
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            error = "Include Control, Option, or Command in the shortcut."
            return
        }
        let other = area ? (preferences.shortcutKey, preferences.shortcutModifiers) : (preferences.areaKey, preferences.areaModifiers)
        guard other != (key, modifiers) else {
            error = "That combination is already Nudge’s other shortcut."
            return
        }
        let old = area ? (preferences.areaKey, preferences.areaModifiers) : (preferences.shortcutKey, preferences.shortcutModifiers)
        let target = area ? areaHotkey : hotkey
        do {
            try target.register(key: key, modifiers: modifiers)
            if area {
                preferences.areaKey = key
                preferences.areaModifiers = modifiers
                areaShortcutLabel = Self.shortcutName(key: key, modifiers: modifiers)
            } else {
                preferences.shortcutKey = key
                preferences.shortcutModifiers = modifiers
                shortcutLabel = Self.shortcutName(key: key, modifiers: modifiers)
            }
            error = nil
        } catch {
            try? target.register(key: old.0, modifiers: old.1)
            self.error = error.localizedDescription
        }
    }
    static func shortcutName(key: UInt32, modifiers: UInt32) -> String {
        let keys: [UInt32: String] = [
            49: "Space", 45: "N", 4: "H", 40: "K", 46: "M", 2: "D", 3: "F", 0: "A", 1: "S", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
            14: "E", 15: "R", 17: "T", 16: "Y", 32: "U", 34: "I", 31: "O", 35: "P", 37: "L", 38: "J", 5: "G",
        ]
        return (modifiers & UInt32(controlKey) != 0 ? "⌃ " : "") + (modifiers & UInt32(optionKey) != 0 ? "⌥ " : "")
            + (modifiers & UInt32(shiftKey) != 0 ? "⇧ " : "") + (modifiers & UInt32(cmdKey) != 0 ? "⌘ " : "") + (keys[key] ?? "Key \(key)")
    }
}
