import AppKit
import Foundation

struct UnitRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    func screenRect(in window: CGRect) -> CGRect {
        CGRect(
            x: window.minX + x * window.width, y: window.minY + y * window.height, width: width * window.width,
            height: height * window.height)
    }
}
extension UnitRect {
    /// Expresses a screen rectangle as fractions of `frame`, with a top-left origin.
    init(_ rect: CGRect, in frame: CGRect) {
        self.init(
            x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height, width: rect.width / frame.width,
            height: rect.height / frame.height)
    }
}
struct ObservedElement: Codable, Equatable {
    var id: String
    var label: String
    var role: String
    var bounds: UnitRect
    var source: String
    /// The named part of the window the element sits in, such as "Toolbar" or "Sidebar".
    var context = ""
    /// What the element leads to: a link's destination, a button's tooltip, a checkbox's state.
    var detail = ""
    /// Inside a web page rather than the app around it.
    var web = false
}
struct Observation: Codable {
    var app: String
    var bundle: String
    var window: String
    var window_id: UInt32
    var elements: [ObservedElement]
    /// The web page's address without query or fragment, when the window shows one.
    var page = ""
    /// What a picture of a chosen area appears to show, from on-device image classification.
    var scene = ""
}
struct ScreenObservation {
    var observation: Observation
    var frame: CGRect
    var windowFrame: CGRect
    var pid: pid_t
    /// Accessibility described too little of the window's content to explain it without text recognition.
    var sparse = false
    var hasOCR: Bool { observation.elements.contains { $0.source == "ocr" } }
}

struct TargetApp: Equatable {
    var pid: pid_t
    var bundle: String
    var name: String
    /// Browsers get a choice between explaining the web page and explaining the browser itself.
    var isBrowser: Bool { Self.browsers.contains(bundle) }
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "com.kagi.kagimacOS",
        "com.duckduckgo.macos.browser", "app.zen-browser.zen",
    ]
    init?(_ app: NSRunningApplication) {
        guard let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else {
            return nil
        }
        pid = app.processIdentifier
        self.bundle = bundle
        name = app.localizedName ?? bundle
    }
}
