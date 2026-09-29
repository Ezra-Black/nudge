import AppKit
import SwiftUI

/// The guide panel never becomes key, so every click is a "first" click. Deliver it instead of swallowing it.
final class GuideHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class GuidePanel: NSPanel {
    /// Only while the feedback box is open, so typing reaches it. Otherwise clicks never take focus from the app.
    var acceptsKeys = false
    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }
}
