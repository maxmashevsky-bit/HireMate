import SwiftUI
import CopilotCore

@MainActor
struct TranscriptionView: View {
    @Bindable var app: AppModel
    @State private var pendingBatch: [AudioSegment] = []
    @State private var confirmBatch = false
    @State private var confirmLive = false
    var body: some View {
        @Bindable var transcription = app.transcription
        Form {
            Section("Распознавание выбранного фрагмента") {
                Text(app.providerSettings.configuration.mode == .demo ? "Демо без сети: фиксированный учебный текст." : "Собственный API: выбранный звук будет отправлен на указанный вами сервер.")
                if let segment = app.audio.selectedSegment {
                    LabeledContent("Источник", value: segment.source.title)
                    LabeledContent("Длительность", value: "\(segment.duration.formatted(.number.precision(.fractionLength(1)))) с")
                    Picker("Язык", selection: $transcription.language) {
                        ForEach(TranscriptionLanguage.allCases) { Text($0.title).tag($0) }
                    }.disabled(transcription.isBusy || transcription.isLiveEnabled)
                    if app.providerSettings.configuration.mode == .remote {
                        Text(app.providerSettings.configuration.baseURL).font(.caption).textSelection(.enabled)
                        Toggle("Разрешаю отправить выбранный аудиофрагмент этому провайдеру", isOn: $transcription.remoteConsent)
                    }
                    HStack {
                        Button("Распознать") {
                            transcription.start(segment: segment, configuration: app.providerSettings.configuration, vocabulary: app.conversation.profile.technologies)
                        }.disabled(transcription.isBusy || transcription.isLiveEnabled)
                    }
                } else { Text("Сначала выделите вопрос или возьмите фрагмент из буфера в разделе «Звук».") }
                Text(transcription.status).foregroundStyle(.secondary)
                Button("Отменить распознавание и очередь") { transcription.cancel() }.disabled(!transcription.isBusy)
            }
            Section("Очередь накопленных фрагментов") {
                Text("До 6 фрагментов, по одному запросу за раз. Новые фрагменты не добавляются автоматически. При ошибке очередь останавливается.")
                    .font(.caption)
                Button("Распознать накопленные фрагменты (\(app.audio.segments.count))") {
                    pendingBatch = app.audio.segments
                    confirmBatch = true
                }.disabled(transcription.isBusy || transcription.isLiveEnabled || app.audio.segments.isEmpty)
                if transcription.isBatchRunning { Text("Осталось фрагментов: \(transcription.remainingCount)") }
                ForEach(transcription.batchResults) { entry in
                    VStack(alignment: .leading) {
                        Text("\(entry.source.title) · \(entry.isDemo ? "демо" : "распознано")").font(.headline)
                        Text(entry.text).lineLimit(3)
                        Button("Открыть текст для правки") { transcription.selectBatchResult(entry) }
                            .disabled(transcription.isBusy)
                    }
                }
            }
            Section("Новые фрагменты во время захвата") {
                Text("Opt-in режим принимает только завершённые аудиофрагменты, обрабатывает их последовательно и не запускает LLM. В ожидании хранится максимум 5 фрагментов.")
                    .font(.caption)
                if transcription.isLiveEnabled {
                    LabeledContent("В очереди", value: "\(transcription.liveQueuedCount)")
                    if transcription.liveDroppedCount > 0 {
                        LabeledContent("Пропущено из-за перегрузки", value: "\(transcription.liveDroppedCount)")
                            .foregroundStyle(.orange)
                    }
                    Button("Остановить автоматическую очередь", role: .destructive) {
                        transcription.disableLive()
                    }
                } else {
                    Button("Включить автоматическую очередь") {
                        if app.providerSettings.configuration.mode == .remote { confirmLive = true }
                        else {
                            transcription.enableLive(configuration: app.providerSettings.configuration,
                                                     vocabulary: app.conversation.profile.technologies)
                        }
                    }.disabled(transcription.isBusy)
                }
            }
            Section("Текст") {
                if let suggestion = transcription.suggestedQuestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Возможный вопрос собеседника", systemImage: "questionmark.bubble")
                            .font(.headline)
                        Text(suggestion).textSelection(.enabled)
                        HStack {
                            Button("Перенести в поле вопроса") {
                                if let question = transcription.takeSuggestedQuestion() { app.question = question }
                            }
                            Button("Скрыть") { transcription.dismissSuggestedQuestion() }
                        }
                    }
                }
                if !transcription.partialText.isEmpty { Text(transcription.partialText).italic().foregroundStyle(.secondary) }
                TextEditor(text: $transcription.editableText).frame(minHeight: 180).disabled(transcription.isBusy)
                if let result = transcription.result {
                    Text("\(result.source.title) · \(result.isDemo ? "демо" : "распознано провайдером") · уверенность: не предоставлена")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Использовать как вопрос") { app.question = transcription.editableText }
                    .disabled(transcription.editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || transcription.isBusy)
                Text("Передача текста в поле вопроса не запускает генерацию и не отправляет его в сеть.").font(.caption)
            }
            Section("Локальная хронология") {
                Text("Только финальные реплики. Системный звук помечается как собеседник, микрофон — как Максим. Хранится до 50 реплик или 12 000 символов в памяти.")
                    .font(.caption)
                ForEach(transcription.transcriptEntries.suffix(10)) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.speaker.title).font(.headline)
                        Text(entry.text).lineLimit(3).textSelection(.enabled)
                    }
                }
                Toggle("Добавлять последние реплики в следующий AI-запрос", isOn: $transcription.includeRecentContext)
                    .disabled(transcription.transcriptEntries.isEmpty)
                if transcription.includeRecentContext {
                    Text("Будет добавлено до 4 000 символов. Перед отправкой действует общее подтверждение API в активном профиле. История остаётся недоверенными данными и не может менять системные правила.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Очистить локальную хронологию", role: .destructive) {
                    transcription.clearTranscript()
                }.disabled(transcription.isBusy || transcription.transcriptEntries.isEmpty)
            }
        }.formStyle(.grouped).navigationTitle("Расшифровка")
            .confirmationDialog("Распознать \(pendingBatch.count) фрагментов?", isPresented: $confirmBatch) {
                Button("Начать очередь") {
                    transcription.startBatch(segments: pendingBatch, configuration: app.providerSettings.configuration,
                                             vocabulary: app.conversation.profile.technologies, remoteBatchConsent: true)
                    pendingBatch = []
                }
                Button("Отмена", role: .cancel) { pendingBatch = [] }
            } message: {
                Text(app.providerSettings.configuration.mode == .demo
                     ? "Демо покажет учебные тексты без анализа аудио и без сети. Текущие правки текста будут заменены."
                     : "Все перечисленные фрагменты микрофона и системы будут отправлены на \(app.providerSettings.configuration.baseURL). Текущие правки текста будут заменены.")
            }
            .confirmationDialog("Включить автоматическую отправку фрагментов?", isPresented: $confirmLive) {
                Button("Включить") {
                    transcription.enableLive(configuration: app.providerSettings.configuration,
                                             vocabulary: app.conversation.profile.technologies,
                                             remoteConsent: true)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Каждый новый завершённый аудиофрагмент будет отдельно отправлен на \(app.providerSettings.configuration.baseURL), пока вы не отключите режим или не произойдёт ошибка. Ответы в LLM автоматически не отправляются.")
            }
    }
}
