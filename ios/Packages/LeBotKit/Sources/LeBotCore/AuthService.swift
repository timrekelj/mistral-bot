import CryptoKit
import Foundation
import Supabase

public struct UserSummary: Sendable, Equatable {
    public var id: UUID
    public var email: String?

    public init(id: UUID, email: String?) {
        self.id = id
        self.email = email
    }
}

public protocol AuthServicing: Sendable {
    /// Emits the current user on subscribe, then on every change (`nil` when signed out).
    func userChanges() -> AsyncStream<UserSummary?>
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    func signInWithApple(idToken: String, nonce: String) async throws
    func signOut() async throws
}

public struct SupabaseAuthService: AuthServicing {
    let auth: AuthClient

    public init(backend: Backend) {
        auth = backend.client.auth
    }

    public func userChanges() -> AsyncStream<UserSummary?> {
        let auth = auth
        return AsyncStream { continuation in
            let task = Task {
                for await (_, session) in auth.authStateChanges {
                    let valid = session.flatMap { $0.isExpired ? nil : $0 }
                    continuation.yield(valid.map { UserSummary(id: $0.user.id, email: $0.user.email) })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func signIn(email: String, password: String) async throws {
        try await auth.signIn(email: email, password: password)
    }

    public func signUp(email: String, password: String) async throws {
        try await auth.signUp(email: email, password: password)
    }

    public func signInWithApple(idToken: String, nonce: String) async throws {
        try await auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }

    public func signOut() async throws {
        try await auth.signOut()
    }
}

/// Nonce pair for Sign in with Apple: Apple receives the SHA-256, Supabase the raw value.
public struct AppleNonce: Sendable {
    public let raw: String
    public let hashed: String

    public init(length: Int = 32) {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        raw = String((0 ..< length).map { _ in charset.randomElement(using: &generator)! })
        hashed = Self.sha256(raw)
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
