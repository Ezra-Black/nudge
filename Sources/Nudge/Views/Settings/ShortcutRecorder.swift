import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var recording: Bool
    var label: String
    var onRecord: (UInt32, UInt32) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.bezelStyle = .rounded
        return b
    }
    func updateNSView(_ b: RecorderButton, context: Context) {
        b.title = recording ? "Press shortcut…" : label
        b.begin = { recording = true }
        b.record = { key, flags in
            recording = false
            onRecord(key, flags)
        }
        b.cancel = { recording = false }
    }
}
final class RecorderButton: NSButton {
    var begin: (() -> Void)?
    var cancel: (() -> Void)?
    var record: ((UInt32, UInt32) -> Void)?
    private var capturing = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        capturing = true
        window?.makeFirstResponder(self)
        begin?()
    }
    override func keyDown(with event: NSEvent) {
        guard capturing else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            capturing = false
            cancel?()
            return
        }
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        capturing = false
        record?(UInt32(event.keyCode), flags)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if capturing {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
