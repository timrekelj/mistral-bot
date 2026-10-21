import LeBotDesign
import SwiftUI

struct ChatView: View {
    @State private var chat = ChatModel()
    @State private var isShowingLibrary = false
    @State private var call: VoiceCallModel?

    private let agentName = "Mistral"

    var body: some View {
        NavigationStack {
            ScrollView {
                if chat.messages.isEmpty {
                    EmptyChatView { chat.draft = $0 }
                        .padding(.top, 96)
                } else {
                    LazyVStack(spacing: 22) {
                        ForEach(chat.messages) { message in
                            MessageRow(message: message, agentName: agentName)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Composer(chat: chat) { startCall() }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingLibrary) {
                LibraryView()
            }
            .fullScreenCover(item: $call) { model in
                VoiceCallView(model: model)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { isShowingLibrary = true } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Palette.textPrimary)
            }
            .accessibilityLabel("Library")
        }
        ToolbarItem(placement: .principal) {
            AgentPicker(name: agentName)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { withAnimation(.smooth) { chat.reset() } } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("New chat")
            .disabled(chat.messages.isEmpty)
        }
    }

    private func startCall() {
        call = VoiceCallModel(agentName: agentName, session: SimulatedVoiceSession())
    }
}

extension VoiceCallModel: Identifiable {}

private struct AgentPicker: View {
    var name: String

    var body: some View {
        Menu {
            Button {} label: { Label(name, systemImage: "checkmark") }
            Divider()
            Button {} label: { Label("New agent", systemImage: "plus") }
                .disabled(true)
        } label: {
            HStack(spacing: 8) {
                PixelMark().frame(width: 18)
                Text(name)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel("Agent: \(name)")
    }
}

private struct EmptyChatView: View {
    var onPick: (String) -> Void

    private let suggestions: [(tag: String, prompt: String)] = [
        ("Research", "Compare the three best e-bikes under €2,000"),
        ("Inbox", "What needs a reply from me today?"),
        ("Plan", "Block two focus mornings next week"),
    ]

    var body: some View {
        VStack(spacing: 28) {
            PixelMark().frame(width: 76)
            Text("Ask anything, or hand off a task.")
                .font(.lbTitle)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(suggestions, id: \.prompt) { suggestion in
                    Button { onPick(suggestion.prompt) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(suggestion.tag)
                                .eyebrow(Palette.accent)
                                .frame(width: 72, alignment: .leading)
                            Text(suggestion.prompt)
                                .font(.callout)
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if suggestion.prompt != suggestions.last?.prompt {
                        Rectangle().fill(Palette.separator).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.horizontal, 12)
    }
}
