import Foundation

enum CalendarDrawerInteraction {
    static func isHorizontal(x: Double, y: Double) -> Bool { abs(x) > abs(y) * 1.25 }

    static func dragProgress(start: Double, translation: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(start + translation / width, 0), 1)
    }

    static func settledOpen(progress: Double, velocity: Double, width: Double) -> Bool {
        guard width > 0 else { return false }
        // Project the release velocity a short distance; no second spring or
        // independent gesture reset is allowed to move the drawer afterwards.
        return progress + velocity * 0.18 / width > 0.5
    }
}
