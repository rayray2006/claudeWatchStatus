import SwiftUI

struct SettingsView: View {
    @StateObject private var prefs = HapticPrefs.shared
    @StateObject private var keepAlive = KeepAliveManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var keepAliveOn: Bool = KeepAliveManager.shared.isEnabled

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $keepAliveOn) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Keep app alive")
                                .font(.system(.body, weight: .medium))
                            Text(keepAlive.isActive ? "Running" : "Off")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveOn) { _, newValue in
                        keepAlive.isEnabled = newValue
                    }
                } header: {
                    Text("Reliability").textCase(nil)
                } footer: {
                    Text("Runs an indoor workout session in the background so wrist taps fire even when the app is closed. Watch face shows a green workout indicator while active. Higher battery use.")
                        .font(.caption2)
                }

                Section {
                    ForEach(TapState.allKnown, id: \.self) { state in
                        NavigationLink {
                            HapticPickerView(state: state, prefs: prefs)
                        } label: {
                            HStack {
                                HapticStateIcon(state: state)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(state.label)
                                        .font(.system(.body, weight: .medium))
                                    Text(prefs.choice(for: state).label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Haptics").textCase(nil)
                } footer: {
                    Text("Plays when the state arrives while the app is active.")
                        .font(.caption2)
                }

                Section {
                    Button(role: .destructive) {
                        Pairing.shared.reset()
                        dismiss()
                    } label: {
                        Label("Reset pairing", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct HapticStateIcon: View {
    let state: TapState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .padding(.trailing, 6)
    }

    private var color: Color {
        switch state {
        case .idle:          return .gray
        case .thinking:      return .indigo
        case .working:       return .orange
        case .done:          return .green
        case .needsApproval: return .blue
        }
    }
}

struct HapticPickerView: View {
    let state: TapState
    @ObservedObject var prefs: HapticPrefs

    var body: some View {
        List {
            ForEach(HapticChoice.allCases) { choice in
                Button {
                    prefs.setChoice(choice, for: state)
                    Task { await choice.play() }
                } label: {
                    HStack {
                        Text(choice.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if prefs.choice(for: state) == choice {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(state.label)
    }
}
