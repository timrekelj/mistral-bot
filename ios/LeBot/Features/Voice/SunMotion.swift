import Foundation

struct SunTarget: Equatable {
    var energy: Double = 0
    var connect: Double = 1
    var listen: Double = 0
    var think: Double = 0
    var speak: Double = 0
}

/// Frame-rate–independent smoothing for the shader uniforms. Loudness reacts fast on
/// attack and decays slowly (like a VU meter); moods cross-fade over ~0.5 s.
final class SunMotion {
    private(set) var current = SunTarget()
    private var lastTime: Double?

    func advance(to time: Double, toward target: SunTarget) -> SunTarget {
        let dt = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time
        let energyRate = target.energy > current.energy ? 18.0 : 5.0
        current.energy = Self.approach(current.energy, target.energy, rate: energyRate, dt: dt)
        current.connect = Self.approach(current.connect, target.connect, rate: 4, dt: dt)
        current.listen = Self.approach(current.listen, target.listen, rate: 4, dt: dt)
        current.think = Self.approach(current.think, target.think, rate: 4, dt: dt)
        current.speak = Self.approach(current.speak, target.speak, rate: 4, dt: dt)
        return current
    }

    static func approach(_ value: Double, _ target: Double, rate: Double, dt: Double) -> Double {
        target + (value - target) * exp(-rate * dt)
    }
}
