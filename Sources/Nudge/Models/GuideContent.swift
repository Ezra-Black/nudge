import Foundation

enum GuidePrimary: Equatable {
    case next, confirm, finish, rescan, retry, setup
    var title: String {
        switch self {
        case .next: "Next"
        case .confirm: "Done"
        case .finish: "Finish"
        case .rescan: "Look again"
        case .retry: "Try again"
        case .setup: "Open Setup"
        }
    }
    var symbol: String {
        switch self {
        case .next: "chevron.right"
        case .confirm, .finish: "checkmark"
        case .rescan, .retry: "arrow.clockwise"
        case .setup: "gearshape"
        }
    }
}
/// The question at the end of a guide, and what follows the answer.
enum FeedbackStage: Equatable { case ask, happy, note, sent }
/// Everything the guide card shows. A value, so the same card can be measured offscreen before it animates in.
struct GuideContent: Equatable {
    enum Kind: Equatable { case loading, page, notice, choice }
    var kind = Kind.loading
    var app = ""
    var title = ""
    var message = ""
    var hint = ""
    var page = 0
    var pages = 0
    var canBack = false
    var primary = GuidePrimary.next
    var canSkip = false
    var forward = true
    /// The step's explanation is still being written; its control is already highlighted.
    var busy = false
    /// Options offered on a `.choice` card, first one highlighted.
    var choices: [GuideChoice] = []
    /// Set on the last card: "Did I do good?", then the reply or a note box.
    var feedback: FeedbackStage?
    var serial = 0
}
struct GuideChoice: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
}
/// Where the guide character floats (relative to the window's corner), how it feels, and where it points.
struct MascotState: Equatable {
    var visible = false
    var point = CGPoint.zero
    var mood = MascotMood.happy
    var angle = 0.0
}
enum GuideAction {
    case back, forward
    case jump(Int)
    case primary, skip, pause, close
    case choose(String)
    case speak
    case answer(Bool)
    case send(String)
    case lookAgain
}
