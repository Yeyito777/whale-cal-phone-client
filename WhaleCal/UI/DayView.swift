import SwiftUI

struct DayView: View {
    @Bindable var model: CalendarConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Occurrence?
    @State private var showNew = false
    @State private var showCalendars = false
    @State private var showCalendarManager = false

    var body: some View {
        CalendarDrawerHost(model: model, isPresented: $showCalendars, onManage: { showCalendarManager = true }) {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let day = Dates.key(model.selectedDate)
                if day < model.loadedFrom || day > model.loadedTo {
                    ContentUnavailableView(model.connected ? "Loading day…" : "This date isn’t cached", systemImage: "calendar", description: Text("Connect to load this schedule."))
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Button { model.selectedDate = Dates.add(-1, to: model.selectedDate) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Previous day")
                            Spacer()
                            VStack(spacing: 4) {
                                Text(model.selectedDate.formatted(.dateTime.weekday(.wide))).font(.title2.weight(.semibold))
                                Text(model.selectedDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Whale.muted)
                            }
                            Spacer()
                            Button { model.selectedDate = Dates.add(1, to: model.selectedDate) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Next day")
                        }.padding(.horizontal)
                        ScrollView {
                            DayTimelineView(model: model, date: model.selectedDate, now: timeline.date) { selection = $0 }
                                .padding(.horizontal).padding(.bottom, 20)
                        }
                    }.padding(.top, 8).background(Whale.background)
                }
            }
            .navigationTitle("Day schedule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showNew = true } label: { Image(systemName: "plus") }.disabled(!model.connected) }
            }
            .sheet(item: $selection) { EventDetailView(model: model, original: $0) }
            .sheet(isPresented: $showNew) { EventEditorView(model: model, date: model.selectedDate) }
        }
        }
        .sheet(isPresented: $showCalendarManager) { CalendarsView(model: model) }
        .tint(Whale.accent).preferredColorScheme(.dark)
    }
}

struct EventDetailView: View {
    @Bindable var model: CalendarConnectionModel
    let original: Occurrence
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var busy = false
    @State private var error: String?
    private var item: Occurrence { model.occurrences.first { $0.id == original.id } ?? model.deadlines.first { $0.id == original.id } ?? original }
    private var concurrent: [ConcurrentOccurrence] {
        DaySchedule.concurrent(with: item, in: model.occurrences.filter { model.isVisible($0.event.calendarId) })
    }

    var body: some View {
        Group {
            if embedded { details }
            else { NavigationStack { details } }
        }.tint(Whale.accent).preferredColorScheme(.dark)
    }

    private var details: some View {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(item.event.isDeadline ? "DEADLINE" : "EVENT", systemImage: item.event.isDeadline ? "diamond.fill" : "calendar")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Whale.accent)
                        Text(item.event.title).font(.title2.weight(.semibold)).strikethrough(item.isComplete)
                        if item.event.isDeadline {
                            Text("Due \(Dates.date(item.startDate).formatted(date: .abbreviated, time: .omitted))\(item.event.startTime.map { " · " + $0 } ?? "")")
                            Text(item.isComplete ? "Completed" : item.isOverdue(at: Date()) ? "Overdue" : "Pending")
                                .foregroundStyle(item.isOverdue(at: Date()) ? Whale.warning : Whale.muted)
                            if item.event.startTime == nil { Text("No time specified").font(.caption).foregroundStyle(Whale.muted) }
                        } else {
                            Text(item.event.timeLabel).font(.system(.body, design: .monospaced))
                            Text(item.startDate == item.endDate ? Dates.date(item.startDate).formatted(date: .abbreviated, time: .omitted) : "\(item.startDate) → \(item.endDate)").foregroundStyle(Whale.muted)
                        }
                    }.padding(.vertical, 8)
                }
                if let calendar = model.calendar(item.event.calendarId) {
                    Section { Label { Text(calendar.name) } icon: { Circle().fill(Color(hex: calendar.color)).frame(width: 10, height: 10) } }
                }
                if !concurrent.isEmpty {
                    Section {
                        ForEach(concurrent) { overlap in
                            NavigationLink {
                                EventDetailView(model: model, original: overlap.item, embedded: true)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(overlap.item.event.title).font(.body.weight(.medium)).strikethrough(overlap.item.isComplete)
                                    if let calendar = model.calendar(overlap.item.event.calendarId) {
                                        Label { Text(calendar.name) } icon: {
                                            Circle().fill(Color(hex: calendar.color)).frame(width: 7, height: 7)
                                        }.font(.caption).foregroundStyle(Whale.muted)
                                    }
                                    Text("Together \(overlapLabel(overlap))").font(.caption).foregroundStyle(Whale.accent)
                                }.padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("At the same time")
                    } footer: {
                        Text(model.connected ? "In visible calendars. Overlapping doesn’t necessarily mean a conflict." : "Based on the saved schedule, in visible calendars.")
                    }
                }
                if let rule = item.event.recurrence {
                    Section("Recurrence") {
                        Text("Every \(rule.interval) · \(rule.frequency)")
                        if let until = rule.until { Text("Through \(until)") }
                        if let count = rule.count { Text("\(count) occurrences") }
                        Text("Completion applies only to the \(item.startDate) occurrence. Editing or deleting affects the whole series.").font(.caption).foregroundStyle(Whale.muted)
                    }
                }
                if let location = item.event.location, !location.isEmpty { Section("Location") { Text(location).textSelection(.enabled) } }
                if let notes = item.event.notes, !notes.isEmpty { Section("Notes") { Text(notes).textSelection(.enabled) } }
                if let error { Section { Text(error).foregroundStyle(Whale.warning) } }
                Section {
                    Button {
                        busy = true
                        Task {
                            await model.toggleComplete(item)
                            await model.refresh()
                            error = model.actionError
                            model.actionError = nil
                            busy = false
                        }
                    } label: { Label(item.isComplete ? "Mark unfinished" : "Mark complete", systemImage: item.isComplete ? "arrow.uturn.backward" : "checkmark.circle") }
                    Button { editing = true } label: { Label(item.event.recurrence == nil ? "Edit" : "Edit series", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = true } label: { Label(item.event.recurrence == nil ? "Delete event" : "Delete entire series", systemImage: "trash") }
                }.disabled(!model.connected || busy)
            }
            .scrollContentBackground(.hidden).background(Whale.background)
            .navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("Event details \(item.id)")
            .toolbar {
                if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            }
            .sheet(isPresented: $editing) { EventEditorView(model: model, date: Dates.date(item.startDate), event: item.event) }
            .confirmationDialog(item.event.recurrence == nil ? "Delete this item?" : "Delete every occurrence in this series?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    busy = true
                    Task {
                        do { try await model.mutate(["type": "delete_event", "id": item.event.id]); dismiss() }
                        catch { self.error = error.localizedDescription; busy = false }
                    }
                }
            }
    }

    private func overlapLabel(_ overlap: ConcurrentOccurrence) -> String {
        let sameDay = Dates.key(overlap.start) == Dates.key(overlap.end)
        if sameDay, Dates.key(overlap.start) == item.startDate {
            return "\(overlap.start.formatted(date: .omitted, time: .shortened))–\(overlap.end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(overlap.start.formatted(date: .abbreviated, time: .shortened)) – \(overlap.end.formatted(date: .abbreviated, time: .shortened))"
    }
}
