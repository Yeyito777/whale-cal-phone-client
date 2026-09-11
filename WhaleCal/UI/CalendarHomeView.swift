import SwiftUI

struct CalendarHomeView: View {
    @Environment(\.whaleTheme) private var theme
    @Bindable var model: CalendarConnectionModel
    @State private var mode = "Month"
    @State private var query = ""
    @State private var showCalendars = false
    @State private var showCalendarManager = false
    @State private var showSettings = false
    @State private var showNew = false
    @State private var selectedItem: Occurrence?
    @State private var showDay = false
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            CalendarDrawerHost(model: model, isPresented: $showCalendars, gesturesEnabled: !searchFocused, onManage: { showCalendarManager = true }) {
            VStack(spacing: 0) {
                header
                if !model.connected || model.connectionError != nil {
                    HStack {
                        Text(model.connectionError == nil ? "Offline · saved calendar" : "Connection needs attention")
                        Spacer()
                        Button("Details") { showSettings = true }
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.muted).padding(.horizontal, 20).padding(.bottom, 8)
                }
                WhaleViewTabs(selection: $mode).padding(.horizontal, 8).padding(.bottom, 8)
                if showSearch {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                        TextField("Search this view", text: $query).font(.subheadline).focused($searchFocused)
                            .submitLabel(.search).onSubmit { searchFocused = false }
                        Button { closeSearch() } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32) }.accessibilityLabel("Close search")
                    }.padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal).padding(.bottom, 8)
                }
                if mode == "Deadlines" {
                    DeadlineChecklistView(model: model, query: query)
                } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if mode != "Agenda" { calendarGrid }
                        if mode == "Agenda" { agenda }
                        else { selectedDay }
                    }.padding(.horizontal).padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.refresh() }
                }
            }
            }
            .background(theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCalendarManager) { CalendarsView(model: model) }
            .sheet(isPresented: $showSettings) { ConnectionSettingsView(model: model) }
            .sheet(isPresented: $showNew) { EventEditorView(model: model, date: mode == "Deadlines" ? Date() : model.selectedDate, defaultKind: mode == "Deadlines" ? "deadline" : "event") }
            .sheet(item: $selectedItem) { EventDetailView(model: model, original: $0) }
            .sheet(isPresented: $showDay) { DayView(model: model) }
            .alert("Calendar", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
                Button("OK") { model.actionError = nil }
            } message: { Text(model.actionError ?? "") }
            .onChange(of: Dates.key(Dates.monthStart(model.selectedDate))) { _, _ in model.scheduleRefresh() }
            .onChange(of: showSearch) { _, visible in searchFocused = visible }
            .onChange(of: showCalendars) { _, visible in if visible { searchFocused = false } }
        }.preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(mode == "Deadlines" ? "Deadlines" : model.selectedDate.formatted(.dateTime.month(.wide))).font(.system(size: 23, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8).accessibilityIdentifier("Month heading")
                if mode != "Deadlines" { Text(model.selectedDate.formatted(.dateTime.year())).font(.system(size: 12)).foregroundStyle(theme.muted) }
            }
            if mode != "Deadlines" {
                Button { move(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 12)).frame(width: 32, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Previous \(mode.lowercased())")
                Button { move(1) } label: { Image(systemName: "chevron.right").font(.system(size: 12)).frame(width: 32, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Next \(mode.lowercased())")
            }
            Spacer(minLength: 4)
            Button { showNew = true } label: { Image(systemName: "plus").font(.system(size: 20, weight: .regular)).frame(width: 40, height: 44).contentShape(Rectangle()) }.disabled(!model.connected).accessibilityLabel(mode == "Deadlines" ? "New deadline" : "New event")
            Menu {
                Button { showCalendars = true } label: { Label("Calendars", systemImage: "calendar") }
                Button("Today") { model.selectedDate = Date() }
                Button {
                    if showSearch { closeSearch() } else { showSearch = true }
                } label: { Label(showSearch ? "Hide search" : "Search", systemImage: "magnifyingglass") }
                Divider()
                Button { showSettings = true } label: { Label("Connection", systemImage: "gearshape") }.accessibilityIdentifier("Connection settings")
            } label: { Image(systemName: "ellipsis").font(.system(size: 18)).frame(width: 36, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Calendar options")
        }.buttonStyle(.plain).foregroundStyle(theme.text).padding(.leading, 20).padding(.trailing, 12).padding(.top, 4).padding(.bottom, 6)
    }
    private func closeSearch() {
        query = ""
        searchFocused = false
        showSearch = false
    }
    private func move(_ step: Int) {
        model.selectedDate = mode == "Week" ? Dates.add(step * 7, to: model.selectedDate) : Dates.add(step, .month, to: model.selectedDate)
    }
    private var gridDays: [Date] {
        mode == "Week" ? (0..<7).map { Dates.add($0, to: Dates.weekStart(model.selectedDate)) } : Dates.monthDays(model.selectedDate)
    }
    private var calendarGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(theme.muted).frame(maxWidth: .infinity)
                }
            }.padding(.bottom, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
                ForEach(gridDays, id: \.self) { day in dayCell(day) }
            }
        }
    }
    private func dayCell(_ day: Date) -> some View {
        let today = Dates.key(day) == Dates.key(Date())
        let selected = Dates.key(day) == Dates.key(model.selectedDate)
        let inMonth = Dates.monthStart(day) == Dates.monthStart(model.selectedDate)
        let items = model.items(on: day, query: query)
        return Button {
            if selected { showDay = true } else { model.selectedDate = day }
        } label: {
            VStack(spacing: 7) {
                Text("\(Dates.calendar.component(.day, from: day))")
                    .font(.system(size: 15, weight: selected || today ? .semibold : .regular))
                    .foregroundStyle(today ? theme.text : inMonth ? theme.text : theme.muted.opacity(0.45))
                    .frame(width: 29, height: 27)
                HStack(spacing: 3) {
                    ForEach(Array(items.prefix(3))) { item in
                        if item.event.isDeadline {
                            Rectangle().fill(Color(hex: model.calendar(item.event.calendarId)?.color ?? "#7aa2f7")).frame(width: 4, height: 4).rotationEffect(.degrees(45))
                        } else {
                            Circle().fill(Color(hex: model.calendar(item.event.calendarId)?.color ?? "#7aa2f7")).frame(width: 4, height: 4)
                        }
                    }
                    if items.count > 3 { Text("+").font(.system(size: 8)) }
                }.frame(height: 5)
            }.frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(selected ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottom) { if today { Rectangle().fill(theme.accent).frame(width: 14, height: 2) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(items.count) items\(selected ? ", selected" : "")")
    }
    private var selectedDay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
            Button { showDay = true } label: {
                HStack {
                    Text(model.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold)).foregroundStyle(theme.text)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(theme.muted)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("Day details").accessibilityHint("Open day schedule")
            Spacer()
            if Dates.key(model.selectedDate) != Dates.key(Date()) {
                Button("Today") { model.selectedDate = Date() }.font(.system(size: 12)).foregroundStyle(theme.muted).frame(minWidth: 44, minHeight: 44)
            }
            }.buttonStyle(.plain)
            let day = Dates.key(model.selectedDate)
            if day < model.loadedFrom || day > model.loadedTo {
                emptyDay(model.selectedDate)
            } else if query.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    DayTimelineView(model: model, date: model.selectedDate, now: timeline.date) { selectedItem = $0 }
                }
            } else {
                let items = model.items(on: model.selectedDate, query: query)
                if items.isEmpty { emptyDay(model.selectedDate) }
                ForEach(items) { item in
                    Button { selectedItem = item } label: { EventRow(item: item, calendar: model.calendar(item.event.calendarId)) }.buttonStyle(.plain)
                }
            }
        }.padding(.top, 6)
    }
    private var agenda: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(0..<31, id: \.self) { offset in
                let date = Dates.add(offset, to: model.selectedDate)
                let items = model.items(on: date, query: query)
                if !items.isEmpty {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(theme.muted)
                    ForEach(items) { item in
                        Button { selectedItem = item } label: { EventRow(item: item, calendar: model.calendar(item.event.calendarId)) }.buttonStyle(.plain)
                    }
                }
            }
            if !(0..<31).contains(where: { !model.items(on: Dates.add($0, to: model.selectedDate), query: query).isEmpty }) { emptyDay(model.selectedDate) }
        }
    }
    private func emptyDay(_ date: Date) -> some View {
        let key = Dates.key(date)
        let cached = key >= model.loadedFrom && key <= model.loadedTo
        return VStack(spacing: 8) {
            Text(!cached ? (model.connected ? "Loading calendar…" : "This date isn’t cached") : query.isEmpty ? "No events" : "No matching items").font(.subheadline).foregroundStyle(theme.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}
