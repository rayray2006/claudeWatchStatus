import SwiftUI

struct HomeView: View {
    @Bindable var auth: AuthStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    NavigationLink(destination: SetupView(auth: auth)) {
                        primaryCard(
                            title: "Set up Mac",
                            subtitle: "Copy a one-line snippet into your Claude Code settings",
                            systemImage: "laptopcomputer",
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: SettingsView(auth: auth)) {
                        primaryCard(
                            title: "Settings",
                            subtitle: "Manage keys, devices, and your account",
                            systemImage: "gearshape",
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Nudge")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.85, green: 0.55, blue: 0.35).opacity(0.15))
                    .frame(width: 100, height: 100)
                Text("✦")
                    .font(.system(size: 40))
                    .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.35))
            }
            Text("Wrist nudges for your AI agent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func primaryCard(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundColor(Color(red: 0.85, green: 0.55, blue: 0.35))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
