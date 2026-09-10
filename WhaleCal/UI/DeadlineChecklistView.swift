import SwiftUI

struct DeadlineChecklistView: View {
    let model: CalendarConnectionModel
    var query = ""
    @State private var filter = "Pending"
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var details: Occurrence?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmation: Bool?

    private var visible: [Occurrence] {
        model.deadlines.filter {
            model.isVisible($0.event.calendarId) && (query.isEmpty || [$0.event.title, $0.event.notes ?? "", $0.event.location ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    private var displayed: [Occurrence] {
        visible.filter { filter == "All" || $0.isComplete == (filter == "Completed") }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Deadline filter", selection: $filter) {
                    Text("Pending \(visible.filter { !$0.isComplete }.count)").tag("Pending")
                    Text("Completed \(visible.filter(\.isComplete).count)").tag("Completed")
                    Text("All").tag("All")
                }.pickerStyle(.segmented).accessibilityIdentifier("Deadline filter").disabled(busy)
            }.padding(.horizontal)
            HStack {
                Button(selecting ? "Cancel selection" : "Select") { selecting.toggle(); selected = [] }
                Spacer()
                if selecting {
                    Text("\(selected.count) selected").font(.caption).foregroundStyle(Whale.muted)
                    Button("Select shown") { selected = Set(displayed.map(\.id)) }
                }
            }.font(.subheadline).padding(.horizontal).frame(minHeight: 36).disabled(busy)
            if selecting && !selected.isEmpty {
                HStack {
                    Button("Mark complete") { confirmation = true }
                    Spacer()
                    Button("Reopen") { confirmation = false }
                }.padding(.horizontal).frame(minHeight: 40).disabled(busy || !model.connected)
            }
            if let error { Text(error).font(.caption).foregroundStyle(Whale.warning).padding(.horizontal) }
            if busy { ProgressView().accessibilityLabel("Updating selected deadlines") }
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !model.deadlinesLoaded {
                            Text("Connect to load the full deadline checklist.").foregroundStyle(Whale.muted)
                        } else if displayed.isEmpty {
                            Text("No \(filter == "All" ? "" : filter.lowercased() + " ")deadlines in this view.").foregroundStyle(Whale.muted)
                        }
                        let groups = sections(now: timeline.date)
                        ForEach(groups, id: \.title) { section in
                            Text(section.title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(section.title == "Overdue" ? Whale.warning : Whale.muted).padding(.top, 12)
                            ForEach(section.items) { item in row(item, now: timeline.date) }
                        }
                        if visible.contains(where: { $0.event.recurrence != nil }) {
                            Text("Repeating deadlines: all past occurrences and the next 12 months.").font(.caption).foregroundStyle(Whale.muted).padding(.top, 12)
                        }
                    }.padding(.horizontal).padding(.bottom, 24)
                }.refreshable { await model.refresh() }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("Deadline checklist")
        .sheet(item: $details) { EventDetailView(model: model, original: $0) }
        .confirmationDialog(confirmation == true ? "Complete selected deadlines?" : "Reopen selected deadlines?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let completed = confirmation {
                let targets = DeadlineSchedule.targets(displayed, selected: selected, completed: completed)
                Button("\(completed ? "Complete" : "Reopen") \(targets.count) deadlines") {
                    perform(targets, completed: completed)
                }.disabled(targets.isEmpty)
            }
        } message: {
            Text("Only selected occurrences in the current filter and visible calendars will change—not entire recurring series.")
        }
        .onChange(of: displayed.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .onChange(of: filter) { _, _ in selected = []; confirmation = nil }
        .onChange(of: query) { _, _ in selected = []; confirmation = nil }
    }

    private struct SectionItems { let title: String; var items: [Occurrence] }
    private func sections(now: Date) -> [SectionItems] {
        var result: [SectionItems] = []
        for item in displayed {
            let title = DeadlineSchedule.section(item, now: now)
            if result.last?.title == title { result[result.count - 1].items.append(item) }
            else { result.append(SectionItems(title: title, items: [item])) }
        }
        return result
    }
    private func row(_ item: Occurrence, now: Date) -> some View {
        let calendar = model.calendar(item.event.calendarId)
        let color = item.isComplete ? Whale.muted : Color(hex: calendar?.color ?? "#1d9bf0")
        return HStack(alignment: .top, spacing: 6) {
            Button {
                if selecting { toggle(item) }
                else { perform([item], completed: !item.isComplete) }
            } label: {
                Image(systemName: selecting ? (selected.contains(item.id) ? "checkmark.circle.fill" : "circle") : (item.isComplete ? "checkmark.circle.fill" : "circle"))
                    .font(.title3).foregroundStyle(selecting ? Whale.accent : color).frame(width: 44, height: 44)
            }.disabled(busy || (!selecting && !model.connected))
                .accessibilityLabel(selecting ? "Select \(item.event.title)" : "\(item.isComplete ? "Reopen" : "Complete") \(item.event.title)")
                .accessibilityIdentifier("Deadline check \(item.id)")
            Button { if selecting { toggle(item) } else { details = item } } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.event.title).font(.body.weight(.medium)).strikethrough(item.isComplete)
                        .foregroundStyle(item.isComplete ? Whale.muted : .white).fixedSize(horizontal: false, vertical: true)
                    Text("\(DeadlineSchedule.dueLabel(item, now: now)) · \(item.event.startTime ?? "Date only")")
                        .font(.subheadline).foregroundStyle(!item.isComplete && (item.isOverdue(at: now) || item.startDate == Dates.key(now)) ? Whale.warning : Whale.muted)
                    Text("\(calendar?.name ?? "Calendar")\(item.event.recurrence == nil ? "" : " · Repeats")")
                        .font(.caption).foregroundStyle(color)
                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.disabled(busy).accessibilityIdentifier("Deadline details \(item.id)")
        }.buttonStyle(.plain)
    }
    private func toggle(_ item: Occurrence) {
        if !selected.insert(item.id).inserted { selected.remove(item.id) }
    }
    private func perform(_ targets: [Occurrence], completed: Bool) {
        guard !busy, model.connected else { return }
        busy = true; error = nil
        Task { @MainActor in
            var count = 0
            for item in targets {
                do {
                    try await model.setCompleted(item, completed: completed)
                    count += 1; selected.remove(item.id)
                } catch {
                    self.error = "Updated \(count) of \(targets.count). \(error.localizedDescription) Refresh before retrying."
                    break
                }
            }
            await model.refresh()
            busy = false
        }
    }
}
