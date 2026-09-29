// Nudge brand asset. Copyright © 2026 Ezra Black. All rights reserved.
// Not covered by the Apache License: see LICENSE-BRAND.md and TRADEMARKS.md at the repository root.

import AppKit
import SwiftUI

enum MascotArt {
    /// A template silhouette of Nudge for the menu bar: the blob with its eyes cut out.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2.5, y: 1.5, width: 16, height: 14.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 0.8, y: 11, width: 6, height: 5.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 6, width: 2.4, height: 3.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 12, y: 5.6, width: 2.4, height: 3.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
    /// Every expression on one sheet, for checking the character's art.
    @MainActor static func exportSheet(to file: URL) throws {
        let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(150)), count: 7), spacing: 6) {
            ForEach(MascotMood.allCases, id: \.self) { mood in
                VStack(spacing: 0) {
                    MascotView(mood: mood, size: 80, pointing: 0.6, animated: false)
                    Text(mood.name).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Color(hex: "#3A3A3A"))
                }
            }
        }
        .padding(20)
        .background(Color(hex: "#EEF1FB"))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return
        }
        try data.write(to: file)
    }
    /// The banner and a sample guide card in the current theme, for checking the look.
    @MainActor static func exportThemePreview(to file: URL, dark: Bool) throws {
        let look = Preferences.shared.appearance
        let sample = GuideContent(
            kind: .page, app: "Toolbar", title: "Share this page",
            message: "Sends a link to this page by Mail, Messages or AirDrop, so someone else can see it too.", page: 2, pages: 9,
            canBack: true)
        let preview = VStack(alignment: .leading, spacing: 30) {
            NudgeBanner(mood: .waving).frame(width: 620)
            HStack(alignment: .top, spacing: 30) {
                GuideCard(content: sample, icon: nil)
                    .background { CardBackdrop(look: look, embedded: true) }
                MascotView(mood: .pointing, size: 60, pointing: .pi, animated: false)
            }
        }
        .padding(50)
        .background(
            LinearGradient(
                colors: dark ? [Color(hex: "#1B1D2B"), Color(hex: "#2A2440")] : [Color(hex: "#F4F5FA"), Color(hex: "#E9E6F7")],
                startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.isSnapshot, true)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return
        }
        try data.write(to: file)
    }
    /// Writes the header image for the README and website: the app icon, with Nudge peeking happily over it from behind.
    /// The background is transparent with a soft glow, so it sits well on light and dark pages.
    @MainActor static func exportHero(to file: URL) throws {
        let hero = ZStack {
            // A gradient rather than a blur, so the glow fades out cleanly on any page.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "#A98BFF").opacity(0.5), Color(hex: "#A98BFF").opacity(0.18), Color(hex: "#A98BFF").opacity(0),
                        ],
                        center: .center, startRadius: 0, endRadius: 380)
                )
                .frame(width: 980, height: 800)
                .offset(y: 120)
            MascotView(mood: .cheery, size: 360, animated: false).offset(y: -70)
            AppIconArt().scaleEffect(0.5).frame(width: 512, height: 512).offset(y: 230)
        }
        // Room on every side for Nudge's own glow to fade out before the edge.
        .frame(width: 1080, height: 1060)
        let renderer = ImageRenderer(content: hero)
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return
        }
        try data.write(to: file)
    }
    /// Writes the app icon's PNGs into an `.iconset` folder for `iconutil`.
    @MainActor static func exportIcon(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: AppIconArt().frame(width: 1024, height: 1024))
                renderer.scale = CGFloat(points * scale) / 1024
                guard let image = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                guard let data = rep.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try data.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
/// The app icon: Nudge waving on a soft twilight squircle.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#2B2F52"), Color(hex: "#5B55A8"), Color(hex: "#9C8BEA")], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            Circle().fill(Color(hex: "#C8B6FF").opacity(0.45)).frame(width: 560).blur(radius: 90).offset(y: 20)
            MascotView(mood: .waving, size: 430, animated: false).offset(y: 30)
        }
        .frame(width: 1024, height: 1024)
    }
}
