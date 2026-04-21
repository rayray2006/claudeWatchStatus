import Foundation

enum TapState: String, Codable {
    case idle
    case working
    case done
    case needsApproval = "approval"

    var isActive: Bool {
        self == .working
    }

    var needsTap: Bool {
        self == .done || self == .needsApproval
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working..."
        case .done: return "Done"
        case .needsApproval: return "Needs you"
        }
    }
}
