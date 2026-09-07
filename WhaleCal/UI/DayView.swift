import SwiftUI

struct DayView: View {
    @Bindable var model: CalendarConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Occurrence?
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let day = Dates.key(model.selectedDate)
                let items = model.items(on: model.selectedDate)
                let gaps = DaySchedule.gaps(items, day: day)
                let now = Dates.calendar.component(.hour, from: timeline.date) * 60 + Dates.calendar.component(.minute, from: timeline.date)
                let today = day == Dates.key(timeline.date)
                if day < model.loadedFrom || day > model.loadedTo {
                    ContentUnavailableView(model.connected ? "Loading day…" : "This date isn’t cached", systemImage: "calendar", description: Text("Connect to load this schedule."))
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button { model.selectedDate = Dates.add(-1, to: model.selectedDate) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 44) }
                            Spacer()
                            VStack(spacing: 4) {
                                Text(model.selectedDate.formatted(.dateTime.weekday(.wide))).font(.title2.weight(.semibold))
                                Text(model.selectedDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Whale.muted)
                            }
                            Spacer()
                            Button { model.selectedDate = Dates.add(1, to: model.selectedDate) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 44) }
                        }
                        HStack {
                            Label("\(Dates.duration(gaps.reduce(0) { $0 + $1.end - $1.start })) free", systemImage: "clock")
                            Spacer()
                            if today { Text("Now \(Dates.clock(now))").foregroundStyle(Whale.accent) }
                        }.font(.system(size: 12, design: .monospaced)).foregroundStyle(Whale.muted).padding(.vertical, 8)
                        if !model.connected { Text("Cached schedule · reconnect to make changes").font(.caption).foregroundStyle(Whale.warning) }
                        ForEach(items.filter { $0.event.isDeadline || $0.event.startTime == nil || $0.event.endTime == nil }) { item in
                            Button { selection = item } label: { EventRow(item: item, calendar: model.calendar(item.event.calendarId), now: timeline.date) }.buttonStyle(.plain)
                        }
                        Text("TIMELINE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Whale.muted).padding(.top, 8)
                        ForEach(timelineRows(items, gaps: gaps, day: day)) { row in
                            if let item = row.item {
                                VStack(alignment: .leading, spacing: 5) {
                                    if today, let interval = DaySchedule.busyInterval(item, day: day), interval.start <= now && now < interval.end {
                                        Text("● NOW").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Whale.accent)
                                    }
                                    Button { selection = item } label: { EventRow(item: item, calendar: model.calendar(item.event.calendarId), now: timeline.date) }.buttonStyle(.plain)
                                }
                            } else if let gap = row.gap {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(Dates.clock(gap.start))–\(Dates.clock(gap.end))")
                                        Text("\(Dates.duration(gap.end - gap.start)) free").foregroundStyle(Whale.muted)
                                    }
                                    Spacer()
                                    if today && gap.start <= now && now < gap.end { Text("● NOW").foregroundStyle(Whale.accent) }
                                }.font(.system(size: 11, design: .monospaced)).foregroundStyle(Whale.muted).padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Whale.muted.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4])))
                            }
                        }
                        Text("Only timed events with an end time reserve time. Deadlines, all-day items and durationless markers don’t reduce free time.")
                            .font(.caption).foregroundStyle(Whale.muted).padding(.top, 8)
                    }.padding()
                }.background(Whale.background)
                }
            }
            .navigationTitle("Day schedule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { showNew = true } label: { Image(systemName: "plus") }.disabled(!model.connected) }
            }
            .sheet(item: $selection) { EventDetailView(model: model, original: $0) }
            .sheet(isPresented: $showNew) { EventEditorView(model: model, date: model.selectedDate) }
        }.tint(Whale.accent).preferredColorScheme(.dark)
    }
    private struct Row: Identifiable {
        var id: String
        var minute: Int
        var item: Occurrence?
        var gap: FreeGap?
    }
    private func timelineRows(_ items: [Occurrence], gaps: [FreeGap], day: String) -> [Row] {
        let events = items.compactMap { item -> Row? in
            guard let interval = DaySchedule.busyInterval(item, day: day) else { return nil }
            return Row(id: item.id, minute: interval.start, item: item)
        }
        return (events + gaps.map { Row(id: "gap-\($0.start)", minute: $0.start, gap: $0) }).sorted { $0.minute < $1.minute }
    }
}

struct EventDetailView: View {
    @Bindable var model: CalendarConnectionModel
    let original: Occurrence
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var busy = false
    @State private var error: String?
    private var item: Occurrence { model.occurrences.first { $0.id == original.id } ?? original }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(item.event.isDeadline ? "DEADLINE" : "EVENT", systemImage: item.event.isDeadline ? "diamond.fill" : "calendar")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Whale.accent)
                        Text(item.event.title).font(.title2.weight(.semibold)).strikethrough(item.isComplete)
                        Text(item.event.timeLabel).font(.system(.body, design: .monospaced))
                        Text(item.startDate == item.endDate ? item.startDate : "\(item.startDate) → \(item.endDate)").foregroundStyle(Whale.muted)
                        if item.isOverdue(at: Date()) { Text("Overdue").foregroundStyle(Whale.warning) }
                    }.padding(.vertical, 8)
                }
                if let calendar = model.calendar(item.event.calendarId) {
                    Section { Label { Text(calendar.name) } icon: { Circle().fill(Color(hex: calendar.color)).frame(width: 10, height: 10) } }
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
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
        }.tint(Whale.accent).preferredColorScheme(.dark)
    }
}
