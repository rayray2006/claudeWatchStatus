import SwiftUI

struct SetupView: View {
    @Bindable var auth: AuthStore

    @State private var apiKey: String?
    @State private var loading = true
    @State private var loadError: String?
    @State private var testStatus: String?
    @State private var testing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading {
                    ProgressView().padding(.top, 40)
                } else if let err = loadError {
                    errorBanner(err)
                } else if let key = apiKey {
                    stepHeader("1. Copy this snippet", "…and paste it into your Claude Code settings.json, merging with any existing hooks block.")
                    snippetCard(key: key)

                    stepHeader("2. Paste it", "Open `~/.claude/settings.json` on your Mac, add or merge the hooks block, save.")

                    stepHeader("3. Test", "Fire a sample push from here to make sure your Watch is wired up.")
                    testButton
                }
            }
            .padding()
        }
        .navigationTitle("Set up Mac")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await ensureKey()
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func snippetCard(key: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(snippet(for: key))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Button {
                UIPasteboard.general.string = snippet(for: key)
            } label: {
                Label("Copy snippet", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var testButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await sendTest() }
            } label: {
                HStack {
                    if testing { ProgressView().controlSize(.small) }
                    Text(testing ? "Sending…" : "Send test push")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(testing)

            if let testStatus {
                Text(testStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Behavior

    private func ensureKey() async {
        guard let token = auth.sessionToken else { loading = false; return }
        do {
            let created = try await auth.api.createAPIKey(sessionToken: token, label: "ios-default")
            apiKey = created.key
            loadError = nil
        } catch {
            loadError = "Couldn't create an API key: \(error.localizedDescription)"
        }
        loading = false
    }

    private func sendTest() async {
        guard let key = apiKey else { return }
        testing = true
        defer { testing = false }
        do {
            let r = try await auth.api.sendPush(apiKey: key, status: "working")
            testStatus = "Sent. Delivered to \(r.delivered) device(s)."
        } catch {
            testStatus = "Failed: \(error.localizedDescription)"
        }
    }

    private func snippet(for key: String) -> String {
        let base = APIClient.baseURL.absoluteString
        let url = "\(base)/api/v1/push"
        return """
        {
          "hooks": {
            "PreToolUse": [{
              "type": "command",
              "command": "curl -sS -H 'Authorization: Bearer \(key)' -H 'content-type: application/json' -d '{\\"status\\":\\"working\\"}' \(url) >/dev/null 2>&1 &"
            }],
            "Stop": [{
              "type": "command",
              "command": "curl -sS -H 'Authorization: Bearer \(key)' -H 'content-type: application/json' -d '{\\"status\\":\\"done\\"}' \(url) >/dev/null 2>&1 &"
            }],
            "Notification": [{
              "type": "command",
              "command": "curl -sS -H 'Authorization: Bearer \(key)' -H 'content-type: application/json' -d '{\\"status\\":\\"approval\\"}' \(url) >/dev/null 2>&1 &"
            }]
          }
        }
        """
    }
}
