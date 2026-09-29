import AppKit
import Foundation
import SwiftUI

struct NudgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
extension Encodable {
    func jsonObject() throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) }
}
extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
    // AX and ScreenCaptureKit use a top-left origin at the primary display; AppKit uses bottom-left.
    @MainActor var appKitRect: CGRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: minX, y: primaryTop - maxY, width: width, height: height)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex) ?? .white) }
}
