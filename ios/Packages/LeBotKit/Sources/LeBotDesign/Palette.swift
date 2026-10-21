import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Colours follow Mistral's brand system: the five-step "rainbow" (yellow → red),
/// warm beiges for light surfaces and a tinted near-black for dark ones.
public enum Palette {
    // MARK: Rainbow, hottest (core) to coolest (edge)
    public static let yellow = Color(hex: 0xFFD800)
    public static let amber = Color(hex: 0xFFAF00)
    public static let orange = Color(hex: 0xFF8205)
    public static let flame = Color(hex: 0xFA500F)
    public static let red = Color(hex: 0xE10500)

    public static let rainbow: [Color] = [yellow, amber, orange, flame, red]

    // MARK: Neutrals
    public static let beige = Color(hex: 0xFFFAEB)
    public static let beigeDeep = Color(hex: 0xFFF0C3)
    public static let sand = Color(hex: 0xE9E2CB)
    public static let ink = Color(hex: 0x1E1E1E)
    public static let night = Color(hex: 0x0E0D0B)

    // MARK: Semantic (light / dark)
    public static let background = Color(light: 0xFFFAEB, dark: 0x0E0D0B)
    public static let surface = Color(light: 0xFFF3D6, dark: 0x1E1E1E)
    public static let surfaceStrong = Color(light: 0xF3E8C8, dark: 0x2A2925)
    public static let separator = Color(light: 0xE9E2CB, dark: 0x34322C)
    public static let textPrimary = Color(light: 0x1E1E1E, dark: 0xFFFAEB)
    public static let textSecondary = Color(light: 0x6B655A, dark: 0xA8A193)
    public static let accent = flame
    /// Filled primary buttons: ink on light, beige on dark (Mistral's black CTA).
    public static let primaryFill = Color(light: 0x1E1E1E, dark: 0xFFFAEB)
    public static let onPrimaryFill = Color(light: 0xFFFAEB, dark: 0x1E1E1E)
    public static let danger = Color(hex: 0xE5341F)

    public static let rainbowGradient = LinearGradient(
        colors: rainbow, startPoint: .top, endPoint: .bottom
    )
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #endif
    }
}
