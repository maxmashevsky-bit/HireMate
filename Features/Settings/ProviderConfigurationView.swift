import SwiftUI
import CopilotCore

@MainActor
struct ProviderConfigurationView: View {
    @Bindable var settings: ProviderSettingsModel
    var body: some View {
        Picker("Режим", selection: $settings.configuration.mode) {
            ForEach(ProviderMode.allCases) { Text($0.title).tag($0) }
        }
        if settings.configuration.mode == .remote {
            TextField("Базовый URL API, включая /v1 если требуется", text: $settings.configuration.baseURL)
            TextField("Модель ответов", text: $settings.configuration.textModel)
            Toggle("Модель ответов поддерживает изображения (vision)", isOn: $settings.configuration.visionEnabled)
            Text("Включайте только по документации своего сервера. Совместимость модели не проверена автоматически.").font(.caption)
            TextField("Модель распознавания", text: $settings.configuration.transcriptionModel)
            Toggle("Разрешить локальный endpoint", isOn: $settings.configuration.allowLocalEndpoint)
            Text("Локальный сервер получает те же данные. HTTP разрешён только для localhost; в остальных случаях требуется HTTPS. Перенаправления запросов запрещены.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Контекст: \(settings.configuration.maxContextTokens) токенов", value: $settings.configuration.maxContextTokens, in: 1_024...131_072, step: 1_024)
            Stepper("Резерв ответа: \(settings.configuration.reservedOutputTokens)", value: $settings.configuration.reservedOutputTokens, in: 128...8_192, step: 128)
            Slider(value: $settings.configuration.timeoutSeconds, in: 5...180, step: 5) {
                Text("Таймаут: \(Int(settings.configuration.timeoutSeconds)) с")
            }
        }
        Button("Сохранить параметры") { settings.save() }
        if !settings.message.isEmpty { Text(settings.message).font(.caption).foregroundStyle(.secondary) }
    }
}
