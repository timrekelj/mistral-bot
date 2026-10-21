import Foundation
@testable import LeBotCore
import Testing

struct APIKeyTests {
    @Test func decodesPostgrestRow() throws {
        let json = #"[{"provider":"mistral","key_hint":"…abcd","status":"valid","verified_at":"2026-10-21T08:30:00.123456+00:00"}]"#
        let rows = try JSONDecoder().decode([APIKeyStatus].self, from: Data(json.utf8))
        let row = try #require(rows.first)
        #expect(row.keyHint == "…abcd")
        #expect(row.state == .valid)
        #expect(row.verifiedAt != nil)
    }

    @Test(arguments: [
        "2026-10-21T08:30:00.123Z",
        "2026-10-21T08:30:00Z",
        "2026-10-21 08:30:00.123456+00",
        "2026-10-21T08:30:00+00:00",
    ])
    func parsesServerTimestamps(_ value: String) throws {
        let date = try #require(APIKeyStatus.parseDate(value))
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
        #expect(parts.hour == 8 && parts.minute == 30)
    }

    @Test func toleratesMissingVerification() throws {
        let json = #"{"provider":"mistral","key_hint":"…abcd","status":"invalid","verified_at":null}"#
        let status = try JSONDecoder().decode(APIKeyStatus.self, from: Data(json.utf8))
        #expect(status.state == .invalid)
        #expect(status.verifiedAt == nil)
    }

    @Test(arguments: [
        (422, #"{"error":"That key was rejected by Mistral.","code":"invalid_api_key"}"#, APIKeyError.rejected("That key was rejected by Mistral.")),
        (503, #"{"error":"Couldn't reach Mistral.","code":"provider_unavailable"}"#, .unavailable("Couldn't reach Mistral.")),
        (412, #"{"error":"Add your key.","code":"missing_api_key"}"#, .missing("Add your key.")),
        (400, #"{"error":"That doesn't look like an API key.","code":"malformed_api_key"}"#, .rejected("That doesn't look like an API key.")),
        (400, #"{"error":"body must be JSON"}"#, .server("body must be JSON")),
        (502, "<html>bad gateway</html>", .server("Something went wrong (502). Try again.")),
    ])
    func mapsFunctionErrors(status: Int, body: String, expected: APIKeyError) {
        #expect(APIKeyError.from(status: status, body: Data(body.utf8)) == expected)
    }

    @Test func normalizesPastedKeys() {
        #expect(APIKeyInput.normalize("  \"abc123\"\n") == "abc123")
        #expect(APIKeyInput.isPlausible("A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6"))
        #expect(!APIKeyInput.isPlausible("short"))
        #expect(!APIKeyInput.isPlausible("has a space in the middle of it"))
        #expect(APIKeyInput.hint(for: "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6") == "…O5p6")
    }

    @Test func inMemoryServiceRoundTrip() async throws {
        let service = InMemoryAPIKeyService()
        #expect(try await service.mistralKeyStatus() == nil)
        await #expect(throws: APIKeyError.self) { try await service.saveMistralKey("whatever-bad") }
        let saved = try await service.saveMistralKey("A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6")
        #expect(saved.keyHint == "…O5p6")
        #expect(try await service.mistralKeyStatus() == saved)
        try await service.removeMistralKey()
        #expect(try await service.mistralKeyStatus() == nil)
    }
}
