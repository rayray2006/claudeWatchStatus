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
        ZStack {
            if entry.state == .working {
                // Spinning progress ring behind character
                Circle()
                    .trim(from: 0, to: trimAmount)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(rotationForFrame))
            }

            // Claude character (sized for circular complication)
            ClaudeCharacterView(state: entry.state, size: 24)
        }
        .widgetAccentable()
    }

    // MARK: - Corner Complication
    private var cornerView: some View {
        ZStack {
            ClaudeCharacterView(state: entry.state, size: 20)
        }
        .widgetAccentable()
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

    // MARK: - Animation Helpers

    private var trimAmount: CGFloat {
        switch entry.frame {
        case 0: return 0.25
        case 1: return 0.5
        case 2: return 0.75
        default: return 0.25
        }
    }

    private var rotationForFrame: Double {
        Double(entry.frame) * 120.0
    }

    private var inlineIcon: String {
        switch entry.state {
        case .idle: return "sparkle"
        case .working: return "ellipsis.circle"
        case .done: return "checkmark.circle"
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
