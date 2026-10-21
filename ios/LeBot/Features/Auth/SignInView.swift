import AuthenticationServices
import LeBotCore
import LeBotDesign
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var nonce = AppleNonce()
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                hero
                    .padding(.top, 72)

                VStack(spacing: 14) {
                    appleButton
                    divider
                    emailForm
                }
                .disabled(!appModel.isBackendConfigured || isWorking)

                footer
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
    }

    private var hero: some View {
        VStack(spacing: 20) {
            PixelMark()
                .frame(width: 132)
            VStack(spacing: 8) {
                Text("Le Bot")
                    .font(.lbDisplay)
                    .foregroundStyle(Palette.textPrimary)
                Text("Your Mistral agents, one press away.")
                    .font(.lbCallout)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            nonce = AppleNonce()
            request.requestedScopes = [.email]
            request.nonce = nonce.hashed
        } onCompletion: { result in
            Task { await handleApple(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(.capsule)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Palette.separator).frame(height: 1)
            Text("or").eyebrow()
            Rectangle().fill(Palette.separator).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var emailForm: some View {
        VStack(spacing: 10) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .modifier(FieldStyle())

            SecureField("Password", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
                .modifier(FieldStyle())

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            Button {
                Task { await submit() }
            } label: {
                if isWorking { ProgressView().tint(Palette.onPrimaryFill) }
                else { Text(isCreatingAccount ? "Create account" : "Continue") }
            }
            .buttonStyle(.lbPrimary)
            .disabled(email.isEmpty || password.count < 6)
            .padding(.top, 4)

            Button(isCreatingAccount ? "I already have an account" : "Create an account") {
                withAnimation(.snappy) { isCreatingAccount.toggle() }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, 2)
        }
        .animation(.smooth, value: errorMessage)
    }

    @ViewBuilder
    private var footer: some View {
        if !appModel.isBackendConfigured {
            Text("No backend configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to ios/Config/Local.xcconfig.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        #if DEBUG
        Button("Explore without an account") { appModel.enterPreview() }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Palette.accent)
        #endif
    }

    private func submit() async {
        guard let auth = appModel.auth else { return }
        await run {
            if isCreatingAccount {
                try await auth.signUp(email: email, password: password)
            } else {
                try await auth.signIn(email: email, password: password)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) async {
        guard let auth = appModel.auth else { return }
        await run {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else { throw SignInError.missingAppleToken }
            try await auth.signInWithApple(idToken: idToken, nonce: nonce.raw)
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum SignInError: LocalizedError {
        case missingAppleToken
        var errorDescription: String? { "Apple didn't return an identity token. Try again." }
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.lbBody)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Palette.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.separator))
    }
}

#Preview {
    SignInView().environment(AppModel(config: AppConfig(info: [:])))
}
