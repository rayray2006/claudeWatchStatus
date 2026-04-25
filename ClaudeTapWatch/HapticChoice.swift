import Foundation
import WatchKit

/// User-pickable haptic patterns for each state. Most map directly to a
/// WKHapticType; a couple are custom rhythms layered on top of `.click`.
enum HapticChoice: String, CaseIterable, Identifiable, Codable {
    case none
    case click
    case doubleTap
    case tripleTap
    case success
    case failure
    case retry
    case heartbeat
    case up
    case down
    case start
    case stop
    case navLeft
    case navRight
    case underwater
    case underwaterCritical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:      return "None"
        case .click:     return "Single tap"
        case .doubleTap: return "Double tap"
        case .tripleTap: return "Triple tap"
        case .success:   return "Success"
        case .failure:   return "Failure"
        case .retry:     return "Retry"
        case .heartbeat: return "Heartbeat"
        case .up:        return "Up swipe"
        case .down:      return "Down swipe"
        case .start:     return "Start"
        case .stop:      return "Stop"
        case .navLeft:   return "Left turn"
        case .navRight:  return "Right turn"
        case .underwater:         return "Underwater"
        case .underwaterCritical: return "Underwater critical"
        }
    }

    /// Play the pattern. Safe to call from any thread.
    func play() async {
        let dev = WKInterfaceDevice.current()
        switch self {
        case .none:
            return
        case .click:
            dev.play(.click)
        case .doubleTap:
            dev.play(.notification)
        case .tripleTap:
            for _ in 0..<3 {
                dev.play(.click)
                try? await Task.sleep(for: .milliseconds(130))
            }
        case .success:
            dev.play(.success)
        case .failure:
            dev.play(.failure)
        case .retry:
            dev.play(.retry)
        case .heartbeat:
            dev.play(.click)
            try? await Task.sleep(for: .milliseconds(110))
            dev.play(.click)
            try? await Task.sleep(for: .milliseconds(450))
            dev.play(.click)
            try? await Task.sleep(for: .milliseconds(110))
            dev.play(.click)
        case .up:
            dev.play(.directionUp)
        case .down:
            dev.play(.directionDown)
        case .start:
            dev.play(.start)
        case .stop:
            dev.play(.stop)
        case .navLeft:
            dev.play(.navigationLeftTurn)
        case .navRight:
            dev.play(.navigationRightTurn)
        case .underwater:
            dev.play(.underwaterDepthPrompt)
        case .underwaterCritical:
            dev.play(.underwaterDepthCriticalPrompt)
        }
    }

    /// Default haptic assigned to each state on first launch.
    static func `default`(for state: TapState) -> HapticChoice {
        switch state {
        case .done:          return .doubleTap
        case .needsApproval: return .success
        default:             return .none
        }
    }
}
