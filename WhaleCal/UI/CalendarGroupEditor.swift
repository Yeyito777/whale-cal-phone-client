import SwiftUI

struct CalendarGroupPicker: View {
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
    let model: CalendarConnectionModel
    let group: CalendarGroup
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section {
                    Button("Delete group", role: .destructive) { deleting = true }
                } footer: { Text("Deleting a group keeps all of its calendars and events. Its calendars become ungrouped.") }
                if let error { Text(error).foregroundStyle(Whale.warning) }
            }.disabled(busy || !model.connected)
                .navigationTitle("Edit group").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { perform(["type": "update_group", "id": group.id, "name": name.trimmingCharacters(in: .whitespacesAndNewlines)]) }
                            .disabled(busy || !model.connected || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { name = group.name }
                .interactiveDismissDisabled(busy)
                .confirmationDialog("Delete \(group.name)? Calendars and events will be kept.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete group", role: .destructive) { perform(["type": "delete_group", "id": group.id]) }
                }
        }.preferredColorScheme(.dark).tint(Whale.accent)
    }
    private func perform(_ command: [String: Any]) {
        busy = true; error = nil
        Task {
            do { try await model.mutate(command); await model.refresh(); dismiss() }
            catch { self.error = error.localizedDescription; busy = false }
        }
    }
}
