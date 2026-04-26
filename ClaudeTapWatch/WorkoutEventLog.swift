import Foundation

/// Persistent ring buffer for `WorkoutKeepAliveManager` lifecycle events.
/// Separate from `SessionEventLog` (extended runtime) so the two
/// keep-alive mechanisms can be inspected independently.
enum WorkoutEventKind: String, Codable {
    case startRequested
    case stateChange
    case manualStop
    case startFailed
    case failed
    case skipped
}

struct WorkoutEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: WorkoutEventKind
    let detail: String?

    init(kind: WorkoutEventKind, detail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.kind = kind
        self.detail = detail
    }
}

@MainActor
enum WorkoutEventLog {
    private static let storageKey = "cued.workoutEventLog"
    private static let maxEvents = 200

    static func record(_ kind: WorkoutEventKind, detail: String? = nil) {
        var events = all()
        events.append(WorkoutEvent(kind: kind, detail: detail))
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func all() -> [WorkoutEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([WorkoutEvent].self, from: data) else {
            return []
        }
        return events
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
