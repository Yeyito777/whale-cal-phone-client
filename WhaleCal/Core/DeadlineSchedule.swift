import Foundation

enum DeadlineSchedule {
    static func targets(_ displayed: [Occurrence], selected: Set<String>, completed: Bool) -> [Occurrence] {
        displayed.filter { selected.contains($0.id) && $0.isComplete != completed }
    }
    /// Calendar arithmetic is anchored to the original date, matching cald's
    /// month-end clamping and per-occurrence IDs/completion semantics.
    static func expand(_ events: [CalEvent], from: String, through: String) -> [Occurrence] {
        var result: [Occurrence] = []
        for event in events {
            let base = Dates.date(event.startDate, time: "12:00")
            let duration = max(0, Dates.calendar.dateComponents([.day], from: base, to: Dates.date(event.endDate, time: "12:00")).day ?? 0)
            let count = event.recurrence.map { min(max(0, $0.count ?? 100_000), 100_000) } ?? 1
            for index in 0..<count {
                var date = base
                if let rule = event.recurrence {
                    let amount = max(1, rule.interval) * index
                    switch rule.frequency {
                    case "daily": date = Dates.add(amount, to: base)
                    case "weekly": date = Dates.add(amount * 7, to: base)
                    case "monthly": date = Dates.add(amount, .month, to: base)
                    case "yearly": date = Dates.add(amount, .year, to: base)
                    default: break
                    }
                }
                let start = Dates.key(date)
                if start > through || event.recurrence?.until.map({ start > $0 }) == true { break }
                let end = Dates.key(Dates.add(duration, to: date))
                if end >= from {
                    result.append(Occurrence(id: index == 0 ? event.id : "\(event.id)@\(start)", event: event, startDate: start, endDate: end, occurrenceIndex: index))
                }
            }
        }
        return result
    }

    static func all(_ events: [CalEvent], now: Date = Date()) -> [Occurrence] {
        let horizon = Dates.key(Dates.add(12, .month, to: now))
        return events.filter(\.isDeadline).flatMap { event in
            expand([event], from: event.startDate, through: event.recurrence == nil ? event.endDate : horizon)
        }.sorted {
            if $0.isComplete != $1.isComplete { return !$0.isComplete }
            let a = due($0), b = due($1)
            if a != b { return a < b }
            if $0.event.title != $1.event.title { return $0.event.title < $1.event.title }
            return $0.id < $1.id
        }
    }
    static func due(_ item: Occurrence) -> Date {
        item.event.startTime.map { Dates.date(item.startDate, time: $0) } ?? Dates.add(1, to: Dates.date(item.startDate))
    }
    static func section(_ item: Occurrence, now: Date) -> String {
        if item.isComplete { return "Completed" }
        if item.isOverdue(at: now) { return "Overdue" }
        let today = Dates.key(now)
        if item.startDate == today { return "Today" }
        if item.startDate == Dates.key(Dates.add(1, to: now)) { return "Tomorrow" }
        if item.startDate < Dates.key(Dates.add(7, to: now)) { return "Next seven days" }
        return Dates.date(item.startDate).formatted(.dateTime.month(.wide).year())
    }
    static func dueLabel(_ item: Occurrence, now: Date) -> String {
        if item.startDate == Dates.key(now) { return "Today" }
        if item.startDate == Dates.key(Dates.add(1, to: now)) { return "Tomorrow" }
        let date = Dates.date(item.startDate)
        return date.formatted(item.startDate.prefix(4) == Dates.key(now).prefix(4) ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }
}
