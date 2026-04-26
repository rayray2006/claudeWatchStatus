import Foundation

/// Persistent ring buffer for `LocationKeepAliveManager` lifecycle events.
/// Separate from `SessionEventLog` so the two keep-alive mechanisms can be
/// inspected independently.
enum LocationEventKind: String, Codable {
    case startRequested
    case authChanged
    case started
    case stopped
    case startFailed
    case failed
    case skipped
}

struct LocationEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: LocationEventKind
    let detail: String?

    init(kind: LocationEventKind, detail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.kind = kind
        self.detail = detail
    }
}

@MainActor
enum LocationEventLog {
    private static let storageKey = "cued.locationEventLog"
    private static let maxEvents = 200

    static func record(_ kind: LocationEventKind, detail: String? = nil) {
        var events = all()
        events.append(LocationEvent(kind: kind, detail: detail))
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func all() -> [LocationEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([LocationEvent].self, from: data) else {
            return []
        }
        return events
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
