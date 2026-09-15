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
    @State private var includeVacancy = false
    @State private var pendingNavigation: Navigation?
    private enum Navigation { case createMeeting, createChat, open(Meeting) }
    private var visibleMeetings: [Meeting] { app.conversation.savedMeetings }
    var body: some View {
        @Bindable var conversation = app.conversation
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HMSectionHeader(title: "Список встреч", subtitle: "Всего встреч: \(conversation.savedMeetings.count)")
                HMPanel {
                    HStack(spacing: 12) {
                        TextField("Название встречи, например: Собеседование в Ozon", text: $conversation.newMeetingTitle)
                            .textFieldStyle(.plain).padding(10)
                            .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignTokens.inputBorder))
                        Button("Указать информацию о вакансии", systemImage: "briefcase") { includeVacancy.toggle() }
                            .buttonStyle(.bordered)
                        Button("Создать", systemImage: "plus") { navigate(.createMeeting) }
                            .buttonStyle(HMPrimaryButtonStyle()).disabled(conversation.isLoading)
                    }
                    if includeVacancy {
                        HStack { TextField("Компания", text: .constant("")); TextField("Вакансия", text: .constant("")); TextField("Этап", text: .constant("")) }
                    }
                }
                HStack {
                    Text("Группировать").font(.headline)
                    Spacer()
                    Picker("Группировать", selection: .constant("По дате")) { Text("По дате"); Text("По компании") }.frame(width: 150)
                }
                if visibleMeetings.isEmpty {
                    HMPanel {
                        ContentUnavailableView("Встреч пока нет", systemImage: "bubble.left.and.bubble.right", description: Text("Введите название и создайте первую встречу."))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Сегодня").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(visibleMeetings) { meeting in
                            meetingRow(meeting)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: DesignTokens.contentWidth)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(DesignTokens.canvas)
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

    private func meetingRow(_ meeting: Meeting) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title).font(.headline)
                Text("Вакансия не указана").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(meeting.updatedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            Label("1", systemImage: "bubble.left.and.bubble.right").font(.caption).foregroundStyle(.secondary)
            Button { Task { await app.conversation.open(meeting); app.overlay.show() } } label: { Image(systemName: "play.fill") }
                .buttonStyle(HMPrimaryButtonStyle()).help("Продолжить встречу")
            Button { } label: { Image(systemName: "link") }.help("Связать с вакансией")
            Button { app.requestedSection = .notes } label: { Image(systemName: "note.text") }.help("Открыть заметки")
            Button { renamedChat = meeting.title } label: { Image(systemName: "pencil") }.help("Переименовать")
            Button { deletion = meeting } label: { Image(systemName: "trash") }.help("Удалить")
        }
        .buttonStyle(.borderless)
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
