import SwiftUI

/// Le Bot's mark: a rising pixel sun, one rainbow colour per row.
/// It deliberately avoids Mistral's own logo while sharing its pixel + stripe language.
public struct PixelMark: View {
    public enum Style: Sendable { case rainbow, mono(Color) }

    static let rows: [String] = [
        "...XXX...",
        ".XXXXXXX.",
        "XXXXXXXXX",
        "XXXXXXXXX",
        "XXXXXXXXX",
    ]

    var style: Style

    public init(style: Style = .rainbow) {
        self.style = style
    }

    public var body: some View {
        Canvas { context, size in
            let rows = Self.rows
            let columns = rows[0].count
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows.count))
            let origin = CGPoint(
                x: (size.width - cell * CGFloat(columns)) / 2,
                y: (size.height - cell * CGFloat(rows.count)) / 2
            )
            let inset = cell * 0.06
            for (y, row) in rows.enumerated() {
                let color: Color = switch style {
                case .rainbow: Palette.rainbow[y]
                case let .mono(color): color
                }
                for (x, char) in row.enumerated() where char == "X" {
                    let rect = CGRect(
                        x: origin.x + CGFloat(x) * cell + inset,
                        y: origin.y + CGFloat(y) * cell + inset,
                        width: cell - inset * 2,
                        height: cell - inset * 2
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.12), with: .color(color))
                }
            }
        }
        .aspectRatio(9 / 5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The five rainbow bands as a thin stripe, used as a brand accent.
public struct RainbowStripe: View {
    var axis: Axis

    public init(axis: Axis = .horizontal) {
        self.axis = axis
    }

    public var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        layout {
            ForEach(Palette.rainbow.indices, id: \.self) { index in
                Palette.rainbow[index]
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 32) {
        PixelMark().frame(width: 180)
        PixelMark(style: .mono(.primary)).frame(width: 60)
        RainbowStripe().frame(height: 4)
    }
    .padding()
}
