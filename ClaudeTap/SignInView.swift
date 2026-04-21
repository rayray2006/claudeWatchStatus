import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Bindable var auth: AuthStore

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.55, blue: 0.35).opacity(0.15))
                        .frame(width: 120, height: 120)
                    Text("✦")
                        .font(.system(size: 52))
                        .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.35))
                }

                Text("Nudge")
                    .font(.system(size: 36, weight: .bold))

                Text("Get a wrist nudge when your AI agent finishes a task or needs your attention.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task { await handle(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(10)
                .padding(.horizontal, 24)

                if let err = auth.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth0):
            if let credential = auth0.credential as? ASAuthorizationAppleIDCredential {
                await auth.handleAppleCredential(credential)
            }
        case .failure(let err):
            auth.lastError = err.localizedDescription
        }
    }
}
