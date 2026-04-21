import SwiftUI

struct SettingsView: View {
    @Bindable var auth: AuthStore

    @State private var keys: [APIClient.APIKeySummary] = []
    @State private var devices: [APIClient.DeviceSummary] = []
    @State private var loading = true
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            Section("API keys") {
                if loading {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if keys.isEmpty {
                    Text("No keys yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(keys) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.label ?? key.prefix).font(.body)
                            Text(key.prefix + "…")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Revoke", role: .destructive) {
                                Task { await revokeKey(key.id) }
                            }
                        }
                    }
                }
            }

            Section("Connected watches") {
                if loading {
                    Text("Loading…").foregroundStyle(.secondary)
                } else if devices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No watches connected yet.").foregroundStyle(.secondary)
                        Text("Open the Nudge app on your Apple Watch to register it.")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                } else {
                    ForEach(devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.bundleId).font(.body)
                                Text(device.environment + " · updated " + device.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle().fill(device.isActive ? .green : .secondary).frame(width: 8, height: 8)
                        }
                    }
                }
            }

            Section("Account") {
                Button("Sign out") { auth.signOut() }
                Button("Delete account", role: .destructive) {
                    showingDeleteConfirm = true
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Delete your Nudge account? This revokes all API keys and unregisters all watches.",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible,
        ) {
            Button("Delete permanently", role: .destructive) {
                Task { await auth.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        guard let token = auth.sessionToken else { return }
        loading = true
        async let keysTask = auth.api.listAPIKeys(sessionToken: token)
        async let devicesTask = auth.api.listDevices(sessionToken: token)
        do {
            keys = try await keysTask
            devices = try await devicesTask
        } catch {
            keys = []
            devices = []
        }
        loading = false
    }

    private func revokeKey(_ id: String) async {
        guard let token = auth.sessionToken else { return }
        try? await auth.api.revokeAPIKey(id: id, sessionToken: token)
        await load()
    }
}
