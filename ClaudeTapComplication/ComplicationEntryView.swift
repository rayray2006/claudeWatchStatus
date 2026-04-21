import WidgetKit
import SwiftUI

struct ComplicationEntryView: View {
    let entry: ClaudeTapEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular Complication (primary)
    private var circularView: some View {
        ClaudeSpriteView(state: entry.state)
    }

    // MARK: - Corner Complication
    private var cornerView: some View {
        ClaudeSpriteView(state: entry.state)
            .widgetLabel {
                Text(entry.state.label)
            }
    }

    // MARK: - Inline Complication
    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: inlineIcon)
            Text(entry.state.label)
        }
    }

    private var assetName: String {
        switch entry.state {
        case .idle:          return "ClaudeIdle"
        case .working:       return "ClaudeWorking"
        case .done:          return "ClaudeDone"
        case .needsApproval: return "ClaudeApproval"
        }
    }

    private var inlineIcon: String {
        switch entry.state {
        case .idle:          return "sparkle"
        case .working:       return "ellipsis.circle"
        case .done:          return "checkmark.circle"
        case .needsApproval: return "hand.raised"
        }
    }
}

// MARK: - Widget Definition

@main
struct ClaudeTapComplicationWidget: Widget {
    let kind = ClaudeTapConstants.ComplicationKind.circular

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeTapComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("ClaudeTap")
        .description("See when Claude is working and get tapped when done.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
