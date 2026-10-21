import SwiftUI

/// SF Pro for reading, SF Mono for small uppercase labels — the "terminal" accent
/// that echoes Mistral's technical, pixel-driven identity.
public extension Font {
    static let lbDisplay = Font.system(size: 34, weight: .bold, design: .default)
    static let lbTitle = Font.system(.title2, design: .default, weight: .semibold)
    static let lbHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let lbBody = Font.system(.body)
    static let lbCallout = Font.system(.callout)
    static let lbEyebrow = Font.system(.caption, design: .monospaced, weight: .medium)
    static let lbMono = Font.system(.footnote, design: .monospaced)
}

public struct EyebrowStyle: ViewModifier {
    var color: Color

    public func body(content: Content) -> some View {
        content
            .font(.lbEyebrow)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

public extension View {
    /// Small uppercase monospaced label, e.g. `MISTRAL · LARGE 4`.
    func eyebrow(_ color: Color = Palette.textSecondary) -> some View {
        modifier(EyebrowStyle(color: color))
    }
}
