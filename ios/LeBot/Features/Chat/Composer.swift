import LeBotDesign
import SwiftUI

struct Composer: View {
    @Bindable var chat: ChatModel
    var onCall: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Add attachment")
                .disabled(true)

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $chat.draft, axis: .vertical)
                        .font(.lbBody)
                        .lineLimit(1 ... 6)
                        .focused($isFocused)
                        .padding(.vertical, 13)
                        .padding(.leading, 18)

                    trailingButton
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
        }
        .animation(.snappy(duration: 0.25), value: chat.canSend)
        .animation(.snappy(duration: 0.25), value: chat.isResponding)
    }

    @ViewBuilder
    private var trailingButton: some View {
        if chat.isResponding {
            CircleIconButton(systemName: "stop.fill", fill: Palette.primaryFill, foreground: Palette.onPrimaryFill) {
                chat.stop()
            }
            .accessibilityLabel("Stop")
        } else if chat.canSend {
            CircleIconButton(systemName: "arrow.up", fill: Palette.primaryFill, foreground: Palette.onPrimaryFill) {
                chat.send()
            }
            .accessibilityLabel("Send")
        } else {
            CircleIconButton(systemName: "waveform", fill: Palette.accent, foreground: .white) {
                isFocused = false
                onCall()
            }
            .accessibilityLabel("Start voice call")
        }
    }
}

private struct CircleIconButton: View {
    var systemName: String
    var fill: Color
    var foreground: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
                .background(fill, in: .circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}
