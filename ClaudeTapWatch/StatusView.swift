import SwiftUI
import WatchKit

struct StatusView: View {
    @StateObject private var store = StateStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Always mounted — Canvas re-renders underneath the spinner
                // so the new character is ready by the time the spinner fades.
                PixelClaudeView(state: store.currentState, size: 140)

                if store.isSyncing {
                    Color.black
                        .transition(.opacity)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .transition(.opacity)
                }
            }
            .frame(width: 140, height: 140)

            // Always rendered (so the VStack layout is stable across state
            // transitions); opacity instead of conditional insertion.
            Text(store.currentState.label)
                .font(.system(.headline, weight: .bold))
                .foregroundColor(statusColor)
                .opacity(store.isSyncing ? 0 : 1)

            if store.currentState.isActive && !store.isSyncing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(store.currentStateStartedAt))
                    Text(Self.formatElapsed(elapsed))
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.isSyncing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            WKInterfaceDevice.current().play(.click)
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task { await store.syncFromDeliveredNotifications() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await store.syncFromDeliveredNotifications() }
            }
        }
    }

    private var statusColor: Color {
        switch store.currentState {
        case .idle: return .gray
        case .thinking: return .indigo
        case .working: return .orange
        case .done: return .green
        case .needsApproval: return .blue
        }
    }

    /// "0:23" up to an hour, then "1:05:23".
    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
