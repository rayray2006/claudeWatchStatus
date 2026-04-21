import SwiftUI

struct PairingView: View {
    @Bindable var pairing: Pairing

    var body: some View {
        VStack(spacing: 10) {
            switch pairing.stage {
            case .idle, .requesting:
                ProgressView().controlSize(.large).tint(.white)
                Text("Setting up…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .awaitingUser(let code, _):
                awaitingView(code: code)
            case .paired:
                EmptyView()
            case .failed(let message):
                failedView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .padding()
    }

    private func awaitingView(code: String) -> some View {
        VStack(spacing: 8) {
            Text("Open on any device:")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("nudge-backend-psi\n.vercel.app/p")
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)

            Text("Enter code")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text(formatted(code))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .tracking(3)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") { pairing.retry() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
    }

    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let idx = code.index(code.startIndex, offsetBy: 3)
        return String(code[..<idx]) + " " + String(code[idx...])
    }
}
