import Foundation

/// Values injected through Info.plist from `Config/*.xcconfig`.
public struct AppConfig: Sendable, Equatable {
    public var supabaseURL: URL?
    public var supabaseAnonKey: String?
    public var keychainAccessGroup: String?
    public var appGroup: String?

    public var isBackendConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    public init(info: [String: Any]) {
        supabaseURL = (info["LBSupabaseURL"] as? String)
            .flatMap(Self.nonEmpty)
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == nil || $0.host() == nil ? nil : $0 }
        supabaseAnonKey = (info["LBSupabaseAnonKey"] as? String).flatMap(Self.nonEmpty)
        keychainAccessGroup = (info["LBKeychainAccessGroup"] as? String).flatMap(Self.teamScoped)
        appGroup = (info["LBAppGroup"] as? String).flatMap(Self.nonEmpty)
    }

    public static let main = AppConfig(info: Bundle.main.infoDictionary ?? [:])

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    /// Without a development team the `$(AppIdentifierPrefix)` expands to nothing, and
    /// a group without the 10-character team prefix fails at runtime — fall back to the
    /// default keychain in that case (simulator builds).
    private static func teamScoped(_ value: String) -> String? {
        guard let value = nonEmpty(value),
              let prefix = value.split(separator: ".").first,
              prefix.count == 10,
              prefix.allSatisfy({ $0.isUppercase || $0.isNumber })
        else { return nil }
        return value
    }
}
