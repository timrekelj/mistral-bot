import Foundation

enum CallPhase: String, Sendable, Equatable {
    case connecting, listening, thinking, speaking, ended

    var label: String {
        switch self {
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .ended: "Call ended"
        }
    }
}

enum Speaker: Sendable, Equatable { case user, agent }

struct Caption: Sendable, Equatable, Identifiable {
    var id = UUID()
    var speaker: Speaker
    var text: String
}

enum VoiceEvent: Sendable, Equatable {
    case phase(CallPhase)
    /// Normalised loudness 0…1 for each side of the call.
    case levels(user: Double, agent: Double)
    case caption(Caption)
}

/// A live voice connection. Phase 5 adds the LiveKit + Voxtral implementation;
/// until then `SimulatedVoiceSession` drives the UI.
protocol VoiceSession: Sendable {
    func events() -> AsyncStream<VoiceEvent>
    func setMuted(_ muted: Bool) async
    func end() async
}
