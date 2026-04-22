import WidgetKit
import SwiftUI

struct ClaudeTapEntry: TimelineEntry {
    let date: Date
    let state: TapState
    let frame: Int
}

struct ClaudeTapComplicationProvider: TimelineProvider {
    /// Must match StateStore.staleAfter.
    private static let staleAfter: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> ClaudeTapEntry {
        ClaudeTapEntry(date: .now, state: .idle, frame: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeTapEntry) -> Void) {
        completion(ClaudeTapEntry(date: .now, state: currentState(), frame: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeTapEntry>) -> Void) {
        let now = Date()
        let (state, stateTime) = cachedStateAndTime()

        // Only `done` auto-reverts to idle — the other states stay as-is.
        if state == .done, now.timeIntervalSince(stateTime) >= Self.staleAfter {
            let entry = ClaudeTapEntry(date: now, state: .idle, frame: 0)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
            return
        }

        var entries: [ClaudeTapEntry] = [ClaudeTapEntry(date: now, state: state, frame: 0)]

        if state == .done {
            let revertAt = stateTime.addingTimeInterval(Self.staleAfter)
            if revertAt > now {
                entries.append(ClaudeTapEntry(date: revertAt, state: .idle, frame: 0))
            }
        }

        // Explicit reloads from app/NSE drive most updates; .after() is a
        // recovery hint in case any of those fail to propagate.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }

    private func currentState() -> TapState {
        cachedStateAndTime().0
    }

    private func cachedStateAndTime() -> (TapState, Date) {
        let defaults = ClaudeTapConstants.sharedDefaults
        let raw = defaults?.string(forKey: ClaudeTapConstants.Defaults.stateKey) ?? ""
        let time = defaults?.double(forKey: ClaudeTapConstants.Defaults.stateTimeKey) ?? 0
        let state = TapState(rawValue: raw) ?? .idle
        return (state, Date(timeIntervalSince1970: time))
    }
}
