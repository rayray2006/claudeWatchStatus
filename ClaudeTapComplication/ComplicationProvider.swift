import WidgetKit
import SwiftUI

/// Timeline entry for the Cued Smart Stack widget. Carries both the current
/// state and the wall-clock time that state was entered so the widget can
/// render an auto-ticking elapsed timer via `Text(_:style: .timer)` without
/// needing future timeline reloads.
struct ClaudeTapEntry: TimelineEntry {
    let date: Date
    let state: TapState
    let stateStartedAt: Date
    let relevance: TimelineEntryRelevance?
}

struct ClaudeTapComplicationProvider: TimelineProvider {
    /// Mirrors StateStore.staleAfter — done auto-reverts to idle at +5 min.
    private static let staleAfter: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> ClaudeTapEntry {
        ClaudeTapEntry(date: .now, state: .idle, stateStartedAt: .now, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeTapEntry) -> Void) {
        let (state, started) = cachedStateAndTime()
        completion(
            ClaudeTapEntry(
                date: .now,
                state: state,
                stateStartedAt: started,
                relevance: Self.relevance(for: state)
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeTapEntry>) -> Void) {
        let now = Date()
        let (state, started) = cachedStateAndTime()

        if state == .done, now.timeIntervalSince(started) >= Self.staleAfter {
            let idle = ClaudeTapEntry(
                date: now, state: .idle, stateStartedAt: now,
                relevance: Self.relevance(for: .idle)
            )
            completion(Timeline(entries: [idle], policy: .after(now.addingTimeInterval(300))))
            return
        }

        var entries: [ClaudeTapEntry] = [
            ClaudeTapEntry(
                date: now, state: state, stateStartedAt: started,
                relevance: Self.relevance(for: state)
            )
        ]

        // Queue the idle-revert entry so the Smart Stack transitions without
        // another timeline reload at +5 min.
        if state == .done {
            let revertAt = started.addingTimeInterval(Self.staleAfter)
            if revertAt > now {
                entries.append(
                    ClaudeTapEntry(
                        date: revertAt, state: .idle, stateStartedAt: revertAt,
                        relevance: Self.relevance(for: .idle)
                    )
                )
            }
        }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }

    private func cachedStateAndTime() -> (TapState, Date) {
        let defaults = ClaudeTapConstants.sharedDefaults
        let raw = defaults?.string(forKey: ClaudeTapConstants.Defaults.stateKey) ?? ""
        let time = defaults?.double(forKey: ClaudeTapConstants.Defaults.stateTimeKey) ?? 0
        let state = TapState(rawValue: raw) ?? .idle
        let started = time > 0 ? Date(timeIntervalSince1970: time) : Date()
        return (state, started)
    }

    /// Relevance hint for the Smart Stack. Active states (thinking, working)
    /// score high so the system surfaces the widget during a session.
    /// Approval scores highest — it's blocking. Idle/done drop back down.
    private static func relevance(for state: TapState) -> TimelineEntryRelevance {
        switch state {
        case .needsApproval: return .init(score: 100, duration: 600)
        case .working:       return .init(score: 80,  duration: 600)
        case .thinking:      return .init(score: 70,  duration: 300)
        case .done:          return .init(score: 20,  duration: 60)
        case .idle:          return .init(score: 0,   duration: 60)
        }
    }
}
