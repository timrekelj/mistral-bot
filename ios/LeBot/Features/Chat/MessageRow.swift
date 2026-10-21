import LeBotDesign
import SwiftUI

struct MessageRow: View {
    var message: ChatMessage
    var agentName: String

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(message.text)
                    .font(.lbBody)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Palette.surfaceStrong, in: .rect(cornerRadius: 20))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(agentName).eyebrow()
                if message.text.isEmpty, message.isStreaming {
                    ThinkingPixels()
                } else {
                    Text("\(Self.markdown(message.text))\(cursor)")
                        .font(.lbBody)
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cursor: Text {
        message.isStreaming ? Text(" ▮").foregroundStyle(Palette.accent) : Text("")
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Three rainbow pixels stepping in sequence while the agent hasn't produced text yet.
struct ThinkingPixels: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0 ..< 3, id: \.self) { index in
                    let phase = (sin(t * 6 - Double(index) * 0.9) + 1) / 2
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.rainbow[index + 1])
                        .frame(width: 8, height: 8)
                        .opacity(0.35 + 0.65 * phase)
                        .offset(y: -3 * phase)
                }
            }
            .frame(height: 20)
        }
        .accessibilityLabel("Thinking")
    }
}
