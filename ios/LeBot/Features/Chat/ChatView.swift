import LeBotDesign
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @State private var chat = ChatModel()
    @State private var isShowingLibrary = false
    @State private var isAddingKey = false
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
                VStack(spacing: 10) {
                    if appModel.mistralKey.needsKey {
                        APIKeyPromptCard { isAddingKey = true }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Composer(chat: chat) { startCall() }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .animation(.smooth, value: appModel.mistralKey.needsKey)
            }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingLibrary) {
                LibraryView()
            }
            .sheet(isPresented: $isAddingKey) {
                APIKeySheet()
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

/// Shown above the composer until the user adds a working Mistral API key.
private struct APIKeyPromptCard: View {
    @Environment(AppModel.self) private var appModel
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PixelMark().frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(isRejected ? "Your API key was rejected" : "Add your Mistral API key")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Le Bot runs on your own Mistral account.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            Button(isRejected ? "Replace" : "Add key", action: onAdd)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.onPrimaryFill)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Palette.primaryFill, in: .capsule)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var isRejected: Bool {
        if case let .stored(status) = appModel.mistralKey { status.state == .invalid } else { false }
    }
}

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
