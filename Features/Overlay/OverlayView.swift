import AppKit
import SwiftUI
import CopilotCore

@MainActor
struct OverlayView: View {
    @Bindable var model: AppModel
    @Bindable var controller: OverlayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @State private var audioSettings = false
    @State private var providerSettings = false
    @State private var appearanceSettings = false
    @State private var newChat = false
    @State private var statusDetails = false
    @State private var chatTitle = ""
    @State private var noteQuery = ""
    @State private var selectedNoteID: UUID?
    @State private var historyScrollPolicy = HistoryScrollPolicy()
    @State private var historyViewport = HistoryViewport()
    @State private var historyPosition = ScrollPosition()
    @State private var userIsScrollingHistory = false
    private var busy: Bool { model.isGenerating || model.conversation.isLoading }
    private var newestFirst: Bool { model.preferences.messageOrder == .newestTop }
    private var latestAnchor: UnitPoint { newestFirst ? .top : .bottom }
    private var historyGroups: [MeetingHistoryGroup] {
        MeetingHistoryGroup.chronological(messages: model.conversation.messages, transcripts: model.transcription.transcriptEntries)
    }
    private var displayedGroups: [MeetingHistoryGroup] { newestFirst ? Array(historyGroups.reversed()) : historyGroups }
    private var latestTranscriptGroupID: String? {
        historyGroups.last { if case .transcripts = $0 { return true }; return false }?.id
    }
    private var latestAnswerID: UUID? { model.conversation.messages.last { $0.role == .assistant }?.id }
    private var canSend: Bool { model.canSendQuestion }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if controller.preferences.showsStatusIndicator, controller.preferences.statusCorner.isTop { statusIndicator }
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
            if controller.preferences.showsStatusIndicator, !controller.preferences.statusCorner.isTop { statusIndicator }
        }
        .disabled(controller.isCompatibilityMarkerVisible)
        .accessibilityHidden(controller.isCompatibilityMarkerVisible)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
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

    private var statusIndicator: some View {
        HStack(spacing: 0) {
            if !controller.preferences.statusCorner.isLeading { Spacer(minLength: 0) }
            Button { statusDetails.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: controller.captureExclusionRequested ? "shield.lefthalf.filled" : "shield.slash")
                    Image(systemName: "cursorarrow.slash").foregroundStyle(.secondary)
                    Image(systemName: controller.isClickThrough ? "hand.point.up.left.and.text" : "hand.point.up.left")
                    Label("\(controller.connectedScreenCount)", systemImage: "display").monospacedDigit()
                }.font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Состояние окна: исключение из захвата \(controller.captureExclusionRequested ? "запрошено" : "не запрошено"), защита курсора не поддерживается, \(controller.isClickThrough ? "клики пропускаются" : "окно принимает клики"), дисплеев \(controller.connectedScreenCount)")
            .help("Показать фактические состояния окна")
            .popover(isPresented: $statusDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Состояние рабочего окна").font(.headline)
                    LabeledContent("Исключение из захвата", value: controller.captureExclusionRequested ? "Запрошено у macOS" : "Не запрошено")
                    LabeledContent("Тест ScreenCaptureKit", value: controller.compatibilityResult.title)
                    LabeledContent("Защита курсора", value: "Не поддерживается")
                    LabeledContent("Клики", value: controller.isClickThrough ? "Пропускаются" : "Принимаются окном")
                    LabeledContent("Дисплеи", value: "\(controller.connectedScreenCount)")
                    LabeledContent("Горячие клавиши", value: "\(controller.hotkeys.registeredCount) зарегистрировано")
                    Text("Запрос исключения не гарантирует защиту во всех программах трансляции. Защита курсора и пропуск кликов — независимые возможности.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(width: 390)
            }
            if controller.preferences.statusCorner.isLeading { Spacer(minLength: 0) }
        }
        .frame(height: 24)
        .background(DesignTokens.elevated.opacity(0.6))
    }

    private var header: some View {
        ZStack {
            WindowDragArea(controller: controller)
                .accessibilityLabel("Перетащить окно")
            HStack(spacing: 14) {
                Image(systemName: "asterisk").font(.title2.bold()).foregroundStyle(DesignTokens.accent)
                ViewThatFits(in: .horizontal) {
                    headerTools
                    ScrollView(.horizontal, showsIndicators: false) { headerTools }.frame(height: 36)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14).padding(.vertical, 8)
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 3, height: 3) }
                    }
                }
            }
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 52)
    }

    private var headerTools: some View {
        HStack(spacing: 14) {
            ForEach(controller.preferences.panelLayout.header) { tool in
                if tool == .provider { Spacer(minLength: 24) }
                panelTool(tool)
            }
            if !controller.preferences.panelLayout.header.contains(.provider) { Spacer(minLength: 24) }
        }
    }

    @ViewBuilder private func panelTool(_ tool: MeetingPanelTool) -> some View {
        switch tool {
        case .audio:
            HStack(spacing: 14) {
                Button { toggleAudio() } label: {
                    Image(systemName: model.audio.isRunning ? "mic.fill" : "mic")
                        .font(.title3).foregroundStyle(model.audio.isRunning ? Color.red : .primary)
                }.help(model.audio.isRunning ? "Остановить захват" : "Запустить захват")
                Button { audioSettings.toggle() } label: {
                    Image(systemName: audioSettings ? "chevron.down" : "chevron.up").font(.headline)
                }.help("Режим и настройки микрофона")
                    .popover(isPresented: $audioSettings, arrowEdge: .bottom) {
                        InterviewAudioMenu(model: model).frame(width: 360)
                    }
            }
        case .provider:
            Button { providerSettings.toggle() } label: {
                Label(model.providerSettings.configuration.mode == .demo ? "Демо · без сети" : model.providerSettings.configuration.textModel,
                      systemImage: tool.icon).lineLimit(1)
            }.popover(isPresented: $providerSettings) {
                Form { ProviderConfigurationView(settings: model.providerSettings) }
                    .formStyle(.grouped).frame(width: 450, height: 480)
            }
        case .appearance:
            Button { appearanceSettings.toggle() } label: { Image(systemName: tool.icon) }
                .help("Прозрачность и управление окном")
                .popover(isPresented: $appearanceSettings) { appearanceForm }
        case .headerNotes, .inputNotes:
            Button { controller.toggleNotesPanel() } label: { Image(systemName: tool.icon) }.help("Показать или скрыть заметки")
        case .headerTeleprompter, .inputTeleprompter:
            Button { controller.teleprompter.toggle() } label: { Image(systemName: tool.icon) }.help("Показать или скрыть телесуфлёр")
        case .home:
            Button { controller.openMain(.meetings) } label: { Image(systemName: tool.icon) }.help("Вернуться к списку встреч")
        case .context:
            Button { controller.openMain(.contexts) } label: { Image(systemName: tool.icon) }.help("Контекст профиля")
        case .screenshot:
            Button { controller.openMain(.screenshot) } label: { Image(systemName: tool.icon) }.help("Подготовить снимок экрана")
        case .transcription:
            Button { controller.openMain(.transcription) } label: { Image(systemName: tool.icon) }.help("Распознать выбранный аудиофрагмент")
        case .stop:
            Button { model.stop() } label: { Image(systemName: tool.icon) }.disabled(!busy).help(tool.title)
        case .send:
            Button { model.send() } label: { Image(systemName: tool.icon).font(.title2) }
                .disabled(!canSend).help(tool.title).keyboardShortcut(.return, modifiers: .command)
        case .speech:
            Menu {
                Button("Озвучить ответ") { model.speakAnswer() }.disabled(model.answer.isEmpty || model.isGenerating)
                if model.speech.isSpeaking {
                    Button(model.speech.isPaused ? "Продолжить" : "Пауза") {
                        model.speech.isPaused ? model.speech.resume() : model.speech.pause()
                    }
                    Button("Остановить озвучивание") { model.speech.stop() }
                }
            } label: { Image(systemName: tool.icon) }.help(tool.title)
        }
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if model.conversation.hiddenMessageCount > 0 || model.conversation.clippedMessageCount > 0 {
                            Label("Скрыто: \(model.conversation.hiddenMessageCount), сокращено: \(model.conversation.clippedMessageCount)",
                                  systemImage: "tray.full")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if newestFirst {
                            Color.clear.frame(height: 1).id("latest")
                            streamingAnswer
                        }
                        ForEach(displayedGroups) { group in
                            switch group {
                            case .message(let message):
                                HistoryMessageView(message: message, isLatestAnswer: message.id == latestAnswerID,
                                                   preferences: model.preferences)
                            case .transcripts(let entries):
                                HistoryTranscriptGroupView(entries: entries, isLatest: group.id == latestTranscriptGroupID,
                                                           preferences: model.preferences)
                            }
                        }
                        if !newestFirst {
                            streamingAnswer
                            Color.clear.frame(height: 1).id("latest")
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
                .scrollPosition($historyPosition)
                .defaultScrollAnchor(latestAnchor, for: .initialOffset)
                .onScrollGeometryChange(for: HistoryViewport.self) { geometry in
                    HistoryViewport(offset: geometry.contentOffset.y,
                                    height: geometry.containerSize.height,
                                    contentHeight: geometry.contentSize.height)
                } action: { _, viewport in
                    historyViewport = viewport
                }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        userIsScrollingHistory = true
                        historyScrollPolicy.beginUserScroll()
                    case .idle:
                        if userIsScrollingHistory {
                            historyScrollPolicy.endUserScroll(nearLatest: historyViewport.nearLatest(order: model.preferences.messageOrder))
                            userIsScrollingHistory = false
                        }
                    default: break
                    }
                }
                .onChange(of: model.conversation.messages.count) { _, _ in
                    followLatest(using: proxy)
                }
                .onChange(of: model.conversation.streamingText) { _, _ in
                    followLatest(using: proxy)
                }
                .onChange(of: model.transcription.transcriptEntries) { _, _ in
                    followLatest(using: proxy)
                }
                .onChange(of: model.transcription.partialText) { _, _ in
                    followLatest(using: proxy)
                }
                .onChange(of: model.conversation.activeChatID) { _, _ in
                    historyScrollPolicy = HistoryScrollPolicy()
                    historyViewport = HistoryViewport()
                    userIsScrollingHistory = false
                    proxy.scrollTo("latest", anchor: latestAnchor)
                }
                .onChange(of: model.preferences.messageOrder) { _, _ in
                    historyScrollPolicy.jumpToLatest()
                    userIsScrollingHistory = false
                    proxy.scrollTo("latest", anchor: latestAnchor)
                }
                .onChange(of: controller.historyScrollRequest) { _, _ in
                    let target = historyViewport.pagedOffset(direction: controller.historyScrollDirection)
                    var viewport = historyViewport; viewport.offset = target
                    historyScrollPolicy.endUserScroll(nearLatest: viewport.nearLatest(order: model.preferences.messageOrder))
                    historyPosition.scrollTo(y: target)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !historyScrollPolicy.followsLatest || historyScrollPolicy.hasUnreadContent {
                        Button("К новым сообщениям", systemImage: newestFirst ? "arrow.up" : "arrow.down") {
                            historyScrollPolicy.jumpToLatest()
                            proxy.scrollTo("latest", anchor: latestAnchor)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small).padding(12)
                    }
                }
            }
        }
    }

    private func followLatest(using proxy: ScrollViewProxy) {
        guard historyScrollPolicy.receivedContent(automatically: controller.preferences.smartAutoScroll) else { return }
        withAnimation(reduceMotion ? nil : .linear(duration: controller.preferences.autoScrollAnimationDuration)) {
            proxy.scrollTo("latest", anchor: latestAnchor)
        }
    }

    @ViewBuilder private var streamingAnswer: some View {
        if model.transcription.isBusy {
            HStack(alignment: .top) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.providerSettings.configuration.mode == .demo ? "Демо: учебный текст…" : "Распознавание…")
                        .font(.caption.bold())
                    Text(model.transcription.partialText.isEmpty ? model.transcription.status : model.transcription.partialText)
                        .font(.system(size: model.preferences.messageFontSize))
                }
            }
        } else if model.transcription.lastRequestSucceeded == false {
            Label(model.transcription.status, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        if busy {
            HStack(alignment: .top) {
                ProgressView().controlSize(.small)
                AnswerTextView(text: model.conversation.streamingText.isEmpty ? "Подготавливаем ответ…" : model.conversation.streamingText)
            }
        }
    }

    private var composer: some View {
        @Bindable var conversation = model.conversation
        return VStack(alignment: .leading, spacing: 8) {
            if controller.preferences.showsQuickActions {
                if controller.preferences.compactQuickActions {
                    Menu("Быстрые действия", systemImage: "bolt") {
                        quickActionButtons
                    }.disabled(busy)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { quickActionButtons }
                    }.frame(height: 32)
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(controller.preferences.panelLayout.input) { panelTool($0) }
                    }
                }.frame(height: 36)
                Spacer()
                Text("\(model.question.count) / 4 000").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.borderless)
            Text(model.demoStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Text("Защита захвата: \(controller.compatibilityResult.title)").font(.caption2).foregroundStyle(.secondary)
        }.padding(12)
    }

    private var quickActionButtons: some View {
        ForEach(model.quickActions.actions.filter { $0.profileID == model.profile }) { action in
            Button(action.name) {
                if action.requiresConfirmation { controller.openMain(.actions) }
                model.requestQuickAction(slot: action.slot)
            }.disabled(busy)
        }
    }

    private var filteredNotes: [Note] {
        model.meetingNotes.notes
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
            TextField("Поиск по заметкам", text: Binding(get: { noteQuery }, set: { noteQuery = String($0.prefix(200)) }))
            Text("\(model.meetingNotes.totalNoteCount) заметок · загружено \(filteredNotes.count)")
                .font(.caption).foregroundStyle(.secondary)
            if model.meetingNotes.isSearching { ProgressView("Поиск заметок…").controlSize(.small) }
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
                    if filteredNotes.isEmpty, !model.meetingNotes.isSearching {
                        ContentUnavailableView("Заметки не найдены", systemImage: "note.text")
                    }
                    if model.meetingNotes.hasMore {
                        Button(model.meetingNotes.isLoadingMore ? "Загрузка…" : "Загрузить ещё 50") {
                            Task { await model.meetingNotes.loadMore() }
                        }.disabled(model.meetingNotes.isSearching || model.meetingNotes.isLoadingMore)
                    }
                }
            }
            Divider()
            if let note = model.meetingNotes.notes.first(where: { $0.id == selectedNoteID }) {
                Text(note.title).font(.subheadline.bold())
                ScrollView {
                    AnswerTextView(text: note.markdown)
                }
            } else {
                Text("Выберите заметку").foregroundStyle(.secondary)
            }
            Button("Открыть редактор заметок") { controller.openMain(.notes) }
        }
        .padding(12)
        .frame(width: 300)
        .task(id: model.profile.rawValue + "\u{0}" + noteQuery) {
            do {
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                model.meetingNotes.query = noteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                await model.meetingNotes.refresh()
            } catch is CancellationError { }
            catch { }
        }
        .onChange(of: model.profile) { _, _ in selectedNoteID = nil; noteQuery = "" }
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
private struct HistoryMessageView: View {
    let message: ChatMessage
    let isLatestAnswer: Bool
    @Bindable var preferences: PreferencesStore
    @State private var expandedOverride: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant {
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedOverride ?? !(preferences.collapseAnswers && (!isLatestAnswer || preferences.collapseLatestAnswer)) },
                    set: { expandedOverride = $0 }
                )) {
                    AnswerTextView(text: message.content).padding(.top, 6)
                } label: { heading }
            } else {
                heading
                AnswerTextView(text: message.content)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? DesignTokens.accent.opacity(0.10) : DesignTokens.card.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var heading: some View {
        HStack {
            Text(message.role == .user ? "Вы" : (message.isDemo ? "Учебный пример" : "Ответ AI"))
                .font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            if message.state != .complete {
                Text(message.state == .failed ? "Ошибка" : "Отменено").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct HistoryTranscriptGroupView: View {
    let entries: [TranscriptEntry]
    let isLatest: Bool
    @Bindable var preferences: PreferencesStore
    @State private var expandedOverride: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedOverride ?? !(preferences.collapseTranscripts && (!isLatest || preferences.collapseLatestTranscript)) },
            set: { expandedOverride = $0 }
        )) {
            ForEach(preferences.messageOrder == .newestTop ? Array(entries.reversed()) : entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.speaker.title).font(.caption.bold())
                        Spacer()
                        if entry.isDemo == true { Text("Демо").font(.caption).foregroundStyle(DesignTokens.accent) }
                        else if entry.isDemo == nil { Text("Источник не указан").font(.caption).foregroundStyle(.secondary) }
                        Text("\(entry.duration.formatted(.number.precision(.fractionLength(1)))) с")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(entry.text).font(.system(size: preferences.messageFontSize)).textSelection(.enabled)
                }.padding(.vertical, 6)
            }
            Text("В памяти текущей встречи. Смена встречи очищает расшифровки.")
                .font(.caption).foregroundStyle(.secondary)
        } label: {
            HStack {
                Label("Расшифровки · \(entries.count)", systemImage: "waveform").font(.caption.bold())
                Spacer()
                let demoCount = entries.filter { $0.isDemo == true }.count
                if demoCount > 0 { Text("Демо: \(demoCount)").font(.caption).foregroundStyle(DesignTokens.accent) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
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
private struct WindowDragArea: NSViewRepresentable {
    let controller: OverlayController
    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.controller = controller
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Область перемещения окна")
        return view
    }
    func updateNSView(_ nsView: HandleView, context: Context) { nsView.controller = controller }

    final class HandleView: NSView {
        weak var controller: OverlayController?
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }
        override func mouseDown(with event: NSEvent) { controller?.startDragging(event) }
    }
}
