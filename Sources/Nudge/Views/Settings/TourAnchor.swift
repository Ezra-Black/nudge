import SwiftUI

/// Views mark themselves with `tourAnchor` so the welcome tour can highlight them exactly.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
extension View {
    func tourAnchor(_ id: String) -> some View {
        background(GeometryReader { geometry in Color.clear.preference(key: TourAnchorKey.self, value: [id: geometry.frame(in: .global)]) })
    }
}
