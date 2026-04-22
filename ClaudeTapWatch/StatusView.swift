import SwiftUI
import WatchKit
import WidgetKit

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
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .frame(width: 140, height: 140)

            // Always rendered (so the VStack layout is stable across state
            // transitions); opacity instead of conditional insertion.
            Text(store.currentState.label)
                .font(.system(.headline, weight: .bold))
                .foregroundColor(statusColor)
                .opacity(store.isSyncing ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.18), value: store.isSyncing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            WKInterfaceDevice.current().play(.click)
            showSettings = true
        }
        .confirmationDialog("Settings", isPresented: $showSettings, titleVisibility: .visible) {
            Button("Reset pairing", role: .destructive) {
                Pairing.shared.reset()
            }
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
        case .working: return .orange
        case .done: return .green
        case .needsApproval: return .blue
        }
    }
}
