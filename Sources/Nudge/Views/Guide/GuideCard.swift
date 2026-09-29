import AppKit
import SwiftUI

struct GuideCard: View {
    let content: GuideContent
    var icon: NSImage?
    var draft: Binding<String> = .constant("")
    var perform: (GuideAction) -> Void = { _ in }
    @FocusState private var noteFocused: Bool
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var speaker = Speaker.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var look: GuideAppearance { prefs.appearance }
    /// Button text never drops below a comfortable size, whatever the body text size.
    private var buttonSize: Double { max(16, look.textSize) }

    var body: some View {
        Group {
            if content.kind == .loading { loading } else { card }
        }
        // The panel never becomes key; keep its controls from rendering in the inactive style.
        .environment(\.controlActiveState, .key)
    }
    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(look.accent)
            Text(content.title).font(look.font(look.textSize, weight: .medium))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .fixedSize()
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if speaker.state != .idle && content.kind == .page { playback }
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title).font(look.font(look.textSize + 1, weight: look.titleWeight))
                    if content.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).tint(look.accent)
                            Text(content.message).foregroundStyle(.secondary)
                        }
                        .font(look.font(look.textSize))
                    } else {
                        if !content.message.isEmpty { Text(content.message).font(look.font(look.textSize)).lineSpacing(look.lineSpacing) }
                    }
                    if !content.hint.isEmpty {
                        Label(content.hint, systemImage: "hand.tap")
                            .font(look.font(max(13, look.textSize - 2), weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(content.serial)
                .transition(pageTransition)
            }
            if content.kind == .choice { choiceList } else { footer }
        }
        .padding(20)
        .frame(width: look.cardWidth, alignment: .topLeading)
    }
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = content.forward ? 16 : -16
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: shift)), removal: .opacity.combined(with: .offset(x: -shift)))
    }
    private var header: some View {
        HStack(spacing: 8) {
            if look.showIcon, let icon { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
            Text(caption).font(look.font(max(13, look.textSize - 3), weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            if content.kind == .page && !content.busy && speaker.state == .idle {
                iconButton("speaker.wave.2.fill", help: "Read aloud") { perform(.speak) }
            }
            if content.kind == .page && content.feedback == nil { iconButton("pause.fill", help: "Pause the guide") { perform(.pause) } }
            iconButton("xmark", help: "Close guide (Esc)") { perform(.close) }
        }
    }
    /// Shown while a card is being read aloud, with plainly labeled controls to pause or stop it.
    private var playback: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(look.accent)
                .symbolEffect(.variableColor.iterative, isActive: speaker.state == .speaking && !reduceMotion)
            Text(speaker.state == .paused ? "Reading paused" : "Reading aloud")
                .font(look.font(max(14, look.textSize - 2), weight: .medium))
            Spacer(minLength: 4)
            Button {
                speaker.togglePause()
            } label: {
                Label(speaker.state == .paused ? "Resume" : "Pause", systemImage: speaker.state == .paused ? "play.fill" : "pause.fill")
                    .font(look.font(max(14, look.textSize - 3), weight: .semibold))
            }
            .modifier(NativeButton(prominent: false, shape: .capsule, size: .regular))
            Button {
                speaker.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill").font(look.font(max(14, look.textSize - 3), weight: .semibold))
            }
            .modifier(NativeButton(prominent: false, shape: .capsule, size: .regular))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    private var caption: String {
        guard content.kind == .page, content.pages > 1, content.page < content.pages else { return content.app }
        return "\(content.app) · \(content.page + 1) of \(content.pages)"
    }
    @ViewBuilder private var footer: some View {
        if let stage = content.feedback {
            feedbackFooter(stage)
        } else if content.kind == .page {
            VStack(spacing: 12) {
                if content.pages > 1 && look.showDots { dots.frame(maxWidth: .infinity) }
                HStack(spacing: 10) {
                    bigButton(
                        "Back", symbol: "chevron.left", iconFirst: true, prominent: false, enabled: content.canBack,
                        help: "Back (Shift-Space)"
                    ) { perform(.back) }
                    Spacer(minLength: 0)
                    if content.canSkip {
                        bigButton("Skip", symbol: "forward.end.fill", iconFirst: false, prominent: false, help: "Skip this step") {
                            perform(.skip)
                        }
                    }
                    if content.primary == .next {
                        bigButton("Next", symbol: "chevron.right", iconFirst: false, prominent: true, help: "Next (Space)") {
                            perform(.forward)
                        }
                    } else {
                        primaryButton
                    }
                }
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                primaryButton
            }
        }
    }
    @ViewBuilder private func feedbackFooter(_ stage: FeedbackStage) -> some View {
        switch stage {
        case .ask:
            VStack(alignment: .leading, spacing: 12) {
                if content.pages > 1 && look.showDots { dots.frame(maxWidth: .infinity) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did I do good?").font(look.font(look.textSize + 1, weight: .bold)).foregroundStyle(look.accent)
                    Text("Was everything I told you right?").font(look.font(max(13, look.textSize - 2))).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if content.canBack {
                        bigButton("Back", symbol: "chevron.left", iconFirst: true, prominent: false, help: "Back (Shift-Space)") {
                            perform(.back)
                        }
                    }
                    Spacer(minLength: 0)
                    bigButton("No", symbol: "hand.thumbsdown.fill", iconFirst: true, prominent: false, help: "Something wasn’t right") {
                        perform(.answer(false))
                    }
                    bigButton("Yes!", symbol: "hand.thumbsup.fill", iconFirst: true, prominent: true, help: "Yes, that helped") {
                        perform(.answer(true))
                    }
                }
            }
        case .note:
            VStack(alignment: .leading, spacing: 12) {
                TextField("Tell me what wasn’t right…", text: draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(look.font(look.textSize))
                    .lineLimit(4, reservesSpace: true)
                    .focused($noteFocused)
                    .onSubmit { perform(.send(draft.wrappedValue)) }
                    .padding(12)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(
                            look.accent.opacity(noteFocused ? 0.85 : 0.35), lineWidth: noteFocused ? 2 : 1)
                    )
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { noteFocused = true } }
                HStack(spacing: 10) {
                    bigButton("Never mind", symbol: "xmark", iconFirst: true, prominent: false, help: "Close without sending") {
                        perform(.close)
                    }
                    Spacer(minLength: 0)
                    bigButton(
                        "Send", symbol: "paperplane.fill", iconFirst: true, prominent: true,
                        enabled: !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, help: "Send (Return)"
                    ) { perform(.send(draft.wrappedValue)) }
                }
            }
        case .happy:
            HStack {
                Spacer(minLength: 0)
                bigButton("Close", symbol: "hand.wave.fill", iconFirst: true, prominent: true, help: "Close (Space)") { perform(.close) }
            }
        case .sent:
            HStack(spacing: 10) {
                bigButton("Look again", symbol: "arrow.clockwise", iconFirst: true, prominent: false, help: "Explain this again") {
                    perform(.lookAgain)
                }
                Spacer(minLength: 0)
                bigButton("Close", symbol: "hand.wave.fill", iconFirst: true, prominent: true, help: "Close (Space)") { perform(.close) }
            }
        }
    }
    /// At most seven dots, sliding with the current page. Smaller end dots mean there are more beyond them.
    @ViewBuilder private var dots: some View {
        let shown = 7
        let count = content.pages
        let current = min(content.page, count - 1)
        let first = count <= shown ? 0 : max(0, min(current - shown / 2, count - shown))
        let window = first..<min(count, first + shown)
        HStack(spacing: 7) {
            ForEach(Array(window), id: \.self) { index in
                let more = (index == window.lowerBound && index > 0) || (index == window.upperBound - 1 && index < count - 1)
                Button {
                    perform(.jump(index))
                } label: {
                    Capsule()
                        .fill(index == content.page ? look.accent : Color.secondary.opacity(0.4))
                        .frame(width: index == content.page ? 24 : (more ? 6 : 9), height: more ? 6 : 9)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Step \(index + 1)")
                .accessibilityLabel("Go to step \(index + 1)")
            }
        }
        .fixedSize()
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: content.page)
    }
    private var choiceList: some View {
        VStack(spacing: 8) {
            ForEach(Array(content.choices.enumerated()), id: \.element.id) { index, choice in
                Button {
                    perform(.choose(choice.id))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: choice.symbol).font(.system(size: 20, weight: .medium)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.title).font(look.font(look.textSize, weight: look.titleWeight))
                            Text(choice.detail).font(look.font(max(11, look.textSize - 2), weight: .regular)).opacity(0.8)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .modifier(NativeButton(prominent: index == 0, shape: .roundedRectangle(radius: 14)))
            }
        }
    }
    private var primaryButton: some View {
        bigButton(content.primary.title, symbol: content.primary.symbol, iconFirst: true, prominent: true, help: content.primary.title) {
            perform(.primary)
        }
    }
    /// Large, labeled buttons: easy to read and easy to hit.
    private func bigButton(
        _ title: String, symbol: String, iconFirst: Bool, prominent: Bool, enabled: Bool = true, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if iconFirst { Image(systemName: symbol) }
                Text(title)
                if !iconFirst { Image(systemName: symbol) }
            }
            .font(look.font(buttonSize, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .modifier(NativeButton(prominent: prominent, shape: .capsule, size: .extraLarge))
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(title)
    }
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).frame(width: 18, height: 18)
        }
        .modifier(NativeButton(prominent: false, shape: .circle, size: .regular))
        .help(help)
        .accessibilityLabel(help)
    }
}
