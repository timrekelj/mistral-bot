import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    var role: Role
    var text: String
    var isStreaming = false
}

/// Streams a reply for a prompt. Phase 1 swaps in the Supabase/Mistral implementation.
protocol ChatResponder: Sendable {
    func reply(to prompt: String) -> AsyncStream<String>
}

@MainActor
@Observable
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    var draft = ""

    @ObservationIgnored private let responder: any ChatResponder
    @ObservationIgnored private var streaming: Task<Void, Never>?

    init(responder: any ChatResponder = PreviewResponder()) {
        self.responder = responder
    }

    var isResponding: Bool { streaming != nil }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: prompt))
        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        let index = messages.count - 1
        let stream = responder.reply(to: prompt)
        streaming = Task { [weak self] in
            for await chunk in stream {
                self?.messages[index].text += chunk
            }
            self?.messages[index].isStreaming = false
            self?.streaming = nil
        }
    }

    func stop() {
        streaming?.cancel()
        streaming = nil
        if let last = messages.indices.last { messages[last].isStreaming = false }
    }

    func reset() {
        stop()
        messages = []
        draft = ""
    }
}

/// Local stand-in so the chat UI can be exercised before the Phase 1 runtime exists.
struct PreviewResponder: ChatResponder {
    func reply(to prompt: String) -> AsyncStream<String> {
        let text = """
        This is a **preview reply** — the app isn't talking to Mistral yet.

        In Phase 1, “\(prompt)” goes to the agent runtime on Supabase and streams back from **Mistral Large 4**, with web search, code and your connectors.
        """
        return AsyncStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(450))
                var words = text.split(separator: " ", omittingEmptySubsequences: false).makeIterator()
                var first = true
                while let word = words.next(), !Task.isCancelled {
                    continuation.yield((first ? "" : " ") + word)
                    first = false
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 18 ... 55)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
