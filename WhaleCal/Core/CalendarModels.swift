import Foundation

struct CalCalendar: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var color: String
    var visible: Bool
    var groupId: String?
}

struct CalendarGroup: Codable, Identifiable, Sendable {
    var id: String
    var name: String
}

struct CalendarSection: Identifiable {
    let group: CalendarGroup?
    let calendars: [CalCalendar]
    var id: String { group?.id ?? "__ungrouped" }
    var title: String { group?.name ?? "Ungrouped" }
    static func make(calendars: [CalCalendar], groups: [CalendarGroup]) -> [CalendarSection] {
        let ids = Set(groups.map(\.id))
        let loose = calendars.filter { $0.groupId.map { !ids.contains($0) } ?? true }
        let sections = groups.map { group in CalendarSection(group: group, calendars: calendars.filter { $0.groupId == group.id }) }
        return sections + (loose.isEmpty ? [] : [CalendarSection(group: nil, calendars: loose)])
    }
}

struct RecurrenceRule: Codable, Sendable {
    var frequency: String
    var interval: Int
    var until: String?
    var count: Int?
}

struct CalEvent: Codable, Identifiable, Sendable {
    var kind: String?
    var id: String
    var calendarId: String
    var title: String
    var startDate: String
    var endDate: String
    var startTime: String?
    var endTime: String?
    var location: String?
    var notes: String?
    var recurrence: RecurrenceRule?
    var completed: Bool?
    var completedDates: [String]?
    var isDeadline: Bool { kind == "deadline" }
    var timeLabel: String {
        if isDeadline { return startTime.map { "Due \($0)" } ?? "Due today" }
        guard let startTime else { return "All day" }
        return "\(startTime)–\(endTime ?? "?")"
    }
}

struct Occurrence: Codable, Identifiable, Sendable {
    var id: String
    var event: CalEvent
    var startDate: String
    var endDate: String
    var occurrenceIndex: Int
    var isComplete: Bool {
        event.recurrence != nil
            ? (event.completedDates ?? []).contains(startDate)
            : event.completed == true
    }
    func isOverdue(at now: Date) -> Bool {
        guard event.isDeadline, !isComplete else { return false }
        if let time = event.startTime { return Dates.date(startDate, time: time) <= now }
        return startDate < Dates.key(now)
    }
    func covers(_ day: String) -> Bool { startDate <= day && endDate >= day }
}

struct CalendarDatabase: Codable, Sendable {
    var revision: Int
    var calendars: [CalCalendar]
    var events: [CalEvent]
    var groups: [CalendarGroup]?
}

struct DaemonMessage: Decodable, Sendable {
    var type: String
    var reqId: String?
    var message: String?
    var database: CalendarDatabase?
    var calendars: [CalCalendar]?
    var calendar: CalCalendar?
    var groups: [CalendarGroup]?
    var group: CalendarGroup?
    var occurrences: [Occurrence]?
    var event: CalEvent?
    var revision: Int?
}

enum Dates {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }
    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ key: String, time: String = "00:00") -> Date {
        let d = key.split(separator: "-").compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2 else { return .distantPast }
        return calendar.date(from: DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1])) ?? .distantPast
    }
    static func add(_ amount: Int, _ component: Calendar.Component = .day, to date: Date) -> Date {
        calendar.date(byAdding: component, value: amount, to: date) ?? date
    }
    static func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }
    static func weekStart(_ date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        return add(-((weekday + 5) % 7), to: calendar.startOfDay(for: date))
    }
    static func monthDays(_ date: Date) -> [Date] {
        let start = weekStart(monthStart(date))
        let last = add(-1, to: add(1, .month, to: monthStart(date)))
        let end = add(6, to: weekStart(last))
        let count = calendar.dateComponents([.day], from: start, to: end).day! + 1
        return (0..<count).map { add($0, to: start) }
    }
    static func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }
    static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h" + (minutes % 60 == 0 ? "" : " \(minutes % 60)m")
    }
}

struct FreeGap: Identifiable, Equatable {
    var start: Int
    var end: Int
    var id: Int { start }
    var duration: Int { end - start }
    func contains(_ minute: Int) -> Bool { start <= minute && minute < end }
}

struct DayAvailability {
    let gaps: [FreeGap]
    let minute: Int?
    let activeItems: [Occurrence]

    var totalFree: Int { gaps.reduce(0) { $0 + $1.duration } }
    var freeRemaining: Int? {
        guard let minute else { return nil }
        return gaps.reduce(0) { $0 + max(0, $1.end - max(minute, $1.start)) }
    }
    var freeNow: FreeGap? { minute.flatMap { minute in gaps.first { $0.contains(minute) } } }
    var nextFree: FreeGap? { minute.flatMap { minute in gaps.first { $0.start > minute } } }
    var partOfDay: String? {
        guard let minute else { return nil }
        switch minute {
        case 300..<720: return "Morning"
        case 720..<1020: return "Afternoon"
        case 1020..<1260: return "Evening"
        default: return "Night"
        }
    }
}

struct ScheduleGroup: Identifiable {
    var items: [Occurrence]
    let start: Int
    var end: Int
    var id: String { items[0].id }
}

struct ConcurrentOccurrence: Identifiable {
    let item: Occurrence
    let start: Date
    let end: Date
    var id: String { item.id }
}

enum DaySchedule {
    /// Connected overlap groups. Touching endpoints are sequential, not concurrent.
    /// A chain can share a group without every pair in it overlapping.
    static func groups(_ items: [Occurrence], day: String) -> [ScheduleGroup] {
        let intervals = items.compactMap { item -> (Occurrence, FreeGap)? in
            busyInterval(item, day: day).map { (item, $0) }
        }.sorted {
            if $0.1.start != $1.1.start { return $0.1.start < $1.1.start }
            if $0.1.end != $1.1.end { return $0.1.end > $1.1.end }
            return $0.0.id < $1.0.id
        }
        var result: [ScheduleGroup] = []
        for (item, interval) in intervals {
            if let last = result.last, interval.start < last.end {
                result[result.count - 1].items.append(item)
                result[result.count - 1].end = max(last.end, interval.end)
            } else {
                result.append(ScheduleGroup(items: [item], start: interval.start, end: interval.end))
            }
        }
        return result
    }

    /// Direct intersections only, across occurrence dates (including overnight).
    /// Callers supply visible calendars; deadlines/all-day/unknown ends reserve no time.
    static func concurrent(with target: Occurrence, in items: [Occurrence]) -> [ConcurrentOccurrence] {
        func interval(_ item: Occurrence) -> (Date, Date)? {
            guard !item.isComplete, !item.event.isDeadline, let start = item.event.startTime, let end = item.event.endTime else { return nil }
            let lower = Dates.date(item.startDate, time: start)
            let upper = Dates.date(item.endDate, time: end)
            return lower < upper ? (lower, upper) : nil
        }
        guard let (start, end) = interval(target) else { return [] }
        return items.compactMap { item -> ConcurrentOccurrence? in
            guard item.id != target.id, let (otherStart, otherEnd) = interval(item) else { return nil }
            let lower = max(start, otherStart), upper = min(end, otherEnd)
            guard lower < upper else { return nil }
            return ConcurrentOccurrence(item: item, start: lower, end: upper)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    static func availability(_ items: [Occurrence], day: String, now: Date) -> DayAvailability {
        let minute = day == Dates.key(now)
            ? Dates.calendar.component(.hour, from: now) * 60 + Dates.calendar.component(.minute, from: now)
            : nil
        let active = items.filter { item in
            guard let minute, let interval = busyInterval(item, day: day) else { return false }
            return interval.contains(minute)
        }
        return DayAvailability(gaps: gaps(items, day: day), minute: minute, activeItems: active)
    }
    /// Completed occurrences remain history but release their reservation.
    static func busyInterval(_ item: Occurrence, day: String) -> FreeGap? {
        guard !item.isComplete else { return nil }
        return timedInterval(item, day: day)
    }

    /// Original timed extent, retained for displaying completed history.
    static func timedInterval(_ item: Occurrence, day: String) -> FreeGap? {
        guard item.covers(day), !item.event.isDeadline,
              let start = item.event.startTime, let end = item.event.endTime else { return nil }
        let lower = item.startDate < day ? 0 : Dates.minutes(start)
        let upper = item.endDate > day ? 1440 : Dates.minutes(end)
        return upper > lower ? FreeGap(start: lower, end: upper) : nil
    }
    static func gaps(_ items: [Occurrence], day: String) -> [FreeGap] {
        let busy = items.compactMap { busyInterval($0, day: day) }.sorted { $0.start < $1.start }
        var cursor = 0
        var gaps: [FreeGap] = []
        for block in busy {
            if block.start > cursor { gaps.append(FreeGap(start: cursor, end: block.start)) }
            cursor = max(cursor, block.end)
        }
        if cursor < 1440 { gaps.append(FreeGap(start: cursor, end: 1440)) }
        return gaps
    }
}
