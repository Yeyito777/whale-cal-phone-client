import Foundation

enum CalendarDrawerInteraction {
    static func isHorizontal(x: Double, y: Double) -> Bool { abs(x) > abs(y) * 1.25 }

    static func dragProgress(start: Double, translation: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(start + translation / width, 0), 1)
    }

    /// Cubic x control points are 1/3 and 2/3, so time is linear.
    /// y1 = speed * duration / (3 * distance) preserves release velocity;
    /// keeping it in 0...1 makes the whole curve monotone and non-overshooting.
    static func settleMotion(distance: Double, velocity: Double) -> (duration: Double, firstControlY: Double) {
        let travel = abs(distance)
        guard travel > 0.001 else { return (0, 0) }
        let speed = max(0, velocity * (distance > 0 ? 1 : -1))
        let baseDuration = 0.16 + 0.12 * min(travel / 320, 1)
        let duration = speed > 0 ? min(baseDuration, 3 * travel / speed) : baseDuration
        return (duration, min(1, speed * duration / (3 * travel)))
    }

    static func settledOpen(progress: Double, velocity: Double, width: Double) -> Bool {
        guard width > 0 else { return false }
        // Project the release velocity a short distance; no second spring or
        // independent gesture reset is allowed to move the drawer afterwards.
        return progress + velocity * 0.18 / width > 0.5
    }
}
