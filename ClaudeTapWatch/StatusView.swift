import SwiftUI
import WidgetKit

struct StatusView: View {
    @StateObject private var ntfy = NtfyWatchService.shared
    @AppStorage("apns_registered") private var apnsRegistered: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 6) {
            PixelClaudeView(state: ntfy.currentState, size: 140)

            Text(ntfy.currentState.label)
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
        .onAppear { ntfy.refreshFromDefaults() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                ntfy.refreshFromDefaults()
            }
        }
    }

    private var statusColor: Color {
        switch ntfy.currentState {
        case .idle: return .gray
        case .working: return .orange
        case .done: return .green
        case .needsApproval: return .blue
        }
    }
}
