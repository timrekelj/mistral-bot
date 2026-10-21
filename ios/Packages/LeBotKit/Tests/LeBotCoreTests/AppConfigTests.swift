@testable import LeBotCore
import Testing

struct AppConfigTests {
    @Test func readsConfiguredBackend() {
        let config = AppConfig(info: [
            "LBSupabaseURL": "http://127.0.0.1:54321",
            "LBSupabaseAnonKey": "anon",
            "LBKeychainAccessGroup": "ABCDE12345.com.timrekelj.lebot.shared",
            "LBAppGroup": "group.com.timrekelj.lebot",
        ])
        #expect(config.isBackendConfigured)
        #expect(config.supabaseURL?.absoluteString == "http://127.0.0.1:54321")
        #expect(config.keychainAccessGroup == "ABCDE12345.com.timrekelj.lebot.shared")
        #expect(config.appGroup == "group.com.timrekelj.lebot")
    }

    @Test(arguments: ["", "   ", "$(SUPABASE_URL)", "not a url", "127.0.0.1"])
    func rejectsMissingOrUnexpandedURL(_ value: String) {
        let config = AppConfig(info: ["LBSupabaseURL": value, "LBSupabaseAnonKey": "anon"])
        #expect(config.supabaseURL == nil)
        #expect(!config.isBackendConfigured)
    }

    @Test(arguments: [".com.timrekelj.lebot.shared", "com.timrekelj.lebot.shared", "abcde12345.x"])
    func dropsAccessGroupWithoutTeamPrefix(_ value: String) {
        #expect(AppConfig(info: ["LBKeychainAccessGroup": value]).keychainAccessGroup == nil)
    }

    @Test func appleNonceHashesRawValue() {
        let nonce = AppleNonce()
        #expect(nonce.raw.count == 32)
        #expect(nonce.hashed == AppleNonce.sha256(nonce.raw))
        #expect(nonce.hashed.count == 64)
    }
}
