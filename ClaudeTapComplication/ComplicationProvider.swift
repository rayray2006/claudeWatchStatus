import WidgetKit
import SwiftUI

/// Static, near-empty timeline. The complication's purpose is presence on
/// the watch face (which earns the PKPushType.complication wake budget),
/// not data display.
struct ClaudeTapEntry: TimelineEntry {
    let date: Date
}

struct ClaudeTapComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeTapEntry {
        ClaudeTapEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeTapEntry) -> Void) {
        completion(ClaudeTapEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeTapEntry>) -> Void) {
        // One entry, never expires. We don't drive complication updates from
        // state changes — complication is just there for the wake budget.
        completion(Timeline(entries: [ClaudeTapEntry(date: .now)], policy: .never))
    }
}
