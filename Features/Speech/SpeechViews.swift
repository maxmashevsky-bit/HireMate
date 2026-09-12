import SwiftUI
import AVFoundation

@MainActor
struct SpeechControls: View {
    @Bindable var app: AppModel
    var body: some View {
        HStack {
            Button("Озвучить ответ", systemImage: "speaker.wave.2") { app.speakAnswer() }
                .disabled(app.answer.isEmpty || app.isGenerating)
            if app.speech.isSpeaking {
                Button(app.speech.isPaused ? "Продолжить" : "Пауза") { app.speech.isPaused ? app.speech.resume() : app.speech.pause() }
                Button("Стоп звук") { app.speech.stop() }
            }
        }
    }
}

@MainActor
struct SpeechSettingsView: View {
    @Bindable var speech: SpeechModel
    var body: some View {
        Section("Озвучивание ответа") {
            Picker("Язык", selection: $speech.language) {
                Text("Русский").tag("ru-RU"); Text("English").tag("en-US")
            }
            Picker("Установленный голос", selection: $speech.voiceID) {
                Text("Не выбран").tag("")
                ForEach(speech.compatibleVoices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
            }
            Slider(value: $speech.rate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate) { Text("Скорость") }
            Toggle("Автоматически читать завершённые ответы", isOn: $speech.autoRead)
            Toggle("Понимаю, что голос может попасть в захватываемый системный звук", isOn: $speech.routingAcknowledged)
            Text("Используются установленные системные голоса и системный аудиовыход. Приложение не скачивает голоса и не выбирает отдельное устройство вывода. Авточтение и согласие выключены после запуска.").font(.caption)
            HStack {
                Button("Обновить голоса") { speech.reloadVoices() }
                Button("Остановить озвучивание") { speech.stop() }
            }
            Text(speech.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}
