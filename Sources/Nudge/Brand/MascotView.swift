// Nudge brand asset. Copyright © 2026 Ezra Black. All rights reserved.
// Not covered by the Apache License: see LICENSE-BRAND.md and TRADEMARKS.md at the repository root.

import SwiftUI

private enum Palette {
    static let white = Color(hex: "#FFFFFF")
    static let mist = Color(hex: "#E6EDFF")
    static let periwinkle = Color(hex: "#D6E1FF")
    static let lavender = Color(hex: "#C8B6FF")
    static let blush = Color(hex: "#FFCCF0")
    static let ink = Color(hex: "#232329")
    static let tongue = Color(hex: "#FF8FB8")
    static let tear = Color(hex: "#8FC7FF")
    static let temper = Color(hex: "#FF5A6E")
}

struct MascotView: View {
    var mood: MascotMood = .happy
    var size: CGFloat = 64
    /// Direction of the pointing arm in radians: 0 points right, π/2 points down.
    var pointing: Double = 0
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drawn into an image: hold a still pose rather than catching a blink.
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if animated && !reduceMotion && !isSnapshot {
            TimelineView(.animation) { timeline in
                MascotFigure(mood: mood, size: size, pointing: pointing, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            MascotFigure(mood: mood, size: size, pointing: pointing, time: 0.4)
        }
    }
}

private struct MascotFigure: View {
    let mood: MascotMood
    let size: CGFloat
    let pointing: Double
    let time: Double

    var body: some View {
        let s = size
        let pace = mood == .sleeping ? 1.3 : 2.6
        let bob = sin(time * pace) * s * 0.045
        let squash = sin(time * pace * 2) * 0.018
        let hop = [.celebrating, .excited, .cheery].contains(mood) ? abs(sin(time * 5)) * s * (mood == .cheery ? 0.06 : 0.1) : 0
        let tilt: Double =
            switch mood {
            case .curious: 9
            case .confused: -7
            case .thinking: 5 * sin(time * 1.2)
            case .sleeping: -5
            case .upset, .shy: -4
            default: 0
            }
        // A cross little shake when angry; a small tremble when hiding his eyes.
        let shake = mood == .angry ? sin(time * 38) * s * 0.012 : (mood == .shy ? sin(time * 46) * s * 0.009 : 0)
        ZStack {
            // The shadow on the "ground" shrinks as Nudge floats up.
            Ellipse().fill(Palette.ink.opacity(0.14))
                .frame(width: s * 0.62, height: s * 0.11)
                .scaleEffect(1 - (bob + hop) / s * 1.5)
                .offset(y: s * 0.64)
            ZStack {
                arms(s)
                blob(s)
                face(s)
                if mood == .shy { paws(s) }
            }
            .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
            .rotationEffect(.degrees(tilt))
            .offset(x: shake, y: -bob - hop + (mood == .upset || mood == .shy ? s * 0.03 : 0))
            extras(s)
        }
        .frame(width: s * 1.8, height: s * 1.8)
    }

    private var fill: RadialGradient {
        RadialGradient(
            colors: [Palette.white, Palette.mist, Palette.periwinkle], center: UnitPoint(x: 0.36, y: 0.26), startRadius: 0,
            endRadius: size * 0.78)
    }
    private func blob(_ s: CGFloat) -> some View {
        ZStack {
            // The little wisp trailing from the bottom left.
            Ellipse().fill(fill).frame(width: s * 0.34, height: s * 0.24).rotationEffect(.degrees(35)).offset(x: -s * 0.3, y: s * 0.36)
            Ellipse().fill(fill).frame(width: s, height: s * 0.96)
                .overlay(
                    Ellipse().fill(
                        LinearGradient(
                            colors: [.clear, Palette.lavender.opacity(0.3)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom))
                )
                .overlay(Ellipse().strokeBorder(Palette.white.opacity(0.35), lineWidth: max(0.5, s * 0.008)))
                .overlay(
                    Ellipse().fill(Palette.white.opacity(0.9)).frame(width: s * 0.26, height: s * 0.13).rotationEffect(.degrees(-28))
                        .offset(x: -s * 0.2, y: -s * 0.3).blur(radius: s * 0.025)
                )
                // Flushed when angry, a little blue when upset.
                .overlay(
                    Ellipse().fill(
                        mood == .angry
                            ? Palette.temper.opacity(0.2)
                            : (mood == .upset ? Palette.tear.opacity(0.14) : (mood == .shy ? Palette.blush.opacity(0.16) : .clear))))
        }
        .shadow(color: Palette.lavender.opacity(0.75), radius: s * 0.12)
        .shadow(color: Palette.lavender.opacity(0.35), radius: s * 0.3)
    }
    private func arm(_ s: CGFloat, length: CGFloat = 0.24) -> some View {
        // A soft lavender edge keeps the little arms readable against light windows.
        Capsule().fill(fill).overlay(Capsule().strokeBorder(Palette.lavender.opacity(0.55), lineWidth: max(0.6, s * 0.014)))
            .frame(width: s * length, height: s * 0.15)
            .shadow(color: Palette.lavender.opacity(0.6), radius: s * 0.035)
    }
    @ViewBuilder private func arms(_ s: CGFloat) -> some View {
        let wave = sin(time * 7) * 18
        switch mood {
        case .pointing:
            // Reach toward whatever is being explained, with a small poke.
            let reach = s * (0.5 + 0.025 * sin(time * 4))
            arm(s, length: 0.3).rotationEffect(.radians(pointing)).offset(x: cos(pointing) * reach, y: sin(pointing) * reach * 0.94)
            arm(s).rotationEffect(.degrees(cos(pointing) > 0 ? -150 : 30)).offset(x: cos(pointing) > 0 ? -s * 0.46 : s * 0.46, y: s * 0.12)
        case .waving:
            arm(s).rotationEffect(.degrees(-35 + wave)).offset(x: s * 0.45, y: -s * 0.1)
            arm(s).rotationEffect(.degrees(-150)).offset(x: -s * 0.43, y: s * 0.1)
        case .celebrating, .excited:
            arm(s).rotationEffect(.degrees(-40 + wave)).offset(x: s * 0.44, y: -s * 0.14)
            arm(s).rotationEffect(.degrees(-140 - wave)).offset(x: -s * 0.44, y: -s * 0.14)
        case .cheery, .surprised:
            arm(s).rotationEffect(.degrees(-25 + wave * 0.4)).offset(x: s * 0.45, y: -s * 0.06)
            arm(s).rotationEffect(.degrees(-155 - wave * 0.4)).offset(x: -s * 0.45, y: -s * 0.06)
        case .upset:
            arm(s).rotationEffect(.degrees(70)).offset(x: s * 0.38, y: s * 0.24)
            arm(s).rotationEffect(.degrees(110)).offset(x: -s * 0.38, y: s * 0.24)
        case .angry:
            // Little fists, shaking.
            let fist = sin(time * 20) * 7
            arm(s, length: 0.2).rotationEffect(.degrees(-65 + fist)).offset(x: s * 0.44, y: -s * 0.08)
            arm(s, length: 0.2).rotationEffect(.degrees(-115 - fist)).offset(x: -s * 0.44, y: -s * 0.08)
        case .thinking:
            arm(s, length: 0.2).rotationEffect(.degrees(-70)).offset(x: s * 0.22, y: s * 0.38)
            arm(s).rotationEffect(.degrees(-150)).offset(x: -s * 0.43, y: s * 0.1)
        case .shy:
            // Both arms are up over his eyes, drawn in front of the face by `paws`.
            EmptyView()
        default:
            arm(s).rotationEffect(.degrees(30)).offset(x: s * 0.43, y: s * 0.12)
            arm(s).rotationEffect(.degrees(-150)).offset(x: -s * 0.43, y: s * 0.1)
        }
    }
    /// Arms raised from his sides, with round little paws covering both eyes. Every so often one slips down a touch,
    /// as if peeking.
    private func paws(_ s: CGFloat) -> some View {
        let peek = sin(time * 0.8) > 0.9 ? s * 0.07 : 0
        return ZStack {
            arm(s, length: 0.3).rotationEffect(.degrees(-48)).offset(x: -s * 0.34, y: s * 0.14)
            arm(s, length: 0.3).rotationEffect(.degrees(48)).offset(x: s * 0.34, y: s * 0.13 + peek * 0.5)
            paw(s).offset(x: -s * 0.19, y: s * 0.01)
            paw(s).offset(x: s * 0.19, y: -s * 0.01 + peek)
        }
    }
    private func paw(_ s: CGFloat) -> some View {
        Ellipse().fill(fill)
            .overlay(Ellipse().strokeBorder(Palette.lavender.opacity(0.95), lineWidth: max(0.8, s * 0.022)))
            .frame(width: s * 0.26, height: s * 0.28)
            .shadow(color: Palette.lavender.opacity(0.8), radius: s * 0.03)
    }
    private func face(_ s: CGFloat) -> some View {
        let blink = ![.sleeping, .excited, .celebrating, .cheery].contains(mood) && fmod(time, 4.3) < 0.13
        // Thinking and curious glances drift around the screen.
        let look: CGSize =
            switch mood {
            case .thinking: CGSize(width: s * 0.03 * cos(time * 1.6), height: -s * 0.025)
            case .curious: CGSize(width: s * 0.02, height: -s * 0.01)
            case .pointing: CGSize(width: cos(pointing) * s * 0.025, height: sin(pointing) * s * 0.02)
            default: .zero
            }
        return ZStack {
            eye(s, right: false, blink: blink).offset(x: -s * 0.19 + look.width, y: -s * 0.0 + look.height)
            eye(s, right: true, blink: blink).offset(x: s * 0.19 + look.width, y: -s * 0.02 + look.height)
            if mood == .focused || mood == .angry {
                let slant = mood == .angry ? 28.0 : 20.0
                let lift = mood == .angry ? 0.16 : 0.2
                Capsule().fill(Palette.ink).frame(width: s * 0.17, height: s * 0.04).rotationEffect(.degrees(slant)).offset(
                    x: -s * 0.18, y: -s * lift)
                Capsule().fill(Palette.ink).frame(width: s * 0.17, height: s * 0.04).rotationEffect(.degrees(-slant)).offset(
                    x: s * 0.18, y: -s * (lift + 0.02))
            }
            if mood == .upset {
                // Worried brows, raised in the middle.
                Capsule().fill(Palette.ink).frame(width: s * 0.15, height: s * 0.03).rotationEffect(.degrees(-18)).offset(
                    x: -s * 0.19, y: -s * 0.2)
                Capsule().fill(Palette.ink).frame(width: s * 0.15, height: s * 0.03).rotationEffect(.degrees(18)).offset(
                    x: s * 0.19, y: -s * 0.22)
            }
            Ellipse().fill(Palette.blush.opacity(0.8)).frame(width: s * 0.12, height: s * 0.065).blur(radius: s * 0.008).offset(
                x: -s * 0.33, y: s * 0.14)
            Ellipse().fill(Palette.blush.opacity(0.8)).frame(width: s * 0.12, height: s * 0.065).blur(radius: s * 0.008).offset(
                x: s * 0.33, y: s * 0.12)
            mouth(s).offset(x: look.width * 0.5, y: s * 0.16)
        }
    }
    @ViewBuilder private func eye(_ s: CGFloat, right: Bool, blink: Bool) -> some View {
        let stroke = StrokeStyle(lineWidth: s * 0.035, lineCap: .round, lineJoin: .round)
        switch mood {
        case .excited, .celebrating:
            Chevron(pointsLeft: right).stroke(Palette.ink, style: stroke).frame(width: s * 0.11, height: s * 0.13)
        case .sleeping:
            LidArc().stroke(Palette.ink, style: stroke).frame(width: s * 0.12, height: s * 0.06)
        case .cheery:
            // Smiling "^ ^" eyes.
            HappyArc().stroke(Palette.ink, style: stroke).frame(width: s * 0.13, height: s * 0.07)
        default:
            let scale: CGFloat = (mood == .curious && right) ? 1.15 : (mood == .surprised ? 1.2 : 1)
            ZStack {
                Ellipse().fill(Palette.ink)
                Circle().fill(Palette.white).frame(width: s * 0.065).offset(x: -s * 0.024, y: -s * 0.055)
                Circle().fill(Palette.white.opacity(0.85)).frame(width: s * 0.028).offset(x: s * 0.032, y: s * 0.05)
            }
            .frame(width: s * 0.16 * scale, height: s * 0.235 * scale)
            .scaleEffect(x: 1, y: blink ? 0.1 : (mood == .angry ? 0.72 : 1))
        }
    }
    @ViewBuilder private func mouth(_ s: CGFloat) -> some View {
        switch mood {
        case .thinking, .curious:
            Ellipse().fill(Palette.ink).frame(width: s * 0.05, height: s * 0.055)
        case .confused:
            Wave().stroke(Palette.ink, style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round)).frame(width: s * 0.12, height: s * 0.035)
        case .shy:
            // A small nervous wobble.
            Wave().stroke(Palette.ink, style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round)).frame(width: s * 0.09, height: s * 0.03)
        case .upset, .angry:
            Frown().stroke(Palette.ink, style: StrokeStyle(lineWidth: s * (mood == .angry ? 0.035 : 0.028), lineCap: .round)).frame(
                width: s * 0.13, height: s * 0.05)
        case .surprised:
            Ellipse().fill(Palette.ink)
                .overlay(Ellipse().fill(Palette.tongue).frame(width: s * 0.05, height: s * 0.03).offset(y: s * 0.025).clipShape(Ellipse()))
                .frame(width: s * 0.08, height: s * 0.1)
        case .sleeping, .focused:
            Capsule().fill(Palette.ink).frame(width: s * 0.07, height: s * 0.022)
        default:
            let wide: CGFloat = [.celebrating, .excited, .cheery].contains(mood) ? 1.3 : 1
            Smile().fill(Palette.ink)
                .overlay(
                    Ellipse().fill(Palette.tongue).frame(width: s * 0.11 * wide, height: s * 0.06).offset(y: s * 0.045).clipShape(Smile())
                )
                .frame(width: s * 0.19 * wide, height: s * 0.09 * wide)
        }
    }
    @ViewBuilder private func extras(_ s: CGFloat) -> some View {
        switch mood {
        case .curious:
            Text("?").font(.system(size: s * 0.3, weight: .heavy, design: .rounded)).foregroundStyle(Palette.lavender)
                .offset(x: s * 0.58, y: -s * 0.58 + sin(time * 2) * s * 0.03)
        case .sleeping:
            let rise = fmod(time * 0.5, 1)
            Text("z").font(.system(size: s * 0.16, weight: .bold, design: .rounded)).foregroundStyle(Palette.lavender)
                .offset(x: s * 0.45 + rise * s * 0.1, y: -s * 0.4 - rise * s * 0.25).opacity(1 - rise)
            Text("Z").font(.system(size: s * 0.22, weight: .bold, design: .rounded)).foregroundStyle(Palette.lavender)
                .offset(x: s * 0.62, y: -s * 0.66)
        case .upset:
            // A single tear, now and then.
            let fall = fmod(time * 0.45, 1)
            Tear().fill(Palette.tear)
                .frame(width: s * 0.06, height: s * 0.085)
                .offset(x: -s * 0.24, y: s * 0.08 + fall * s * 0.3)
                .opacity(fall < 0.1 ? fall * 10 : 1 - fall)
        case .angry:
            // The little cross "vein" mark, pulsing.
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(Palette.temper).frame(width: s * 0.05, height: s * 0.12)
                        .offset(y: -s * 0.07).rotationEffect(.degrees(Double(i) * 90 + 45))
                }
            }
            .scaleEffect(1 + 0.12 * sin(time * 9))
            .offset(x: s * 0.52, y: -s * 0.5)
        case .shy:
            // Tremble marks on both sides.
            ForEach(0..<2, id: \.self) { side in
                let x = side == 0 ? -s * 0.64 : s * 0.64
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(Palette.lavender)
                        .frame(width: s * 0.035, height: s * 0.12)
                        .rotationEffect(.degrees((side == 0 ? -1 : 1) * (Double(i) * 30 - 15)))
                        .offset(x: x + (side == 0 ? -1 : 1) * CGFloat(i) * s * 0.06, y: -s * 0.05 + CGFloat(i) * s * 0.12)
                        .opacity(0.35 + 0.65 * abs(sin(time * 10 + Double(i + side))))
                }
            }
        case .surprised:
            Text("!").font(.system(size: s * 0.3, weight: .heavy, design: .rounded)).foregroundStyle(Palette.lavender)
                .offset(x: s * 0.55, y: -s * 0.6 + sin(time * 5) * s * 0.02)
        case .celebrating, .excited, .cheery:
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Palette.lavender)
                    .frame(width: s * 0.045, height: s * 0.15)
                    .rotationEffect(.degrees(Double(i) * 40 - 40))
                    .offset(y: -s * 0.2)
                    .rotationEffect(.degrees(Double(i) * 40 - 40))
                    .offset(x: s * 0.52, y: -s * 0.52)
                    .opacity(0.55 + 0.45 * sin(time * 6 + Double(i)))
            }
        case .thinking:
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Palette.lavender)
                    .frame(width: s * (0.05 + 0.025 * CGFloat(i)))
                    .offset(x: s * (0.45 + 0.1 * CGFloat(i)), y: -s * (0.42 + 0.13 * CGFloat(i)))
                    .opacity(0.4 + 0.6 * max(0, sin(time * 3 - Double(i) * 0.8)))
            }
        default:
            EmptyView()
        }
    }
}

private struct Chevron: Shape {
    var pointsLeft: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: pointsLeft ? r.maxX : r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: pointsLeft ? r.minX : r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: pointsLeft ? r.maxX : r.minX, y: r.maxY))
        return p
    }
}
private struct LidArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        return p
    }
}
private struct HappyArc: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.9))
        return p
    }
}
private struct Frown: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.5))
        return p
    }
}
private struct Tear: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.width / 2), control: CGPoint(x: r.maxX, y: r.midY))
        p.addArc(
            center: CGPoint(x: r.midX, y: r.maxY - r.width / 2), radius: r.width / 2, startAngle: .degrees(0), endAngle: .degrees(180),
            clockwise: false)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        return p
    }
}
private struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.9))
        p.closeSubpath()
        return p
    }
}
private struct Wave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.midY), control: CGPoint(x: r.minX + r.width * 0.25, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.minX + r.width * 0.75, y: r.maxY))
        return p
    }
}
