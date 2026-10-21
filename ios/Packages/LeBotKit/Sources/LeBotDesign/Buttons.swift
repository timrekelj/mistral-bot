import SwiftUI

/// Solid ink capsule: the primary call to action.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lbHeadline)
            .foregroundStyle(Palette.onPrimaryFill)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.primaryFill, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var lbPrimary: PrimaryButtonStyle { .init() }
}

/// Round Liquid Glass control used on the call screen and composer.
public struct GlassCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat
    var tint: Color?

    public init(diameter: CGFloat = 64, tint: Color? = nil) {
        self.diameter = diameter
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.34, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .glassEffect(glass, in: .circle)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }

    private var glass: Glass {
        if let tint { .regular.tint(tint).interactive() } else { .regular.interactive() }
    }
}
