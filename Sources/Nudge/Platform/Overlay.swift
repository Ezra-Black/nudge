import AppKit
import Combine
import SwiftUI

/// Nudge's layer over one display. Dimming, highlight and card are drawn in the same window so they move
/// together, animate with Core Animation and SwiftUI springs rather than window resizes, and follow the
/// explained window as it's dragged. The window only takes clicks while the pointer is over the card.
@MainActor final class Overlay: NSObject {
    let model: GuideModel
    private let follow: FollowModel
    /// Called when the explained window changes size, since highlighted positions no longer hold.
    var onWindowResized: (() -> Void)?
    /// Lifts the layer above the menu bar, for pointing at Nudge's own menu bar icon.
    var raised = false {
        didSet {
            panel.level = NSWindow.Level(rawValue: raised ? NSWindow.Level.statusBar.rawValue + 1 : NSWindow.Level.floating.rawValue + 2)
        }
    }
    private let panel: GuidePanel
    private let highlight = NSView()
    /// Holds the dimming and highlight, flipped to match screen coordinates, translated to follow the window.
    private let stageLayer = CALayer()
    private let host: GuideHostingView<OverlayRoot>
    /// Measures the next card offscreen, to place it before it animates in.
    private let sizer = NSHostingView(rootView: GuideCard(content: GuideContent()))
    private let ring = CAShapeLayer()
    private let pulse = CAShapeLayer()
    /// Darkens everything except the highlighted control (or, on the overview, the app window).
    private let dim = CAShapeLayer()
    /// A chosen area stays framed like a window while what's inside it is explained. Inside, everything but
    /// the current item dims a little, so the eye follows the highlight without losing the rest of the area.
    private let frameLayer = CAShapeLayer()
    private let frameCorners = CAShapeLayer()
    private let innerDim = CAShapeLayer()
    private var frameRect: CGRect?
    private var frameShown = false
    private var innerDimShown = false
    private var link: CADisplayLink?
    private var ringRect: CGRect?
    private var ringShown = false
    private var dimShown = false
    private var cardShown = false
    private var hideToken = 0
    private var serial = 0
    private var frameCount = 0
    private var lookSubscription: AnyCancellable?
    private var speechSubscription: AnyCancellable?
    /// The last placement request, so an appearance change can re-lay it out in place.
    private var lastTarget: CGRect?
    private var lastWindow: CGRect?
    private var lastWindowID: UInt32?
    private var lastFocus = false
    private var lastFocusRect: CGRect?
    private var lastMood: MascotMood?
    /// A brief expression (a cheer, a celebration) that plays over the usual one, and when it ends.
    private var reaction: (mood: MascotMood, until: Date)?
    /// The explained window as last read, top-left origin. Highlight and card are placed relative to its corner.
    private var base = CGRect.zero
    private var trackedWindow: UInt32?
    private var windowOrigin = CGPoint.zero
    private var resizeReported = false
    /// The card's frame relative to the window's corner.
    private var cardRect = CGRect.zero
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var duration: Double { Preferences.shared.transitionSeconds }
    private static var primaryTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    override init() {
        let model = GuideModel()
        let follow = FollowModel()
        self.model = model
        self.follow = follow
        host = GuideHostingView(rootView: OverlayRoot(model: model, follow: follow))
        panel = GuidePanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        host.sizingOptions = []
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.title = "Nudge Guide"
        let root = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        for view in [highlight, host] as [NSView] {
            view.frame = root.bounds
            view.autoresizingMask = [.width, .height]
            root.addSubview(view)
        }
        panel.contentView = root
        highlight.wantsLayer = true
        stageLayer.isGeometryFlipped = true
        stageLayer.frame = highlight.bounds
        highlight.layer?.addSublayer(stageLayer)
        // A deep indigo rather than flat black, in keeping with the theme.
        for layer in [dim, innerDim] {
            layer.fillColor = NSColor(srgbRed: 0.07, green: 0.055, blue: 0.15, alpha: 1).cgColor
            layer.fillRule = .evenOdd
            layer.opacity = 0
            stageLayer.addSublayer(layer)
        }
        // A crisp edge with a soft shadow, like a window's, and the highlight color at its corners.
        frameLayer.fillColor = nil
        frameLayer.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        frameLayer.lineWidth = 1.5
        frameLayer.shadowColor = NSColor.black.cgColor
        frameLayer.shadowOpacity = 0.55
        frameLayer.shadowRadius = 4
        frameLayer.shadowOffset = .zero
        frameCorners.fillColor = nil
        frameCorners.lineWidth = 4
        frameCorners.lineCap = .round
        frameCorners.shadowOpacity = 0.8
        frameCorners.shadowRadius = 6
        frameCorners.shadowOffset = .zero
        for layer in [frameLayer, frameCorners] {
            layer.opacity = 0
            stageLayer.addSublayer(layer)
        }
        for layer in [ring, pulse] {
            layer.fillColor = NSColor.clear.cgColor
            layer.lineJoin = .round
            layer.opacity = 0
            stageLayer.addSublayer(layer)
        }
        ring.shadowOffset = .zero
        ring.shadowRadius = 10
        pulse.lineWidth = 2
        applyLook(Preferences.shared.appearance)
        lookSubscription = Preferences.shared.$appearance.dropFirst().removeDuplicates().sink { [weak self] _ in
            // @Published announces before the value changes; restyle once it has.
            DispatchQueue.main.async { self?.refreshLook() }
        }
        // The playback bar comes and goes with speech; resize the card to match.
        speechSubscription = Speaker.shared.$state.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshLook() }
        }
        link = highlight.displayLink(target: self, selector: #selector(frameTick(_:)))
        link?.add(to: .main, forMode: .common)
        link?.isPaused = true
    }
    private func refreshLook() {
        applyLook(Preferences.shared.appearance)
        if cardShown {
            present(
                model.content, target: lastTarget, window: lastWindow, windowID: lastWindowID, focusWindow: lastFocus,
                focusRect: lastFocusRect, mood: lastMood)
        }
    }
    /// Light or dark for the glass, and the highlight's color and weight.
    private func applyLook(_ look: GuideAppearance) {
        panel.appearance = look.forcedDark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) }
        let color = look.highlightNSColor.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.lineWidth = CGFloat(look.highlightWidth)
        ring.strokeColor = color
        ring.shadowColor = color
        pulse.strokeColor = color
        frameCorners.strokeColor = color
        frameCorners.shadowColor = color
        ring.shadowOpacity = Float(look.glowStrength)
        CATransaction.commit()
        if !look.breathe { ring.removeAnimation(forKey: "breathe") }
    }

    // MARK: Card

    /// Shows `content` beside `target`, or centered on `window` without one. Rects use screen coordinates with a
    /// top-left origin. `windowID` lets the guide follow the window as it moves. `focusWindow` dims everything
    /// outside `window` when there's no single control to point at.
    /// `mood` holds a particular expression for this card (for example upset after a failure) instead of the usual one.
    func present(
        _ content: GuideContent, target: CGRect?, window: CGRect?, windowID: UInt32? = nil, focusWindow: Bool = false,
        focusRect: CGRect? = nil, mood: MascotMood? = nil
    ) {
        lastTarget = target
        lastWindow = window
        lastWindowID = windowID
        lastFocus = focusWindow
        lastFocusRect = focusRect
        lastMood = mood
        var target = target
        var window = window
        var focusRect = focusRect
        // Lay out against where the window is now, even if it moved since it was read.
        if let id = windowID, let read = window, let live = Self.frame(of: id), abs(live.width - read.width) < 2,
            abs(live.height - read.height) < 2
        {
            target = target?.offsetBy(dx: live.minX - read.minX, dy: live.minY - read.minY)
            focusRect = focusRect?.offsetBy(dx: live.minX - read.minX, dy: live.minY - read.minY)
            window = live
        }
        let frame = window ?? Self.mainScreen
        if base != frame {
            base = frame
            resizeReported = false
        }
        trackedWindow = window == nil ? nil : windowID
        stage(on: target ?? frame)
        setFollow(frame.origin)

        var content = content
        let current = model.content
        // Re-showing the same page (for example after the window moved) shouldn't replay its text transition.
        let samePage =
            cardShown && current.kind == content.kind && current.page == content.page && current.title == content.title
            && current.message == content.message
        if !samePage { serial += 1 }
        content.serial = serial
        sizer.rootView = GuideCard(content: content, icon: model.icon)
        let placed = place(
            size: sizer.fittingSize, kind: content.kind, target: target?.appKitRect, window: window?.appKitRect, area: focusRect?.appKitRect
        )
        let rect = CGRect(
            x: placed.minX - frame.minX, y: Self.primaryTop - placed.maxY - frame.minY, width: placed.width, height: placed.height)
        cardRect = rect
        hideToken += 1
        panel.orderFrontRegardless()
        link?.isPaused = false
        if !cardShown {
            cardShown = true
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { model.cardOrigin = rect.origin }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3)) {
                model.content = content
                model.cardVisible = true
            }
        } else {
            let moved = hypot(model.cardOrigin.x - rect.minX, model.cardOrigin.y - rect.minY) > 1
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: max(0.25, duration), bounce: 0.12)) {
                model.content = content
                if moved { model.cardOrigin = rect.origin }
            }
        }
        let pointAt = (target ?? focusRect).map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        let screen = CGRect(
            x: panel.frame.minX - frame.minX, y: Self.primaryTop - panel.frame.maxY - frame.minY, width: panel.frame.width,
            height: panel.frame.height)
        placeMascot(
            content, target: pointAt, card: rect, screen: screen, area: focusRect.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) },
            mood: mood)
        // A chosen area keeps its frame while it's read and explained; the highlight moves between the things inside it.
        if let focusRect { showFrame(focusRect) } else { hideFrame() }
        if let target {
            showRing(target)
        } else if focusRect != nil {
            fadeRing()
            fadeInnerDim()
        } else if focusWindow, window != nil {
            fadeRing()
            spotlight(CGRect(origin: .zero, size: frame.size), radius: 12)
        } else {
            hideRing()
        }
    }
    private func place(size: CGSize, kind: GuideContent.Kind, target: CGRect?, window: CGRect?, area: CGRect? = nil) -> CGRect {
        let anchor = target ?? window ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let screen = NSScreen.screens.max { a, b in a.frame.intersection(anchor).area < b.frame.intersection(anchor).area } ?? NSScreen.main
        let visible = (screen?.visibleFrame ?? anchor).insetBy(dx: 12, dy: 12)
        func fit(_ r: CGRect) -> CGRect {
            CGRect(
                x: max(visible.minX, min(r.minX, visible.maxX - r.width)), y: max(visible.minY, min(r.minY, visible.maxY - r.height)),
                width: r.width, height: min(r.height, visible.height))
        }
        if let area {
            // Beside the chosen area rather than over it, level with what's being explained, so no text is covered.
            let level = target ?? area
            let gap: CGFloat = 16
            let top = min(level.maxY, area.maxY)
            let right = CGRect(x: area.maxX + gap, y: top - size.height, width: size.width, height: size.height)
            let left = CGRect(x: area.minX - gap - size.width, y: top - size.height, width: size.width, height: size.height)
            let below = CGRect(x: level.midX - size.width / 2, y: area.minY - gap - size.height, width: size.width, height: size.height)
            let above = CGRect(x: level.midX - size.width / 2, y: area.maxY + gap, width: size.width, height: size.height)
            let sides = visible.maxX - area.maxX >= area.minX - visible.minX ? [right, left] : [left, right]
            let fitted = (sides + [below, above]).map(fit)
            let clear = area.insetBy(dx: -6, dy: -6)
            if let outside = fitted.first(where: { !$0.intersects(clear) }) { return outside }
            // The area fills most of the screen: overlap it as little as possible, and never the item being explained.
            if target == nil { return fitted.min { a, b in a.intersection(clear).area < b.intersection(clear).area } ?? fitted[0] }
        }
        guard let target else {
            let area = window ?? anchor
            // With nothing to point at, the card sits just above the middle of the window, where the eye already is.
            let y = area.midY - size.height / 2 + min(60, area.height * 0.06)
            return fit(CGRect(x: area.midX - size.width / 2, y: y, width: size.width, height: size.height))
        }
        let gap: CGFloat = 14
        let below = CGRect(x: target.midX - size.width / 2, y: target.minY - gap - size.height, width: size.width, height: size.height)
        let above = CGRect(x: target.midX - size.width / 2, y: target.maxY + gap, width: size.width, height: size.height)
        let right = CGRect(x: target.maxX + gap, y: target.maxY - size.height, width: size.width, height: size.height)
        let left = CGRect(x: target.minX - gap - size.width, y: target.maxY - size.height, width: size.width, height: size.height)
        // Prefer the side with the most room: under toolbar items, beside sidebar and content items.
        let area = window ?? visible
        let upper = target.midY > area.midY
        let onLeft = target.midX < area.midX
        let order =
            upper
            ? [below, onLeft ? right : left, onLeft ? left : right, above] : [onLeft ? right : left, above, onLeft ? left : right, below]
        let clear = target.insetBy(dx: -6, dy: -6)
        let fitted = order.map(fit)
        return fitted.first { !$0.intersects(clear) } ?? fitted.min { a, b in a.intersection(clear).area < b.intersection(clear).area }
            ?? fitted[0]
    }

    /// Nudge floats beside what's highlighted and points at it, or perches on the card when there's nothing to point at.
    private func placeMascot(
        _ content: GuideContent, target: CGRect?, card: CGRect, screen: CGRect, area: CGRect? = nil, mood held: MascotMood?
    ) {
        let s = Preferences.shared.appearance.mascotPoints
        let room = screen.insetBy(dx: s * 0.7, dy: s * 0.7)
        func body(_ p: CGPoint) -> CGRect { CGRect(x: p.x - s * 0.6, y: p.y - s * 0.6, width: s * 1.2, height: s * 1.2) }
        func clearOfCard(_ p: CGPoint) -> Bool { !body(p).intersects(card) }
        var point: CGPoint
        var angle = 0.0
        if let t = target {
            let reach = s * 0.95
            let options = [
                CGPoint(x: t.minX - reach, y: t.midY), CGPoint(x: t.maxX + reach, y: t.midY), CGPoint(x: t.midX, y: t.minY - reach),
                CGPoint(x: t.midX, y: t.maxY + reach),
            ]
            // Always beside what's being explained, never on it. In a chosen area, outside the area when he can be,
            // so he doesn't cover the text that comes next either.
            let outside = options.filter { p in area.map { !body(p).intersects($0) } ?? true }
            point =
                outside.first { room.contains($0) && clearOfCard($0) } ?? options.first { room.contains($0) && clearOfCard($0) }
                ?? options.first { room.contains($0) } ?? options[0]
            angle = atan2(t.midY - point.y, t.midX - point.x)
        } else if content.kind == .loading {
            point = CGPoint(x: card.minX - s * 0.6, y: card.midY)
        } else {
            // Peeking over the card's top edge.
            point = CGPoint(x: card.minX + s * 0.8, y: card.minY - s * 0.42)
            if !room.contains(point) { point = CGPoint(x: card.minX - s * 0.62, y: card.minY + s * 0.7) }
        }
        var mood: MascotMood
        switch content.kind {
        case .loading: mood = .thinking
        case .choice: mood = .curious
        case .notice: mood = content.primary == .setup ? .focused : .confused
        case .page: mood = content.busy ? .thinking : (target != nil ? .pointing : (content.primary == .finish ? .celebrating : .waving))
        }
        baseMood = held ?? mood
        mood = baseMood
        if let reaction, reaction.until > Date() { mood = reaction.mood }
        if !model.mascot.visible {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                model.mascot.point = point
                model.mascot.angle = angle
            }
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.7, bounce: 0.3)) {
            model.mascot = MascotState(visible: true, point: point, mood: mood, angle: angle)
        }
    }

    private var baseMood = MascotMood.happy
    /// Nudge reacts for a moment, then goes back to the expression that suits the card.
    func react(_ mood: MascotMood, for seconds: Double = 1.4) {
        let until = Date().addingTimeInterval(seconds)
        reaction = (mood, until)
        guard model.mascot.visible else { return }
        withAnimation(.smooth(duration: 0.25)) { model.mascot.mood = mood }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, let current = self.reaction, current.until == until else { return }
            self.reaction = nil
            withAnimation(.smooth(duration: 0.3)) { self.model.mascot.mood = self.baseMood }
        }
    }

    /// Lets the card take typing (for the feedback box), or hands the keyboard back to the explained app.
    func allowTyping(_ on: Bool) {
        panel.acceptsKeys = on
        if on {
            panel.makeKey()
        } else if panel.isKeyWindow, panel.isVisible {
            // Ordering out passes the keyboard back; ordering straight in again keeps the card on screen.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    // MARK: Following the window

    /// Keeps the overlay on the display showing `rect`.
    private func stage(on rect: CGRect) {
        frameRect = nil
        let appKit = rect.appKitRect
        let screen = NSScreen.screens.max { a, b in a.frame.intersection(appKit).area < b.frame.intersection(appKit).area } ?? NSScreen.main
        guard let frame = screen?.frame, panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stageLayer.frame = highlight.bounds
        CATransaction.commit()
        ringRect = nil
    }
    private static var mainScreen: CGRect {
        let frame = NSScreen.main?.frame ?? .zero
        return CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
    private static func frame(of window: UInt32) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window)) as? [[String: Any]])?.first,
            let bounds = info[kCGWindowBounds as String] as? [String: Any]
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
    /// Moves highlight, dimming and card together to the window's corner, without animation.
    private func setFollow(_ origin: CGPoint) {
        windowOrigin = origin
        let offset = CGSize(width: origin.x - panel.frame.minX, height: origin.y - (Self.primaryTop - panel.frame.maxY))
        guard offset != follow.offset else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stageLayer.sublayerTransform = CATransform3DMakeTranslation(offset.width, offset.height, 0)
        CATransaction.commit()
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { follow.offset = offset }
    }
    @objc private func frameTick(_ link: CADisplayLink) {
        // Take clicks only while the pointer is over the card; everywhere else they reach the app.
        let card = cardRect.offsetBy(dx: windowOrigin.x, dy: windowOrigin.y).appKitRect
        let over = cardShown && card.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        frameCount += 1
        guard frameCount % 2 == 0, let id = trackedWindow, let live = Self.frame(of: id) else { return }
        if abs(live.width - base.width) > 2 || abs(live.height - base.height) > 2, !resizeReported {
            resizeReported = true
            hideRing()
            onWindowResized?()
        }
        if live.origin != windowOrigin { setFollow(live.origin) }
    }

    // MARK: Highlight

    private static func corner(_ rect: CGRect, _ radius: CGFloat) -> CGFloat { min(radius, rect.height / 2.5, rect.width / 2.5) }
    /// Moves the highlight to `target` with a spring, or draws it in place the first time.
    private func showRing(_ target: CGRect) {
        let look = Preferences.shared.appearance
        let spot = target.offsetBy(dx: -base.minX, dy: -base.minY).insetBy(dx: -4, dy: -4)
        let radius = Self.corner(spot, 10)
        let moved =
            ringRect.map {
                abs($0.minX - spot.minX) + abs($0.minY - spot.minY) + abs($0.width - spot.width) + abs($0.height - spot.height) > 1.5
            } ?? true
        if moved {
            let path = CGPath(roundedRect: spot, cornerWidth: radius, cornerHeight: radius, transform: nil)
            // The glow follows the outline only, so a large highlight stays clear inside instead of filling with color.
            let glow = path.copy(strokingWithWidth: ring.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let previous = ring.presentation()?.path ?? ring.path
            let previousGlow = ring.presentation()?.shadowPath ?? ring.shadowPath
            ring.path = path
            ring.shadowPath = glow
            pulse.path = path
            CATransaction.commit()
            if ringShown, let previous, !reduceMotion {
                spring(ring, from: previous, to: path, keys: ["path"])
                if let previousGlow { spring(ring, from: previousGlow, to: glow, keys: ["shadowPath"]) }
            }
            ringRect = spot
            if look.ripple && !reduceMotion { ping() }
        }
        if !ringShown || ring.opacity < 1 {
            ringShown = true
            fade(ring, to: 1, duration: reduceMotion ? 0.1 : 0.25)
        }
        if let frameRect {
            innerSpotlight(spot.insetBy(dx: -3, dy: -3), radius: radius + 3, within: frameRect)
        } else {
            spotlight(spot.insetBy(dx: -3, dy: -3), radius: radius + 3)
        }
        if ring.animation(forKey: "breathe") == nil && look.breathe && !reduceMotion {
            let breathe = CABasicAnimation(keyPath: "shadowRadius")
            breathe.fromValue = 8
            breathe.toValue = 16
            breathe.duration = 1.8
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(breathe, forKey: "breathe")
        }
    }
    /// Dims everything but `hole`, which is relative to the window's corner. The dimmed area extends far past
    /// the screen so following the window never uncovers an edge.
    private func spotlight(_ hole: CGRect, radius: CGFloat) {
        let look = Preferences.shared.appearance
        guard look.dimBackground else {
            fadeDim()
            return
        }
        let path = CGMutablePath()
        path.addRect(CGRect(x: -20_000, y: -20_000, width: 40_000, height: 40_000))
        let r = Self.corner(hole, radius)
        path.addRoundedRect(in: hole, cornerWidth: r, cornerHeight: r)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let previous = dim.presentation()?.path ?? dim.path
        dim.path = path
        CATransaction.commit()
        if dimShown, let previous, !reduceMotion { spring(dim, from: previous, to: path, keys: ["path"]) }
        let strength = Float(look.dimStrength)
        if !dimShown || dim.opacity != strength {
            dimShown = true
            fade(dim, to: strength, duration: reduceMotion ? 0.1 : 0.35)
        }
    }
    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        let drift: CGFloat = abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
        return drift <= 1
    }
    /// Frames a chosen area (screen coordinates, top-left origin) and dims everything outside it.
    private func showFrame(_ area: CGRect) {
        let spot = area.offsetBy(dx: -base.minX, dy: -base.minY)
        let radius = Self.corner(spot, 10)
        if frameRect.map({ !Self.same($0, spot) }) ?? true {
            let path = CGPath(roundedRect: spot, cornerWidth: radius, cornerHeight: radius, transform: nil)
            let corners = Self.brackets(spot, radius)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            frameLayer.path = path
            frameLayer.shadowPath = path.copy(strokingWithWidth: frameLayer.lineWidth + 1, lineCap: .round, lineJoin: .round, miterLimit: 0)
            frameCorners.path = corners
            frameCorners.shadowPath = corners.copy(
                strokingWithWidth: frameCorners.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
            CATransaction.commit()
        }
        frameRect = spot
        if !frameShown {
            frameShown = true
            for layer in [frameLayer, frameCorners] { fade(layer, to: 1, duration: reduceMotion ? 0.1 : 0.3) }
        }
        spotlight(spot.insetBy(dx: -2, dy: -2), radius: radius + 2)
    }
    private func hideFrame() {
        fadeInnerDim()
        guard frameShown else {
            frameRect = nil
            return
        }
        frameShown = false
        frameRect = nil
        for layer in [frameLayer, frameCorners] { fade(layer, to: 0, duration: reduceMotion ? 0.1 : 0.2) }
    }
    /// Short strokes around each corner, like the corners of a camera viewfinder.
    private static func brackets(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let l = min(22, r.width / 4, r.height / 4)
        let corners = [
            (CGPoint(x: r.minX, y: r.minY + radius + l), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX + radius + l, y: r.minY)),
            (CGPoint(x: r.maxX - radius - l, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.minY + radius + l)),
            (CGPoint(x: r.maxX, y: r.maxY - radius - l), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX - radius - l, y: r.maxY)),
            (CGPoint(x: r.minX + radius + l, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY - radius - l)),
        ]
        for (start, corner, end) in corners {
            path.move(to: start)
            path.addArc(tangent1End: corner, tangent2End: end, radius: radius)
            path.addLine(to: end)
        }
        return path
    }
    /// Inside a framed area, gently dims all but `hole`, the item being explained.
    private func innerSpotlight(_ hole: CGRect, radius: CGFloat, within area: CGRect) {
        let look = Preferences.shared.appearance
        let hole = hole.intersection(area)
        guard look.dimBackground, !hole.isNull, hole.width > 1, hole.height > 1 else {
            fadeInnerDim()
            return
        }
        let path = CGMutablePath()
        let outer = Self.corner(area, 10)
        let inner = Self.corner(hole, radius)
        path.addRoundedRect(in: area, cornerWidth: outer, cornerHeight: outer)
        path.addRoundedRect(in: hole, cornerWidth: inner, cornerHeight: inner)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let previous = innerDim.presentation()?.path ?? innerDim.path
        innerDim.path = path
        CATransaction.commit()
        if innerDimShown, let previous, !reduceMotion { spring(innerDim, from: previous, to: path, keys: ["path"]) }
        let strength = Float(look.dimStrength) * 0.5
        if !innerDimShown || innerDim.opacity != strength {
            innerDimShown = true
            fade(innerDim, to: strength, duration: reduceMotion ? 0.1 : 0.3)
        }
    }
    private func fadeInnerDim() {
        guard innerDimShown else { return }
        innerDimShown = false
        fade(innerDim, to: 0, duration: reduceMotion ? 0.1 : 0.2)
    }
    private func spring(_ layer: CAShapeLayer, from: CGPath, to: CGPath, keys: [String]) {
        for key in keys {
            let spring = CASpringAnimation(keyPath: key)
            spring.fromValue = from
            spring.toValue = to
            spring.mass = 1
            spring.stiffness = 170
            spring.damping = 22
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: key)
        }
    }
    /// One soft ripple when the highlight lands on something new.
    private func ping() {
        let width = CABasicAnimation(keyPath: "lineWidth")
        width.fromValue = 2
        width.toValue = 18
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.55
        opacity.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [width, opacity]
        group.duration = 0.7
        group.beginTime = CACurrentMediaTime() + 0.3
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.add(group, forKey: "ping")
    }
    /// Hides the highlight and the dimming, for example while the person scrolls.
    func hideRing() {
        fadeRing()
        fadeDim()
        hideFrame()
    }
    private func fadeRing() {
        guard ringShown else { return }
        ringShown = false
        ringRect = nil
        pulse.removeAllAnimations()
        fade(ring, to: 0, duration: reduceMotion ? 0.1 : 0.2)
    }
    private func fadeDim() {
        guard dimShown else { return }
        dimShown = false
        fade(dim, to: 0, duration: reduceMotion ? 0.1 : 0.25)
    }
    private func fade(_ layer: CALayer, to value: Float, duration: Double) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.opacity = value
        layer.add(animation, forKey: "fade")
    }
    func hide() {
        hideRing()
        panel.acceptsKeys = false
        guard cardShown else { return }
        cardShown = false
        hideToken += 1
        let token = hideToken
        panel.ignoresMouseEvents = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.22)) {
            model.cardVisible = false
            model.mascot.visible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.hideToken == token, !self.cardShown, !self.ringShown, !self.dimShown else { return }
            self.panel.orderOut(nil)
            self.link?.isPaused = true
            self.trackedWindow = nil
        }
    }
}
