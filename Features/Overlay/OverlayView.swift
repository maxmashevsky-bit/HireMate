import AppKit
import SwiftUI
import CopilotCore

@MainActor
struct OverlayView: View {
    @Bindable var model: AppModel
    @Bindable var controller: OverlayController
    @FocusState private var inputFocused: Bool
    @State private var audioSettings = false
    @State private var providerSettings = false
    @State private var appearanceSettings = false
    @State private var newChat = false
    @State private var chatTitle = ""
    @State private var noteQuery = ""
    @State private var selectedNoteID: UUID?
    private var busy: Bool { model.isGenerating || model.conversation.isLoading }
    private var canSend: Bool {
        !busy && InputValidation.canSend(model.question) &&
        (model.providerSettings.configuration.mode == .demo || model.conversation.remoteConsent)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.isClickThrough {
                Text(controller.restoreInputHint)
                    .font(.caption).padding(8).frame(maxWidth: .infinity).background(.yellow.opacity(0.15))
            }
            HStack(spacing: 0) {
                if controller.isChatRailVisible {
                    chatRail
                    Divider()
                }
                VStack(spacing: 0) {
                    history
                    composer
                }
                if controller.isNotesPanelVisible {
                    Divider()
                    notesPanel
                }
            }
        }
        .disabled(controller.isCompatibilityMarkerVisible)
        .accessibilityHidden(controller.isCompatibilityMarkerVisible)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).strokeBorder(.secondary.opacity(0.25)))
        .overlay {
            if controller.isCompatibilityMarkerVisible {
                ZStack(alignment: .topLeading) {
                    Color.black
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 0) {
                            Color(red: 1, green: 0, blue: 0.82)
                            Color(red: 0, green: 1, blue: 0.82)
                        }
                        .frame(width: 128, height: 48)
                        .accessibilityHidden(true)
                        Text("Проверка захвата окна…").foregroundStyle(.white)
                    }
                    .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
            }
        }
        .tint(DesignTokens.accent)
        .preferredColorScheme(model.theme == .system ? nil : (model.theme == .dark ? .dark : .light))
        .onChange(of: controller.focusRequest) { _, _ in inputFocused = true }
        .onChange(of: controller.preferences.opacity) { _, _ in controller.applyOpacity() }
        .confirmationDialog("Очистить черновик и переключить поддиалог?", isPresented: Binding(
            get: { model.conversation.pendingChatID != nil },
            set: { if !$0 { model.conversation.pendingChatID = nil } })) {
                Button("Переключить", role: .destructive) { model.conversation.confirmSwitch() }
            }
        .sheet(isPresented: $newChat) { newChatForm }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "asterisk").font(.title2.bold()).foregroundStyle(DesignTokens.accent)
            Button { toggleAudio() } label: {
                Image(systemName: model.audio.isRunning ? "mic.fill" : "mic")
                    .font(.title3).foregroundStyle(model.audio.isRunning ? Color.red : .primary)
            }.help(model.audio.isRunning ? "Остановить захват" : "Запустить захват")
            Button { audioSettings.toggle() } label: {
                Image(systemName: audioSettings ? "chevron.down" : "chevron.up").font(.headline)
            }
            .help("Режим и настройки микрофона")
            .popover(isPresented: $audioSettings, arrowEdge: .bottom) {
                InterviewAudioMenu(model: model).frame(width: 360)
            }
            Spacer(minLength: 0)
            DragHandle(controller: controller).frame(width: 28, height: 28).accessibilityLabel("Перетащить окно")
            Spacer(minLength: 0)
            Button { providerSettings.toggle() } label: {
                Label(model.providerSettings.configuration.mode == .demo ? "Демо · без сети" : model.providerSettings.configuration.textModel,
                      systemImage: "cpu").lineLimit(1)
            }.popover(isPresented: $providerSettings) {
                Form { ProviderConfigurationView(settings: model.providerSettings) }
                    .formStyle(.grouped).frame(width: 450, height: 480)
            }
            Button { appearanceSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .help("Прозрачность и управление окном")
                .popover(isPresented: $appearanceSettings) { appearanceForm }
            Button { controller.toggleNotesPanel() } label: { Image(systemName: "note.text") }
                .help("Показать или скрыть заметки")
            Button { controller.teleprompter.toggle() } label: { Image(systemName: "text.viewfinder") }
                .help("Показать или скрыть телесуфлёр")
            Button { controller.openMain(.home) } label: { Image(systemName: "house") }.help("Главный экран")
            Button { controller.hide() } label: { Image(systemName: "xmark") }.help("Скрыть окно")
        }.buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func toggleAudio() {
        guard !model.audio.isStarting, !model.audio.isStopping, !model.audio.isClearing else { return }
        if model.audio.isRunning {
            Task { await model.audio.stop() }
        } else if model.audio.consent {
            model.audio.start()
        } else {
            audioSettings = true
        }
    }

    private var chatRail: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(model.conversation.chats.enumerated()), id: \.element.id) { index, chat in
                        Button { model.conversation.requestSwitch(chat.id) } label: {
                            Text("\(index + 1)").font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(chat.id == model.conversation.activeChatID ? DesignTokens.accent.opacity(0.22) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).help(chat.title).accessibilityLabel("Поддиалог: \(chat.title)")
                            .disabled(model.conversation.isLoading)
                    }
                }
            }
            Button { chatTitle = ""; newChat = true } label: { Image(systemName: "plus") }
                .help("Новый поддиалог").disabled(busy)
            Button { controller.openMain(.meetings) } label: { Image(systemName: "clock.arrow.circlepath") }
                .help("Встречи и история")
        }.buttonStyle(.borderless).padding(.vertical, 12).frame(width: 52)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.conversation.meeting.title).lineLimit(1)
                Spacer()
                Text(model.profile.title)
            }.font(.caption).foregroundStyle(.secondary).padding(12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if model.conversation.hiddenMessageCount > 0 || model.conversation.clippedMessageCount > 0 {
                            Label("Скрыто: \(model.conversation.hiddenMessageCount), сокращено: \(model.conversation.clippedMessageCount)",
                                  systemImage: "tray.full")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.conversation.messages.isEmpty && !busy {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Разговор готов").font(.title3.bold())
                                Text("Введите вопрос ниже. Звук и расшифровка запускаются отдельно.")
                                if model.providerSettings.configuration.mode == .demo {
                                    Text("Демо показывает учебный пример без анализа вопроса и без сети.")
                                }
                            }.foregroundStyle(.secondary).padding(.top, 24)
                        }
                        ForEach(model.conversation.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(message.role == .user ? "Вы" : (message.isDemo ? "Учебный пример" : "Ответ AI"))
                                        .font(.caption.bold()).foregroundStyle(.secondary)
                                    Spacer()
                                    if message.state != .complete { Text("Не завершено").font(.caption).foregroundStyle(.secondary) }
                                }
                                AnswerTextView(text: message.content)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == .user ? DesignTokens.accent.opacity(0.10) : DesignTokens.card.opacity(0.55),
                                            in: RoundedRectangle(cornerRadius: 12))
                                .id(message.id)
                        }
                        if busy {
                            HStack(alignment: .top) {
                                ProgressView().controlSize(.small)
                                AnswerTextView(text: model.conversation.streamingText.isEmpty ? "Подготавливаем ответ…" : model.conversation.streamingText)
                            }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
                .onChange(of: model.conversation.messages.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: controller.historyScrollRequest) { _, _ in
                    if controller.historyScrollDirection < 0, let first = model.conversation.messages.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    } else {
                        proxy.scrollTo("latest", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        @Bindable var conversation = model.conversation
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(model.quickActions.actions.filter { $0.profileID == model.profile }) { action in
                        Button(action.name) {
                            if action.requiresConfirmation { controller.openMain(.actions) }
                            model.requestQuickAction(slot: action.slot)
                        }.disabled(busy)
                    }
                }
            }
            Divider()
            ContextUsageView(conversation: conversation)
            if model.providerSettings.configuration.mode == .remote {
                Toggle("Разрешаю отправить вопрос, контекст и вложения выбранному API", isOn: $conversation.remoteConsent).font(.caption)
            }
            AttachmentPreview(conversation: conversation)
            TextField("Введите вопрос…", text: $model.question, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.plain).focused($inputFocused)
                .onSubmit { if canSend { model.send() } }
                .accessibilityLabel("Вопрос в рабочем окне")
                .padding(.vertical, 6)
            HStack(spacing: 14) {
                Button { controller.openMain(.contexts) } label: { Image(systemName: "person.text.rectangle") }.help("Контекст профиля")
                Button { controller.openMain(.screenshot) } label: { Image(systemName: "camera") }.help("Подготовить снимок экрана")
                Button { controller.openMain(.transcription) } label: { Image(systemName: "text.bubble") }.help("Распознать выбранный аудиофрагмент")
                Button { controller.toggleNotesPanel() } label: { Image(systemName: "note.text") }.help("Заметки профиля")
                Button { controller.teleprompter.toggle() } label: { Image(systemName: "text.viewfinder") }.help("Телесуфлёр")
                Spacer()
                Text("\(model.question.count) / 4 000").font(.caption).foregroundStyle(.secondary)
                Button { model.stop() } label: { Image(systemName: "stop.fill") }.disabled(!busy).help("Остановить ответ")
                Button { model.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(!canSend).help("Отправить вопрос").keyboardShortcut(.return, modifiers: .command)
            }.buttonStyle(.borderless)
            SpeechControls(app: model)
            Text(model.demoStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Text("Окно исключено из штатного захвата экрана macOS.").font(.caption2).foregroundStyle(.secondary)
        }.padding(12)
    }

    private var filteredNotes: [Note] {
        let value = noteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return model.notes.notes }
        return model.notes.notes.filter {
            $0.title.localizedCaseInsensitiveContains(value) ||
            $0.markdown.localizedCaseInsensitiveContains(value) ||
            ($0.folder?.localizedCaseInsensitiveContains(value) ?? false)
        }
    }

    private var noteFolders: [String] {
        Array(Set(filteredNotes.map { note in
            let folder = note.folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return folder.isEmpty ? "Без папки" : folder
        })).sorted { left, right in
            if left == "Без папки" { return true }
            if right == "Без папки" { return false }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Заметки").font(.headline)
                Spacer()
                Text(controller.preferences.shortcutLabel(for: .notes)).font(.caption).foregroundStyle(.secondary)
                Button { controller.toggleNotesPanel() } label: { Image(systemName: "xmark") }
                    .help("Закрыть заметки")
            }
            TextField("Поиск по заметкам", text: $noteQuery)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(noteFolders, id: \.self) { folder in
                        DisclosureGroup(folder) {
                            ForEach(filteredNotes.filter {
                                ($0.folder?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                 ? $0.folder! : "Без папки") == folder
                            }) { note in
                                Button(note.title) { selectedNoteID = note.id }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if filteredNotes.isEmpty {
                        ContentUnavailableView("Заметки не найдены", systemImage: "note.text")
                    }
                }
            }
            Divider()
            if let note = model.notes.notes.first(where: { $0.id == selectedNoteID }) {
                Text(note.title).font(.subheadline.bold())
                ScrollView {
                    Text(.init(note.markdown)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Выберите заметку").foregroundStyle(.secondary)
            }
            Button("Открыть редактор заметок") { controller.openMain(.notes) }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var appearanceForm: some View {
        @Bindable var preferences = controller.preferences
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Непрозрачность")
                Spacer()
                TextField("Проценты", value: Binding(
                    get: { Int((preferences.opacity * 100).rounded()) },
                    set: { preferences.opacity = Double(min(100, max(35, $0))) / 100 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityLabel("Непрозрачность окна, проценты")
                Text("%")
            }
            Slider(value: $preferences.opacity, in: 0.35...1)
            Button(controller.isClickThrough ? "Вернуть клики окну" : "Пропускать клики сквозь окно") {
                appearanceSettings = false; controller.toggleClickThrough()
            }
            Divider()
            Text("Положение и размер").font(.headline)
            HStack {
                Text("Сдвинуть")
                Spacer()
                Button { controller.moveBy(dx: -preferences.moveStep, dy: 0) } label: { Image(systemName: "arrow.left") }
                    .help("Сдвинуть влево")
                Button { controller.moveBy(dx: 0, dy: preferences.moveStep) } label: { Image(systemName: "arrow.up") }
                    .help("Сдвинуть вверх")
                Button { controller.moveBy(dx: 0, dy: -preferences.moveStep) } label: { Image(systemName: "arrow.down") }
                    .help("Сдвинуть вниз")
                Button { controller.moveBy(dx: preferences.moveStep, dy: 0) } label: { Image(systemName: "arrow.right") }
                    .help("Сдвинуть вправо")
            }
            HStack {
                Text("Ширина")
                Spacer()
                Button { controller.resizeBy(dx: -preferences.resizeStep, dy: 0) } label: { Image(systemName: "minus") }
                    .help("Уменьшить ширину")
                Button { controller.resizeBy(dx: preferences.resizeStep, dy: 0) } label: { Image(systemName: "plus") }
                    .help("Увеличить ширину")
            }
            HStack {
                Text("Высота")
                Spacer()
                Button { controller.resizeBy(dx: 0, dy: -preferences.resizeStep) } label: { Image(systemName: "minus") }
                    .help("Уменьшить высоту")
                Button { controller.resizeBy(dx: 0, dy: preferences.resizeStep) } label: { Image(systemName: "plus") }
                    .help("Увеличить высоту")
            }
            Button("Перенести на следующий дисплей") {
                appearanceSettings = false
                controller.moveToNextScreen()
            }
            .disabled(controller.connectedScreenCount < 2)
            .help("Восстановить положение окна на следующем подключённом дисплее")
            Text(controller.restoreInputHint).font(.caption)
        }.buttonStyle(.borderless).padding(20).frame(width: 330)
    }

    private var newChatForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Новый поддиалог").font(.headline)
            TextField("Название", text: $chatTitle)
            if !model.question.isEmpty || model.conversation.attachment != nil {
                Text("При создании черновик текущего вопроса и вложение будут очищены.").font(.callout)
            }
            HStack {
                Button("Отмена") { newChat = false }
                Spacer()
                Button("Создать") {
                    model.conversation.newChatTitle = chatTitle
                    Task { await model.conversation.createSubchat() }
                    newChat = false
                }.disabled(chatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
        }.padding(24).frame(width: 360)
    }
}

@MainActor
private struct InterviewAudioMenu: View {
    @Bindable var model: AppModel
    @State private var translationLanguage = "Отключено"

    private var transcriptionModel: String {
        let configured = model.providerSettings.configuration.transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? "Демо-распознавание" : configured
    }

    var body: some View {
        @Bindable var audio = model.audio
        VStack(alignment: .leading, spacing: 6) {
            modeButton(.automatic, title: "VAD", subtitle: "Сам определяет речь", symbol: "waveform")
            modeButton(.manual, title: "Start / Stop", subtitle: "Пишет между двумя нажатиями", symbol: "togglepower")
            modeButton(.oneShot, title: "One-Shot", subtitle: "Берёт последние \(Int(audio.configuration.oneShot)) секунд", symbol: "bolt")
            Divider().padding(.vertical, 5)
            Menu {
                Text(transcriptionModel)
                Button("Открыть настройки моделей") { model.requestedSection = .settings }
            } label: {
                optionRow(title: "Модель расшифровки", value: transcriptionModel, symbol: "cpu")
            }
            Menu {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Button(language.title) { model.transcription.language = language }
                }
            } label: {
                optionRow(title: "Язык расшифровки", value: model.transcription.language.title, symbol: "character.book.closed")
            }
            Menu {
                ForEach(["Отключено", "Русский", "Английский"], id: \.self) { language in
                    Button(language) { translationLanguage = language }
                }
            } label: {
                optionRow(title: "Язык перевода", value: translationLanguage, symbol: "character.bubble")
            }
            Divider().padding(.top, 5)
            Toggle("Согласие участников получено", isOn: $audio.consent)
                .font(.caption).disabled(audio.isRunning || audio.isStarting || audio.isStopping)
            if audio.isRunning {
                Label("Захват включён · \(Int(audio.elapsed)) с", systemImage: "record.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(DesignTokens.card)
    }

    private func modeButton(_ mode: AudioQuestionMode, title: String, subtitle: String, symbol: String) -> some View {
        Button {
            guard !model.audio.isRunning, !model.audio.isStarting, !model.audio.isStopping else { return }
            model.audio.questionMode = mode
        } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.title3).frame(width: 28).foregroundStyle(mode == model.audio.questionMode ? DesignTokens.accent : .primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(mode == model.audio.questionMode ? DesignTokens.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(model.audio.isRunning || model.audio.isStarting || model.audio.isStopping)
    }

    private func optionRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold())
        }
        .contentShape(Rectangle()).padding(.horizontal, 10).padding(.vertical, 8)
    }
}

@MainActor
private struct DragHandle: NSViewRepresentable {
    let controller: OverlayController
    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.controller = controller
        return view
    }
    func updateNSView(_ nsView: HandleView, context: Context) { nsView.controller = controller }

    final class HandleView: NSView {
        weak var controller: OverlayController?
        override func mouseDown(with event: NSEvent) { controller?.startDragging(event) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.setFill()
            for x in [CGFloat(8), CGFloat(14)] {
                for y in [CGFloat(8), CGFloat(14), CGFloat(20)] {
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2)).fill()
                }
            }
        }
    }
}
