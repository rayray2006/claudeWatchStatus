import SwiftUI

struct PixelClaudeView: View {
    let state: TapState
    var size: CGFloat = 170

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var assetName: String {
        switch state {
        case .idle:          return "ClaudeIdle"
        case .working:       return "ClaudeWorking"
        case .done:          return "ClaudeDone"
        case .needsApproval: return "ClaudeApproval"
        }
    }
}
