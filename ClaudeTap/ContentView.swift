import SwiftUI

struct ContentView: View {
    @StateObject private var watch = WatchConnector.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.55, blue: 0.35).opacity(0.15))
                        .frame(width: 100, height: 100)
                    Text("✦")
                        .font(.system(size: 44))
                        .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.35))
                }
                .padding(.top, 20)

                Text("ClaudeTap")
                    .font(.title.bold())

                Text("Your Apple Watch receives Claude Code\nstatus updates directly via APNs.\nThis iOS app isn't required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                statusRow("Apple Watch", connected: watch.isWatchReachable)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func statusRow(_ label: String, connected: Bool) -> some View {
        HStack {
            Circle()
                .fill(connected ? .green : .secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(connected ? "Reachable" : "Not reachable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
