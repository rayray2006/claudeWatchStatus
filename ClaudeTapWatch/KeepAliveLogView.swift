import SwiftUI

/// Inspector for the keep-alive event log. Shows session lifecycle in
/// reverse chronological order so you can see what's been happening
/// without Xcode attached.
struct KeepAliveLogView: View {
    @State private var events: [SessionEvent] = []

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
                        SessionEventLog.clear()
                        events = []
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Keep-alive log")
        .onAppear { events = SessionEventLog.all() }
    }
}

private struct EventRow: View {
    let event: SessionEvent

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
        case .started:        return "Started"
        case .willExpire:     return "Will expire"
        case .chained:        return "Chained"
        case .invalidated:    return "Invalidated"
        case .manualStop:     return "Manually stopped"
        case .idleTimeout:    return "Idle timeout"
        case .skipped:        return "Skipped"
        }
    }

    private var color: Color {
        switch event.kind {
        case .startRequested:           return .blue
        case .started, .chained:        return .green
        case .willExpire:               return .yellow
        case .invalidated:              return .red
        case .manualStop, .idleTimeout: return .orange
        case .skipped:                  return .gray
        }
    }
}
