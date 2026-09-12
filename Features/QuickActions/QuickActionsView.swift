import SwiftUI
import CopilotCore

@MainActor
struct QuickActionsView: View {
    @Bindable var app: AppModel
    @State private var edited: QuickAction?
    var body: some View {
        Form {
            Section("Пять действий") {
                Text("Сочетания \(app.overlay.preferences.shortcutPreset.symbols)1–5 используют соответствующий слот. Другой профиль нужно выбрать вручную: контексты не смешиваются.")
                ForEach(app.quickActions.actions) { action in
                    HStack {
                        Text("\(action.slot)").monospacedDigit()
                        VStack(alignment: .leading) {
                            Text(action.name).font(.headline)
                            Text(action.profileID.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Настроить") { edited = action }
                        Button("Выполнить") { app.requestQuickAction(slot: action.slot) }.disabled(action.profileID != app.profile)
                    }
                }
                Text(app.quickActions.message).font(.caption)
            }
            Section("Снимки") {
                Text("Действие может использовать только заранее просмотренный снимок, приложенный к вопросу. Горячая клавиша сама не делает снимок.")
            }
        }.formStyle(.grouped).navigationTitle("Быстрые действия")
            .sheet(item: $edited) { action in QuickActionEditor(store: app.quickActions, action: action) }
    }
}

@MainActor
private struct QuickActionEditor: View {
    let store: QuickActionStore
    @State var action: QuickAction
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Text("Слот \(action.slot)").font(.headline)
            TextField("Название до 15 символов", text: $action.name)
            Picker("Профиль", selection: $action.profileID) { ForEach(ProfileID.allCases) { Text($0.title).tag($0) } }
            TextEditor(text: $action.prompt).frame(height: 140)
            TextField("Стиль ответа", text: $action.outputStyle)
            TextField("Модель (пусто — текущая)", text: $action.selectedModel)
            Toggle("Приложить уже просмотренный снимок", isOn: $action.includeScreenshot)
            Toggle("Показывать подтверждение перед запуском", isOn: $action.requiresConfirmation)
            Text("Если отключить подтверждение, горячая клавиша сможет запустить запрос при действующем согласии на API.").font(.caption)
            HStack {
                Button("Отмена") { dismiss() }
                Button("Сохранить") { store.save(action); dismiss() }.disabled(!action.isValid)
            }
        }.formStyle(.grouped).padding().frame(width: 570, height: 540)
    }
}

@MainActor
struct QuickActionConfirmation: View {
    @Bindable var app: AppModel
    let action: QuickAction
    var body: some View {
        @Bindable var conversation = app.conversation
        VStack(alignment: .leading, spacing: 14) {
            Text(action.name).font(.title2.bold())
            Text("Профиль: \(action.profileID.title)")
            Text(app.providerSettings.configuration.mode == .demo ? "Демо выдаст фиксированный пример без анализа." : "API: \(app.providerSettings.configuration.baseURL)")
            Text("Модель: \(action.selectedModel.isEmpty ? app.providerSettings.configuration.textModel : action.selectedModel)").font(.caption)
            ScrollView { Text(app.question.isEmpty ? "Без текста вопроса" : app.question).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 150)
            Text(action.prompt).font(.callout)
            if action.includeScreenshot { AttachmentPreview(conversation: app.conversation) }
            else { Text("Снимок в этот запрос не включается.").font(.caption) }
            if app.providerSettings.configuration.mode == .remote {
                Toggle("Разрешаю отправить вопрос, активный контекст и выбранное вложение этому API", isOn: $conversation.remoteConsent)
            }
            HStack {
                Button("Отмена") { app.pendingQuickAction = nil }
                Spacer()
                Button("Выполнить") { app.runQuickAction(action) }.buttonStyle(.borderedProminent)
                    .disabled(app.conversation.isGenerating || action.profileID != app.profile)
            }
        }.padding(24).frame(width: 560)
    }
}
