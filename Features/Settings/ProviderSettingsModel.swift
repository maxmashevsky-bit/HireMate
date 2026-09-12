import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class ProviderSettingsModel {
    var configuration: ModelConfiguration { didSet { if oldValue != configuration { onConfigurationChange?() } } }
    var onConfigurationChange: (() -> Void)?
    private let defaults: UserDefaults
    var message = ""
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "provider.configuration.v1"),
           let loaded = try? JSONDecoder().decode(ModelConfiguration.self, from: data), loaded.schemaVersion == 1 {
            configuration = loaded
        } else { configuration = ModelConfiguration() }
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
}
