import LeBotCore
import LeBotDesign
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditingKey = false

    var body: some View {
        List {
            Section {
                Button { isEditingKey = true } label: {
                    APIKeyRow(state: appModel.mistralKey)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Add or replace your Mistral API key")
            } header: {
                Text("Mistral")
            } footer: {
                Text("Your agents, voice calls and web searches all run on this key.")
            }

            Section("Account") {
                LabeledContent("Signed in as", value: accountLabel)
                Button("Sign out", role: .destructive) {
                    dismiss()
                    Task { await appModel.signOut() }
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.versionLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingKey) { APIKeySheet() }
        .task { await appModel.refreshKeyStatus() }
    }

    private var accountLabel: String {
        switch appModel.state {
        case let .signedIn(user): user.email ?? "Apple ID"
        case .preview: "Preview"
        default: "—"
        }
    }
}

struct APIKeyRow: View {
    var state: AppModel.KeyState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(iconFill, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("API key")
                    .font(.body)
                    .foregroundStyle(Palette.textPrimary)
                subtitle
            }
            Spacer()
            Text(actionLabel)
                .font(.callout)
                .foregroundStyle(Palette.textSecondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary.opacity(0.6))
        }
        .contentShape(.rect)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch state {
        case .unknown:
            Text("Checking…").eyebrow()
        case .missing:
            Text("Not added").eyebrow(Palette.accent)
        case let .stored(status) where status.state == .invalid:
            Text("\(status.keyHint) · Rejected").eyebrow(Palette.danger)
        case let .stored(status):
            if let verifiedAt = status.verifiedAt {
                Text("\(status.keyHint) · Verified \(verifiedAt, format: .relative(presentation: .named))").eyebrow()
            } else {
                Text("\(status.keyHint) · Saved").eyebrow()
            }
        }
    }

    private var actionLabel: String {
        if case .stored = state { "Replace" } else { "Add" }
    }

    private var iconFill: Color {
        state.needsKey ? Palette.accent : Palette.ink
    }
}

extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
