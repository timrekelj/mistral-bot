@testable import LeBot
import LeBotCore
import Testing

@MainActor
struct APIKeyFormModelTests {
    @Test func savesNormalizedKey() async throws {
        let form = APIKeyFormModel(service: InMemoryAPIKeyService())
        form.draft = "  \"A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6\"\n"
        #expect(form.canSave)
        let status = try #require(await form.save())
        #expect(status.keyHint == "…O5p6")
        #expect(form.errorMessage == nil)
        #expect(!form.isWorking)
    }

    @Test func showsRejectionAndClearsItWhenEditing() async {
        let form = APIKeyFormModel(service: InMemoryAPIKeyService())
        form.draft = "A1b2C3d4E5f6G7h8I9j0-bad"
        #expect(await form.save() == nil)
        #expect(form.errorMessage == "That key was rejected by Mistral.")
        form.draft += "x"
        #expect(form.errorMessage == nil)
    }

    @Test func refusesImplausibleKeys() async {
        let form = APIKeyFormModel(service: InMemoryAPIKeyService())
        form.draft = "too short"
        #expect(!form.canSave)
        #expect(await form.save() == nil)
    }

    @Test func removesStoredKey() async throws {
        let service = InMemoryAPIKeyService(status: APIKeyStatus(keyHint: "…abcd", state: .valid, verifiedAt: nil))
        let form = APIKeyFormModel(service: service)
        #expect(await form.remove())
        #expect(try await service.mistralKeyStatus() == nil)
    }

    @Test func keyStateNeedsKeyOnlyWhenMissingOrRejected() {
        #expect(!AppModel.KeyState.unknown.needsKey)
        #expect(AppModel.KeyState.missing.needsKey)
        #expect(AppModel.KeyState.stored(APIKeyStatus(keyHint: "…a", state: .invalid, verifiedAt: nil)).needsKey)
        #expect(!AppModel.KeyState.stored(APIKeyStatus(keyHint: "…a", state: .valid, verifiedAt: nil)).needsKey)
    }
}
