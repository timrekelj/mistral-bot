import LeBotCore
import LeBotDesign
import SwiftUI

/// Add, replace or remove the user's Mistral API key.
struct APIKeySheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var form: APIKeyFormModel?
    @State private var isConfirmingRemoval = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let form { content(form) }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Mistral API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if form == nil { form = APIKeyFormModel(service: appModel.apiKeys) }
            isFieldFocused = true
        }
    }

    private var stored: APIKeyStatus? {
        if case let .stored(status) = appModel.mistralKey { status } else { nil }
    }

    @ViewBuilder
    private func content(_ form: APIKeyFormModel) -> some View {
        @Bindable var form = form
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Le Bot runs on your own Mistral account, so usage is billed to you directly.")
                    .font(.callout)
                    .foregroundStyle(Palette.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(stored == nil ? "Key" : "New key").eyebrow()
                    HStack(spacing: 10) {
                        SecureField("Paste your key", text: $form.draft)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                            .focused($isFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { Task { await save(form) } }
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { form.draft = first }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .tint(Palette.accent)
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 6)
                    .frame(height: 52)
                    .background(Palette.surface, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(borderColor(form)))

                    if let error = form.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                            .transition(.opacity)
                    } else if let stored {
                        Text("Current key \(stored.keyHint) stays active until you save a new one.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                Button {
                    Task { await save(form) }
                } label: {
                    if form.isWorking {
                        HStack(spacing: 10) {
                            ProgressView().tint(Palette.onPrimaryFill)
                            Text("Checking with Mistral…")
                        }
                    } else {
                        Text("Save key")
                    }
                }
                .buttonStyle(.lbPrimary)
                .disabled(!form.canSave)

                Link(destination: URL(string: "https://console.mistral.ai/api-keys")!) {
                    Label("Create a key in Mistral's console", systemImage: "arrow.up.right")
                        .font(.callout.weight(.medium))
                }
                .tint(Palette.accent)

                privacyNote

                if stored != nil {
                    Button("Remove key", role: .destructive) { isConfirmingRemoval = true }
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .confirmationDialog(
                            "Remove your Mistral API key?",
                            isPresented: $isConfirmingRemoval,
                            titleVisibility: .visible
                        ) {
                            Button("Remove key", role: .destructive) { Task { await remove(form) } }
                        } message: {
                            Text("Your agents stop working until you add a key again, including scheduled tasks.")
                        }
                }
            }
            .padding(20)
            .animation(.smooth, value: form.errorMessage)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Palette.accent)
                .padding(.top, 2)
            Text("Mistral verifies the key first. It's then stored encrypted on the Le Bot server so your agents can work while the app is closed. The app never shows it again — only the last four characters.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.opacity(0.6), in: .rect(cornerRadius: 14))
    }

    private func borderColor(_ form: APIKeyFormModel) -> Color {
        form.errorMessage == nil ? Palette.separator : Palette.danger.opacity(0.6)
    }

    private func save(_ form: APIKeyFormModel) async {
        guard let status = await form.save() else { return }
        appModel.keyDidChange(status)
        dismiss()
    }

    private func remove(_ form: APIKeyFormModel) async {
        guard await form.remove() else { return }
        appModel.keyDidChange(nil)
        dismiss()
    }
}
