import SwiftUI

@main
struct WhaleCalApp: App {
    @State private var model = CalendarConnectionModel()
    @AppStorage(CalendarThemeName.storageKey) private var themeSelection = CalendarThemeName.dark.rawValue
    private var theme: WhalePalette { CalendarThemeName(savedValue: themeSelection).palette }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-concurrency") {
                ConcurrencyPreview()
            } else {
                calendar
            }
            #else
            calendar
            #endif
            }
            .environment(\.whaleTheme, theme)
            .foregroundStyle(theme.text)
            .tint(theme.accent)
            .preferredColorScheme(.dark)
        }
    }

    private var calendar: some View {
            CalendarHomeView(model: model)
                .preferredColorScheme(.dark)
                .tint(theme.accent)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.start() }
                    if phase == .background { model.stop() }
                }
    }
}

#if DEBUG
/// Deterministic, read-only UI coverage. Never connects or writes calendar data.
private struct ConcurrencyPreview: View {
    @State private var model: CalendarConnectionModel = {
        let model = CalendarConnectionModel()
        let day = "2026-09-07"
        model.selectedDate = Dates.date(day)
        model.loadedFrom = day
        model.loadedTo = day
        model.calendars = [
            CalCalendar(id: "work", name: "Work", color: "#1d9bf0", visible: true, groupId: "fixture-group"),
            CalCalendar(id: "personal", name: "Personal", color: "#50c878", visible: true)
        ]
        model.groups = [CalendarGroup(id: "fixture-group", name: "Projects")]
        model.occurrences = [
            ("Focus session", "09:00", "10:00", "work"),
            ("Delivery window", "09:30", "11:00", "personal"),
            ("Planning session", "10:30", "12:00", "work"),
            ("Finished errand", "12:30", "13:00", "personal")
        ].enumerated().map { index, value in
            let event = CalEvent(id: "fixture-\(index)", calendarId: value.3, title: value.0,
                                 startDate: day, endDate: day, startTime: value.1, endTime: value.2, completed: index == 3)
            return Occurrence(id: event.id, event: event, startDate: day, endDate: day, occurrenceIndex: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-dense") {
            for index in 0..<3 {
                let event = CalEvent(id: "dense-\(index)", calendarId: "work", title: "Parallel task \(index + 1)", startDate: day, endDate: day, startTime: "09:00", endTime: "10:00")
                model.occurrences.append(Occurrence(id: event.id, event: event, startDate: day, endDate: day, occurrenceIndex: 0))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-deadlines") {
            let today = Dates.key(Date())
            let next = Dates.key(Dates.add(1, to: Date()))
            model.deadlines = DeadlineSchedule.all([
                CalEvent(kind: "deadline", id: "old-due", calendarId: "work", title: "Overdue submission", startDate: "2020-01-01", endDate: "2020-01-01"),
                CalEvent(kind: "deadline", id: "today-due", calendarId: "personal", title: "Read the project brief and prepare questions", startDate: today, endDate: today, notes: "A readable, multi-paragraph deadline.\n\nKeep this detail available without truncation."),
                CalEvent(kind: "deadline", id: "next-due", calendarId: "work", title: "Tomorrow review", startDate: next, endDate: next, startTime: "15:00"),
                CalEvent(kind: "deadline", id: "done-due", calendarId: "personal", title: "Finished deadline", startDate: today, endDate: today, completed: true)
            ])
            model.deadlinesLoaded = true
        }
        return model
    }()

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-editor") { EventEditorView(model: model, date: model.selectedDate) }
        else if ProcessInfo.processInfo.arguments.contains("--ui-test-deadlines") { CalendarHomeView(model: model) }
        else { DayView(model: model) }
    }
}
#endif
