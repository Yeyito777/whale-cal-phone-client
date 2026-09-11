import SwiftUI

/// The Exocortex palettes share the canonical iPhone/TUI colors. Muted text
/// is lifted slightly where needed for readable small calendar labels on iOS.
struct WhalePalette {
    let name: CalendarThemeName
    let background: Color
    let sidebar: Color
    let surface: Color
    let selection: Color
    let accent: Color
    let secondary: Color
    let text: Color
    let muted: Color
    let warning: Color
    let green: Color
    let line: Color
    var preview: [Color] { [accent, secondary, surface] }
}

extension CalendarThemeName {
    var palette: WhalePalette {
        switch self {
        case .dark:
            WhalePalette(name: self, background: Color(hex: "#111315"), sidebar: Color(hex: "#111315"),
                         surface: Color(hex: "#1B1E21"), selection: Color(hex: "#1B1E21"),
                         accent: Color(hex: "#A7C4DB"), secondary: Color(hex: "#979DA5"), text: .white,
                         muted: Color(hex: "#979DA5"), warning: Color(hex: "#D5AE7B"), green: Color(hex: "#8BB89A"),
                         line: Color.white.opacity(0.09))
        case .whale:
            WhalePalette(name: self, background: Color(hex: "#00050F"), sidebar: Color(hex: "#030814"),
                         surface: Color(hex: "#090D35"), selection: Color(hex: "#0F193C"),
                         accent: Color(hex: "#1D9BF0"), secondary: Color(hex: "#48CAE4"), text: .white,
                         muted: Color(hex: "#929AA8"), warning: Color(hex: "#FFD60A"), green: Color(hex: "#50C878"),
                         line: Color(hex: "#555555").opacity(0.4))
        case .cerberus:
            WhalePalette(name: self, background: Color(hex: "#141414"), sidebar: Color(hex: "#1A1A1A"),
                         surface: Color(hex: "#252525"), selection: Color(hex: "#333333"),
                         accent: Color(hex: "#D32F2F"), secondary: Color(hex: "#FF6B6B"), text: Color(hex: "#E0E0E0"),
                         muted: Color(hex: "#A0A0A0"), warning: Color(hex: "#FFA726"), green: Color(hex: "#66BB6A"),
                         line: Color(hex: "#555555").opacity(0.4))
        case .tonikawa:
            WhalePalette(name: self, background: Color(hex: "#131116"), sidebar: Color(hex: "#17131A"),
                         surface: Color(hex: "#211A21"), selection: Color(hex: "#302331"),
                         accent: Color(hex: "#E47FAC"), secondary: Color(hex: "#B99AD8"), text: Color(hex: "#EEE9ED"),
                         muted: Color(hex: "#A396A0"), warning: Color(hex: "#D6A65D"), green: Color(hex: "#87B695"),
                         line: Color(hex: "#655B63").opacity(0.4))
        }
    }
}

private struct WhaleThemeKey: EnvironmentKey {
    static let defaultValue = CalendarThemeName.dark.palette
}

extension EnvironmentValues {
    var whaleTheme: WhalePalette {
        get { self[WhaleThemeKey.self] }
        set { self[WhaleThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x1d9bf0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct EventRow: View {
    @Environment(\.whaleTheme) private var theme
    let item: Occurrence
    let calendar: CalCalendar?
    var now = Date()
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: calendar?.color ?? "#1d9bf0")).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if item.event.isDeadline { Image(systemName: "diamond.fill").font(.system(size: 9)) }
                    Text(item.event.title).font(.system(size: 16, weight: .medium)).strikethrough(item.isComplete)
                    if item.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.green) }
                }
                HStack(spacing: 6) {
                    Text(item.event.timeLabel)
                    if item.event.recurrence != nil { Image(systemName: "repeat") }
                    if item.isOverdue(at: now) { Text("OVERDUE").foregroundStyle(theme.warning) }
                }.font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.muted)
                if let location = item.event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin").font(.caption).foregroundStyle(theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(item.isComplete ? theme.muted : theme.text)
        .padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
        .fixedSize(horizontal: false, vertical: true)
    }
}
