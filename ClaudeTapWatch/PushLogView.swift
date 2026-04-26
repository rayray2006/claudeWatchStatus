import SwiftUI

struct PushLogView: View {
    @State private var events: [PushEvent] = []

    var body: some View {
        List {
            if events.isEmpty {
                Text("No events recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(events.reversed()) { event in
                        EventRow(event: event)
                    }
                } header: {
                    Text("\(events.count) events").textCase(nil)
                }
            }

            if !events.isEmpty {
                Section {
                    Button(role: .destructive) {
                        PushEventLog.clear()
                        events = []
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Push log")
        .onAppear { events = PushEventLog.all() }
    }
}

private struct EventRow: View {
    let event: PushEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let detail = event.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 1)
    }

    private var label: String {
        switch event.kind {
        case .foregroundDelivered:    return "Foreground"
        case .backgroundDelivered:    return "Background"
        case .complicationDelivered:  return "Complication"
        case .hapticPlayed:           return "Haptic"
        case .hapticSkippedDebounce:  return "Haptic skipped (dedupe)"
        case .hapticSkippedNone:      return "Haptic skipped (.none)"
        }
    }

    private var color: Color {
        switch event.kind {
        case .foregroundDelivered, .backgroundDelivered, .complicationDelivered: return .blue
        case .hapticPlayed:                                                       return .green
        case .hapticSkippedDebounce, .hapticSkippedNone:                         return .yellow
        }
    }
}
