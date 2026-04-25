import WidgetKit
import SwiftUI

/// Two surfaces from one widget:
///   - `.accessoryCircular`: face complication slot. Earns the
///     PKPushType.complication wake budget so done/approval pushes wake the
///     app from deep suspension. Renders sprite-only, filling the circle.
///   - `.accessoryRectangular`: Smart Stack rotation. Sprite fills the full
///     vertical height alongside the colored state label + ticking timer.
struct ComplicationEntryView: View {
    let entry: ClaudeTapEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ClaudeSpriteView(state: entry.state)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rectangularView: some View {
        HStack(spacing: 6) {
            // Fill the full ~42pt vertical space of the rectangular slot
            // while keeping a square aspect — much bigger than the prior
            // fixed 38pt frame.
            ClaudeSpriteView(state: entry.state)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.state.label)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                if entry.state.isActive {
                    // `Text(_:style: .timer)` auto-updates at ~1Hz without
                    // needing extra timeline reloads — SwiftUI renders the
                    // ticking elapsed time natively on watchOS.
                    Text(entry.stateStartedAt, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Cued")
        .description("Claude Code status — add to your watch face for wrist-tap delivery, surfaces in Smart Stack during sessions.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
