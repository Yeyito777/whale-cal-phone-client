import SwiftUI

struct DayView: View {
    @Environment(\.whaleTheme) private var theme
    @Bindable var model: CalendarConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Occurrence?
    @State private var showNew = false
    @State private var showCalendars = false
    @State private var showCalendarManager = false

    var body: some View {
        CalendarDrawerHost(model: model, isPresented: $showCalendars, onManage: { showCalendarManager = true }) {
            NavigationStack {
                VStack(spacing: 0) {
                    WhalePageHeader(title: "Day schedule", onClose: { dismiss() }, actionSymbol: "plus", actionEnabled: model.connected, onAction: { showNew = true })
                    HStack {
                        Text(model.selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 17, weight: .medium))
                        Spacer()
                        Button { model.selectedDate = Dates.add(-1, to: model.selectedDate) } label: {
                            Image(systemName: "chevron.left").font(.system(size: 13)).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.accessibilityLabel("Previous day")
                        Button { model.selectedDate = Dates.add(1, to: model.selectedDate) } label: {
                            Image(systemName: "chevron.right").font(.system(size: 13)).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.accessibilityLabel("Next day")
                    }.buttonStyle(.plain).padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 4)
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        let day = Dates.key(model.selectedDate)
                        ScrollView {
                            if day < model.loadedFrom || day > model.loadedTo {
                                Text(model.connected ? "Loading day…" : "Connect to load this date.").font(.subheadline).foregroundStyle(theme.muted).padding(20)
                            } else {
                                DayTimelineView(model: model, date: model.selectedDate, now: timeline.date) { selection = $0 }
                                    .padding(.horizontal, 20).padding(.bottom, 24)
                            }
                        }
                    }
                }.background(theme.background).toolbar(.hidden, for: .navigationBar)
                    .sheet(item: $selection) { EventDetailView(model: model, original: $0) }
                    .sheet(isPresented: $showNew) { EventEditorView(model: model, date: model.selectedDate) }
            }
        }
        .sheet(isPresented: $showCalendarManager) { CalendarsView(model: model) }
        .tint(theme.accent).preferredColorScheme(.dark)
    }
}

struct EventDetailView: View {
    @Environment(\.whaleTheme) private var theme
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
        }.tint(theme.accent).preferredColorScheme(.dark)
    }

    private var details: some View {
        VStack(spacing: 0) {
            WhalePageHeader(title: "Details", closeLabel: embedded ? "Back" : "Done", onClose: { dismiss() }, actionTitle: "Edit", actionEnabled: model.connected && !busy, onAction: { editing = true })
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            if let calendar = model.calendar(item.event.calendarId) {
                                Circle().fill(Color(hex: calendar.color)).frame(width: 6, height: 6)
                                Text(calendar.name)
                                Text("·")
                            }
                            Text(item.event.isDeadline ? "Deadline" : "Event")
                            if item.isComplete { Text("· Completed") }
                        }.font(.system(size: 12)).foregroundStyle(theme.muted)
                        Text(item.event.title).font(.system(size: 25, weight: .medium)).lineSpacing(3)
                            .strikethrough(item.isComplete).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 5) {
                            if item.event.isDeadline {
                                Text("Due \(Dates.date(item.startDate).formatted(date: .abbreviated, time: .omitted))\(item.event.startTime.map { " · " + $0 } ?? " · Date only")")
                                if item.isOverdue(at: Date()) { Text("Overdue").foregroundStyle(theme.warning) }
                            } else {
                                Text(item.startDate == item.endDate ? Dates.date(item.startDate).formatted(date: .abbreviated, time: .omitted) : "\(Dates.date(item.startDate).formatted(date: .abbreviated, time: .omitted)) – \(Dates.date(item.endDate).formatted(date: .abbreviated, time: .omitted))")
                                Text(item.event.timeLabel).monospacedDigit()
                            }
                        }.font(.subheadline).foregroundStyle(theme.muted)
                    }
                    Rectangle().fill(theme.line).frame(height: 1)
                    if let location = item.event.location, !location.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            WhaleSectionLabel(text: "Location")
                            Text(location).font(.callout).textSelection(.enabled)
                        }
                    }
                    if let notes = item.event.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            WhaleSectionLabel(text: "Notes")
                            Text(notes).font(.callout).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !concurrent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            WhaleSectionLabel(text: "At the same time")
                            ForEach(concurrent) { overlap in
                                NavigationLink {
                                    EventDetailView(model: model, original: overlap.item, embedded: true)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(overlap.item.event.title).font(.callout).foregroundStyle(.primary)
                                            Text(overlapLabel(overlap)).font(.caption).foregroundStyle(theme.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.muted)
                                    }.frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let rule = item.event.recurrence {
                        VStack(alignment: .leading, spacing: 8) {
                            WhaleSectionLabel(text: "Repeats")
                            Text(recurrenceDescription(rule)).font(.callout)
                            if let until = rule.until { Text("Through \(Dates.date(until).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(theme.muted) }
                            if let count = rule.count { Text("\(count) occurrences").font(.caption).foregroundStyle(theme.muted) }
                            Text("Completion changes this occurrence. Edits and deletion affect the series.").font(.caption).foregroundStyle(theme.muted)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(theme.warning) }
                    HStack {
                        Button {
                            busy = true
                            Task {
                                await model.toggleComplete(item)
                                await model.refresh()
                                error = model.actionError; model.actionError = nil; busy = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.isComplete ? "arrow.uturn.backward" : "checkmark")
                                Text(item.isComplete ? "Reopen" : "Mark complete")
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        Spacer()
                        Button("Delete", role: .destructive) { deleting = true }.foregroundStyle(theme.muted).frame(minHeight: 44)
                    }.buttonStyle(.plain).font(.system(size: 14)).disabled(!model.connected || busy)
                        .padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }.accessibilityElement(children: .contain).accessibilityIdentifier("Event details \(item.id)")
        }.background(theme.background).toolbar(.hidden, for: .navigationBar)
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

    private func recurrenceDescription(_ rule: RecurrenceRule) -> String {
        if rule.interval == 1 { return rule.frequency.capitalized }
        let unit = ["daily": "days", "weekly": "weeks", "monthly": "months", "yearly": "years"][rule.frequency] ?? rule.frequency
        return "Every \(rule.interval) \(unit)"
    }
    private func overlapLabel(_ overlap: ConcurrentOccurrence) -> String {
        if Dates.key(overlap.start) == Dates.key(overlap.end), Dates.key(overlap.start) == item.startDate {
            return "\(overlap.start.formatted(date: .omitted, time: .shortened))–\(overlap.end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(overlap.start.formatted(date: .abbreviated, time: .shortened)) – \(overlap.end.formatted(date: .abbreviated, time: .shortened))"
    }
}
