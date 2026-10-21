import Foundation
import LeBotCore
import Observation

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UserSummary)
        /// Explore the UI without a backend (debug builds only).
        case preview
    }

    private(set) var state: State
    /// Whether the signed-in user has added their Mistral API key (`.unknown` until loaded).
    private(set) var mistralKey: KeyState = .unknown
    let auth: (any AuthServicing)?

    @ObservationIgnored private let remoteKeys: (any APIKeyServicing)?
    @ObservationIgnored private let previewKeys = InMemoryAPIKeyService()

    enum KeyState: Equatable {
        case unknown
        case missing
        case stored(APIKeyStatus)

        var needsKey: Bool {
            switch self {
            case .missing: true
            case let .stored(status): status.state == .invalid
            case .unknown: false
            }
        }
    }

    init(config: AppConfig) {
        let backend = Backend(config: config)
        auth = backend.map(SupabaseAuthService.init)
        remoteKeys = backend.map(SupabaseAPIKeyService.init)
        state = auth == nil ? .signedOut : .loading
    }

    /// Preview mode keeps keys in memory so the flow can be explored without a backend.
    var apiKeys: any APIKeyServicing {
        state == .preview ? previewKeys : (remoteKeys ?? previewKeys)
    }

    func refreshKeyStatus() async {
        guard state != .signedOut, state != .loading else { return }
        do {
            let status = try await apiKeys.mistralKeyStatus()
            mistralKey = status.map(KeyState.stored) ?? .missing
        } catch {
            // Leave the previous state; the prompt only shows once we know the key is missing.
        }
    }

    func keyDidChange(_ status: APIKeyStatus?) {
        mistralKey = status.map(KeyState.stored) ?? .missing
    }

    var isBackendConfigured: Bool { auth != nil }

    var user: UserSummary? {
        if case let .signedIn(user) = state { user } else { nil }
    }

    func observeAuth() async {
        guard let auth else { return }
        for await user in auth.userChanges() {
            if state == .preview { continue }
            let next = user.map(State.signedIn) ?? .signedOut
            if next != state { mistralKey = .unknown }
            state = next
            await refreshKeyStatus()
        }
    }

    func enterPreview() {
        state = .preview
        Task { await refreshKeyStatus() }
    }

    func signOut() async {
        mistralKey = .unknown
        if state == .preview {
            state = .signedOut
            return
        }
        try? await auth?.signOut()
    }
}
