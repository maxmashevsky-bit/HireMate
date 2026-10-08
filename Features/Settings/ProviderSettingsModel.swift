import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class ProviderSettingsModel {
    var configuration: ModelConfiguration {
        didSet {
            if let activeSlotNumber, modelSlots[activeSlotNumber]?.matches(configuration) != true { self.activeSlotNumber = nil }
            if oldValue != configuration { onConfigurationChange?() }
        }
    }
    private(set) var modelSlots: [Int: ModelSlot] = [:]
    private(set) var activeSlotNumber: Int? {
        didSet {
            if let activeSlotNumber { defaults.set(activeSlotNumber, forKey: "provider.activeModelSlot.v1") }
            else { defaults.removeObject(forKey: "provider.activeModelSlot.v1") }
        }
    }
    var onConfigurationChange: (() -> Void)?
    private let defaults: UserDefaults
    var message = ""
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "provider.configuration.v1"),
           let loaded = try? JSONDecoder().decode(ModelConfiguration.self, from: data), loaded.schemaVersion == 1 {
            configuration = loaded
        } else { configuration = ModelConfiguration() }
        if let data = defaults.data(forKey: "provider.modelSlots.v1"),
           let slots = try? JSONDecoder().decode([ModelSlot].self, from: data),
           slots.count <= 5, slots.allSatisfy(\.isValid), Set(slots.map(\.number)).count == slots.count {
            modelSlots = Dictionary(uniqueKeysWithValues: slots.map { ($0.number, $0) })
        }
        let storedActive = defaults.object(forKey: "provider.activeModelSlot.v1") as? Int
        activeSlotNumber = storedActive.flatMap { modelSlots[$0]?.matches(configuration) == true ? $0 : nil }
    }
    func save() {
        do {
            if configuration.mode == .remote {
                _ = try configuration.endpoint("models")
                guard (5...180).contains(configuration.timeoutSeconds) else { throw ProviderError.invalidBudget }
            }
            defaults.set(try JSONEncoder().encode(configuration), forKey: "provider.configuration.v1")
            message = "Несекретные параметры сохранены. Соединение с API не проверялось."
        } catch { message = (error as? ProviderError)?.localizedDescription ?? "Не удалось сохранить параметры." }
    }
    func saveModelSlot(number: Int, name: String, model: String, supportsVision: Bool,
                       maxContextTokens: Int? = nil, reservedOutputTokens: Int? = nil) -> Bool {
        do {
            guard configuration.mode == .remote else { throw ProviderError.modelMissing }
            var candidate = configuration
            candidate.textModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            candidate.visionEnabled = supportsVision
            if let maxContextTokens { candidate.maxContextTokens = maxContextTokens }
            if let reservedOutputTokens { candidate.reservedOutputTokens = reservedOutputTokens }
            try candidate.validate()
            let slot = ModelSlot(number: number, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                 model: candidate.textModel, supportsVision: supportsVision,
                                 providerIdentity: try candidate.modelSlotProviderIdentity(),
                                 maxContextTokens: candidate.maxContextTokens, reservedOutputTokens: candidate.reservedOutputTokens)
            guard slot.isValid else { throw ProviderError.modelMissing }
            var next = modelSlots; next[number] = slot
            try persistSlots(next)
            modelSlots = next
            if activeSlotNumber == number, !slot.matches(configuration) { activeSlotNumber = nil }
            message = "Слот сохранён для текущего API. Возможности модели указаны вручную; запрос не отправлялся."
            return true
        } catch {
            message = (error as? ProviderError)?.localizedDescription ?? "Слот не сохранён."
            return false
        }
    }
    func removeModelSlot(_ number: Int) {
        var next = modelSlots; next.removeValue(forKey: number)
        do {
            try persistSlots(next); modelSlots = next
            if activeSlotNumber == number { activeSlotNumber = nil }
            message = "Слот очищен. Текущая конфигурация API сохранена."
        } catch { message = "Не удалось очистить слот." }
    }
    func isSlotAvailable(_ number: Int) -> Bool {
        guard configuration.mode == .remote, let slot = modelSlots[number] else { return false }
        return (try? configuration.modelSlotProviderIdentity()) == slot.providerIdentity
    }
    @discardableResult
    func activateModelSlot(_ number: Int) -> Bool {
        guard isSlotAvailable(number), let slot = modelSlots[number] else {
            message = "Слот не настроен для текущего API. Адрес провайдера не переключается автоматически."
            return false
        }
        var next = configuration
        next.textModel = slot.model; next.visionEnabled = slot.supportsVision
        next.maxContextTokens = slot.maxContextTokens; next.reservedOutputTokens = slot.reservedOutputTokens
        do {
            try next.validate()
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: "provider.configuration.v1")
            configuration = next; activeSlotNumber = number
            message = "Выбрана модель из слота \(number). Запрос не отправлялся."
            return true
        } catch { message = (error as? ProviderError)?.localizedDescription ?? "Слот недоступен."; return false }
    }
    @discardableResult
    func cycleModelSlot() -> Bool {
        let available = modelSlots.keys.filter(isSlotAvailable).sorted()
        guard !available.isEmpty else { message = "Настройте хотя бы один слот текущего API."; return false }
        let currentIndex = activeSlotNumber.flatMap { available.firstIndex(of: $0) }
        let nextIndex = currentIndex.map { ($0 + 1) % available.count } ?? 0
        return activateModelSlot(available[nextIndex])
    }
    private func persistSlots(_ slots: [Int: ModelSlot]) throws {
        defaults.set(try JSONEncoder().encode(slots.values.sorted { $0.number < $1.number }), forKey: "provider.modelSlots.v1")
    }
}
