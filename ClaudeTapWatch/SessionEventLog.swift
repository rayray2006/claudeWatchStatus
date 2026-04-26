import Foundation

/// Persistent ring buffer of `KeepAliveManager` lifecycle events. Lets us
/// inspect on-watch what the keep-alive has been doing without keeping
/// Xcode attached all day. Entries persist across launches via
/// `UserDefaults.standard`; bounded to `maxEvents` so it doesn't grow.
enum SessionEventKind: String, Codable {
    case startRequested
    case started
    case willExpire
    case chained
    case invalidated
    case manualStop
    case idleTimeout
    case skipped
}

struct SessionEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: SessionEventKind
    let detail: String?

    init(kind: SessionEventKind, detail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.kind = kind
        self.detail = detail
    }
}

@MainActor
enum SessionEventLog {
    private static let storageKey = "cued.keepAliveEventLog"
    private static let maxEvents = 200

    static func record(_ kind: SessionEventKind, detail: String? = nil) {
        var events = all()
        events.append(SessionEvent(kind: kind, detail: detail))
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func all() -> [SessionEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([SessionEvent].self, from: data) else {
            return []
        }
        return events
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
