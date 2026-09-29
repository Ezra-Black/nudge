import SwiftUI

/// The welcome banner: Nudge waving on the same twilight gradient as the app icon, with a violet glow.
struct NudgeBanner: View {
    var mood: MascotMood
    @ObservedObject private var prefs = Preferences.shared
    var body: some View {
        let accent = prefs.appearance.accent
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nudge").font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#FFFFFF"), Color(hex: "#D6E1FF"), Color(hex: "#C8B6FF")], startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                Text("A little help, right where you are.").font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(
                    .white.opacity(0.85))
            }
            Spacer(minLength: 0)
            MascotView(mood: mood, size: 78)
                .frame(width: 120, height: 120)
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#2B2F52"), Color(hex: "#4A4690"), Color(hex: "#8B7CE0")], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .overlay(alignment: .trailing) {
                    Circle().fill(Color(hex: "#C8B6FF").opacity(0.45)).frame(width: 200).blur(radius: 50).offset(x: 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.35), radius: 16, y: 4)
        }
        .padding(.vertical, 6)
    }
}
