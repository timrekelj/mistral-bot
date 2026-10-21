@testable import LeBot
import Observation
import Testing

private struct ScriptedResponder: ChatResponder {
    var chunks: [String]
    func reply(to _: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            chunks.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

@MainActor
struct ChatModelTests {
    @Test(.timeLimit(.minutes(1)))
    func streamsReplyAndClearsRespondingState() async {
        let chat = ChatModel(responder: ScriptedResponder(chunks: ["Hel", "lo"]))
        chat.draft = "  hi  "
        chat.send()
        #expect(chat.isResponding)
        #expect(chat.draft.isEmpty)

        await confirmation { finished in
            // `isResponding` must be observable, or the composer keeps showing Stop.
            while chat.isResponding {
                await withCheckedContinuation { resume in
                    withObservationTracking { _ = chat.isResponding } onChange: { resume.resume() }
                }
            }
            finished()
        }
        #expect(chat.messages.map(\.text) == ["hi", "Hello"])
        #expect(chat.messages.last?.isStreaming == false)
    }

    @Test func ignoresBlankDrafts() {
        let chat = ChatModel(responder: ScriptedResponder(chunks: []))
        chat.draft = "   \n"
        chat.send()
        #expect(chat.messages.isEmpty)
        #expect(!chat.canSend)
    }
}
