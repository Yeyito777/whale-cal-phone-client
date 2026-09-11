import SwiftUI

struct CalendarGroupPicker: View {
    @Environment(\.whaleTheme) private var theme
    let groups: [CalendarGroup]
    @Binding var selection: String
    var body: some View {
        Picker("Group", selection: $selection) {
            Text("Ungrouped").tag("")
            ForEach(groups) { group in Text(group.name).tag(group.id) }
        }
    }
}

struct CalendarGroupEditor: View {
    @Environment(\.whaleTheme) private var theme
    let model: CalendarConnectionModel
    let group: CalendarGroup
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Group {
                TextField("Name", text: $name)
                Section {
                    Button("Delete group", role: .destructive) { deleting = true }
                } footer: { Text("Deleting a group keeps all of its calendars and events. Its calendars become ungrouped.") }
                if let error { Text(error).foregroundStyle(theme.warning) }
                }.listRowBackground(theme.background).listRowSeparatorTint(theme.line)
            }.disabled(busy || !model.connected)
                .listStyle(.plain).scrollContentBackground(.hidden).background(theme.background)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    WhalePageHeader(title: "Edit group", closeLabel: "Cancel", onClose: { dismiss() }, closeEnabled: !busy, actionTitle: "Save", actionEnabled: !busy && model.connected && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, onAction: {
                        perform(["type": "update_group", "id": group.id, "name": name.trimmingCharacters(in: .whitespacesAndNewlines)])
                    })
                }
                .onAppear { name = group.name }
                .interactiveDismissDisabled(busy)
                .confirmationDialog("Delete \(group.name)? Calendars and events will be kept.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete group", role: .destructive) { perform(["type": "delete_group", "id": group.id]) }
                }
        }.preferredColorScheme(.dark).tint(theme.accent)
    }
    private func perform(_ command: [String: Any]) {
        busy = true; error = nil
        Task {
            do { try await model.mutate(command); await model.refresh(); dismiss() }
            catch { self.error = error.localizedDescription; busy = false }
        }
    }
}
