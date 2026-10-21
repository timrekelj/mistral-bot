import LeBotDesign
import SwiftUI

struct VoiceCallView: View {
    @State var model: VoiceCallModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)

            Spacer(minLength: 12)

            PixelSunView(target: model.sunTarget)
                .frame(maxWidth: 360)
                .padding(.horizontal, 16)

            Spacer(minLength: 12)

            captionView
                .frame(height: 96, alignment: .top)
                .padding(.horizontal, 32)

            controls
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sensoryFeedback(.impact(weight: .light), trigger: model.phase)
        .onAppear { model.start() }
    }

    private var background: some View {
        ZStack {
            Palette.night
            RadialGradient(
                colors: [Palette.flame.opacity(0.16), .clear],
                center: .center, startRadius: 40, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(model.agentName)
                .font(.lbTitle)
                .foregroundStyle(Palette.beige)

            HStack(spacing: 8) {
                StatusDot(phase: model.phase)
                Text(model.phase.label)
                    .eyebrow(Palette.beige.opacity(0.75))
                if let connectedAt = model.connectedAt, model.phase != .ended {
                    Text("·").eyebrow(Palette.beige.opacity(0.4))
                    TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                        Text(Self.duration(from: connectedAt, to: context.date))
                            .eyebrow(Palette.beige.opacity(0.75))
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var captionView: some View {
        ZStack(alignment: .top) {
            if let caption = model.caption {
                Text(caption.text)
                    .font(caption.speaker == .agent ? .title3.weight(.medium) : .body)
                    .foregroundStyle(caption.speaker == .agent ? Palette.beige : Palette.beige.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .id(caption.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.smooth(duration: 0.45), value: model.caption)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 22) {
                Button(action: model.toggleMute) {
                    Image(systemName: model.isMuted ? "mic.slash.fill" : "mic.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(GlassCircleButtonStyle(tint: model.isMuted ? Palette.beige.opacity(0.35) : nil))
                .accessibilityLabel(model.isMuted ? "Unmute" : "Mute")

                Button {} label: { Image(systemName: "video.fill") }
                    .buttonStyle(GlassCircleButtonStyle())
                    .accessibilityLabel("Camera")
                    .disabled(true)

                Button {
                    model.end()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassCircleButtonStyle(diameter: 72, tint: Palette.danger))
                .accessibilityLabel("End call")
            }
        }
    }

    static func duration(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct StatusDot: View {
    var phase: CallPhase

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 7, height: 7)
            .phaseAnimator([false, true], trigger: phase) { dot, pulse in
                dot.opacity(phase == .connecting && pulse ? 0.3 : 1)
            } animation: { _ in .easeInOut(duration: 0.6) }
    }

    private var color: Color {
        switch phase {
        case .connecting: Palette.amber
        case .listening: Palette.yellow
        case .thinking: Palette.orange
        case .speaking: Palette.flame
        case .ended: Palette.beige.opacity(0.4)
        }
    }
}

#Preview {
    VoiceCallView(model: VoiceCallModel(agentName: "Mistral", session: SimulatedVoiceSession()))
}
