import AppKit
import ApplicationServices
import CryptoKit
import ScreenCaptureKit
import Vision

final class ScreenObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Nudge.observation", qos: .userInitiated)
    /// Apps whose web accessibility tree Nudge switched on, with the value to restore. Touched only on `queue`.
    private var exposed: [pid_t: Bool] = [:]
    private var chromium: [String: Bool] = [:]
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var captureGranted: Bool { CGPreflightScreenCaptureAccess() }
    /// Whether Screen Recording has been switched on, even before Nudge restarts. The preflight check only
    /// changes after a relaunch, but other apps' window titles become readable as soon as permission is given.
    static var captureSwitchedOn: Bool {
        if captureGranted { return true }
        let me = getpid()
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != me, (info[kCGWindowLayer as String] as? Int) == 0,
                let owner = info[kCGWindowOwnerName as String] as? String, owner != "Dock", owner != "Window Server"
            else { return false }
            return !((info[kCGWindowName as String] as? String) ?? "").isEmpty
        }
    }

    /// Named regions. They label their contents; a labeled one can also be a tour stop itself.
    private static let areaRoles: Set<String> = [
        "AXToolbar", "AXTabGroup", "AXOutline", "AXTable", "AXList", "AXGroup", "AXScrollArea", "AXWebArea", "AXSplitGroup", "AXBrowser",
        "AXSheet", "AXPopover",
    ]
    /// Controls whose children only restate their own label.
    private static let leafRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXSearchField", "AXTextArea",
        "AXComboBox", "AXSlider", "AXLink", "AXIncrementor", "AXDisclosureTriangle", "AXColorWell", "AXImage", "AXMenuBarItem",
    ]
    private static let ignoredRoles: Set<String> = [
        "", "AXWindow", "AXMenu", "AXMenuBar", "AXMenuItem", "AXRow", "AXCell", "AXColumn", "AXUnknown", "AXLayoutArea", "AXLayoutItem",
        "AXValueIndicator", "AXScrollBar", "AXSplitter", "AXGrowArea", "AXMatte", "AXRuler", "AXWebArea", "AXSplitGroup", "AXBrowser",
        "AXSheet", "AXPopover",
    ]
    private static let fieldRoles: Set<String> = ["AXTextField", "AXSearchField", "AXTextArea", "AXComboBox"]

    init() {
        // A hung app must not stall a read for the 6 s system default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    func read(_ target: TargetApp, includeOCR: Bool, includeMenuBar: Bool = false) async throws -> ScreenObservation {
        try Task.checkCancellation()
        let snapshot: ScreenObservation = try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let warming = exposeWebContent(target)
                    if warming { Thread.sleep(forTimeInterval: 0.4) }
                    var snapshot = try Self.readAX(target, includeMenuBar: includeMenuBar)
                    // Chromium fills its tree asynchronously. Give a freshly enabled one a second look.
                    if warming && snapshot.sparse {
                        Thread.sleep(forTimeInterval: 0.7)
                        snapshot = try Self.readAX(target, includeMenuBar: includeMenuBar)
                    }
                    continuation.resume(returning: snapshot)
                } catch { continuation.resume(throwing: error) }
            }
        }
        try Task.checkCancellation()
        return includeOCR ? try await addingText(to: snapshot) : snapshot
    }
    /// Adds locally recognized text that Accessibility didn't already describe.
    func addingText(to snapshot: ScreenObservation) async throws -> ScreenObservation {
        guard Self.captureGranted else { return snapshot }
        var snapshot = snapshot
        let frame = snapshot.frame
        let known = snapshot.observation.elements.filter { !Self.areaRoles.contains($0.role) }.map {
            ($0.label.lowercased(), $0.bounds.screenRect(in: frame))
        }
        for var element in try await Self.recognize(windowID: snapshot.observation.window_id) {
            let rect = element.bounds.screenRect(in: snapshot.windowFrame)
            let label = element.label.lowercased()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            // Skip text that repeats, or sits on, a control Accessibility already reported.
            if known.contains(where: { $0.0 == label || $0.1.contains(center) }) { continue }
            element.bounds = UnitRect(rect, in: frame)
            snapshot.observation.elements.append(element)
        }
        snapshot.sparse = false
        return snapshot
    }
    /// Reads the text in a chosen area and looks at its pictures, so plain text or a photo can be explained as well as
    /// controls. Uses a screenshot of just that area, without Nudge's own overlay. Everything runs on this Mac.
    func inspectArea(_ region: CGRect, in snapshot: ScreenObservation) async throws -> ScreenObservation {
        guard Self.captureGranted else { return snapshot }
        let image = try await Self.capture(region)
        let found = try await Task.detached(priority: .userInitiated) { () -> ([(String, CGRect)], [String], [CGRect]) in
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            let classify = VNClassifyImageRequest()
            let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([text, classify, objects])
            let lines = (text.results ?? []).compactMap { result -> (String, CGRect)? in
                guard let candidate = result.topCandidates(1).first, candidate.confidence > 0.5 else { return nil }
                return (String(candidate.string.prefix(120)), result.boundingBox)
            }
            let labels = (classify.results ?? []).filter { $0.confidence > 0.3 }.prefix(6).map {
                $0.identifier.replacingOccurrences(of: "_", with: " ")
            }
            let salient = (objects.results?.first?.salientObjects ?? []).map(\.boundingBox)
            return (lines, Array(labels), salient)
        }.value
        var snapshot = snapshot
        let frame = snapshot.frame
        // Vision's boxes are fractions of the picture with the origin at the bottom left.
        func onScreen(_ box: CGRect) -> CGRect {
            CGRect(
                x: region.minX + box.minX * region.width, y: region.minY + (1 - box.maxY) * region.height, width: box.width * region.width,
                height: box.height * region.height)
        }
        let known = snapshot.observation.elements.filter { !Self.areaRoles.contains($0.role) }.map {
            ($0.label.lowercased(), $0.bounds.screenRect(in: frame))
        }
        var textRects: [CGRect] = []
        for (label, box) in found.0 {
            let rect = onScreen(box).intersection(frame)
            guard !rect.isNull, rect.width > 2, rect.height > 2 else { continue }
            textRects.append(rect)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if known.contains(where: { $0.0 == label.lowercased() || $0.1.contains(center) }) { continue }
            snapshot.observation.elements.append(
                ObservedElement(
                    id: "ocr-" + Self.id(label + "|\(Int(rect.minX / 8))|\(Int(rect.minY / 8))"), label: label, role: "visible text",
                    bounds: UnitRect(rect, in: frame), source: "ocr"))
        }
        snapshot.observation.scene = found.1.joined(separator: ", ")
        // Pictures: the ones the app reports, then whatever stands out in the screenshot that isn't text or a control.
        // If the area is one picture with hardly any text, the whole area is the picture.
        let controls = snapshot.observation.elements.filter {
            $0.source == "ax" && !Self.areaRoles.contains($0.role) && $0.role != "AXImage" && $0.role != "AXStaticText"
                && $0.role != "AXHeading"
        }.map { $0.bounds.screenRect(in: frame) }
        func share(_ r: CGRect, of rects: [CGRect]) -> CGFloat { rects.reduce(0) { $0 + r.intersection($1).area } / max(r.area, 1) }
        var candidates: [(rect: CGRect, alt: String)] = snapshot.observation.elements.filter { $0.role == "AXImage" }.compactMap { e in
            let r = e.bounds.screenRect(in: frame).intersection(region)
            return !r.isNull && r.width >= 40 && r.height >= 40 && r.area >= e.bounds.screenRect(in: frame).area * 0.6 ? (r, e.label) : nil
        }
        for box in found.2 {
            let r = onScreen(box).intersection(region)
            guard !r.isNull, r.width >= 40, r.height >= 40, r.area >= region.area * 0.025, share(r, of: textRects) < 0.25,
                share(r, of: controls) < 0.5
            else { continue }
            candidates.append((r, ""))
        }
        if candidates.isEmpty && found.0.reduce(0, { $0 + $1.0.count }) < 40 && !found.1.isEmpty { candidates.append((region, "")) }
        var pictures: [(rect: CGRect, alt: String)] = []
        for c in candidates.sorted(by: {
            !$0.alt.isEmpty && $1.alt.isEmpty || ($0.alt.isEmpty == $1.alt.isEmpty && $0.rect.area > $1.rect.area)
        }) where pictures.count < 4 {
            let repeats = pictures.contains {
                let overlap = $0.rect.intersection(c.rect).area
                return overlap > 0.6 * min($0.rect.area, c.rect.area)
            }
            if !repeats { pictures.append(c) }
        }
        let scale = CGFloat(image.width) / max(region.width, 1)
        for picture in pictures {
            let r = picture.rect
            let crop = CGRect(
                x: (r.minX - region.minX) * scale, y: (r.minY - region.minY) * scale, width: r.width * scale, height: r.height * scale
            ).integral
            guard let piece = image.cropping(to: crop) else { continue }
            let seen = (try? await Task.detached(priority: .userInitiated) { try Self.look(at: piece) }.value) ?? []
            let subject = seen.first ?? ""
            // Something that stood out but can't be named is probably not a picture at all.
            if picture.alt.isEmpty && subject.isEmpty && r != region { continue }
            let label = !picture.alt.isEmpty ? String(picture.alt.prefix(100)) : (subject.isEmpty ? "Picture" : "Picture of \(subject)")
            snapshot.observation.elements.append(
                ObservedElement(
                    id: "see-" + Self.id("\(Int(r.minX / 8))|\(Int(r.minY / 8))|\(Int(r.width / 8))|\(Int(r.height / 8))"), label: label,
                    role: "picture", bounds: UnitRect(r, in: frame), source: "vision",
                    detail: seen.isEmpty ? "" : "looks like: " + seen.prefix(5).joined(separator: ", ")))
        }
        snapshot.sparse = false
        return snapshot
    }
    /// What a picture seems to show, most telling first: animals and people it can find, then what the whole
    /// picture resembles (for example "a dog", "grass", "outdoor"). Empty when nothing is clear enough to say.
    nonisolated private static func look(at image: CGImage) throws -> [String] {
        let classify = VNClassifyImageRequest()
        let animals = VNRecognizeAnimalsRequest()
        let faces = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([classify, animals, faces])
        var seen: [String] = []
        var counts: [String: Int] = [:]
        for animal in animals.results ?? [] {
            if let best = animal.labels.first, best.confidence > 0.5 { counts[best.identifier.lowercased(), default: 0] += 1 }
        }
        for (name, count) in counts.sorted(by: { $0.value > $1.value }) { seen.append(count == 1 ? "a \(name)" : "\(count) \(name)s") }
        let people = (faces.results ?? []).filter { $0.confidence > 0.6 }.count
        if people > 0 { seen.append(people == 1 ? "a person" : "\(people) people") }
        let named = Set(counts.keys)
        for label in (classify.results ?? []).filter({ $0.confidence > 0.3 }).prefix(6) {
            let name = label.identifier.replacingOccurrences(of: "_", with: " ")
            if !named.contains(name) && !seen.contains(name) && !seen.contains("a \(name)") { seen.append(name) }
        }
        return seen
    }
    private static func capture(_ region: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard
            let display = content.displays.max(by: {
                $0.frame.intersection(region).width * $0.frame.intersection(region).height < $1.frame.intersection(region).width
                    * $1.frame.intersection(region).height
            })
        else {
            throw NudgeError("I couldn’t find the display with that area.")
        }
        let ours = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ours, exceptingWindows: [])
        let local = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).intersection(
            CGRect(origin: .zero, size: display.frame.size))
        guard !local.isNull, local.width > 2, local.height > 2 else { throw NudgeError("That area is off the screen.") }
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.sourceRect = local
        configuration.width = max(1, Int(local.width * scale))
        configuration.height = max(1, Int(local.height * scale))
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
    /// Chromium browsers and Electron apps only build a page's accessibility tree for assistive
    /// clients. Returns true the first time it is switched on, so the caller can let it populate.
    private func exposeWebContent(_ target: TargetApp) -> Bool {
        guard exposed[target.pid] == nil, usesChromium(target) else { return false }
        let app = AXUIElementCreateApplication(target.pid)
        var previous: CFTypeRef?
        let wasOn =
            AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &previous) == .success && (previous as? Bool) == true
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        exposed[target.pid] = wasOn
        return true
    }
    /// Restores the app's original accessibility mode once guidance ends.
    func release(_ pid: pid_t) {
        queue.async { [self] in
            guard let wasOn = exposed.removeValue(forKey: pid), !wasOn else { return }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
    }
    private func usesChromium(_ target: TargetApp) -> Bool {
        if let known = chromium[target.bundle] { return known }
        var result = [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.brave.Browser",
            "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser", "org.chromium.Chromium",
        ].contains(target.bundle)
        if !result, let url = NSRunningApplication(processIdentifier: target.pid)?.bundleURL {
            let frameworks =
                (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Contents/Frameworks").path)) ?? []
            result = frameworks.contains { $0.contains("Electron") || $0.contains("Chromium") || $0.hasSuffix(" Framework.framework") }
        }
        chromium[target.bundle] = result
        return result
    }
    /// The app owning the frontmost ordinary window under `point` (top-left origin), other than Nudge.
    static func app(at point: CGPoint) -> TargetApp? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != getpid(),
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point)
            else { continue }
            return NSRunningApplication(processIdentifier: pid_t(pid)).flatMap(TargetApp.init)
        }
        return nil
    }
    /// The app's frontmost on-screen window, straight from the window server. Cheap enough for the main thread.
    static func frontWindowFrame(_ pid: pid_t) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where (info[kCGWindowOwnerPID as String] as? Int) == Int(pid) && (info[kCGWindowLayer as String] as? Int) == 0 {
            if let dict = info[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: dict as CFDictionary), rect.width > 40, rect.height > 40
            {
                return rect
            }
        }
        return nil
    }
    private static func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func clean(_ value: String?) -> String {
        (value ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
    private static func text(_ element: AXUIElement, _ name: String) -> String { clean(attr(element, name) as? String) }
    private static func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = attr(element, kAXPositionAttribute), let s = attr(element, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
            CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0,
            size.height > 0
        else { return nil }
        return CGRect(origin: point, size: size)
    }
    private static func id(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
    /// Visible text inside an unlabeled control. Web links and buttons usually label themselves this way.
    private static func descendantText(_ node: AXUIElement) -> String {
        var pending = (attr(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        var found: [String] = []
        var visited = 0
        while !pending.isEmpty, visited < 12, found.joined().count < 60 {
            let current = pending.removeFirst()
            visited += 1
            switch text(current, kAXRoleAttribute) {
            case "AXStaticText":
                let value = text(current, kAXValueAttribute)
                if !value.isEmpty { found.append(value) }
            case "AXImage":
                let value = text(current, kAXDescriptionAttribute)
                if !value.isEmpty { found.append(value) }
            default: pending.append(contentsOf: ((attr(current, kAXChildrenAttribute) as? [AXUIElement]) ?? []).prefix(6))
            }
        }
        return clean(found.joined(separator: " "))
    }
    private static func site(of host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
    /// Where a link leads, in words. Same-site links by path, others by site. Queries and fragments are dropped.
    private static func destination(_ url: URL, from page: URL?) -> String {
        switch url.scheme?.lowercased() {
        case "mailto": return "starts an email"
        case "tel": return "starts a phone call"
        case "http", "https": break
        default: return ""
        }
        guard let host = url.host() else { return "" }
        let path = url.path(percentEncoded: false)
        let trimmed = path == "/" ? "" : path
        if let page, page.host() == host {
            if path == page.path(percentEncoded: false) {
                return url.fragment() == nil ? "reloads this page" : "jumps to a section of this page"
            }
            return trimmed.isEmpty ? "goes to this site’s home page" : "goes to " + String(trimmed.prefix(60)) + " on this site"
        }
        return "goes to " + String((site(of: host) + trimmed).prefix(70))
    }
    private static func readAX(_ target: TargetApp, includeMenuBar: Bool) throws -> ScreenObservation {
        let windows =
            (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
                ($0[kCGWindowOwnerPID as String] as? Int) == Int(target.pid) && ($0[kCGWindowLayer as String] as? Int) == 0
                    && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
            }
        let application = AXUIElementCreateApplication(target.pid)
        func asElement(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        let window =
            asElement(attr(application, kAXFocusedWindowAttribute))
            ?? asElement(attr(application, kAXMainWindowAttribute))
            ?? (attr(application, kAXWindowsAttribute) as? [AXUIElement])?.first(where: { rect($0) != nil })
        let axFrame = window.flatMap(rect)
        func windowRect(_ info: [String: Any]) -> CGRect? {
            guard let dict = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: dict as CFDictionary)
        }
        let info = windows.min { a, b in
            guard let axFrame else { return false }
            func distance(_ v: [String: Any]) -> Double {
                guard let r = windowRect(v) else { return .infinity }
                return abs(r.minX - axFrame.minX) + abs(r.minY - axFrame.minY) + abs(r.width - axFrame.width)
                    + abs(r.height - axFrame.height)
            }
            return distance(a) < distance(b)
        }
        guard let info, let frame = windowRect(info), frame.width > 40, frame.height > 40,
            let windowID = info[kCGWindowNumber as String] as? UInt32
        else { throw NudgeError("I couldn’t find a visible window. Open the app you want help with, then press the Nudge shortcut.") }
        // Tours explain the window itself. The menu bar is only offered when a goal might need a menu command.
        let menuBar = includeMenuBar ? asElement(attr(application, kAXMenuBarAttribute)) : nil
        let menuFrame = menuBar.flatMap(rect)
        let referenceFrame = menuFrame.map { frame.union($0) } ?? frame
        let title = window.map { text($0, kAXTitleAttribute) } ?? info[kCGWindowName as String] as? String ?? target.name
        var elements: [ObservedElement] = []
        var timedOut = false
        var lookups = 0
        let start = Date()
        // One IPC per node rather than a round trip per attribute. Never batch input values.
        let names = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXPositionAttribute,
            kAXSizeAttribute, kAXChildrenAttribute, "AXHidden", kAXHelpAttribute, "AXPlaceholderValue", "AXVisibleRows",
            "AXVisibleChildren", kAXRoleDescriptionAttribute, "AXURL",
        ]
        struct Item {
            let node: AXUIElement
            let path: String
            let depth: Int
            let clip: CGRect
            let area: String
            var web = false
        }
        // Breadth first, so the toolbar, sidebar and content all get read before any one of them is explored deeply.
        var pending: [Item] = window.map { [Item(node: $0, path: "window", depth: 0, clip: frame, area: "")] } ?? []
        var head = 0
        var pageURL: URL?
        while head < pending.count, head < 2500, elements.count < 500 {
            guard Date().timeIntervalSince(start) < 2.5 else {
                timedOut = true
                break
            }
            let item = pending[head]
            head += 1
            var result: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item.node, names as CFArray, [], &result) == .success,
                let values = result as? [Any], values.count == names.count
            else { continue }
            let fields = Dictionary(uniqueKeysWithValues: zip(names, values))
            func string(_ name: String) -> String { clean(fields[name] as? String) }
            if fields["AXHidden"] as? Bool == true { continue }
            var role = string(kAXRoleAttribute)
            let subrole = string(kAXSubroleAttribute)
            if subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField" { continue }
            if subrole == "AXSearchField" { role = "AXSearchField" }
            var bounds: CGRect? {
                guard let p = fields[kAXPositionAttribute], let z = fields[kAXSizeAttribute],
                    CFGetTypeID(p as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(z as CFTypeRef) == AXValueGetTypeID()
                else { return nil }
                var point = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(z as! AXValue, .cgSize, &size), size.width > 0,
                    size.height > 0
                else { return nil }
                return CGRect(origin: point, size: size)
            }
            let r = bounds
            // Breadth first reaches the page before any of its links.
            if role == "AXWebArea", pageURL == nil, let url = fields["AXURL"] as? URL { pageURL = url }
            var clip = item.clip
            // Content scrolled out of a scroll area keeps its coordinates; clip it away.
            if role == "AXScrollArea", let r {
                clip = clip.intersection(r)
                if clip.isNull || clip.width < 4 || clip.height < 4 { continue }
            }
            let name = string(kAXTitleAttribute).isEmpty ? string(kAXDescriptionAttribute) : string(kAXTitleAttribute)
            var label = name
            // Read static labels only. Typed input, passwords and document text values are omitted.
            if label.isEmpty && role == "AXStaticText" { label = text(item.node, kAXValueAttribute) }
            if label.isEmpty && fieldRoles.contains(role) { label = string("AXPlaceholderValue") }
            if label.isEmpty && (role == "AXHeading" || (leafRoles.contains(role) && role != "AXImage")), lookups < 120 {
                lookups += 1
                label = descendantText(item.node)
            }
            if label.isEmpty && [kAXButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXCheckBoxRole].contains(role) {
                label = string(kAXHelpAttribute)
            }
            if label.isEmpty && (role == "AXTextField" || role == "AXSearchField") { label = string(kAXRoleDescriptionAttribute) }
            var area = item.area
            if areaRoles.contains(role) {
                switch role {
                case "AXToolbar": area = name.isEmpty ? "Toolbar" : name
                case "AXWebArea": area = "Web page"
                case "AXSheet": area = name.isEmpty ? "Dialog" : name
                case "AXPopover": area = name.isEmpty ? "Popover" : name
                case "AXTabGroup": area = name.isEmpty ? (area.isEmpty ? "Tabs" : area) : name
                case "AXOutline", "AXTable", "AXList", "AXBrowser": area = name.isEmpty ? (area.isEmpty ? "List" : area) : name
                default: if !name.isEmpty { area = name }
                }
            }
            let isArea = areaRoles.contains(role)
            var include = !label.isEmpty && !ignoredRoles.contains(role)
            if role == "AXStaticText" { include = label.count > 1 }
            if role == "AXGroup" || role == "AXScrollArea", let r {
                include = include && r.width * r.height < frame.width * frame.height * 0.9
            }
            if include, let r {
                let visible = r.intersection(clip)
                // Controls must be essentially on screen. Areas only need to be partly visible.
                if !visible.isNull, visible.width > 3, visible.height > 3,
                    visible.width * visible.height >= r.width * r.height * (isArea ? 0.25 : 0.85)
                {
                    let identifier = string(kAXIdentifierAttribute)
                    let stable = identifier.isEmpty ? item.path : identifier + "|" + item.path
                    var detail = ""
                    switch role {
                    case "AXLink": if let url = fields["AXURL"] as? URL { detail = destination(url, from: pageURL) }
                    case "AXCheckBox": if let value = attr(item.node, kAXValueAttribute) as? Int { detail = value == 0 ? "off" : "on" }
                    case "AXPopUpButton":
                        let value = text(item.node, kAXValueAttribute)
                        if !value.isEmpty && value != label { detail = "shows " + String(value.prefix(40)) }
                    default: break
                    }
                    let help = string(kAXHelpAttribute)
                    if detail.isEmpty, role != "AXLink", !help.isEmpty, help.lowercased() != label.lowercased() {
                        detail = "tip: " + String(help.prefix(90))
                    }
                    elements.append(
                        ObservedElement(
                            id: id(stable + "|" + role + "|" + label), label: String(label.prefix(100)), role: role,
                            bounds: UnitRect(visible, in: referenceFrame), source: "ax", context: item.area, detail: detail, web: item.web))
                }
            }
            if leafRoles.contains(role) || item.depth >= 40 { continue }
            var children = (fields["AXVisibleRows"] as? [AXUIElement]) ?? []
            if children.isEmpty { children = (fields["AXVisibleChildren"] as? [AXUIElement]) ?? [] }
            let listLike = !children.isEmpty || ["AXTable", "AXOutline", "AXList", "AXBrowser"].contains(role)
            if children.isEmpty { children = (fields[kAXChildrenAttribute] as? [AXUIElement]) ?? [] }
            // A long list adds little beyond its first rows and would crowd out the rest of the window.
            for (i, child) in children.prefix(listLike ? 12 : 150).enumerated() {
                pending.append(
                    Item(
                        node: child, path: item.path + ".\(i)", depth: item.depth + 1, clip: clip, area: area,
                        web: item.web || role == "AXWebArea"))
            }
        }
        // A link or button that took its label from its own text shouldn't appear twice.
        let labeled = elements.filter { $0.role != "AXStaticText" && !areaRoles.contains($0.role) }.map {
            ($0.label.lowercased(), $0.bounds.screenRect(in: referenceFrame))
        }
        elements.removeAll { e in
            guard e.role == "AXStaticText" else { return false }
            let r = e.bounds.screenRect(in: referenceFrame)
            let center = CGPoint(x: r.midX, y: r.midY)
            let label = e.label.lowercased()
            return labeled.contains { $0.1.contains(center) && $0.0.contains(label) }
        }
        let content = elements.filter { !areaRoles.contains($0.role) }
        let cells = Set(
            content.map { e -> Int in
                let x = min(0.999, max(0, e.bounds.x + e.bounds.width / 2))
                let y = min(0.999, max(0, e.bounds.y + e.bounds.height / 2))
                return Int(y * 3) * 3 + Int(x * 3)
            })
        if let menuBar, menuFrame != nil, let items = attr(menuBar, kAXChildrenAttribute) as? [AXUIElement] {
            // Menu-bar headings only; don't recursively crawl all unopened menus.
            for (index, item) in items.prefix(12).enumerated() {
                let label = text(item, kAXTitleAttribute)
                guard !label.isEmpty, let r = rect(item), r.width > 3, r.height > 3, referenceFrame.contains(r) else { continue }
                elements.append(
                    ObservedElement(
                        id: id("menubar.\(index)|" + label), label: label, role: "AXMenuBarItem", bounds: UnitRect(r, in: referenceFrame),
                        source: "ax", context: "Menu bar"))
            }
        }
        Log.observation.notice(
            "AX read: window=\(window != nil), visited=\(head), elements=\(elements.count), cells=\(cells.count), deadlineHit=\(timedOut)")
        let page = pageURL.flatMap { url in url.host().map { site(of: $0) + url.path(percentEncoded: false) } } ?? ""
        return ScreenObservation(
            observation: Observation(
                app: target.name, bundle: target.bundle, window: title, window_id: windowID, elements: elements,
                page: String(page.prefix(80))), frame: referenceFrame, windowFrame: frame, pid: target.pid,
            sparse: content.count < 15 || cells.count < 4)
    }
    private static func recognize(windowID: UInt32) async throws -> [ObservedElement] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw NudgeError("The window changed before I could read it. Try again.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(2.0, 1600.0 / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        try Task.checkCancellation()
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { result -> ObservedElement? in
                guard let candidate = result.topCandidates(1).first, candidate.confidence > 0.72 else { return nil }
                let label = String(candidate.string.prefix(100))
                let b = result.boundingBox
                return ObservedElement(
                    id: "ocr-" + id(label + "|\(Int(b.minX*30))|\(Int(b.minY*30))"), label: label, role: "visible text",
                    bounds: UnitRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height), source: "ocr")
            }
        }.value
    }
}
