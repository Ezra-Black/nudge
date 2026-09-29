import SwiftUI

/// Shifts its content with the window. Only this wrapper re-renders as the window moves, not the card inside.
struct FollowLayer<Content: View>: View {
    @ObservedObject var follow: FollowModel
    @ViewBuilder var content: Content
    var body: some View { content.offset(x: follow.offset.width, y: follow.offset.height) }
}
struct OverlayRoot: View {
    @ObservedObject var model: GuideModel
    let follow: FollowModel
    @ObservedObject private var prefs = Preferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        FollowLayer(follow: follow) {
            ZStack(alignment: .topLeading) {
                Color.clear
                if model.cardVisible {
                    StyledCard(model: model)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                        .offset(x: model.cardOrigin.x, y: model.cardOrigin.y)
                }
                if model.mascot.visible && prefs.appearance.showMascot {
                    MascotView(mood: model.mascot.mood, size: prefs.appearance.mascotPoints, pointing: model.mascot.angle)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                        .position(model.mascot.point)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
