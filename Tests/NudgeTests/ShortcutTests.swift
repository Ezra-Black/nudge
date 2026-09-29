import Carbon
import Testing

@testable import Nudge

@Suite("Shortcut names")
@MainActor
struct ShortcutTests {
    @Test("Modifiers are listed in the order macOS menus use")
    func order() {
        let name = AppController.shortcutName(key: 49, modifiers: UInt32(controlKey | shiftKey))
        #expect(name == "⌃ ⇧ Space")
        #expect(AppController.shortcutName(key: 0, modifiers: UInt32(cmdKey | optionKey)) == "⌥ ⌘ A")
    }

    @Test("Unknown keys still get a readable name")
    func unknownKey() {
        #expect(AppController.shortcutName(key: 200, modifiers: UInt32(controlKey)) == "⌃ Key 200")
    }
}
