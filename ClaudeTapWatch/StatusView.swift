import SwiftUI
import WidgetKit

struct StatusView: View {
    @StateObject private var store = StateStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Always mounted. When currentState changes, Canvas starts
                // redrawing in the background — while the spinner overlay (if
                // any) is still up, hiding the work-in-progress render.
                PixelClaudeView(state: store.currentState, size: 140)

                if store.isSyncing {
                    Color.black
                        .transition(.opacity)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .frame(width: 140, height: 140)
            .animation(.easeInOut(duration: 0.18), value: store.isSyncing)

            if !store.isSyncing {
                Text(store.currentState.label)
                    .font(.system(.headline, weight: .bold))
                    .foregroundColor(statusColor)
                    .transition(.opacity)
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
