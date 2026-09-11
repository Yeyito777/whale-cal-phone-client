import Foundation

enum CalendarThemeName: String, CaseIterable, Identifiable {
    case dark, whale, cerberus, tonikawa

    static let storageKey = "whaleCal.theme"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    init(savedValue: String?) {
        self = savedValue.flatMap(Self.init(rawValue:)) ?? .dark
    }

    var summary: String {
        switch self {
        case .dark: "Quiet charcoal · default"
        case .whale: "Deep blue and cyan"
        case .cerberus: "Red accents on charcoal"
        case .tonikawa: "Rose and lavender on plum"
        }
    }
}
