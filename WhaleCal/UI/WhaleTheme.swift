import SwiftUI

enum Whale {
    static let background = Color(hex: "#00050f")
    static let surface = Color(hex: "#090d35")
    static let accent = Color(hex: "#1d9bf0")
    static let muted = Color(hex: "#929caf")
    static let warning = Color(hex: "#ffd60a")
    static let green = Color(hex: "#50c878")
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x1d9bf0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct EventRow: View {
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
                    if item.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(Whale.green) }
                }
                HStack(spacing: 6) {
                    Text(item.event.timeLabel)
                    if item.event.recurrence != nil { Image(systemName: "repeat") }
                    if item.isOverdue(at: now) { Text("OVERDUE").foregroundStyle(Whale.warning) }
                }.font(.system(size: 11, design: .monospaced)).foregroundStyle(Whale.muted)
                if let location = item.event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin").font(.caption).foregroundStyle(Whale.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(item.isComplete ? Whale.muted : .white)
        .padding(12).background(Whale.surface, in: RoundedRectangle(cornerRadius: 10))
        .fixedSize(horizontal: false, vertical: true)
    }
}
