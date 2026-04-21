import SwiftUI

struct ContentView: View {
    @StateObject private var ntfy = NtfyService.shared
    @StateObject private var watch = WatchConnector.shared
    @StateObject private var liveActivity: LiveActivityManager = {
        if #available(iOS 16.2, *) { return LiveActivityManager.shared }
        return LiveActivityManager.shared
    }()
    @AppStorage("saved_topic", store: ClaudeTapConstants.sharedDefaults)
    private var topic: String = "claudetap-4d845a7d2113"

    @State private var editingTopic: String = ""
    @State private var hasConnected = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Claude character header
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

                Text("Get a tap on your wrist when\nClaude needs your attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Topic input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Topic")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("e.g. claudetap-secret-abc123", text: $editingTopic)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button(action: connectTapped) {
                            Image(systemName: ntfy.isConnected ? "wifi" : "wifi.slash")
                                .foregroundColor(ntfy.isConnected ? .green : .primary)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)

                // Status
                VStack(spacing: 12) {
                    statusRow("ntfy.sh", connected: ntfy.isConnected)
                    statusRow("Apple Watch", connected: watch.isWatchReachable)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Current state
                if ntfy.isConnected {
                    HStack {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 8, height: 8)
                        Text("Claude: \(ntfy.lastMessage.label)")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                // Live Activity tokens
                if #available(iOS 16.2, *) {
                    liveActivityPanel
                }

                Spacer()
            }
            .onAppear {
                editingTopic = topic
                if !topic.isEmpty && !hasConnected {
                    ntfy.connect(topic: topic)
                    hasConnected = true
                }
            }
        }
    }

    @available(iOS 16.2, *)
    private var liveActivityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live Activity")
                    .font(.caption.bold())
                Spacer()
                Text(liveActivity.isRunning ? "Running" : "Idle")
                    .font(.caption2)
                    .foregroundStyle(liveActivity.isRunning ? .green : .secondary)
            }

            tokenRow("Activity token", token: liveActivity.pushToken)
            tokenRow("Push-to-start", token: liveActivity.pushToStartToken)

            HStack {
                Button("Restart") { liveActivity.endAll(); liveActivity.adoptExistingOrStart() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("End") { liveActivity.endAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func tokenRow(_ label: String, token: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                UIPasteboard.general.string = token
            } label: {
                Text(token.isEmpty ? "—" : "\(String(token.prefix(8)))…")
                    .font(.system(.caption2, design: .monospaced))
            }
            .buttonStyle(.plain)
            .disabled(token.isEmpty)
        }
    }

    private var stateColor: Color {
        switch ntfy.lastMessage {
        case .idle: return .gray
        case .working: return .orange
        case .done: return .green
        case .needsApproval: return .blue
        }
    }

    private func connectTapped() {
        let trimmed = editingTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        topic = trimmed
        ntfy.connect(topic: trimmed)
    }

    private func statusRow(_ label: String, connected: Bool) -> some View {
        HStack {
            Circle()
                .fill(connected ? .green : .red.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(connected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
