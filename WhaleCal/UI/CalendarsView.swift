import SwiftUI

struct CalendarsView: View {
    @Bindable var model: CalendarConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var busy = false
    @State private var editing: CalCalendar?
    @State private var editingGroup: CalendarGroup?
    @State private var groupName = ""
    @State private var newGroupId = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.calendars) { calendar in
                        HStack {
                            Button {
                                model.toggleVisibility(calendar.id)
                            } label: {
                                HStack {
                                    Image(systemName: model.isVisible(calendar.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color(hex: calendar.color))
                                    VStack(alignment: .leading) {
                                        Text(calendar.name).foregroundStyle(.white)
                                        if let group = model.groups.first(where: { $0.id == calendar.groupId }) {
                                            Text(group.name).font(.caption).foregroundStyle(Whale.muted)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { editing = calendar } label: { Image(systemName: "ellipsis").padding(8) }.buttonStyle(.borderless).accessibilityLabel("Edit \(calendar.name)")
                        }
                    }
                } header: { Text("Calendars") } footer: { Text("Visibility is saved on this phone for this connection. It doesn’t change the terminal or other phones.") }
                Section("New calendar") {
                    TextField("Name", text: $name)
                    CalendarGroupPicker(groups: model.groups, selection: $newGroupId)
                    Button("Create calendar") {
                        var command: [String: Any] = ["type": "create_calendar", "name": name.trimmingCharacters(in: .whitespacesAndNewlines)]
                        if !newGroupId.isEmpty { command["groupId"] = newGroupId }
                        perform(command, clearName: true)
                    }
                        .disabled(!model.connected || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    ForEach(model.groups) { group in
                        Button { editingGroup = group } label: {
                            HStack { Text(group.name); Spacer(); Image(systemName: "ellipsis") }
                        }
                    }
                    TextField("New group name", text: $groupName)
                    Button("Create group") {
                        busy = true; error = nil
                        Task {
                            do {
                                try await model.mutate(["type": "create_group", "name": groupName.trimmingCharacters(in: .whitespacesAndNewlines)])
                                await model.refresh(); groupName = ""
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }.disabled(!model.connected || groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: { Text("Groups") } footer: {
                    Text("Groups are shared across clients. Collapsing a group only changes this phone’s sidebar—it doesn’t hide its calendars.")
                }
                if let error { Section { Text(error).foregroundStyle(Whale.warning) } }
            }
            .disabled(busy)
            .scrollContentBackground(.hidden).background(Whale.background)
            .navigationTitle("Calendars").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { CalendarEditorView(model: model, calendar: $0) }
            .sheet(item: $editingGroup) { CalendarGroupEditor(model: model, group: $0) }
        }.tint(Whale.accent).preferredColorScheme(.dark)
    }
    private func perform(_ command: [String: Any], clearName: Bool = false) {
        busy = true; error = nil
        Task {
            do { try await model.mutate(command); await model.refresh(); if clearName { name = "" } }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

private struct CalendarEditorView: View {
    let model: CalendarConnectionModel
    let calendar: CalCalendar
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = ""
    @State private var groupId = ""
    @State private var deleting = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Color (#rrggbb)", text: $color).autocorrectionDisabled().textInputAutocapitalization(.never)
                CalendarGroupPicker(groups: model.groups, selection: $groupId)
                if let error { Text(error).foregroundStyle(Whale.warning) }
                Section { Button("Delete calendar and all its events", role: .destructive) { deleting = true } }
            }
            .disabled(busy || !model.connected)
            .navigationTitle("Edit calendar").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let patch: [String: Any] = ["name": name, "color": color, "groupId": groupId.isEmpty ? NSNull() : groupId as Any]
                    perform(["type": "update_calendar", "id": calendar.id, "patch": patch])
                }.disabled(busy || !model.connected || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { name = calendar.name; color = calendar.color; groupId = calendar.groupId ?? "" }
            .interactiveDismissDisabled(busy)
            .confirmationDialog("Delete \(calendar.name) and every event in it? This cannot be undone.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete calendar and events", role: .destructive) { perform(["type": "delete_calendar", "id": calendar.id]) }
            }
        }
    }
    private func perform(_ command: [String: Any]) {
        busy = true
        Task {
            do { try await model.mutate(command); dismiss() }
            catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

struct ConnectionSettingsView: View {
    @Bindable var model: CalendarConnectionModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Label(model.status, systemImage: model.connected ? "lock.shield.fill" : "network").foregroundStyle(model.connected ? Whale.green : Whale.warning)
                        .accessibilityIdentifier("Connection status").accessibilityValue(model.connected ? "Live" : "Offline")
                    LabeledContent("Host", value: "\(model.configuration.username)@\(model.configuration.host):\(model.configuration.port)")
                    LabeledContent("SSH tunnel", value: "\(model.configuration.bridgeHost):\(model.configuration.bridgePort)")
                    LabeledContent("Revision", value: String(model.revision))
                    if let sync = model.lastSync { LabeledContent("Last synced", value: sync.formatted(date: .abbreviated, time: .standard)) }
                    Text("Dates and times are local wall-clock values, matching Whale Cal. Display timezone: \(TimeZone.current.identifier).").font(.caption).foregroundStyle(Whale.muted)
                    Button("Reconnect now") { model.reconnect() }
                    Button("Refresh calendar") { Task { await model.refresh() } }.disabled(!model.connected)
                }
                if let error = model.connectionError { Section("Connection error") { Text(error).font(.caption).textSelection(.enabled) } }
                Section("Device public key") {
                    Text(model.publicKey.isEmpty ? "Generating identity…" : model.publicKey).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: model.publicKey) { Label("Share public key", systemImage: "square.and.arrow.up") }.disabled(model.publicKey.isEmpty)
                    Text("A unique Ed25519 private key stays in this iPhone’s Keychain. First-time authorization grants forwarding only to the calendar bridge; no shell access.").font(.caption).foregroundStyle(Whale.muted)
                }
                Section("Pinned host public key") {
                    Text(model.configuration.pinnedHostKey.isEmpty ? "Not configured" : model.configuration.pinnedHostKey).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    Text("No public calendar port. All calendar traffic is encrypted by SSH and verified against the pinned server key. Offline snapshots are read-only; changes are never silently queued or retried.").font(.caption).foregroundStyle(Whale.muted)
                }
                Section { Text("Whale Cal · iPhone 0.1\nNative client for the existing cald daemon.").font(.caption).foregroundStyle(Whale.muted) }
            }
            .scrollContentBackground(.hidden).background(Whale.background)
            .navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.tint(Whale.accent).preferredColorScheme(.dark)
    }
}
