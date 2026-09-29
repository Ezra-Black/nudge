import Foundation
import OSLog

/// Nudge's log channels, under the app's own bundle identifier so forks log under theirs.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Nudge"
    static let model = Logger(subsystem: subsystem, category: "model")
    static let observation = Logger(subsystem: subsystem, category: "observation")
}
