import Foundation
import Observation

enum ConnectionFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { "Connection failed" } }
}

@MainActor @Observable
final class CalendarConnectionModel {
    var calendars: [CalCalendar] = []
    var occurrences: [Occurrence] = []
    var selectedDate = Date()
    var connected = false
    var status = "Connecting…"
    var connectionError: String?
    var actionError: String?
    var publicKey = ""
    var revision = 0
    var lastSync: Date?
    var loading = false
    var loadedFrom = ""
    var loadedTo = ""
    let configuration = SSHConnectionConfiguration.current

    @ObservationIgnored private let transport = SSHForwardedTransport()
    @ObservationIgnored private var session: Task<Void, Never>?
    @ObservationIgnored private var teardown: Task<Void, Never>?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pending: [String: CheckedContinuation<DaemonMessage, Error>] = [:]
    @ObservationIgnored private var timeouts: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshGeneration = UUID()

    private struct Cache: Codable {
        var calendars: [CalCalendar]
        var occurrences: [Occurrence]
        var from: String
        var to: String
        var saved: Date
    }
    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("calendar-snapshot.json")
    }
    init() {
        if let data = try? Data(contentsOf: Self.cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            calendars = cache.calendars
            occurrences = cache.occurrences
            loadedFrom = cache.from
            loadedTo = cache.to
            lastSync = cache.saved
        }
    }

    func start() {
        guard session == nil else { return }
        let token = UUID()
        generation = token
        let cleanup = teardown
        session = Task { [weak self] in
            await cleanup?.value
            await self?.run(token)
        }
    }

    func stop() {
        generation = UUID()
        let oldSession = session
        let previousTeardown = teardown
        oldSession?.cancel()
        session = nil
        reader?.cancel()
        reader = nil
        refreshTask?.cancel()
        refreshGeneration = UUID()
        connected = false
        status = "Offline · cached view"
        failPending("Disconnected. A sent change may have succeeded; refresh before retrying.")
        loading = false
        // Serialize close/open, including an SSH handshake still in flight at backgrounding.
        teardown = Task {
            await previousTeardown?.value
            await oldSession?.value
            await transport.close()
        }
    }

    func reconnect() { stop(); start() }

    private func run(_ token: UUID) async {
        guard generation == token, !Task.isCancelled else { return }
        var delay: UInt64 = 1
        while !Task.isCancelled && generation == token {
            do {
                status = "Connecting over SSH…"
                let identity = try DeviceIdentityStore.loadOrCreate()
                publicKey = identity.publicKeyOpenSSH
                print("WHALE_CAL_DEVICE_PUBLIC_KEY \(publicKey)")
                let stream = try await transport.open(identity: identity)
                guard generation == token, !Task.isCancelled else { return }
                buffer.removeAll()
                reader = Task { [weak self] in
                    for await event in stream {
                        guard let self, self.generation == token, !Task.isCancelled else { return }
                        switch event {
                        case .bytes(let bytes): self.receive(bytes)
                        case .closed: self.failPending("SSH connection closed"); self.connected = false
                        case .error(let text): self.failPending(text); self.connected = false; self.connectionError = text
                        }
                    }
                    guard let self, self.generation == token else { return }
                    self.connected = false
                    self.failPending("SSH connection closed")
                }
                _ = try await request(["type": "probe"])
                guard generation == token else { return }
                connected = true
                connectionError = nil
                status = "Live · \(configuration.host)"
                print("WHALE_CAL_DAEMON_PONG received")
                await refresh()
                delay = 1
                while !Task.isCancelled && generation == token && connected {
                    try await Task.sleep(for: .seconds(15))
                    _ = try await request(["type": "probe"])
                }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                connectionError = error.localizedDescription
            }
            guard generation == token, !Task.isCancelled else { return }
            connected = false
            status = "Reconnecting in \(delay)s · cached view"
            failPending("Disconnected. Check the calendar before retrying a change.")
            reader?.cancel()
            await transport.close()
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 30)
        }
    }

    private func request(_ command: [String: Any]) async throws -> DaemonMessage {
        try Task.checkCancellation()
        let id = UUID().uuidString
        var payload = command
        payload["reqId"] = id
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(10)
        let wire = data
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                self?.finish(id, result: .failure(ConnectionFailure.message("Request timed out. A sent change may have succeeded; refresh before retrying.")))
            }
            Task {
                do { try await transport.send(wire) }
                catch { finish(id, result: .failure(error)) }
            }
        }
    }

    private func finish(_ id: String, result: Result<DaemonMessage, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    private func failPending(_ text: String) {
        for id in Array(pending.keys) { finish(id, result: .failure(ConnectionFailure.message(text))) }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 32 * 1024 * 1024 else {
            buffer.removeAll(); failPending("Calendar response exceeds 32 MB"); connected = false; return
        }
        while let index = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<index])
            buffer.removeSubrange(...index)
            if line.isEmpty { continue }
            do {
                let message = try JSONDecoder().decode(DaemonMessage.self, from: line)
                if let rev = message.revision { revision = max(revision, rev) }
                if let id = message.reqId, pending[id] != nil {
                    finish(id, result: message.type == "error"
                        ? .failure(ConnectionFailure.message(message.message ?? "Calendar rejected the request"))
                        : .success(message))
                }
                if ["event_created", "event_updated", "event_deleted", "calendar_created", "calendar_updated", "calendar_deleted"].contains(message.type) {
                    scheduleRefresh()
                }
                if message.type == "daemon_shutdown" { connected = false; failPending("Calendar daemon is restarting") }
            } catch {
                connectionError = "Could not decode calendar response: \(error.localizedDescription)"
                failPending(connectionError!)
                connected = false
            }
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            await refresh()
        }
    }

    func refresh() async {
        guard connected else { return }
        let token = UUID()
        refreshGeneration = token
        loading = true
        let days = Dates.monthDays(selectedDate)
        let from = Dates.key(days.first!), to = Dates.key(Dates.add(31, to: days.last!))
        do {
            let c = try await request(["type": "list_calendars"])
            let e = try await request(["type": "list_events", "from": from, "to": to])
            guard refreshGeneration == token, connected, !Task.isCancelled else { return }
            calendars = c.calendars ?? []
            occurrences = e.occurrences ?? []
            loadedFrom = from
            loadedTo = to
            lastSync = Date()
            connectionError = nil
            let cache = Cache(calendars: calendars, occurrences: occurrences, from: from, to: to, saved: lastSync!)
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: Self.cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            print("WHALE_CAL_SYNC calendars=\(calendars.count) occurrences=\(occurrences.count) revision=\(revision)")
        } catch {
            if refreshGeneration == token { connectionError = error.localizedDescription }
        }
        if refreshGeneration == token { loading = false }
    }

    func mutate(_ command: [String: Any]) async throws {
        guard connected else { throw ConnectionFailure.message("Reconnect before changing the calendar.") }
        _ = try await request(command)
        scheduleRefresh()
    }

    func toggleComplete(_ item: Occurrence) async {
        var command: [String: Any] = ["type": "complete_event", "id": item.event.id, "completed": !item.isComplete]
        if item.event.recurrence != nil { command["occurrenceDate"] = item.startDate }
        do { try await mutate(command) } catch { actionError = error.localizedDescription }
    }

    func calendar(_ id: String) -> CalCalendar? { calendars.first { $0.id == id } }
    func items(on date: Date, query: String = "") -> [Occurrence] {
        let day = Dates.key(date)
        return occurrences.filter { item in
            item.covers(day) && (query.isEmpty || [item.event.title, item.event.notes ?? "", item.event.location ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted {
            let a = $0.event.startTime ?? "", b = $1.event.startTime ?? ""
            return a == b ? $0.event.title < $1.event.title : a < b
        }
    }
}
