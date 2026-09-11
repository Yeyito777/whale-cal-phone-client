import SwiftUI

struct EventEditorView: View {
    @Environment(\.whaleTheme) private var theme
    let model: CalendarConnectionModel
    let date: Date
    var event: CalEvent?
    var defaultKind = "event"
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = "event"
    @State private var calendarId = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var timed = true
    @State private var hasEnd = true
    @State private var startTime = Dates.date("2000-01-01", time: "09:00")
    @State private var endTime = Dates.date("2000-01-01", time: "10:00")
    @State private var location = ""
    @State private var notes = ""
    @State private var frequency = "none"
    @State private var interval = 1
    @State private var recurrenceEnd = "never"
    @State private var until = Date()
    @State private var count = 10
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                Section {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $kind) { Text("Event").tag("event"); Text("Deadline").tag("deadline") }.pickerStyle(.menu)
                    Picker("Calendar", selection: $calendarId) { ForEach(model.calendars) { Text($0.name).tag($0.id) } }
                }
                Section(kind == "deadline" ? "Due" : "Schedule") {
                    DatePicker(kind == "deadline" ? "Due date" : "Start date", selection: $startDate, displayedComponents: .date)
                    Toggle(kind == "deadline" ? "Due time" : "Timed event", isOn: $timed)
                    if timed { DatePicker(kind == "deadline" ? "Due time" : "Start", selection: $startTime, displayedComponents: .hourAndMinute) }
                    if kind == "event" {
                        DatePicker("End date", selection: $endDate, in: Dates.calendar.startOfDay(for: startDate)..., displayedComponents: .date)
                        if timed {
                            Toggle("Reserve a duration", isOn: $hasEnd)
                            if hasEnd { DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute) }
                        }
                    }
                }
                Section("Repeat") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(["none", "daily", "weekly", "monthly", "yearly"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    if frequency != "none" {
                        Stepper("Interval: \(interval)", value: $interval, in: 1...999)
                        Picker("Ends", selection: $recurrenceEnd) { Text("Never").tag("never"); Text("On date").tag("until"); Text("After count").tag("count"); if event?.recurrence?.until != nil && event?.recurrence?.count != nil { Text("Date and count").tag("both") } }
                        if recurrenceEnd == "until" || recurrenceEnd == "both" { DatePicker("Last start date", selection: $until, in: Dates.calendar.startOfDay(for: startDate)..., displayedComponents: .date) }
                        if recurrenceEnd == "count" || recurrenceEnd == "both" { Stepper("\(count) occurrences", value: $count, in: 1...10000) }
                    }
                    if event?.recurrence != nil { Text("You are editing the entire series, starting \(event!.startDate).").font(.caption).foregroundStyle(theme.warning) }
                }
                Section("Location") { TextField("Optional location", text: $location) }
                Section("Notes") { TextEditor(text: $notes).frame(minHeight: 120) }
                if let error { Section { Text(error).foregroundStyle(theme.warning) } }
                }.listRowBackground(theme.background).listRowSeparatorTint(theme.line)
            }
            .listStyle(.plain).font(.callout).scrollContentBackground(.hidden).background(theme.background).disabled(saving)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                WhalePageHeader(title: event == nil ? "New item" : "Edit item", closeLabel: "Cancel", onClose: { dismiss() }, closeEnabled: !saving, actionTitle: saving ? "Saving…" : "Save", actionEnabled: !saving && model.connected && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !calendarId.isEmpty, onAction: { save() })
            }
            .interactiveDismissDisabled(saving)
            .onAppear { load() }
            .onChange(of: startDate) { old, new in
                if Dates.key(endDate) == Dates.key(old) || endDate < new { endDate = new }
                if until < new { until = new }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        calendarId = event?.calendarId ?? model.calendars.first(where: { model.isVisible($0.id) })?.id ?? model.calendars.first?.id ?? ""
        kind = defaultKind
        if defaultKind == "deadline" { timed = false }
        startDate = event.map { Dates.date($0.startDate) } ?? date
        endDate = event.map { Dates.date($0.endDate) } ?? date
        until = Dates.add(1, .year, to: startDate)
        guard let event else { return }
        title = event.title; kind = event.kind ?? "event"
        timed = event.startTime != nil; hasEnd = event.endTime != nil
        if let time = event.startTime { startTime = Dates.date("2000-01-01", time: time) }
        if let time = event.endTime { endTime = Dates.date("2000-01-01", time: time) }
        location = event.location ?? ""; notes = event.notes ?? ""
        if let rule = event.recurrence {
            frequency = rule.frequency; interval = rule.interval
            if let end = rule.until { recurrenceEnd = "until"; until = Dates.date(end) }
            if let limit = rule.count { recurrenceEnd = rule.until == nil ? "count" : "both"; count = limit }
        }
    }
    private func timeKey(_ date: Date) -> String {
        Dates.clock(Dates.calendar.component(.hour, from: date) * 60 + Dates.calendar.component(.minute, from: date))
    }
    private func save() {
        error = nil
        let start = Dates.key(startDate), end = kind == "deadline" ? start : Dates.key(endDate)
        if end < start { error = "End date must not precede start date."; return }
        if kind == "event", timed, hasEnd, start == end, timeKey(endTime) <= timeKey(startTime) {
            error = "End time must be later than start time. For overnight events, choose the next end date."; return
        }
        var draft: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines), "kind": kind, "calendarId": calendarId, "startDate": start, "endDate": end, "location": location, "notes": notes]
        if timed { draft["startTime"] = timeKey(startTime) }
        else if event != nil { draft["startTime"] = NSNull() }
        if kind == "event", timed, hasEnd { draft["endTime"] = timeKey(endTime) }
        else if event != nil { draft["endTime"] = NSNull() }
        if frequency != "none" {
            var rule: [String: Any] = ["frequency": frequency, "interval": interval]
            if recurrenceEnd == "until" || recurrenceEnd == "both" { rule["until"] = Dates.key(until) }
            if recurrenceEnd == "count" || recurrenceEnd == "both" { rule["count"] = count }
            draft["recurrence"] = rule
        } else if event != nil { draft["recurrence"] = NSNull() }
        let command: [String: Any] = event.map { ["type": "update_event", "id": $0.id, "patch": draft] } ?? ["type": "create_event", "event": draft]
        saving = true
        Task {
            do { try await model.mutate(command); dismiss() }
            catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
