import SwiftUI

/// Inspector for the location-keep-alive event log.
struct LocationLogView: View {
    @State private var events: [LocationEvent] = []

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
                        LocationEventLog.clear()
                        events = []
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Location log")
        .onAppear { events = LocationEventLog.all() }
    }
}

private struct EventRow: View {
    let event: LocationEvent

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
        case .startRequested: return "Start requested"
        case .authChanged:    return "Auth changed"
        case .started:        return "Started"
        case .stopped:        return "Stopped"
        case .startFailed:    return "Start failed"
        case .failed:         return "Failed"
        case .skipped:        return "Skipped"
        }
    }

    private var color: Color {
        switch event.kind {
        case .startRequested:           return .blue
        case .started:                  return .green
        case .authChanged:              return .yellow
        case .stopped:                  return .orange
        case .startFailed, .failed:     return .red
        case .skipped:                  return .gray
        }
    }
}
