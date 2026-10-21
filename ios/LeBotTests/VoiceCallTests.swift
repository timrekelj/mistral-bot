import Foundation
@testable import LeBot
import Testing

private struct SilentSession: VoiceSession {
    func events() -> AsyncStream<VoiceEvent> { AsyncStream { $0.finish() } }
    func setMuted(_: Bool) async {}
    func end() async {}
}

@MainActor
struct VoiceCallModelTests {
    let model = VoiceCallModel(agentName: "Mistral", session: SilentSession())

    @Test func startsConnectingWithoutTimer() {
        #expect(model.phase == .connecting)
        #expect(model.connectedAt == nil)
        #expect(model.sunTarget.connect == 1)
    }

    @Test func firstLivePhaseStartsTimerOnce() throws {
        model.apply(.phase(.speaking))
        let connectedAt = try #require(model.connectedAt)
        model.apply(.phase(.listening))
        #expect(model.connectedAt == connectedAt)
    }

    @Test func energyFollowsWhoeverIsTalking() {
        model.apply(.phase(.speaking))
        model.apply(.levels(user: 0.2, agent: 0.8))
        #expect(model.sunTarget.energy == 0.8)
        #expect(model.sunTarget.speak == 1)

        model.apply(.phase(.listening))
        #expect(model.sunTarget.energy == 0.2)
        #expect(model.sunTarget.listen == 1)
    }

    @Test func muteSilencesUserLevel() {
        model.apply(.phase(.listening))
        model.toggleMute()
        model.apply(.levels(user: 0.9, agent: 0))
        #expect(model.isMuted)
        #expect(model.userLevel == 0)
    }

    @Test func endedCallIgnoresLateEvents() {
        model.end()
        model.apply(.phase(.speaking))
        model.apply(.caption(Caption(speaker: .agent, text: "late")))
        #expect(model.phase == .ended)
        #expect(model.caption == nil)
    }
}

struct SunMotionTests {
    @Test func convergesTowardTarget() {
        let motion = SunMotion()
        let target = SunTarget(energy: 1, connect: 0, listen: 0, think: 0, speak: 1)
        var state = motion.advance(to: 0, toward: target)
        for frame in 1 ... 120 { state = motion.advance(to: Double(frame) / 60, toward: target) }
        #expect(abs(state.energy - 1) < 0.01)
        #expect(abs(state.speak - 1) < 0.01)
        #expect(state.connect < 0.01)
    }

    @Test func loudnessAttacksFasterThanItDecays() {
        let rise = SunMotion.approach(0, 1, rate: 18, dt: 1 / 60)
        let fall = 1 - SunMotion.approach(1, 0, rate: 5, dt: 1 / 60)
        #expect(rise > fall)
    }

    @Test func clampsLongFrameGaps() {
        let motion = SunMotion()
        _ = motion.advance(to: 0, toward: SunTarget())
        let state = motion.advance(to: 10, toward: SunTarget(energy: 1))
        #expect(state.energy < 0.9) // a 10 s hitch doesn't snap straight to the target
    }
}

struct SimulatedSpeechTests {
    @Test func levelStaysInRangeAndFadesAtEdges() {
        for step in 0 ... 400 {
            let level = SimulatedVoiceSession.speechLevel(at: Double(step) / 100, duration: 4)
            #expect((0 ... 1).contains(level))
        }
        #expect(SimulatedVoiceSession.speechLevel(at: 0, duration: 4) == 0)
        #expect(SimulatedVoiceSession.speechLevel(at: 4, duration: 4) == 0)
    }
}

struct CallDurationTests {
    @Test(arguments: [(0.0, "00:00"), (9.6, "00:09"), (61, "01:01"), (600, "10:00")])
    func formats(seconds: Double, expected: String) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(VoiceCallView.duration(from: start, to: start.addingTimeInterval(seconds)) == expected)
    }
}
