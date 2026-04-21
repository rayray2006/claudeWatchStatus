import WidgetKit
import SwiftUI

struct ClaudeTapEntry: TimelineEntry {
    let date: Date
    let state: TapState
    let frame: Int // For animation frames (0-2)
}

struct ClaudeTapComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeTapEntry {
        ClaudeTapEntry(date: .now, state: .idle, frame: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeTapEntry) -> Void) {
        let state = currentState()
        completion(ClaudeTapEntry(date: .now, state: state, frame: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeTapEntry>) -> Void) {
        let state = currentState()

        if state == .working {
            // Create alternating frames for "animation" effect
            var entries: [ClaudeTapEntry] = []
            let now = Date()
            for i in 0..<30 {
                let entryDate = now.addingTimeInterval(Double(i) * 2.0)
                entries.append(ClaudeTapEntry(
                    date: entryDate,
                    state: .working,
                    frame: i % 3
                ))
            }
            let timeline = Timeline(entries: entries, policy: .after(now.addingTimeInterval(60)))
            completion(timeline)
        } else {
            // Static entry for non-working states
            let entry = ClaudeTapEntry(date: .now, state: state, frame: 0)
            let timeline = Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(300)))
            completion(timeline)
        }
    }

    private func currentState() -> TapState {
        guard let stateStr = ClaudeTapConstants.sharedDefaults?.string(
            forKey: ClaudeTapConstants.Defaults.stateKey
        ) else { return .idle }
        return TapState(rawValue: stateStr) ?? .idle
    }
}
