// Renders the 1024×1024 app icon: the pixel-sun mark on night black with a warm glow.
// Usage: swift scripts/make-app-icon.swift LeBot/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.png")
let size = 1024
let rows = ["...XXX...", ".XXXXXXX.", "XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX"]
let rainbow: [UInt32] = [0xFFD800, 0xFFAF00, 0xFF8205, 0xFA500F, 0xE10500]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
let full = CGRect(x: 0, y: 0, width: size, height: size)
ctx.setFillColor(color(0x0E0D0B))
ctx.fill(full)

let glow = CGGradient(colorsSpace: space, colors: [color(0xFA500F, 0.42), color(0xFA500F, 0)] as CFArray, locations: [0, 1])!
let center = CGPoint(x: 512, y: 500)
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 520, options: [])

let cell: CGFloat = 84
let columns = CGFloat(rows[0].count)
let origin = CGPoint(x: (CGFloat(size) - cell * columns) / 2, y: (CGFloat(size) - cell * CGFloat(rows.count)) / 2)
for (y, row) in rows.enumerated() {
    for (x, char) in row.enumerated() where char == "X" {
        // Core Graphics is bottom-up: the first row is the top of the mark.
        let rect = CGRect(
            x: origin.x + CGFloat(x) * cell + 4,
            y: origin.y + CGFloat(rows.count - 1 - y) * cell + 4,
            width: cell - 8, height: cell - 8
        )
        ctx.setFillColor(color(rainbow[y]))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.fillPath()
    }
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path)")
