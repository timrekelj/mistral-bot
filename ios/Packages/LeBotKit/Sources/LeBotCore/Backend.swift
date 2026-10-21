import Foundation
import Supabase

/// Owns the single Supabase client. The session lives in the shared keychain group so
/// the widget extension and App Intents can reuse it (Action Button quick call).
public final class Backend: Sendable {
    public let client: SupabaseClient

    public init?(config: AppConfig) {
        guard let url = config.supabaseURL, let key = config.supabaseAnonKey else { return nil }
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(
                        service: "com.timrekelj.lebot.auth",
                        accessGroup: config.keychainAccessGroup
                    ),
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
