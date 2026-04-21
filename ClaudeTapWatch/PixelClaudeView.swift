import SwiftUI

struct PixelClaudeView: View {
    let state: TapState
    var size: CGFloat = 170

    var body: some View {
        ClaudeSpriteView(state: state)
            .frame(width: size, height: size)
    }
}
