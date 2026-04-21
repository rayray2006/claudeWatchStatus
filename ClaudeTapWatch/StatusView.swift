import SwiftUI
import WidgetKit

struct StatusView: View {
    @StateObject private var store = StateStore.shared
    @AppStorage("apns_registered") private var apnsRegistered: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                PixelClaudeView(state: store.currentState, size: 140)

                if store.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .padding(6)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.isSyncing)

            Text(store.currentState.label)
                .font(.system(.headline, weight: .bold))
                .foregroundColor(statusColor)

            HStack(spacing: 4) {
                Circle()
                    .fill(apnsRegistered ? .green : .orange)
                    .frame(width: 5, height: 5)
                Text(apnsRegistered ? "Push ready" : "Registering...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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
        case .working: return .orange
        case .done: return .green
        case .needsApproval: return .blue
        }
    }
}
