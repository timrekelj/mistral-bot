import SwiftUI

/// The live-call visual: the `pixelSun` Metal shader plus a soft bloom underneath.
struct PixelSunView: View {
    var target: SunTarget
    var cell: CGFloat = 9

    @State private var motion = SunMotion()
    @State private var epoch = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: false)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSince(epoch)
            let uniforms = motion.advance(to: context.date.timeIntervalSince(epoch), toward: target)
            GeometryReader { proxy in
                let shader = ShaderLibrary.pixelSun(
                    .float2(proxy.size),
                    .float(time),
                    .float(cell),
                    .float(uniforms.energy),
                    .float(uniforms.connect),
                    .float(uniforms.listen),
                    .float(uniforms.think),
                    .float(uniforms.speak)
                )
                ZStack {
                    Rectangle()
                        .colorEffect(shader)
                        .blur(radius: 38)
                        .opacity(0.55 + 0.3 * uniforms.energy)
                        .blendMode(.plusLighter)
                    Rectangle()
                        .colorEffect(shader)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    PixelSunView(target: SunTarget(energy: 0.6, connect: 0, speak: 1))
        .padding()
        .background(.black)
}
