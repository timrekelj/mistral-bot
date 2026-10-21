import LeBotDesign
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        PixelMark().frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mistral").font(.headline)
                            Text("Main agent · Large 4").eyebrow()
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Agents")
                }

                Section("Conversations") {
                    Text("Your conversations will appear here.")
                        .font(.callout)
                        .foregroundStyle(Palette.textSecondary)
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
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var accountLabel: String {
        switch appModel.state {
        case let .signedIn(user): user.email ?? "Apple ID"
        case .preview: "Preview"
        default: "—"
        }
    }
}

private extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
