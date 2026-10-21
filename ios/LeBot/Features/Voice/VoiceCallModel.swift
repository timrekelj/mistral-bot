import Foundation
import Observation

@MainActor
@Observable
final class VoiceCallModel {
    let agentName: String
    private(set) var phase: CallPhase = .connecting
    private(set) var userLevel: Double = 0
    private(set) var agentLevel: Double = 0
    private(set) var caption: Caption?
    private(set) var connectedAt: Date?
    private(set) var isMuted = false

    @ObservationIgnored private let session: any VoiceSession
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(agentName: String, session: any VoiceSession) {
        self.agentName = agentName
        self.session = session
    }

    func start() {
        guard listener == nil else { return }
        let stream = session.events()
        listener = Task { [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted { userLevel = 0 }
        let muted = isMuted
        Task { await session.setMuted(muted) }
    }

    func end() {
        listener?.cancel()
        listener = nil
        phase = .ended
        userLevel = 0
        agentLevel = 0
        Task { await session.end() }
    }

    func apply(_ event: VoiceEvent) {
        guard phase != .ended else { return }
        switch event {
        case let .phase(next):
            if connectedAt == nil, next != .connecting, next != .ended { connectedAt = .now }
            phase = next
        case let .levels(user, agent):
            userLevel = isMuted ? 0 : user
            agentLevel = agent
        case let .caption(next):
            caption = next
        }
    }

    /// Targets the pixel sun eases toward each frame.
    var sunTarget: SunTarget {
        SunTarget(
            energy: phase == .speaking ? agentLevel : phase == .listening ? userLevel : 0,
            connect: phase == .connecting ? 1 : 0,
            listen: phase == .listening ? 1 : 0,
            think: phase == .thinking ? 1 : 0,
            speak: phase == .speaking ? 1 : 0
        )
    }
}
