import Foundation
import Supabase

/// What the app may know about a stored provider key: never the key itself, only its
/// last four characters and whether Mistral accepted it.
public struct APIKeyStatus: Sendable, Equatable, Decodable {
    public enum State: String, Sendable, Decodable { case valid, invalid }

    public var provider: String
    public var keyHint: String
    public var state: State
    public var verifiedAt: Date?

    public init(provider: String = "mistral", keyHint: String, state: State, verifiedAt: Date?) {
        self.provider = provider
        self.keyHint = keyHint
        self.state = state
        self.verifiedAt = verifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case keyHint = "key_hint"
        case state = "status"
        case verifiedAt = "verified_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        keyHint = try container.decode(String.self, forKey: .keyHint)
        state = try container.decode(State.self, forKey: .state)
        verifiedAt = try container.decodeIfPresent(String.self, forKey: .verifiedAt).flatMap(Self.parseDate)
    }

    /// Postgres (`2026-10-21 08:30:00.123456+00`) and JS (`2026-10-21T08:30:00.123Z`) timestamps.
    static func parseDate(_ value: String) -> Date? {
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        for candidate in [normalized, normalized + ":00"] {
            if let date = fractional.date(from: candidate) ?? plain.date(from: candidate) { return date }
        }
        return nil
    }
}

public enum APIKeyError: LocalizedError, Equatable {
    case rejected(String)
    case unavailable(String)
    case missing(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case let .rejected(message), let .unavailable(message), let .missing(message), let .server(message):
            message
        }
    }

    /// Maps an Edge Function error body (`{ "error": "...", "code": "..." }`).
    public static func from(status: Int, body: Data) -> APIKeyError {
        struct Body: Decodable {
            var error: String?
            var code: String?
        }
        let parsed = try? JSONDecoder().decode(Body.self, from: body)
        let message = parsed?.error ?? "Something went wrong (\(status)). Try again."
        switch parsed?.code {
        case "invalid_api_key", "malformed_api_key": return .rejected(message)
        case "provider_unavailable": return .unavailable(message)
        case "missing_api_key": return .missing(message)
        default: return .server(message)
        }
    }
}

public protocol APIKeyServicing: Sendable {
    func mistralKeyStatus() async throws -> APIKeyStatus?
    /// Verifies the key with Mistral, then stores it encrypted server-side.
    func saveMistralKey(_ key: String) async throws -> APIKeyStatus
    func removeMistralKey() async throws
}

public struct SupabaseAPIKeyService: APIKeyServicing {
    let client: SupabaseClient

    public init(backend: Backend) {
        client = backend.client
    }

    public func mistralKeyStatus() async throws -> APIKeyStatus? {
        let rows: [APIKeyStatus] = try await client
            .from("provider_credentials")
            .select("provider,key_hint,status,verified_at")
            .eq("provider", value: "mistral")
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    public func saveMistralKey(_ key: String) async throws -> APIKeyStatus {
        struct Payload: Encodable {
            var provider = "mistral"
            var apiKey: String
            enum CodingKeys: String, CodingKey { case provider, apiKey = "api_key" }
        }
        return try await mapErrors {
            try await client.functions.invoke(
                "api-keys",
                options: FunctionInvokeOptions(method: .post, body: Payload(apiKey: key))
            ) { data, _ in try JSONDecoder().decode(APIKeyStatus.self, from: data) }
        }
    }

    public func removeMistralKey() async throws {
        try await mapErrors {
            try await client.functions.invoke(
                "api-keys",
                options: FunctionInvokeOptions(method: .delete, body: ["provider": "mistral"])
            )
        }
    }

    private func mapErrors<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let FunctionsError.httpError(code, data) {
            throw APIKeyError.from(status: code, body: data)
        }
    }
}

/// Backend-free stand-in for preview mode and tests. Keys ending in "bad" are rejected.
public actor InMemoryAPIKeyService: APIKeyServicing {
    private var status: APIKeyStatus?

    public init(status: APIKeyStatus? = nil) {
        self.status = status
    }

    public func mistralKeyStatus() -> APIKeyStatus? { status }

    public func saveMistralKey(_ key: String) async throws -> APIKeyStatus {
        try await Task.sleep(for: .milliseconds(600))
        guard !key.hasSuffix("bad") else { throw APIKeyError.rejected("That key was rejected by Mistral.") }
        let saved = APIKeyStatus(keyHint: APIKeyInput.hint(for: key), state: .valid, verifiedAt: .now)
        status = saved
        return saved
    }

    public func removeMistralKey() { status = nil }
}

/// Client-side clean-up of pasted keys, mirroring the server's checks.
public enum APIKeyInput {
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
    }

    public static func isPlausible(_ key: String) -> Bool {
        key.count >= 16 && key.count <= 200 && !key.contains(where: \.isWhitespace)
    }

    public static func hint(for key: String) -> String {
        "…" + key.suffix(4)
    }
}
