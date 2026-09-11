import SwiftUI

struct CalendarDrawerHost<Content: View>: View {
    @Environment(\.whaleTheme) private var theme
    let model: CalendarConnectionModel
    @Binding var isPresented: Bool
    var gesturesEnabled = true
    let onManage: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        CalendarDrawerSurface(
            // Hosting controllers are separate SwiftUI roots; explicitly carry
            // the palette across this UIKit boundary, including presented sheets.
            content: content().environment(\.whaleTheme, theme).foregroundStyle(theme.text).tint(theme.accent),
            drawer: CalendarDrawerView(model: model, onClose: close, onManage: {
                close()
                onManage()
            }).frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.whaleTheme, theme).foregroundStyle(theme.text).tint(theme.accent),
            isPresented: $isPresented,
            gesturesEnabled: gesturesEnabled,
            reduceMotion: reduceMotion
        )
        // Let the hosted scroll view extend behind the home indicator instead
        // of clipping the entire UIKit surface at the outer SwiftUI safe area.
        // Keyboard avoidance remains enabled (.container only).
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityAction(.escape) { close() }
    }
    private func close() { isPresented = false }
}

private struct CalendarDrawerView: View {
    @Environment(\.whaleTheme) private var theme
    let model: CalendarConnectionModel
    let onClose: () -> Void
    let onManage: () -> Void
    @AppStorage("collapsedCalendarGroups") private var collapsedGroups = "[]"
    @State private var showingTheme = false

    private var collapsed: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(collapsedGroups.utf8))) ?? [])
    }
    private func toggleGroup(_ id: String) {
        var ids = collapsed
        if !ids.insert(id).inserted { ids.remove(id) }
        if let data = try? JSONEncoder().encode(ids.sorted()), let text = String(data: data, encoding: .utf8) { collapsedGroups = text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Calendars").font(.system(size: 19, weight: .medium))
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.subheadline).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Close calendars")
            }.padding(.leading, 20).padding(.trailing, 8).padding(.top, 12).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.calendarSections) { section in
                        if let group = section.group {
                            Button { toggleGroup(group.id) } label: {
                                HStack {
                                    Image(systemName: collapsed.contains(group.id) ? "chevron.right" : "chevron.down").font(.caption)
                                    Text(group.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(section.calendars.count)").font(.caption).foregroundStyle(theme.muted)
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("Calendar group \(group.id)")
                                .accessibilityValue(collapsed.contains(group.id) ? "Collapsed" : "Expanded")
                        } else if !model.groups.isEmpty {
                            Text("Ungrouped").font(.caption.weight(.semibold)).foregroundStyle(theme.muted).padding(.top, 12)
                        }
                        if section.group == nil || !collapsed.contains(section.id) {
                            calendarRows(section.calendars)
                        }
                    }
                    if model.calendars.isEmpty {
                        Text(model.connected ? "No calendars yet" : "Connect to load calendars").foregroundStyle(theme.muted).padding(.vertical)
                    }
                }.padding(.horizontal, 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button { showingTheme = true } label: {
                    HStack {
                        Label("Theme", systemImage: "paintpalette")
                        Spacer()
                        Text(theme.name.title).foregroundStyle(theme.muted)
                    }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("Choose theme")
                    .accessibilityValue(theme.name.title)
                Button(action: onManage) {
                    Label("Manage calendars", systemImage: "slider.horizontal.3").font(.subheadline).frame(minHeight: 44)
                }
            }.padding(20)
        }
        .background(theme.sidebar)
        .sheet(isPresented: $showingTheme) { ThemeSettingsView() }
        .accessibilityElement(children: .contain).accessibilityIdentifier("Calendar drawer")
    }

    private func calendarRows(_ calendars: [CalCalendar]) -> some View {
                    ForEach(calendars) { calendar in
                        let visible = model.isVisible(calendar.id)
                        Button { model.toggleVisibility(calendar.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17)).foregroundStyle(Color(hex: calendar.color).opacity(0.8))
                                Text(calendar.name).font(.system(size: 15)).foregroundStyle(visible ? theme.text : theme.muted)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(calendar.name)
                        .accessibilityValue(visible ? "Selected" : "Not selected")
                        .accessibilityHint("Double tap to \(visible ? "hide" : "show") this calendar")
                        .accessibilityIdentifier("Calendar visibility \(calendar.id)")
                    }
    }

}
