import SwiftUI
import CopilotCore

@MainActor
struct AudioCaptureView: View {
    @Bindable var audio: AudioSessionModel
    private var sessionBusy: Bool { audio.isRunning || audio.isStarting || audio.isStopping }
    private var fragmentUnavailable: Bool {
        !audio.isRunning || audio.isStopping || audio.isClearing || audio.isPreparingSegment
    }
    var body: some View {
        Form {
            Section("Источники и режим") {
                Picker("Источник", selection: $audio.inputMode) {
                    ForEach(AudioInputMode.allCases) { Text($0.title).tag($0) }
                }.disabled(sessionBusy)
                Picker("Выделение вопроса", selection: $audio.questionMode) {
                    ForEach(AudioQuestionMode.allCases) { Text($0.title).tag($0) }
                }.disabled(sessionBusy)
                Toggle("Участники согласны на захват звука для этой встречи", isOn: $audio.consent)
                    .disabled(sessionBusy)
                HStack {
                    Button(audio.isStarting ? "Подключение…" : "Начать захват") { audio.start() }
                        .disabled(!audio.consent || sessionBusy || audio.isClearing)
                    Button(audio.isStopping ? "Остановка…" : "Остановить") { Task { await audio.stop() } }
                        .disabled(audio.isStopping || (!audio.isRunning && !audio.isStarting))
                    if audio.isRunning { Label("ЗВУК · \(Int(audio.elapsed)) с", systemImage: "mic.fill").foregroundStyle(.red) }
                }
                Text(audio.status).foregroundStyle(.secondary)
                Text("Системный звук: используется первый доступный дисплей. Микрофон: системное устройство ввода. Автовозобновления после сна или отключения устройства нет.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Уровни") {
                ForEach(audio.inputMode.sources) { source in
                    VStack(alignment: .leading) {
                        HStack { Text(source.title); Spacer(); Text(audio.states[source]?.rawValue ?? "Не активен") }
                        ProgressView(value: min(1, Double(audio.levels[source] ?? 0) * 5))
                        Text("Буфер: \(Int(audio.buffered[source] ?? 0)) с").font(.caption)
                    }
                }
            }
            Section("Фрагмент вопроса") {
                if audio.questionMode == .manual {
                    Button(audio.isManualQuestion ? "Завершить вопрос" : "Начать вопрос") {
                        Task { await audio.toggleManualQuestion() }
                    }.disabled(fragmentUnavailable)
                } else if audio.questionMode == .oneShot {
                    Button("Взять последние \(Int(audio.configuration.oneShot)) секунд") {
                        Task { await audio.captureOneShot() }
                    }.disabled(fragmentUnavailable)
                } else {
                    Text("Фрагменты выделяются по уровню сигнала и паузам. Шум может быть принят за речь. Никакая отправка в AI автоматически не выполняется.")
                }
                ForEach(audio.segments) { segment in
                    HStack {
                        Button { audio.selectedSegmentID = segment.id } label: {
                            Label("\(segment.source.title) · \(segment.duration.formatted(.number.precision(.fractionLength(1)))) с",
                                  systemImage: audio.selectedSegmentID == segment.id ? "checkmark.circle.fill" : "waveform")
                        }
                        Spacer()
                        Button("Удалить", role: .destructive) { audio.removeSegment(segment.id) }
                    }
                }
                Button("Очистить буфер и фрагменты", role: .destructive) { Task { await audio.clear() } }
                    .disabled(audio.isClearing || audio.isStopping)
                Text("Только память: сохраняются последние 6 фрагментов. Экран не сохраняется; MP4-запись выключена.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Выделение речи · временный алгоритм по энергии") {
                HStack { Text("Pre-roll"); Slider(value: $audio.configuration.preRoll, in: 0...15, step: 1); Text("\(Int(audio.configuration.preRoll)) с") }
                HStack { Text("Последние секунды"); Slider(value: $audio.configuration.oneShot, in: 5...60, step: 1); Text("\(Int(audio.configuration.oneShot)) с") }
                HStack { Text("Длина фрагмента"); Slider(value: $audio.configuration.chunkSeconds, in: 5...15, step: 1); Text("\(Int(audio.configuration.chunkSeconds)) с") }
                HStack { Text("Пауза микрофона"); Slider(value: $audio.configuration.micSilence, in: 0.5...5, step: 0.5) }
                HStack { Text("Пауза системы"); Slider(value: $audio.configuration.systemSilence, in: 0.5...5, step: 0.5) }
                HStack { Text("Порог"); Slider(value: $audio.configuration.threshold, in: 0.001...0.1) }
                Toggle("Отбрасывать фрагменты без речи", isOn: $audio.configuration.speechCheck)
                Toggle("Очистить буфер после OneShot", isOn: $audio.configuration.clearAfterOneShot)
                Text("Это energy-based VAD, не Silero. Модели не загружаются. Новые параметры применяются при следующем запуске захвата.").font(.caption)
            }.disabled(sessionBusy)
        }.formStyle(.grouped).navigationTitle("Звук")
    }
}
