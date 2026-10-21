import Foundation
import Synchronization

/// Scripted conversation with speech-like loudness so the call UI can be designed and
/// tested without a backend.
final class SimulatedVoiceSession: VoiceSession {
    private struct Beat {
        var phase: CallPhase
        var duration: Double
        var caption: Caption?
    }

    private let script: [Beat] = [
        Beat(phase: .connecting, duration: 1.8),
        Beat(phase: .speaking, duration: 3.0, caption: Caption(speaker: .agent, text: "I'm here. What should we work on?")),
        Beat(phase: .listening, duration: 3.6, caption: Caption(speaker: .user, text: "Plan my week and check what's urgent in my inbox.")),
        Beat(phase: .thinking, duration: 1.6),
        Beat(phase: .speaking, duration: 4.4, caption: Caption(speaker: .agent, text: "On it. The inbox agent is triaging your mail while I draft the week.")),
        Beat(phase: .listening, duration: 3.0, caption: Caption(speaker: .user, text: "Also book time for the gym on Thursday.")),
        Beat(phase: .thinking, duration: 1.2),
        Beat(phase: .speaking, duration: 3.6, caption: Caption(speaker: .agent, text: "Done — Thursday at 7 is blocked. Anything else?")),
    ]

    private let muted = Mutex(false)
    private let task = Mutex<Task<Void, Never>?>(nil)

    func events() -> AsyncStream<VoiceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
        let worker = Task { [script, weak self] in
            var index = 0
            while !Task.isCancelled {
                // Loop the conversation after the greeting.
                let beat = script[index]
                continuation.yield(.phase(beat.phase))
                if let caption = beat.caption { continuation.yield(.caption(caption)) }
                let start = ContinuousClock.now
                while !Task.isCancelled {
                    let elapsed = (ContinuousClock.now - start) / .seconds(1)
                    if elapsed >= beat.duration { break }
                    let level = Self.speechLevel(at: elapsed, duration: beat.duration)
                    let isMuted = self?.muted.withLock { $0 } ?? false
                    continuation.yield(.levels(
                        user: beat.phase == .listening && !isMuted ? level : 0,
                        agent: beat.phase == .speaking ? level : 0
                    ))
                    try? await Task.sleep(for: .milliseconds(33))
                }
                index = index + 1 < script.count ? index + 1 : 2
            }
            continuation.finish()
        }
        task.withLock { $0 = worker }
        continuation.onTermination = { _ in worker.cancel() }
        return stream
    }

    func setMuted(_ muted: Bool) async {
        self.muted.withLock { $0 = muted }
    }

    func end() async {
        task.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    /// Syllable-rate bursts under a sentence envelope — close enough to real speech energy.
    static func speechLevel(at t: Double, duration: Double) -> Double {
        let envelope = min(1, t / 0.25) * min(1, max(0, duration - t) / 0.35)
        let syllables = pow(abs(sin(t * 4.3 * .pi / 2)), 0.7)
        let wobble = 0.55 + 0.25 * sin(t * 7.3) + 0.20 * sin(t * 13.1 + 1.2)
        return max(0, min(1, envelope * syllables * wobble * 1.15))
    }
}
