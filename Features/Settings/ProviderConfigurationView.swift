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

@MainActor
struct ModelSlotEditor: View {
    @Bindable var settings: ProviderSettingsModel
    let number: Int
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var modelID: String
    @State private var supportsVision: Bool
    @State private var contextTokens: Int
    @State private var outputTokens: Int

    init(settings: ProviderSettingsModel, slot: ModelSlot) {
        self.settings = settings; number = slot.number
        _name = State(initialValue: slot.name)
        _modelID = State(initialValue: slot.model)
        _supportsVision = State(initialValue: slot.supportsVision)
        _contextTokens = State(initialValue: settings.modelSlots[slot.number]?.maxContextTokens ?? settings.configuration.maxContextTokens)
        _outputTokens = State(initialValue: settings.modelSlots[slot.number]?.reservedOutputTokens ?? settings.configuration.reservedOutputTokens)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Модель · слот \(number)").font(.title2.bold())
            TextField("Название слота", text: $name).textFieldStyle(.roundedBorder)
            TextField("Точное имя модели API", text: $modelID).textFieldStyle(.roundedBorder)
            Toggle("Модель поддерживает изображения", isOn: $supportsVision)
            Stepper("Бюджет контекста: \(contextTokens)", value: $contextTokens, in: 1_024...1_048_576, step: 1_024)
            Stepper("Резерв ответа: \(outputTokens)", value: $outputTokens, in: 128...8_192, step: 128)
            Text("Имя модели и поддержку изображений нужно проверить по документации API. Слот сохраняет модель и бюджет для текущего адреса провайдера; ключ хранится отдельно в Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            if !settings.message.isEmpty { Text(settings.message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить слот") {
                    if settings.saveModelSlot(number: number, name: name, model: modelID, supportsVision: supportsVision,
                                              maxContextTokens: contextTokens, reservedOutputTokens: outputTokens) { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 ||
                              modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelID.count > 256)
            }
        }.padding(24).frame(width: 460)
    }
}
