import SwiftUI
import CopilotCore

@MainActor
struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var step = 0
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
                    Text("После знакомства откройте «Звук», разрешите выбранный источник и запустите захват. Индикатор уровня и фрагменты доступны там. Автоматический тест звука в этом маршруте пока отсутствует.")
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
                Button("Назад") { step -= 1 }.disabled(step == 0)
                Spacer()
                Button("Завершить знакомство позже") { model.showOnboarding = false }
                Button(step == 6 ? "Начать демо" : "Далее") {
                    if step == 6 { model.finishOnboarding() } else { step += 1 }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(30).frame(width: 690, height: 450).tint(DesignTokens.accent)
    }
}
