import AppKit
import SwiftUI

/// A ⌘⇧5-style box for choosing part of the screen to explain. Drag to draw it, drag inside to move it,
/// drag a handle to resize it, or click a window to take all of it. Return or the button explains the area;
/// Escape cancels. The result is in screen coordinates with a top-left origin.
@MainActor final class AreaSelector {
    private var panel: SelectionPanel?
    private var completion: ((CGRect?) -> Void)?
    var isActive: Bool { panel != nil }

    func begin(_ done: @escaping (CGRect?) -> Void) {
        finish(nil)
        completion = done
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            finish(nil)
            return
        }
        let panel = SelectionPanel(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in self?.finish(rect) }
        panel.contentView = view
        panel.alphaValue = 0
        // A non-activating panel can still take Return and Escape without pulling focus from the app.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }
    func cancel() { finish(nil) }
    private func finish(_ local: CGRect?) {
        guard let panel else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let global = local.map { r -> CGRect in
            let g = r.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
            return CGRect(x: g.minX, y: top - g.maxY, width: g.width, height: g.height)
        }
        self.panel = nil
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
        let done = completion
        completion = nil
        NSCursor.arrow.set()
        done?(global)
    }
}
final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private enum Mode {
        case idle
        case draw(CGPoint)
        case move(CGPoint, CGRect)
        case resize(Int, CGRect)
    }
    private var mode = Mode.idle
    private var selection: CGRect?
    private var dragged = false
    private let dim = CAShapeLayer()
    private let border = CAShapeLayer()
    private let handles = CAShapeLayer()
    private lazy var hint = GuideHostingView(rootView: SelectionHint())
    private lazy var toolbar = GuideHostingView(
        rootView: SelectionToolbar(cancel: { [weak self] in self?.onFinish?(nil) }, confirm: { [weak self] in self?.confirm() }))

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let highlight = Preferences.shared.appearance.highlightNSColor.cgColor
        dim.fillRule = .evenOdd
        dim.fillColor = NSColor(srgbRed: 0.07, green: 0.055, blue: 0.15, alpha: 0.45).cgColor
        border.fillColor = nil
        border.strokeColor = highlight
        border.lineWidth = 2.5
        border.shadowColor = highlight
        border.shadowOpacity = 0.7
        border.shadowRadius = 8
        border.shadowOffset = .zero
        handles.fillColor = NSColor.white.cgColor
        handles.strokeColor = NSColor.black.withAlphaComponent(0.25).cgColor
        handles.lineWidth = 0.5
        handles.shadowColor = NSColor.black.cgColor
        handles.shadowOpacity = 0.35
        handles.shadowRadius = 2
        handles.shadowOffset = .zero
        for sublayer in [dim, border, handles] { layer?.addSublayer(sublayer) }
        for view in [hint, toolbar] as [NSView] { addSubview(view) }
        toolbar.isHidden = true
        update()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor(convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateCursor(convert(event.locationInWindow, from: nil)) }
    private func updateCursor(_ point: CGPoint) {
        // Over the buttons it's an ordinary arrow; inside the box it's a hand for moving it.
        if !toolbar.isHidden && toolbar.frame.contains(point) {
            NSCursor.arrow.set()
            return
        }
        if let s = selection, handle(at: point, in: s) == nil, s.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: Drawing

    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY),
        ]
    }
    private func handle(at point: CGPoint, in r: CGRect) -> Int? {
        handlePoints(r).firstIndex { hypot($0.x - point.x, $0.y - point.y) < 12 }
    }
    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        path.addRect(bounds)
        if let s = selection { path.addRect(s) }
        dim.path = path
        border.path = selection.map { CGPath(rect: $0, transform: nil) }
        let dots = CGMutablePath()
        if let s = selection, !isDrawing {
            for p in handlePoints(s) { dots.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)) }
        }
        handles.path = dots
        CATransaction.commit()
        let hintSize = hint.fittingSize
        hint.frame = CGRect(
            x: bounds.midX - hintSize.width / 2, y: bounds.maxY - hintSize.height - 90, width: hintSize.width, height: hintSize.height)
        hint.isHidden = selection != nil
        if let s = selection, !isDrawing {
            let size = toolbar.fittingSize
            var y = s.minY - size.height - 16
            if y < bounds.minY + 20 { y = min(s.maxY + 16, bounds.maxY - size.height - 20) }
            if y + size.height > s.minY && y < s.maxY { y = s.minY + 16 }
            let x = max(bounds.minX + 16, min(s.midX - size.width / 2, bounds.maxX - size.width - 16))
            toolbar.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            toolbar.isHidden = false
        } else {
            toolbar.isHidden = true
        }
    }
    private var isDrawing: Bool {
        if case .draw = mode { return dragged }
        if case .resize = mode { return true }
        return false
    }

    // MARK: Mouse and keys

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragged = false
        if !toolbar.isHidden && toolbar.frame.contains(p) { return }
        if event.clickCount == 2, let s = selection, s.contains(p) {
            confirm()
            return
        }
        if let s = selection, let h = handle(at: p, in: s) {
            mode = .resize(h, s)
        } else if let s = selection, s.contains(p) {
            mode = .move(p, s)
            NSCursor.closedHand.set()
        } else {
            mode = .draw(p)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let clamped = CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
        dragged = true
        switch mode {
        case .draw(let start):
            selection = CGRect(
                x: min(start.x, clamped.x), y: min(start.y, clamped.y), width: abs(clamped.x - start.x), height: abs(clamped.y - start.y))
        case .move(let start, let original):
            var moved = original.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
            selection = moved
        case .resize(let h, let original):
            var minX = original.minX
            var maxX = original.maxX
            var minY = original.minY
            var maxY = original.maxY
            if [0, 6, 7].contains(h) { minX = clamped.x }
            if [2, 3, 4].contains(h) { maxX = clamped.x }
            if [0, 1, 2].contains(h) { minY = clamped.y }
            if [4, 5, 6].contains(h) { maxY = clamped.y }
            selection = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        case .idle: break
        }
        update()
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if case .draw = mode, !dragged, let window = windowFrame(at: p) {
            // A click without dragging takes the whole window under the pointer.
            selection = window
        }
        if let s = selection, s.width < 12 || s.height < 12 { selection = nil }
        mode = .idle
        update()
        updateCursor(p)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish?(nil)
        case 36, 76: confirm()
        default: super.keyDown(with: event)
        }
    }
    private func confirm() {
        guard let s = selection else { return }
        onFinish?(s)
    }
    /// The frame of the frontmost ordinary window under `point`, in this view's coordinates.
    private func windowFrame(at point: CGPoint) -> CGRect? {
        guard let window else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let global = CGPoint(x: point.x + window.frame.minX, y: top - (point.y + window.frame.minY))
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list
        where (info[kCGWindowLayer as String] as? Int) == 0 && (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) != getpid() {
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let r = CGRect(dictionaryRepresentation: bounds as CFDictionary), r.contains(global)
            else { continue }
            let local = CGRect(x: r.minX - window.frame.minX, y: top - r.maxY - window.frame.minY, width: r.width, height: r.height)
            return local.intersection(self.bounds)
        }
        return nil
    }
}

private struct SelectionHint: View {
    @ObservedObject private var prefs = Preferences.shared
    var body: some View {
        let look = prefs.appearance
        VStack(spacing: 4) {
            Label("Drag over the part you’d like explained", systemImage: "rectangle.dashed")
                .font(look.font(max(16, look.textSize), weight: .semibold))
            Text("Click a window to choose all of it · Esc to cancel")
                .font(look.font(max(13, look.textSize - 3), weight: .regular)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background { CardBackdrop(look: look) }
        .fixedSize()
        .padding(24)
    }
}
private struct SelectionToolbar: View {
    var cancel: () -> Void
    var confirm: () -> Void
    @ObservedObject private var prefs = Preferences.shared
    var body: some View {
        let look = prefs.appearance
        HStack(spacing: 10) {
            Button(action: cancel) { Label("Cancel", systemImage: "xmark").padding(.horizontal, 6).padding(.vertical, 3) }
                .modifier(NativeButton(prominent: false, shape: .capsule, size: .extraLarge))
            Button(action: confirm) {
                Label("Explain This Area", systemImage: "sparkle.magnifyingglass").padding(.horizontal, 6).padding(.vertical, 3)
            }
            .modifier(NativeButton(prominent: true, shape: .capsule, size: .extraLarge))
        }
        .font(look.font(max(16, look.textSize), weight: .semibold))
        .padding(10)
        .background { CardBackdrop(look: look) }
        .environment(\.controlActiveState, .key)
        .fixedSize()
        .padding(24)
    }
}
