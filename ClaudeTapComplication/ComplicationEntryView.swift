import WidgetKit
import SwiftUI

struct ComplicationEntryView: View {
    let entry: ClaudeTapEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        default:
            rectangularView
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 12) {
            ClaudeSpriteView(state: entry.state)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.state.label)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if entry.state.isActive {
                    // `Text(_:style: .timer)` auto-updates at ~1Hz without
                    // needing extra timeline reloads — SwiftUI renders the
                    // ticking elapsed time natively on watchOS.
                    Text(entry.stateStartedAt, style: .timer)
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateColor: Color {
        switch entry.state {
        case .idle:          return .gray
        case .thinking:      return .indigo
        case .working:       return .orange
        case .done:          return .green
        case .needsApproval: return .blue
        }
    }
}

// MARK: - Widget Definition

@main
struct ClaudeTapWidget: Widget {
    let kind = ClaudeTapConstants.ComplicationKind.smartStack

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeTapComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
                // Modern widget API: closure-based container background.
                // Using `.clear` directly (the old shape) silently makes the
                // system treat the widget as empty in some watchOS versions.
                .containerBackground(for: .widget) {
                    Color.black
                }
        }
        .configurationDisplayName("Cued")
        .description("See your coding agent's state — thinking, working, done, or waiting on you.")
        .supportedFamilies([.accessoryRectangular])
    }
}
