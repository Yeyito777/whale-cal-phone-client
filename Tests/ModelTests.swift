import Foundation

@main @MainActor
enum ModelTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(name)") }
    }
    static func item(_ start: String? = "09:00", _ end: String? = "10:00", day: String = "2026-09-07", endDay: String? = nil, kind: String? = nil) -> Occurrence {
        let event = CalEvent(kind: kind, id: "e", calendarId: "c", title: "Test", startDate: day, endDate: endDay ?? day, startTime: start, endTime: end)
        return Occurrence(id: UUID().uuidString, event: event, startDate: day, endDate: endDay ?? day, occurrenceIndex: 0)
    }
    static func main() throws {
        let day = "2026-09-07"
        check(Dates.key(Dates.date(day)) == day, "date roundtrip")
        check(Dates.key(Dates.weekStart(Dates.date("2026-09-13"))) == day, "Monday week")
        check(Dates.monthDays(Dates.date("2021-02-01")).count == 28, "four-week February")
        check(Dates.monthDays(Dates.date("2026-08-01")).count == 42, "six-week month")
        check(Dates.monthDays(Dates.date("2026-09-01")).count == 35, "five-week month")
        check(Dates.key(Dates.add(1, to: Dates.date("2028-02-28"))) == "2028-02-29", "leap day")
        check(Dates.duration(90) == "1h 30m", "duration")
        check(Dates.clock(1440) == "24:00", "day boundary")
        check(DaySchedule.gaps([], day: day) == [FreeGap(start: 0, end: 1440)], "empty day")
        check(DaySchedule.gaps([item()], day: day) == [FreeGap(start: 0, end: 540), FreeGap(start: 600, end: 1440)], "timed reservation")
        check(DaySchedule.gaps([item(), item("09:30", "11:00"), item("11:00", "12:00")], day: day) == [FreeGap(start: 0, end: 540), FreeGap(start: 720, end: 1440)], "overlap and touching union")
        for marker in [item(nil, nil), item("09:00", nil), item("09:00", "10:00", kind: "deadline")] {
            check(DaySchedule.gaps([marker], day: day) == [FreeGap(start: 0, end: 1440)], "markers do not reserve time")
        }
        check(DaySchedule.busyInterval(item("23:00", "02:00", day: "2026-09-06", endDay: day), day: day) == FreeGap(start: 0, end: 120), "overnight start clipping")
        check(DaySchedule.busyInterval(item("23:00", "02:00", day: day, endDay: "2026-09-08"), day: day) == FreeGap(start: 1380, end: 1440), "overnight end clipping")
        var completed = item()
        completed.event.completed = true
        check(completed.isComplete, "nonrecurring completion")
        check(DaySchedule.busyInterval(completed, day: day) != nil, "completed events still reserve time")
        completed.event.recurrence = RecurrenceRule(frequency: "weekly", interval: 1)
        check(!completed.isComplete, "series ignores base completion")
        completed.event.completedDates = [day]
        check(completed.isComplete, "occurrence completion")
        completed.startDate = "2026-09-14"
        check(!completed.isComplete, "other occurrence unchanged")
        let deadline = item(nil, nil, kind: "deadline")
        check(!deadline.isOverdue(at: Dates.date(day, time: "23:59")), "date-only deadline not prematurely overdue")
        check(deadline.isOverdue(at: Dates.date("2026-09-08")), "deadline overdue next day")
        check(item("09:00", nil, kind: "deadline").isOverdue(at: Dates.date(day, time: "09:01")), "timed deadline overdue")
        check(!item().isOverdue(at: Dates.date("2026-09-08")), "events never deadline overdue")
        let message = try JSONDecoder().decode(DaemonMessage.self, from: Data("{\"type\":\"events_list\",\"reqId\":\"x\",\"revision\":3,\"occurrences\":[]}".utf8))
        check(message.occurrences?.isEmpty == true && message.revision == 3, "protocol decode")
        let legacy = try JSONDecoder().decode(CalEvent.self, from: Data("{\"id\":\"e\",\"calendarId\":\"c\",\"title\":\"Deadline in title\",\"startDate\":\"2026-09-07\",\"endDate\":\"2026-09-07\"}".utf8))
        check(!legacy.isDeadline, "legacy types never inferred from titles")
        var configuration = SSHConnectionConfiguration(host: "calendar.invalid", port: 22, username: "test", bridgeHost: "127.0.0.1", bridgePort: 46282, pinnedHostKey: "ssh-ed25519 placeholder")
        // Cryptographic parsing happens in the SSH transport; configuration validation
        // independently enforces completeness, valid ports and a loopback target.
        check((try? configuration.validate()) != nil, "complete SSH configuration")
        configuration.pinnedHostKey = ""
        check((try? configuration.validate()) == nil, "missing pin fails closed")
        configuration.pinnedHostKey = "ssh-ed25519 placeholder"
        configuration.bridgeHost = "0.0.0.0"
        check((try? configuration.validate()) == nil, "non-loopback bridge rejected")
        configuration.bridgeHost = "127.0.0.1"
        configuration.port = 0
        check((try? configuration.validate()) == nil, "invalid SSH port rejected")
        print("PASS: \(checks) model / scheduling / protocol checks")
    }
}
