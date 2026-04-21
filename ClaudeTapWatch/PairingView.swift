import SwiftUI

struct PairingView: View {
    @Bindable var pairing: Pairing

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                switch pairing.stage {
                case .idle, .requesting:
                    settingUp
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .awaitingUser(let code, _):
                    awaitingUser(code: code)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .pairedCelebrate:
                    celebrate
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                case .paired:
                    Color.clear // StatusView takes over at the app root
                case .failed(let message):
                    failed(message: message)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: stageKey)
        }
    }

    // MARK: - Stages

    private var settingUp: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large).tint(.white)
            Text("Setting up…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func awaitingUser(code: String) -> some View {
        VStack(spacing: 0) {
            Text("Open in a browser:")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("getcued.vercel.app")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(.orange)
                .padding(.top, 2)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 8)

            Text("Enter code")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(formatted(code))
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white)
                .padding(.top, 4)
                .monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var celebrate: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.green)
            }
            Text("Paired!")
                .font(.system(.headline, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26))
                .foregroundColor(.orange)
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") { pairing.retry() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// Stable key to drive the stage transition animation.
    private var stageKey: String {
        switch pairing.stage {
        case .idle: return "idle"
        case .requesting: return "requesting"
        case .awaitingUser(let code, _): return "awaiting-\(code)"
        case .pairedCelebrate: return "celebrate"
        case .paired: return "paired"
        case .failed(let m): return "failed-\(m)"
        }
    }

    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let idx = code.index(code.startIndex, offsetBy: 3)
        return String(code[..<idx]) + " " + String(code[idx...])
    }
}
