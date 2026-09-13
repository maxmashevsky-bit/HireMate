import SwiftUI
import CopilotCore

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var secretInput = ""
    var body: some View {
        Form {
            Section("Внешний вид") {
                Picker("Тема", selection: $model.theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                Text("Язык: русский. Настройки хранятся на этом Mac.")
            }
            OverlaySettingsView(controller: model.overlay)
            SpeechSettingsView(speech: model.speech)
            Section("AI-провайдер") {
                ProviderConfigurationView(settings: model.providerSettings)
                Text("API-ключ остаётся только в Keychain. Режим распознавания использует выбранные параметры.")
                Text("Демо не использует ключ. Отправка в собственный API запускается отдельной командой и может тарифицироваться провайдером.").foregroundStyle(.secondary)
                SecureField("API-ключ — только macOS Keychain", text: $secretInput)
                    .textContentType(.password)
                HStack {
                    Button("Сохранить в Keychain") {
                        model.saveSecret(secretInput)
                        secretInput = ""
                    }.disabled(secretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Удалить ключ", role: .destructive) { model.deleteSecret(); secretInput = "" }
                }
                Text("Ключ не хранится в настройках, базе данных или логах. Поле очищается после сохранения и при уходе с экрана.").font(.caption)
            }
            Section("Приватность") {
                LabeledContent("Аналитика приложения", value: "Не используется")
                Text("Захват звука запускается отдельно в разделе «Звук». Запись экрана в файл отсутствует.")
                LabeledContent("История демо", value: "Только в памяти")
                Text("Сохранённые встречи можно экспортировать и удалить в разделе «Встречи». Снимки и аудиобуфер не записываются в историю.").foregroundStyle(.secondary)
            }
            Section("Знакомство") {
                Button("Повторить вводный маршрут") { model.showOnboarding = true }
            }
        }.formStyle(.grouped).navigationTitle("Настройки")
            .onDisappear { secretInput = "" }
    }
}

@MainActor
struct DiagnosticsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("Разрешения macOS") {
                LabeledContent("Микрофон", value: model.microphone.title)
                HStack {
                    Button("Запросить микрофон") { Task { await model.requestMicrophone() } }
                        .disabled(model.microphone != .notRequested)
                    Button("Открыть настройки микрофона") { openSettings(screen: false) }
                }
                LabeledContent("Экран и системный звук", value: model.screen.title)
                HStack {
                    Button("Запросить доступ к экрану") { model.requestScreen() }.disabled(model.screen == .granted)
                    Button("Открыть настройки экрана") { openSettings(screen: true) }
                }
                Button("Обновить статусы") { model.refreshPermissions() }
                Text("Системные настройки → Конфиденциальность и безопасность → Микрофон / Запись экрана и системного аудио. Отрицательный результат проверки экрана не позволяет отличить отказ от ещё не запрошенного доступа.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Что сейчас проверяется") {
                Text("Статусы разрешений, состояние рабочего окна и локальные метрики. Эти проверки не начинают захват звука или экрана.")
                Text("Реальный тест микрофона, системного звука и совместимости с трансляцией запускается вручную в соответствующих разделах.").foregroundStyle(.secondary)
            }
            Section("Рабочее окно") {
                LabeledContent("Окно подсказок", value: model.overlay.isVisible ? "Показано" : "Скрыто")
                LabeledContent("Пропуск кликов", value: model.overlay.isClickThrough ? "Включён" : "Выключен")
                LabeledContent("Непрозрачность", value: "\(Int(model.overlay.preferences.opacity * 100))%")
                LabeledContent("Глобальные сочетания", value: model.overlay.preferences.shortcutsEnabled
                               ? "\(model.overlay.hotkeys.registeredCount) зарегистрировано" : "Выключены")
                LabeledContent("Последняя глобальная команда",
                               value: model.overlay.hotkeys.lastTriggeredAction?.title ?? "Не получена")
                if let time = model.overlay.hotkeys.lastTriggeredAt {
                    LabeledContent("Время команды", value: time.formatted(date: .omitted, time: .standard))
                    Button("Очистить отметку команды") { model.overlay.hotkeys.clearLastTrigger() }
                }
                Text("Для ручной проверки оставьте этот экран открытым, перейдите в другое приложение и нажмите сочетание. Сохраняются только название команды и время в памяти; введённые символы не записываются.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.overlay.hotkeys.issues.isEmpty {
                    ForEach(model.overlay.hotkeys.issues, id: \.self) { issue in
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack {
                    Button(model.overlay.isVisible ? "Скрыть рабочее окно" : "Показать рабочее окно") {
                        model.overlay.toggle()
                    }
                    Button("Вернуть ввод") { model.overlay.focusInput() }
                    Button(model.overlay.isClickThrough ? "Принимать клики" : "Пропускать клики") {
                        model.overlay.toggleClickThrough()
                    }.disabled(!model.overlay.isVisible)
                }
                Divider()
                LabeledContent("Тест ScreenCaptureKit", value: model.overlay.compatibilityResult.title)
                Button(model.overlay.compatibilityResult == .running ? "Проверяем…" : "Проверить попадание окна в снимок") {
                    model.overlay.testCaptureCompatibility()
                }
                .disabled(model.overlay.compatibilityResult == .running || model.screen != .granted)
                if model.screen != .granted {
                    Text("Для теста нужен разрешённый доступ к записи экрана. Сам тест запускается только этой кнопкой.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Результат относится только к ScreenCaptureKit на этом Mac в момент проверки. Сторонние программы могут захватывать экран иначе; абсолютная невидимость не гарантируется.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Рабочее окно остаётся поверх обычных окон и может быть видно в трансляции экрана. Режим пропуска кликов переключается в настройках окна или глобальным сочетанием.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Локальная производительность") {
                latencyRows(title: "STT", first: model.transcription.lastFirstEventMilliseconds,
                            total: model.transcription.lastRequestMilliseconds,
                            queue: model.transcription.lastQueueWaitMilliseconds,
                            firstLabel: "первое событие",
                            succeeded: model.transcription.lastRequestSucceeded)
                latencyRows(title: "LLM", first: model.conversation.lastFirstTokenMilliseconds,
                            total: model.conversation.lastLLMRequestMilliseconds,
                            firstLabel: "первый токен",
                            succeeded: model.conversation.lastLLMRequestSucceeded)
                Button("Очистить измерения") {
                    model.transcription.clearLatencyMetrics()
                    model.conversation.clearLatencyMetrics()
                }
                .disabled((model.transcription.lastRequestMilliseconds == nil && model.conversation.lastLLMRequestMilliseconds == nil) ||
                          model.transcription.isBusy || model.conversation.isGenerating)
                Text("Значения хранятся только в памяти до очистки или перезапуска. Текст, аудио, изображения, URL и ключи в измерения не входят.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Локальная база") {
                if let result = model.databaseLatency {
                    LabeledContent("Количество чтений", value: "\(result.sampleCount)")
                    LabeledContent("Минимум", value: milliseconds(result.minimumMilliseconds))
                    LabeledContent("p95", value: milliseconds(result.p95Milliseconds))
                        .foregroundStyle(result.p95Milliseconds < 100 ? Color.primary : .orange)
                    LabeledContent("Максимум", value: milliseconds(result.maximumMilliseconds))
                    Text(result.p95Milliseconds < 100 ? "Текущий замер укладывается в целевой бюджет <100 мс." : "Текущий замер выше целевого бюджета <100 мс.")
                        .font(.caption).foregroundStyle(result.p95Milliseconds < 100 ? Color.secondary : .orange)
                } else {
                    Text("Замер ещё не запускался.").foregroundStyle(.secondary)
                }
                Button(model.isMeasuringDatabase ? "Измеряем…" : "Измерить 20 локальных чтений") {
                    Task { await model.measureDatabaseLatency() }
                }
                .disabled(model.isMeasuringDatabase)
                Text("Тест только читает список встреч активного профиля. Он не выводит содержимое записей и не использует сеть.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Этот Mac") {
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Оперативная память", value: "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) ГБ")
                Text("Серийный номер и идентификатор устройства не собираются.").font(.caption)
            }
        }.formStyle(.grouped).navigationTitle("Диагностика")
            .onAppear { model.refreshPermissions() }
    }
    private func openSettings(screen: Bool) {
        if !model.permissions.openSettings(screen: screen) {
            model.notice = "Откройте Системные настройки → Конфиденциальность и безопасность вручную."
        }
    }
    @ViewBuilder
    private func latencyRows(title: String, first: Int?, total: Int?, queue: Int? = nil,
                             firstLabel: String, succeeded: Bool?) -> some View {
        if let total {
            LabeledContent("\(title): результат", value: succeeded == true ? "Успешно" : "Не завершён")
            if let queue { LabeledContent("\(title): очередь", value: "\(queue) мс") }
            if let first { LabeledContent("\(title): \(firstLabel)", value: "\(first) мс") }
            LabeledContent("\(title): полностью", value: "\(total) мс")
        } else {
            LabeledContent(title, value: "Нет измерений")
        }
    }
    private func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3))) + " мс"
    }
}
