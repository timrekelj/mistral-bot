import Foundation
import LeBotCore
import Observation

@MainActor
@Observable
final class APIKeyFormModel {
    var draft = "" {
        didSet { if draft != oldValue { errorMessage = nil } }
    }
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: any APIKeyServicing

    init(service: any APIKeyServicing) {
        self.service = service
    }

    var normalizedKey: String { APIKeyInput.normalize(draft) }
    var canSave: Bool { !isWorking && APIKeyInput.isPlausible(normalizedKey) }

    /// Returns the stored status on success; on failure keeps the draft and shows why.
    func save() async -> APIKeyStatus? {
        guard canSave else { return nil }
        return await perform { try await service.saveMistralKey(normalizedKey) }
    }

    func remove() async -> Bool {
        await perform { try await service.removeMistralKey() } != nil
    }

    private func perform<T>(_ work: () async throws -> T) async -> T? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            return try await work()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
