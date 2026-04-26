import Foundation
import WatchKit

/// User-pickable haptic patterns for each state. Each maps to either a
/// `WKHapticType` (Apple's predefined patterns) or a custom sequence of
/// them with timed delays. There is no public watchOS API for downloading
/// or installing third-party haptic packs — `WKHapticType` enumerates
/// every system-provided pattern, and `CHHapticEngine` (Core Haptics) is
/// the only way to author custom waveforms; on Apple Watch, `CHHapticEngine`
/// is limited compared to iPhone (transient events only on most devices,
/// minimal intensity/sharpness control), so the meaningful expansion comes
/// from sequencing `WKHapticType`s with tuned timings.
enum HapticChoice: String, CaseIterable, Identifiable, Codable {
    case none

    // System singles
    case click
    case doubleTap          // = .notification
    case success
    case failure
    case retry
    case start
    case stop
    case up
    case down
    case navLeft
    case navRight
    case genericNav         // .navigationGenericManeuver
    case underwater
    case underwaterCritical

    // Custom sequences (WKHapticType + delays)
    case tripleTap          // 3 clicks ~130ms apart
    case heartbeat          // lub-dub
    case doubleHeartbeat    // heartbeat × 2
    case timekeeper         // 4 evenly-spaced clicks (clock tick)
    case alarm              // 3 rapid .notification
    case chime              // .notification + .success
    case ascending          // click → notification → success
    case descending         // success → notification → failure
    case drumroll           // 6 quick clicks
    case buzz               // 4 fast clicks
    case sosMorse           // Morse SOS pattern (... --- ...)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:               return "None"
        case .click:              return "Single tap"
        case .doubleTap:          return "Double tap"
        case .success:            return "Success"
        case .failure:            return "Failure"
        case .retry:              return "Retry"
        case .start:              return "Start"
        case .stop:               return "Stop"
        case .up:                 return "Up swipe"
        case .down:               return "Down swipe"
        case .navLeft:            return "Left turn"
        case .navRight:           return "Right turn"
        case .genericNav:         return "Generic maneuver"
        case .underwater:         return "Underwater"
        case .underwaterCritical: return "Underwater critical"
        case .tripleTap:          return "Triple tap"
        case .heartbeat:          return "Heartbeat"
        case .doubleHeartbeat:    return "Double heartbeat"
        case .timekeeper:         return "Timekeeper"
        case .alarm:              return "Alarm"
        case .chime:              return "Chime"
        case .ascending:          return "Ascending"
        case .descending:         return "Descending"
        case .drumroll:           return "Drumroll"
        case .buzz:               return "Buzz"
        case .sosMorse:           return "SOS"
        }
    }

    /// Play the pattern. Safe to call from any thread.
    func play() async {
        let dev = WKInterfaceDevice.current()
        switch self {
        case .none:               return
        case .click:              dev.play(.click)
        case .doubleTap:          dev.play(.notification)
        case .success:            dev.play(.success)
        case .failure:            dev.play(.failure)
        case .retry:              dev.play(.retry)
        case .start:              dev.play(.start)
        case .stop:               dev.play(.stop)
        case .up:                 dev.play(.directionUp)
        case .down:               dev.play(.directionDown)
        case .navLeft:            dev.play(.navigationLeftTurn)
        case .navRight:           dev.play(.navigationRightTurn)
        case .genericNav:         dev.play(.navigationGenericManeuver)
        case .underwater:         dev.play(.underwaterDepthPrompt)
        case .underwaterCritical: dev.play(.underwaterDepthCriticalPrompt)

        case .tripleTap:
            await Self.playSequence([(.click, 130), (.click, 130), (.click, 0)])
        case .heartbeat:
            await Self.playSequence([(.click, 110), (.click, 450), (.click, 110), (.click, 0)])
        case .doubleHeartbeat:
            await Self.playSequence([
                (.click, 110), (.click, 450), (.click, 110), (.click, 600),
                (.click, 110), (.click, 450), (.click, 110), (.click, 0),
            ])
        case .timekeeper:
            await Self.playSequence([(.click, 500), (.click, 500), (.click, 500), (.click, 0)])
        case .alarm:
            await Self.playSequence([(.notification, 220), (.notification, 220), (.notification, 0)])
        case .chime:
            await Self.playSequence([(.notification, 250), (.success, 0)])
        case .ascending:
            await Self.playSequence([(.click, 200), (.notification, 250), (.success, 0)])
        case .descending:
            await Self.playSequence([(.success, 250), (.notification, 200), (.failure, 0)])
        case .drumroll:
            await Self.playSequence([
                (.click, 55), (.click, 55), (.click, 55),
                (.click, 55), (.click, 55), (.click, 0),
            ])
        case .buzz:
            await Self.playSequence([(.click, 80), (.click, 80), (.click, 80), (.click, 0)])
        case .sosMorse:
            // ... --- ... — short clicks for dots, double-taps for dashes
            await Self.playSequence([
                (.click, 150), (.click, 150), (.click, 350),
                (.notification, 200), (.notification, 200), (.notification, 350),
                (.click, 150), (.click, 150), (.click, 0),
            ])
        }
    }

    private static func playSequence(_ steps: [(WKHapticType, UInt64)]) async {
        let dev = WKInterfaceDevice.current()
        for (haptic, delayMs) in steps {
            dev.play(haptic)
            if delayMs > 0 {
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
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
