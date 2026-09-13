import SwiftUI
import CopilotCore

@MainActor
struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var step = 0
    @State private var audioTest: Task<Void, Never>?
    @State private var audioTestPeak: Float = 0
    @State private var audioTestMessage = ""
    private let titles = ["Добро пожаловать", "Ваши данные остаются на Mac", "Микрофон — по вашему действию",
                          "Доступ к экрану", "Проверка звука", "Выбор провайдера", "Первый контекст"]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Max Interview Copilot", systemImage: "bubble.left.and.text.bubble.right")
                Spacer()
                Text("\(step + 1) из \(titles.count)").foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step + 1), total: Double(titles.count))
            Text(titles[step]).font(.largeTitle.bold())
            Group {
                switch step {
                case 0:
                    Text("Личное пространство Максима Машевского для подготовки к Go-интервью. Помощь и запись предназначены для разрешённых встреч и согласованных сценариев доступности. Приложение не обещает прохождение интервью или невидимость.")
                case 1:
                    Text("Настройки и выбранная для сохранения история остаются на Mac. API-ключи хранятся в macOS Keychain. Демо не использует сеть; внешний API получает данные только после вашего согласия и команды.")
                case 2:
                    Text("Микрофон: \(model.microphone.title). Можно продолжить без разрешения. Захват включается отдельно в разделе «Звук».")
                    Button("Разрешить микрофон") { Task { await model.requestMicrophone() } }.disabled(model.microphone != .notRequested)
                case 3:
                    Text("Экран: \(model.screen.title). Можно пропустить. Даже после разрешения приложение не начнёт захват автоматически.")
                    Button("Запросить доступ к экрану") { model.requestScreen() }.disabled(model.screen == .granted)
                case 4:
                    Text("Нажмите кнопку и говорите обычным голосом три секунды. Проверка использует только микрофон, ничего не записывает на диск и не обращается к сети.")
                    ProgressView(value: min(1, Double(audioTestPeak) * 5))
                    HStack {
                        Button(audioTest != nil ? "Микрофон проверяется…" : "Проверить микрофон") {
                            startAudioTest()
                        }
                        .disabled(model.microphone != .granted || audioTest != nil || model.audio.isRunning || model.audio.isStarting || model.audio.isStopping)
                        if audioTest != nil {
                            Button("Остановить проверку") { audioTest?.cancel() }
                        }
                    }
                    if model.microphone != .granted {
                        Text("Сначала разрешите микрофон на предыдущем шаге.").foregroundStyle(.secondary)
                    } else if !audioTestMessage.isEmpty {
                        Text(audioTestMessage).foregroundStyle(audioTestPeak > 0.001 ? .green : .secondary)
                    }
                case 5:
                    Text("По умолчанию используется Fake Provider: готовые учебные примеры без сети и API-ключа. Собственный API можно настроить отдельно. Демо не анализирует введённый вопрос.")
                default:
                    Text("Выберите формат подготовки. Контексты разделены; неподтверждённый опыт не используется.")
                    Picker("Контекст", selection: $model.profile) {
                        ForEach(ProfileID.allCases) { Text($0.title).tag($0) }
                    }.disabled(model.notes.hasEdits)
                    Text(model.profile.format).foregroundStyle(.secondary)
                }
            }.font(.body)
            Spacer()
            HStack {
                Button("Назад") { step -= 1 }.disabled(step == 0 || audioTest != nil)
                Spacer()
                Button("Завершить знакомство позже") { model.showOnboarding = false }.disabled(audioTest != nil)
                Button(step == 6 ? "Начать демо" : "Далее") {
                    if step == 6 { model.finishOnboarding() } else { step += 1 }
                }.buttonStyle(.borderedProminent).disabled(audioTest != nil)
            }
        }
        .padding(30).frame(width: 690, height: 450).tint(DesignTokens.accent)
        .onDisappear {
            guard audioTest != nil else { return }
            audioTest?.cancel()
            Task { await model.audio.stop(reason: "Проверка микрофона остановлена") }
        }
    }

    private func startAudioTest() {
        guard audioTest == nil, model.microphone == .granted,
              !model.audio.isRunning, !model.audio.isStarting, !model.audio.isStopping else { return }
        let oldMode = model.audio.inputMode
        let oldQuestionMode = model.audio.questionMode
        let oldConsent = model.audio.consent
        audioTestPeak = 0
        audioTestMessage = "Подключаем микрофон…"
        model.audio.inputMode = .microphone
        model.audio.questionMode = .manual
        model.audio.consent = true
        model.audio.start()
        audioTest = Task { @MainActor in
            var started = false
            for _ in 0..<30 {
                if Task.isCancelled { break }
                if model.audio.isRunning { started = true; break }
                if !model.audio.isStarting { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if started {
                audioTestMessage = "Говорите…"
                for _ in 0..<30 {
                    if Task.isCancelled { break }
                    audioTestPeak = max(audioTestPeak, model.audio.levels[.microphone] ?? 0)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let wasCancelled = Task.isCancelled
            let startFailure = model.audio.status
            await model.audio.stop(reason: "Проверка микрофона завершена")
            model.audio.inputMode = oldMode
            model.audio.questionMode = oldQuestionMode
            model.audio.consent = oldConsent
            audioTest = nil
            if wasCancelled {
                audioTestMessage = "Проверка остановлена."
            } else if !started {
                audioTestMessage = "Не удалось начать проверку: \(startFailure)"
            } else if audioTestPeak > 0.001 {
                audioTestMessage = "Микрофон работает. Сигнал получен локально."
            } else {
                audioTestMessage = "Микрофон подключён, но сигнал слишком тихий. Проверьте устройство ввода macOS."
            }
        }
    }
}
