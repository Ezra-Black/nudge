import AppKit
import Combine

@MainActor final class GuideModel: ObservableObject {
    @Published var content = GuideContent()
    @Published var icon: NSImage?
    /// The card's top-left corner relative to the explained window's corner, and whether it's on screen.
    @Published var cardOrigin = CGPoint.zero
    @Published var cardVisible = false
    @Published var mascot = MascotState()
    /// What the person is typing in the feedback box.
    @Published var draft = ""
    var perform: ((GuideAction) -> Void)?
}

/// Where the explained window currently is, in overlay coordinates. Updated every frame while it moves.
@MainActor final class FollowModel: ObservableObject { @Published var offset = CGSize.zero }
