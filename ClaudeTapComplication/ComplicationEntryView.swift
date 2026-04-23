import WidgetKit
import SwiftUI

/// Minimal complication. Display is intentionally tiny — its only job is to
/// be present on the user's watch face so the app earns the privileged
/// `PKPushType.complication` push wake budget. Tactical wakes (done /
/// approval pushes) come via that PushKit channel, not this widget's
/// timeline.
struct ComplicationEntryView: View {
    let entry: ClaudeTapEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            // Cued mascot square
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 204/255, green: 120/255, blue: 92/255))
            HStack(spacing: 4) {
                eye()
                eye()
            }
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            circularView
                .frame(width: 22, height: 22)
            Text("Cued")
                .font(.system(.headline, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private var inlineView: some View {
        Text("Cued")
    }

    private func eye() -> some View {
        Capsule()
            .fill(Color.black)
            .frame(width: 2, height: 5)
    }
}

// MARK: - Widget Definition

@main
struct ClaudeTapWidget: Widget {
    let kind = ClaudeTapConstants.ComplicationKind.smartStack

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeTapComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black
                }
        }
        .configurationDisplayName("Cued")
        .description("Add to your watch face for reliable wrist-tap delivery.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}
