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
        check(DaySchedule.busyInterval(completed, day: day) == nil, "completed events release time")
        check(DaySchedule.timedInterval(completed, day: day) != nil, "completed history retains its original extent")
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
        let freeMorning = DaySchedule.availability([item()], day: day, now: Dates.date(day, time: "08:30"))
        check(freeMorning.minute == 510 && freeMorning.partOfDay == "Morning", "current wall-clock time and day period")
        check(freeMorning.freeNow == FreeGap(start: 0, end: 540), "current free block")
        check(freeMorning.freeRemaining == 870, "remaining free time excludes elapsed free time")
        check(freeMorning.totalFree == 1380, "whole-day free time stays separate")
        let overlapping = DaySchedule.availability([item(), item("09:30", "11:00")], day: day, now: Dates.date(day, time: "09:45"))
        check(overlapping.activeItems.count == 2, "all overlapping events shown as current")
        check(overlapping.freeNow == nil && overlapping.nextFree?.start == 660, "next free block follows overlapping union")
        check(overlapping.freeRemaining == 780, "overlaps not double-counted in remaining time")
        let boundary = DaySchedule.availability([item()], day: day, now: Dates.date(day, time: "10:00"))
        check(boundary.activeItems.isEmpty && boundary.freeNow?.start == 600, "event end is free immediately")
        let startBoundary = DaySchedule.availability([item()], day: day, now: Dates.date(day, time: "09:00"))
        check(startBoundary.freeNow == nil && startBoundary.activeItems.count == 1, "event start is busy immediately")
        let tonight = DaySchedule.availability([item(nil, nil, kind: "deadline")], day: day, now: Dates.date(day, time: "22:00"))
        check(tonight.freeRemaining == 120 && tonight.partOfDay == "Night", "late-night free time stops at midnight")
        check(tonight.freeNow?.end == 1440 && tonight.activeItems.isEmpty, "deadlines do not create current reservations")
        let otherDay = DaySchedule.availability([item()], day: day, now: Dates.date("2026-09-08", time: "09:30"))
        check(otherDay.minute == nil && otherDay.freeRemaining == nil && otherDay.activeItems.isEmpty, "no current-time claims on another day")
        let full = DaySchedule.availability([item("00:00", "00:00", day: "2026-09-06", endDay: "2026-09-08")], day: day, now: Dates.date(day, time: "17:00"))
        check(full.totalFree == 0 && full.freeRemaining == 0 && full.nextFree == nil, "fully booked overnight day")
        check(full.partOfDay == "Evening", "evening time of day")
        let a = item("09:00", "10:00"), b = item("09:30", "11:00"), c = item("10:30", "12:00")
        let chain = DaySchedule.groups([c, a, b], day: day)
        check(chain.count == 1 && chain[0].items.map(\.id) == [a.id, b.id, c.id], "overlap chains grouped in chronological order")
        check(chain[0].start == 540 && chain[0].end == 720, "shared chart scale spans overlap union")
        check(DaySchedule.groups([a, item("10:00", "11:00")], day: day).count == 2, "touching events not labeled concurrent")
        let nested = DaySchedule.groups([item("09:30", "09:45"), a, item("09:40", "09:50")], day: day)
        check(nested.count == 1 && nested[0].end == 600, "nested events preserve outer extent")
        check(DaySchedule.groups([a, item()], day: day)[0].items.count == 2, "identical time ranges both retained")
        check(DaySchedule.groups([item(nil, nil), item("09:00", nil), deadline], day: day).isEmpty, "nonreserving items excluded from concurrency")
        check(DaySchedule.groups([], day: day).isEmpty, "empty schedule has no groups")
        let direct = DaySchedule.concurrent(with: a, in: [a, b, c])
        check(direct.map(\.id) == [b.id], "details show direct overlaps, not transitive neighbors or self")
        check(direct[0].start == Dates.date(day, time: "09:30") && direct[0].end == Dates.date(day, time: "10:00"), "details report actual shared time")
        check(DaySchedule.concurrent(with: a, in: [item("10:00", "11:00"), deadline, item(nil, nil), item("09:00", nil)]).isEmpty, "details exclude touching and nonreserving items")
        check(DaySchedule.concurrent(with: deadline, in: [a]).isEmpty, "deadline is never a concurrent reservation")
        let overnight = item("23:00", "02:00", day: "2026-09-06", endDay: day)
        let midnight = item("01:00", "03:00")
        let nightOverlap = DaySchedule.concurrent(with: overnight, in: [midnight])
        check(nightOverlap.count == 1 && nightOverlap[0].start == Dates.date(day, time: "01:00") && nightOverlap[0].end == Dates.date(day, time: "02:00"), "overnight details use occurrence dates")
        let nightGroup = DaySchedule.groups([overnight, midnight], day: day)
        check(nightGroup.count == 1 && nightGroup[0].start == 0 && nightGroup[0].end == 180, "overnight overlap chart clipped to selected day")
        check(DaySchedule.concurrent(with: a, in: [item(day: "2026-09-08")]).isEmpty, "same hours on different dates do not overlap")
        var done = b
        done.event.completed = true
        check(DaySchedule.concurrent(with: a, in: [done]).isEmpty, "completed history is not an active overlap")
        check(DaySchedule.concurrent(with: done, in: [a]).isEmpty, "completed target has no active conflicts")
        check(DaySchedule.availability([done], day: day, now: Dates.date(day, time: "10:00")).activeItems.isEmpty, "completed history is never happening now")
        check(DaySchedule.gaps([done], day: day) == [FreeGap(start: 0, end: 1440)], "completion merges the entire free span")
        check(DaySchedule.gaps([a, done, c], day: day) == [FreeGap(start: 0, end: 540), FreeGap(start: 600, end: 630), FreeGap(start: 720, end: 1440)], "completion leaves overlapping unfinished reservations busy")
        let parallel = DayTimelineLayout(items: [a, b, c], day: day)
        check(parallel.maxLanes == 2, "parallel timeline reuses ended lanes in overlap chains")
        check(parallel.cards.first(where: { $0.id == a.id })?.lane == parallel.cards.first(where: { $0.id == c.id })?.lane, "nonoverlapping cards share a lane")
        check(parallel.y(540) < parallel.y(570) && parallel.y(570) < parallel.y(600), "shared boundary scale is ordered")
        check(parallel.y(1440) == parallel.height, "timeline reaches end of day")
        let historyLayout = DayTimelineLayout(items: [done], day: day)
        check(historyLayout.cards.count == 2 && historyLayout.maxLanes == 2, "completed history displayed beside free time")
        check(historyLayout.cards.first(where: { $0.item == nil })?.interval == FreeGap(start: 0, end: 1440), "parallel free lane is maximal, not split by history")
        check(historyLayout.gaps.isEmpty, "parallel availability not duplicated outside lanes")
        let sequential = DayTimelineLayout(items: [a, item("10:00", "11:00")], day: day)
        check(sequential.maxLanes == 1, "adjacent events occupy full width")
        let dense = DayTimelineLayout(items: [a, item(), item(), item()], day: day)
        check(dense.maxLanes == 4 && Set(dense.cards.map(\.lane)).count == 4, "dense overlaps retain every lane")
        let emptyLayout = DayTimelineLayout(items: [], day: day)
        check(emptyLayout.cards.isEmpty && emptyLayout.gaps == [FreeGap(start: 0, end: 1440)], "empty timeline is unboxed full-day availability")
        let groupList = [CalendarGroup(id: "g", name: "Work"), CalendarGroup(id: "empty", name: "Empty")]
        let calendarList = [CalCalendar(id: "one", name: "One", color: "#123456", visible: false, groupId: "g"), CalCalendar(id: "two", name: "Two", color: "#123456", visible: true, groupId: "missing")]
        let sections = CalendarSection.make(calendars: calendarList, groups: groupList)
        check(sections.count == 3 && sections[0].calendars[0].id == "one", "persistent groups organize calendars including hidden members")
        check(sections[1].calendars.isEmpty, "empty groups remain manageable")
        check(sections[2].group == nil && sections[2].calendars[0].id == "two", "unknown or removed groups fall back to ungrouped")
        let legacyCalendar = try JSONDecoder().decode(CalCalendar.self, from: Data("{\"id\":\"old\",\"name\":\"Old\",\"color\":\"#123456\",\"visible\":true}".utf8))
        check(legacyCalendar.groupId == nil, "legacy calendars decode without groups")
        let groupMessage = try JSONDecoder().decode(DaemonMessage.self, from: Data("{\"type\":\"groups_list\",\"groups\":[{\"id\":\"g\",\"name\":\"Work\"}],\"revision\":9}".utf8))
        check(groupMessage.groups?.first?.name == "Work", "group protocol response decodes")
        var monthly = item(day: "2024-01-31", kind: "deadline").event
        monthly.recurrence = RecurrenceRule(frequency: "monthly", interval: 1, count: 3)
        let monthlyItems = DeadlineSchedule.expand([monthly], from: "2024-01-01", through: "2024-12-31")
        check(monthlyItems.map(\.startDate) == ["2024-01-31", "2024-02-29", "2024-03-31"], "recurrence clamps month ends without drifting")
        check(monthlyItems[0].id == monthly.id && monthlyItems[1].id == "\(monthly.id)@2024-02-29", "local expansion preserves daemon occurrence IDs")
        monthly.completedDates = ["2024-02-29"]
        check(DeadlineSchedule.all([monthly], now: Dates.date(day)).filter(\.isComplete).count == 1, "deadline completion stays per occurrence")
        let oldDeadline = item(nil, nil, day: "2001-01-01", kind: "deadline")
        let distantDeadline = item(nil, nil, day: "2040-01-01", kind: "deadline")
        check(DeadlineSchedule.all([oldDeadline.event, distantDeadline.event], now: Dates.date(day)).count == 2, "one-off deadlines never age out or lose distant future dates")
        var repeating = item(nil, nil, day: "2026-09-07", kind: "deadline").event
        repeating.recurrence = RecurrenceRule(frequency: "yearly", interval: 1)
        check(DeadlineSchedule.all([repeating], now: Dates.date(day)).map(\.startDate) == [day, "2027-09-07"], "future recurrence expansion bounded at twelve months")
        repeating.recurrence?.until = day
        check(DeadlineSchedule.all([repeating], now: Dates.date(day)).count == 1, "recurrence until is inclusive")
        let timedDeadline = item("09:00", nil, kind: "deadline")
        check(timedDeadline.isOverdue(at: Dates.date(day, time: "09:00")), "deadline becomes due at the exact minute")
        check(!deadline.isOverdue(at: Dates.date(day, time: "23:59")), "date-only deadlines remain pending through due day")
        check(DeadlineSchedule.section(timedDeadline, now: Dates.date(day, time: "10:00")) == "Overdue", "overdue deadlines have priority hierarchy")
        check(DeadlineSchedule.dueLabel(deadline, now: Dates.date(day)) == "Today", "deadline relative due labels")
        let selectedDeadline = item("11:00", nil, kind: "deadline")
        let unselectedDeadline = item("12:00", nil, kind: "deadline")
        check(DeadlineSchedule.targets([selectedDeadline, unselectedDeadline], selected: [selectedDeadline.id], completed: true).map(\.id) == [selectedDeadline.id], "bulk completion is limited to selected shown occurrences")
        check(DeadlineSchedule.targets([selectedDeadline], selected: [unselectedDeadline.id], completed: true).isEmpty, "hidden or filtered-out selections are not bulk targets")
        var completedDeadline = selectedDeadline
        completedDeadline.event.completed = true
        check(DeadlineSchedule.targets([completedDeadline], selected: [completedDeadline.id], completed: true).isEmpty, "bulk complete does not toggle already completed items")
        check(DeadlineSchedule.targets([completedDeadline], selected: [completedDeadline.id], completed: false).count == 1, "bulk reopen is explicit")
        check(DaySchedule.groups([a, b, c].reversed(), day: day).map { $0.items.map(\.id) } == chain.map { $0.items.map(\.id) }, "group ordering stable across refresh input order")
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
        check(CalendarDrawerInteraction.isHorizontal(x: 100, y: 20), "right swipe opens without blocking vertical scroll")
        check(!CalendarDrawerInteraction.isHorizontal(x: 20, y: 100), "vertical scrolling is not a drawer gesture")
        check(!CalendarDrawerInteraction.isHorizontal(x: 50, y: 50), "diagonal scrolling is not a drawer gesture")
        check(CalendarDrawerInteraction.dragProgress(start: 0, translation: -80, width: 320) == 0, "closed drawer ignores left drag")
        check(CalendarDrawerInteraction.dragProgress(start: 1, translation: 80, width: 320) == 1, "open drawer cannot overshoot right")
        check(CalendarDrawerInteraction.dragProgress(start: 1, translation: -100, width: 320) == 0.6875, "drawer follows left drag")
        check(CalendarDrawerInteraction.dragProgress(start: 0.4, translation: 0, width: 320) == 0.4, "re-grab starts at visible animation position without jumping")
        check(CalendarDrawerInteraction.dragProgress(start: 0.4, translation: 32, width: 320) == 0.5, "interrupted animation continues tracking one-to-one")
        check(CalendarDrawerInteraction.settledOpen(progress: 0.7, velocity: 0, width: 320), "long right drag opens drawer")
        check(!CalendarDrawerInteraction.settledOpen(progress: 0.2, velocity: 0, width: 320), "short drag snaps closed")
        check(CalendarDrawerInteraction.settledOpen(progress: 0.35, velocity: 500, width: 320), "right flick opens drawer")
        check(!CalendarDrawerInteraction.settledOpen(progress: 0.3, velocity: 0, width: 320), "long left drag dismisses drawer")
        check(CalendarDrawerInteraction.settledOpen(progress: 0.8, velocity: 0, width: 320), "short left drag stays open")
        check(!CalendarDrawerInteraction.settledOpen(progress: 0.65, velocity: -500, width: 320), "left flick dismisses drawer")
        check(CalendarDrawerInteraction.dragProgress(start: 0.4, translation: 32, width: 0) == 0, "zero-width layout is safe")
        let updated = try JSONDecoder().decode(DaemonMessage.self, from: Data("{\"type\":\"calendar_updated\",\"calendar\":{\"id\":\"c\",\"name\":\"Test\",\"color\":\"#1d9bf0\",\"visible\":false},\"revision\":4}".utf8))
        check(updated.calendar?.visible == false, "acknowledged visibility decodes for immediate drawer state")
        print("PASS: \(checks) model / scheduling / protocol checks")
    }
}
