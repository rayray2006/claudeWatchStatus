import Foundation

/// Persistent ring buffer for push-arrival + haptic outcomes. Lets you see
/// without Xcode attached: did pushes arrive at all, did handlers fire,
/// did haptics play. Independent from the keep-alive logs.
enum PushEventKind: String, Codable {
    case foregroundDelivered  // willPresent fired
    case backgroundDelivered  // didReceiveRemoteNotification fired
    case complicationDelivered  // PushKit complication wake
    case hapticPlayed
    case hapticSkippedDebounce
    case hapticSkippedNone  // user has the haptic preference set to .none
}

struct PushEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: PushEventKind
    let detail: String?

    init(kind: PushEventKind, detail: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.kind = kind
        self.detail = detail
    }
}

@MainActor
enum PushEventLog {
    private static let storageKey = "cued.pushEventLog"
    private static let maxEvents = 300

    static func record(_ kind: PushEventKind, detail: String? = nil) {
        var events = all()
        events.append(PushEvent(kind: kind, detail: detail))
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func all() -> [PushEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([PushEvent].self, from: data) else {
            return []
        }
        return events
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
