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
    let auth: (any AuthServicing)?

    init(config: AppConfig) {
        auth = Backend(config: config).map(SupabaseAuthService.init)
        state = auth == nil ? .signedOut : .loading
    }

    var isBackendConfigured: Bool { auth != nil }

    var user: UserSummary? {
        if case let .signedIn(user) = state { user } else { nil }
    }

    func observeAuth() async {
        guard let auth else { return }
        for await user in auth.userChanges() {
            if state == .preview { continue }
            state = user.map(State.signedIn) ?? .signedOut
        }
    }

    func enterPreview() {
        state = .preview
    }

    func signOut() async {
        if state == .preview {
            state = .signedOut
            return
        }
        try? await auth?.signOut()
    }
}
