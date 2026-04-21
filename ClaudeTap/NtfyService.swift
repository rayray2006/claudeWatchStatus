import Foundation
import Combine
import UserNotifications

final class NtfyService: ObservableObject, @unchecked Sendable {
    @Published var isConnected = false
    @Published var lastMessage: TapState = .idle

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var topic: String = ""
    private var reconnectWork: DispatchWorkItem?

    static let shared = NtfyService()

    private init() {}

    func connect(topic: String) {
        self.topic = topic
        disconnect()
        startConnection()
    }

    func disconnect() {
        reconnectWork?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func startConnection() {
        guard !topic.isEmpty else { return }

        let urlString = "\(ClaudeTapConstants.ntfyWebSocketURL)/\(topic)/ws"
        guard let url = URL(string: urlString) else { return }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        session = URLSession(configuration: config)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        DispatchQueue.main.async {
            self.isConnected = true
        }

        listenForMessages()
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.listenForMessages()
            case .failure:
                DispatchQueue.main.async { [weak self] in
                    self?.isConnected = false
                    self?.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String, event == "message",
              let body = json["message"] as? String
        else { return }

        let state: TapState
        if let parsed = try? JSONDecoder().decode([String: String].self, from: Data(body.utf8)),
           let statusStr = parsed["status"],
           let tapState = TapState(rawValue: statusStr) {
            state = tapState
        } else {
            // Fallback: treat plain text as the status
            state = TapState(rawValue: body.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .done
        }

        DispatchQueue.main.async {
            self.lastMessage = state

            // Save to shared defaults for complication
            let defaults = ClaudeTapConstants.sharedDefaults
            defaults?.set(state.rawValue, forKey: ClaudeTapConstants.Defaults.stateKey)
            if state.needsTap {
                defaults?.set(Date().timeIntervalSince1970, forKey: ClaudeTapConstants.Defaults.lastTapKey)
            }

            // Forward to Watch via WatchConnectivity
            WatchConnector.shared.sendState(state)

            // Send local notification for Watch haptic tap
            if state.needsTap {
                self.sendWatchTapNotification(state: state)
            }
        }
    }

    private func sendWatchTapNotification(state: TapState) {
        let content = UNMutableNotificationContent()
        content.title = "Claude"
        content.body = state == .needsApproval ? "Needs your approval" : "Done"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("tap.caf"))
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "claudetap-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startConnection()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
