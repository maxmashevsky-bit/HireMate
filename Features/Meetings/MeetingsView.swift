import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CopilotCore

@MainActor
struct MeetingsView: View {
    @Bindable var app: AppModel
    var searchQuery = ""
    @State private var deletion: Meeting?
    @State private var deleteChat = false
    @State private var renameTarget: Meeting?
    @State private var renameTitle = ""
    @State private var pendingNavigation: Navigation?
    private enum Navigation { case createMeeting, createChat, open(Meeting) }
    private var visibleMeetings: [Meeting] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.conversation.savedMeetings.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }
    private var meetingDays: [Date] {
        Array(Set(visibleMeetings.map { Calendar.current.startOfDay(for: $0.createdAt) })).sorted(by: >)
    }
    var body: some View {
        @Bindable var conversation = app.conversation
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HMSectionHeader(title: "Список встреч", subtitle: "Всего встреч: \(conversation.savedMeetings.count)")
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Найдено встреч: \(visibleMeetings.count)").font(.caption).foregroundStyle(.secondary)
                }
                HMPanel {
                    HStack(spacing: 12) {
                        TextField("Название встречи, например: Собеседование в Ozon", text: $conversation.newMeetingTitle)
                            .textFieldStyle(.plain).padding(10)
                            .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignTokens.inputBorder))
                        Button("Создать", systemImage: "plus") { navigate(.createMeeting) }
                            .buttonStyle(HMPrimaryButtonStyle()).disabled(conversation.isLoading)
                    }
                    Toggle("Сохранять встречу и историю на этом Mac", isOn: $conversation.saveNewMeetingHistory)
                        .disabled(conversation.isLoading)
                    Text(conversation.saveNewMeetingHistory
                         ? "Встреча и поддиалоги будут доступны в списке после перезапуска."
                         : "История только в памяти: встреча не попадёт в список и исчезнет после смены встречи или выхода.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(conversation.status).font(.caption).foregroundStyle(.secondary)
                }
                if visibleMeetings.isEmpty {
                    HMPanel {
                        ContentUnavailableView(conversation.savedMeetings.isEmpty ? "Встреч пока нет" : "Встречи не найдены",
                                               systemImage: "bubble.left.and.bubble.right",
                                               description: Text(conversation.savedMeetings.isEmpty ? "Введите название и создайте первую встречу." : "Измените или очистите поисковый запрос."))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(meetingDays, id: \.self) { day in
                            Text(day.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(visibleMeetings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }) { meeting in
                                meetingRow(meeting)
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth: DesignTokens.contentWidth)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(DesignTokens.canvas)
        .task { await conversation.loadLibrary() }
        .sheet(item: $renameTarget) { meeting in
            VStack(alignment: .leading, spacing: 16) {
                Text("Переименовать встречу").font(.title2.bold())
                TextField("Название", text: $renameTitle)
                    .textFieldStyle(.roundedBorder).disabled(conversation.isLoading)
                Text(conversation.status).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Отмена") { renameTarget = nil }.keyboardShortcut(.cancelAction)
                        .disabled(conversation.isLoading)
                    Spacer()
                    Button(conversation.isLoading ? "Сохранение…" : "Сохранить") {
                        Task {
                            if await conversation.renameMeeting(meeting, to: renameTitle) { renameTarget = nil }
                        }
                    }.keyboardShortcut(.defaultAction)
                        .disabled(conversation.isLoading || renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameTitle.count > 120)
                }
            }.padding(24).frame(width: 420)
        }
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

    private func meetingRow(_ meeting: Meeting) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title).font(.headline)
                Text("Вакансия не указана").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(meeting.updatedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            Label(app.conversation.meetingOverviews[meeting.id].map { "\($0.subchatCount)" } ?? "—", systemImage: "bubble.left.and.bubble.right")
                .font(.caption).foregroundStyle(.secondary).help("Поддиалоги")
            Label(app.conversation.meetingOverviews[meeting.id].map { "\($0.messageCount)" } ?? "—", systemImage: "text.bubble")
                .font(.caption).foregroundStyle(.secondary).help("Сообщения")
            Button { navigate(.open(meeting)) } label: { Image(systemName: "play.fill") }
                .buttonStyle(HMPrimaryButtonStyle()).help("Продолжить встречу")
            Button { } label: { Image(systemName: "link") }.disabled(true).help("Связь с вакансией пока недоступна")
            Button { app.requestedSection = .notes } label: { Image(systemName: "note.text") }.help("Открыть заметки")
            Button { renameTitle = meeting.title; renameTarget = meeting } label: { Image(systemName: "pencil") }.help("Переименовать")
            Button { deletion = meeting } label: { Image(systemName: "trash") }.help("Удалить")
        }
        .buttonStyle(.borderless)
        .disabled(app.conversation.isLoading)
        .padding(13)
        .background(DesignTokens.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(DesignTokens.hairline))
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
            case .createMeeting:
                let previousID = app.conversation.meeting.id
                await app.conversation.createMeeting()
                if app.conversation.meeting.id != previousID { app.overlay.show() }
            case .createChat: await app.conversation.createSubchat()
            case .open(let meeting):
                await app.conversation.open(meeting)
                if app.conversation.meeting.id == meeting.id { app.overlay.show() }
            }
        }
    }
    private func export(markdown: Bool) async {
        do {
            let transcript = try app.transcription.timelineForExport(meetingID: app.conversation.meeting.id)
            let data = try await app.conversation.exportCurrent(markdown: markdown, transcriptTimeline: transcript)
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
