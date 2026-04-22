import Foundation
import SwiftUI

@MainActor
final class HapticPrefs: ObservableObject {
    static let shared = HapticPrefs()

    @Published private var choices: [TapState: HapticChoice] = [:]

    private static func key(for state: TapState) -> String { "haptic_\(state.rawValue)" }

    private init() {
        let d = UserDefaults.standard
        var c: [TapState: HapticChoice] = [:]
        for state in TapState.allKnown {
            let raw = d.string(forKey: Self.key(for: state))
            c[state] = raw.flatMap(HapticChoice.init(rawValue:)) ?? HapticChoice.default(for: state)
        }
        self.choices = c
    }

    func choice(for state: TapState) -> HapticChoice {
        choices[state] ?? HapticChoice.default(for: state)
    }

    func setChoice(_ choice: HapticChoice, for state: TapState) {
        choices[state] = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.key(for: state))
    }
}

extension TapState {
    static let allKnown: [TapState] = [.idle, .thinking, .working, .done, .needsApproval]
}
