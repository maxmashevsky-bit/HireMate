import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CopilotCore

@MainActor
struct MeetingsView: View {
    @Bindable var app: AppModel
    @State private var deletion: Meeting?
    @State private var deleteChat = false
    @State private var renamedChat = ""
    @State private var search = ""
    @State private var pendingNavigation: Navigation?
    private enum Navigation { case createMeeting, createChat, open(Meeting) }
    private var visibleMeetings: [Meeting] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.conversation.savedMeetings.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }
    var body: some View {
        @Bindable var conversation = app.conversation
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.profile.title).font(.headline)
                TextField("Название встречи", text: $conversation.newMeetingTitle)
                Toggle("Сохранять историю на Mac", isOn: $conversation.saveNewMeetingHistory)
                Button("Создать встречу") { navigate(.createMeeting) }.disabled(conversation.isLoading)
                Divider()
                Text("Сохранённые встречи").font(.subheadline.bold())
                TextField("Поиск по названию", text: $search).textFieldStyle(.roundedBorder)
                Text("Найдено: \(visibleMeetings.count)").font(.caption).foregroundStyle(.secondary)
                List(visibleMeetings) { meeting in
                    HStack {
                        Button(meeting.title) { navigate(.open(meeting)) }.buttonStyle(.plain)
                        Spacer()
                        Button { deletion = meeting } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }.disabled(conversation.isLoading)
                Button("Обновить список") { Task { await conversation.loadLibrary() } }
            }.padding().frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(conversation.meeting.title).font(.title2.bold())
                    Spacer()
                    Label(conversation.meeting.isEphemeral ? "В памяти" : "На Mac", systemImage: conversation.meeting.isEphemeral ? "memorychip" : "internaldrive")
                        .font(.caption)
                    Menu("Экспорт") {
                        Button("Markdown · читаемый текст") { Task { await export(markdown: true) } }
                        Button("JSON · структурированные данные") { Task { await export(markdown: false) } }
                    }.disabled(conversation.isGenerating || conversation.isLoading)
                }
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(conversation.chats) { chat in
                            Button(chat.title) { conversation.requestSwitch(chat.id) }
                                .buttonStyle(.bordered).tint(chat.id == conversation.activeChatID ? DesignTokens.accent : .secondary)
                        }
                    }
                }
                HStack {
                    TextField("Новый поддиалог", text: $conversation.newChatTitle)
                    Button("Создать") { navigate(.createChat) }
                    Button("Удалить текущий", role: .destructive) { deleteChat = true }.disabled(conversation.chats.count < 2)
                }.disabled(conversation.isLoading)
                HStack {
                    TextField("Новое название текущего поддиалога", text: $renamedChat)
                    Button("Переименовать") { Task { await conversation.renameActiveChat(renamedChat) } }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(conversation.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(message.role == .user ? "Вы" : (message.isDemo ? "Демонстрационный образец" : "Ответ AI")).font(.caption.bold())
                                    if message.state != .complete { Text(message.state == .cancelled ? "Остановлено" : "Не завершено").font(.caption).foregroundStyle(.secondary) }
                                }
                                AnswerTextView(text: message.content)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignTokens.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if conversation.isGenerating { AnswerTextView(text: conversation.streamingText.isEmpty ? "Ожидание ответа…" : conversation.streamingText) }
                    }
                }
                if app.providerSettings.configuration.mode == .remote {
                    Toggle("Разрешаю отправить вопрос, подтверждённые факты и историю этого поддиалога в API", isOn: $conversation.remoteConsent)
                    Text(app.providerSettings.configuration.baseURL).font(.caption).foregroundStyle(.secondary)
                }
                RetrievalSourcesView(app: app)
                ContextUsageView(conversation: conversation)
                AttachmentPreview(conversation: conversation)
                TextEditor(text: $conversation.draft).frame(height: 80).border(.secondary.opacity(0.3))
                HStack {
                    Button(app.providerSettings.configuration.mode == .demo ? "Показать образец" : "Отправить в API") { app.send() }
                        .buttonStyle(.borderedProminent).disabled((conversation.isGenerating || conversation.isLoading) || !InputValidation.canSend(conversation.draft))
                    Button("Остановить") { app.stop() }.disabled(!conversation.isGenerating && !conversation.isLoading)
                    Spacer()
                }
                SpeechControls(app: app)
                Text(conversation.status).font(.caption).foregroundStyle(.secondary)
                if conversation.unsavedMessageCount > 0 {
                    HStack {
                        Text("Сообщений без записи на диск: \(conversation.unsavedMessageCount)").foregroundStyle(.orange)
                        Button("Повторить сохранение") { Task { await conversation.retryUnsavedMessages() } }
                            .disabled(conversation.isSavingMessages)
                    }.font(.caption)
                }
            }.padding().frame(minWidth: 500)
        }
        .navigationTitle("Встречи")
        .task { await conversation.loadLibrary() }
        .confirmationDialog("Продолжить? Незавершённый ответ будет остановлен, черновик вопроса и вложение будут очищены.",
                            isPresented: Binding(get: { pendingNavigation != nil }, set: { if !$0 { pendingNavigation = nil } })) {
            Button("Продолжить и очистить черновик", role: .destructive) {
                if let action = pendingNavigation { perform(action) }
                pendingNavigation = nil
            }
        }
        .confirmationDialog("Удалить встречу и все её поддиалоги?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("Удалить", role: .destructive) { if let meeting = deletion { Task { await conversation.deleteMeeting(meeting) } }; deletion = nil }
        }
        .confirmationDialog("Удалить текущий поддиалог вместе с историей?", isPresented: $deleteChat) {
            Button("Удалить поддиалог", role: .destructive) { Task { await conversation.deleteActiveChat() } }
        }
        .confirmationDialog("Несохранённый вопрос будет очищен. Переключить поддиалог?", isPresented: Binding(get: { conversation.pendingChatID != nil }, set: { if !$0 { conversation.pendingChatID = nil } })) {
            Button("Переключить", role: .destructive) { conversation.confirmSwitch() }
        }
    }
    private func navigate(_ action: Navigation) {
        guard !app.conversation.isLoading else { return }
        if app.isGenerating || !app.question.isEmpty || app.conversation.attachment != nil {
            pendingNavigation = action
        } else { perform(action) }
    }
    private func perform(_ action: Navigation) {
        app.speech.stop()
        Task {
            switch action {
            case .createMeeting: await app.conversation.createMeeting()
            case .createChat: await app.conversation.createSubchat()
            case .open(let meeting): await app.conversation.open(meeting)
            }
        }
    }
    private func export(markdown: Bool) async {
        do {
            let data = try await app.conversation.exportCurrent(markdown: markdown)
            let panel = NSSavePanel()
            panel.allowedContentTypes = markdown ? [UTType(filenameExtension: "md") ?? .plainText] : [.json]
            panel.nameFieldStringValue = markdown ? "meeting-export.md" : "meeting-export.json"
            guard await panel.begin() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            app.notice = "Встреча экспортирована. Ключи и параметры Keychain в экспорт не включаются."
        } catch { app.notice = "Экспорт не выполнен. Проверьте доступность выбранной папки." }
    }
}
