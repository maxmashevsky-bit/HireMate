import AppKit
import SwiftUI
import CopilotCore

@MainActor
struct DemoView: View {
    @Bindable var model: AppModel
    @State private var pendingProfile: ProfileID?
    @State private var copiedAnswer = false
    @FocusState private var questionFocused: Bool
    private var busy: Bool { model.isGenerating || model.conversation.isLoading }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader
                profileCard
                questionCard
                answerCard
            }.padding(32).frame(maxWidth: DesignTokens.contentWidth)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(DesignTokens.canvas)
            .navigationTitle("Сегодня").task { await model.conversation.loadLibrary() }
            .onChange(of: model.answer) { _, _ in copiedAnswer = false }
            .confirmationDialog("Переключить профиль? Незавершённый ответ будет остановлен, черновики вопроса и заметки будут очищены.",
                                isPresented: Binding(get: { pendingProfile != nil }, set: { if !$0 { pendingProfile = nil } })) {
                Button("Переключить и очистить черновики", role: .destructive) {
                    guard let next = pendingProfile else { return }
                    model.notes.cancelEdits(); model.profile = next; pendingProfile = nil
                }
            }
    }
    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Пространство для подготовки").font(.system(size: 30, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Text("Один профиль. Один разговор. Всё начинается на вашем Mac.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.overlay.toggle() } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 38)).foregroundStyle(DesignTokens.accent)
                    }.buttonStyle(.plain).help("Показать или скрыть окно подсказок")
                        .accessibilityLabel("Окно подсказок")
                }
    }
    private var profileCard: some View {
        @Bindable var conversation = model.conversation
        return InfoCard {
                    Label(model.providerSettings.configuration.mode == .demo ? "Демонстрационный режим" : "Собственный API", systemImage: "sparkles").font(.headline)
                    Text(model.providerSettings.configuration.mode == .demo ? "Готовый учебный пример без анализа вопроса. Захват звука запускается отдельно. Демо не отправляет данные в сеть." : "Вопрос, активный профиль и ограниченная история текущего поддиалога будут отправлены в ваш API после подтверждения.")
                    Picker("Профиль", selection: Binding(get: { model.profile }, set: { selectProfile($0) })) {
                        ForEach(ProfileID.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).padding(.vertical, 6)
                    Text(model.conversation.profile.answerFormat).font(.callout).foregroundStyle(.secondary)
                    if model.providerSettings.configuration.mode == .remote {
                        Divider()
                        Toggle("Разрешаю отправить вопрос, контекст и выбранные вложения в API", isOn: $conversation.remoteConsent)
                        Text(model.providerSettings.configuration.baseURL).font(.caption).textSelection(.enabled)
                    }
                }
    }
    private var questionCard: some View {
        @Bindable var conversation = model.conversation
        return InfoCard {
                    Text("Попробуйте ввод вопроса").font(.headline)
                    AttachmentPreview(conversation: model.conversation)
                    TextEditor(text: $model.question)
                        .font(.body).scrollContentBackground(.hidden)
                        .padding(8).frame(minHeight: 100, maxHeight: 160)
                        .focused($questionFocused)
                        .accessibilityLabel("Вопрос")
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.inputBorder))
                    HStack(spacing: 12) {
                        Text("\(model.question.count) / 4 000 символов · текущий поддиалог")
                            .font(.caption).foregroundStyle(model.question.count > 4_000 ? Color.orange : .secondary)
                        Spacer()
                        Button("Остановить") { model.stop() }.disabled(!model.isGenerating && !model.conversation.isLoading)
                        Button(model.providerSettings.configuration.mode == .demo ? "Показать образец" : "Отправить в API") { model.send() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("Отправить вопрос: ⌘↩")
                            .disabled(!InputValidation.canSend(model.question) || busy ||
                                      (model.providerSettings.configuration.mode == .remote && !conversation.remoteConsent))
                    }
                }
    }
    private var answerCard: some View {
        InfoCard {
                    HStack {
                        Text(isDemoAnswer ? "Учебный ответ" : "Ответ AI").font(.headline)
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                        if !model.answer.isEmpty {
                            Button(copiedAnswer ? "Скопировано" : "Копировать", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                copiedAnswer = NSPasteboard.general.setString(model.answer, forType: .string)
                            }.buttonStyle(.borderless)
                        }
                    }
                    AnswerTextView(text: model.answer.isEmpty ? emptyAnswer : model.answer)
                        .textSelection(.enabled).lineSpacing(4)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    RetrievalSourcesView(app: model)
                    SpeechControls(app: model)
                    Text(model.demoStatus).font(.caption).foregroundStyle(.secondary)
                }
    }
    private var isDemoAnswer: Bool {
        if model.isGenerating { return model.providerSettings.configuration.mode == .demo }
        return model.conversation.messages.last(where: { $0.role == .assistant })?.isDemo ?? (model.providerSettings.configuration.mode == .demo)
    }
    private var emptyAnswer: String {
        if busy { return "Подготавливаем ответ…" }
        return model.providerSettings.configuration.mode == .demo
            ? "Введите вопрос и нажмите «Показать образец». Для каждого профиля подготовлен отдельный учебный пример."
            : "Введите вопрос и разрешите отправку выбранному API. Ответ появится здесь постепенно."
    }
    private func selectProfile(_ next: ProfileID) {
        guard next != model.profile else { return }
        if busy || !model.question.isEmpty || model.conversation.attachment != nil || model.notes.hasEdits {
            pendingProfile = next
        } else { model.profile = next }
    }
}
