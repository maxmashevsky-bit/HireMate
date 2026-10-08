import AppKit
import SwiftUI
import CopilotCore

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var pane: HMSettingsPane = .audioCapture
    @State private var secretInput = ""
    @State private var recordingEnabled = false
    @State private var recordSystemAudio = true
    @State private var fps = "30 fps"
    @State private var resolution = "4K"
    @State private var quality = "CRF 18"
    @State private var bitrate = "192 kbps"
    @State private var hotkeySearch = ""
    @State private var editingHotkey: GlobalHotkeyService.Action?
    @State private var editingModelSlot: ModelSlot?
    @State private var blocksMetaKeys = false
    @State private var editingQuickAction: QuickAction?
    @State private var disguiseName = "HireMate"
    @State private var disguiseIcon = "briefcase.fill"
    @State private var settingsSearch = ""
    @State private var storageSnapshot: StorageSnapshot?
    @State private var storageIsLoading = false
    @State private var storageIssue: String?
    private let storageInspector: any StorageInspecting

    init(model: AppModel, storageInspector: any StorageInspecting = LocalStorageInspector()) {
        self.model = model
        self.storageInspector = storageInspector
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Поиск по названию…", text: $settingsSearch).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).frame(height: 38)
                .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 9))
                .padding(16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HMSectionHeader(title: pane.title, subtitle: pane.subtitle)
                        settingsPage
                    }
                    .padding(.horizontal, 22).padding(.bottom, 22)
                    .frame(maxWidth: 980, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .background(DesignTokens.canvas)
        }
        .onDisappear { secretInput = "" }
        .sheet(item: $editingQuickAction) { action in
            QuickActionEditor(store: model.quickActions, action: action)
        }
        .sheet(item: $editingModelSlot) { slot in
            ModelSlotEditor(settings: model.providerSettings, slot: slot)
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Настройки").font(.title3.bold()).padding(.horizontal, 12).padding(.vertical, 10)
                    settingsGroup("Запись", [.audioCapture, .interviewRecording])
                    settingsGroup("Звук", [.speech])
                    settingsGroup("Управление", [.hotkeys, .models, .metaKeys, .cursor, .quickActions])
                    settingsGroup("Приложение", [.appearance, .meetingPanel, .teleprompter, .chat, .system, .storage, .disguise])
                }.padding(8)
            }
            Divider()
            VStack(spacing: 3) {
                Label("Локальный режим", systemImage: "person.crop.circle").frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.secondary)
                Button { NSApplication.shared.terminate(nil) } label: { Label("Завершить приложение", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            }.padding(14)
        }
        .frame(width: 206)
        .background(DesignTokens.sidebar)
    }

    private func settingsGroup(_ title: String, _ panes: [HMSettingsPane]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
            ForEach(panes) { item in
                Button { pane = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 12, weight: pane == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(pane == item ? DesignTokens.accent : .primary)
                        .background(pane == item ? DesignTokens.accentSoft : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var settingsPage: some View {
        switch pane {
        case .audioCapture: audioCapturePage
        case .interviewRecording: recordingPage
        case .speech: speechPage
        case .hotkeys: hotkeysPage
        case .models: modelsPage
        case .metaKeys: metaKeysPage
        case .cursor: cursorPage
        case .quickActions: quickActionsPage
        case .appearance: appearancePage
        case .meetingPanel: meetingPanelPage
        case .teleprompter: teleprompterPage
        case .chat: chatPage
        case .system: systemPage
        case .storage: storagePage
        case .disguise: disguisePage
        }
    }

    private var audioCapturePage: some View {
        @Bindable var audio = model.audio
        let sessionBusy = audio.isRunning || audio.isStarting || audio.isStopping
        return VStack(spacing: 14) {
            HMPanel("Источник звука", subtitle: "Выберите, что попадёт в локальную расшифровку") {
                Picker("Источник", selection: $audio.inputMode) { ForEach(AudioInputMode.allCases) { Text($0.title).tag($0) } }
                Picker("Режим записи", selection: $audio.questionMode) { ForEach(AudioQuestionMode.allCases) { Text($0.title).tag($0) } }
            }.disabled(sessionBusy)
            HMPanel("Схема записи") {
                HStack(spacing: 10) {
                    sourceStep("Буфер", "\(audio.configuration.preRoll.formatted(.number.precision(.fractionLength(0...1)))) сек", "waveform.path", .blue)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    sourceStep("Старт / стоп", "вопрос", "bolt.fill", DesignTokens.accent)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    sourceStep("Запись", audio.isRunning ? "идёт" : "готова", "record.circle", DesignTokens.success)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    sourceStep("Отправка", "вручную", "paperplane", .orange)
                }
                HStack {
                    Button(audio.isStarting ? "Отменить подключение" : audio.isRunning ? "Остановить" : "Начать захват") {
                        if audio.isRunning || audio.isStarting { Task { await audio.stop() } } else { audio.start() }
                    }.buttonStyle(HMPrimaryButtonStyle())
                        .disabled(audio.isStopping || audio.isClearing || (!sessionBusy && !audio.consent))
                    Toggle("Согласие участников получено", isOn: $audio.consent)
                        .disabled(sessionBusy)
                }
                Text(audio.status).font(.caption).foregroundStyle(.secondary)
            }
            HMPanel("Микрофон и буфер") {
                LabeledContent("Микрофон", value: "Системное устройство ввода")
                settingSlider("Длина буфера", value: $audio.configuration.preRoll, range: 0...15, suffix: "\(audio.configuration.preRoll.formatted(.number.precision(.fractionLength(0...1)))) сек")
                Toggle("Отправлять подготовленный снимок вместе со звуком", isOn: .constant(false)).disabled(true)
                Text("Источник, режим и параметры буфера сохраняются. Захват запускается вручную после согласия участников. Снимок можно приложить отдельно к вопросу.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Расширенные настройки") {
                    settingSlider("One-Shot", value: $audio.configuration.oneShot, range: 5...60, suffix: "\(audio.configuration.oneShot.formatted(.number.precision(.fractionLength(0...1)))) сек")
                    settingSlider("Порог речи", value: $audio.configuration.threshold, range: 0.001...0.1, suffix: audio.configuration.threshold.formatted(.number.precision(.fractionLength(3))))
                }
            }.disabled(sessionBusy)
        }
    }

    private var recordingPage: some View {
        VStack(spacing: 14) {
            HMPanel("Запись интервью", subtitle: "Видео и два независимых аудиоканала") {
                Text("Запись видеофайла пока не подключена. Эти параметры недоступны; звук для расшифровки запускается отдельно в разделе «Запись звука».")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Записывать интервью в файл", isOn: $recordingEnabled)
                    .disabled(true)
                Toggle("Системный звук", isOn: $recordSystemAudio)
                    .disabled(true)
                HStack {
                    Button(recordingEnabled ? "Остановить запись" : "Начать запись", systemImage: "record.circle") { recordingEnabled.toggle() }
                        .buttonStyle(HMPrimaryButtonStyle()).disabled(true)
                    Button("Записать 5 секунд", systemImage: "waveform") {}.disabled(true)
                    Spacer(); HMStatusPill(text: "Не подключено", color: .secondary)
                }
            }.disabled(true)
            HMPanel("Параметры файла") {
                Picker("Частота кадров", selection: $fps) { ForEach(["24 fps", "30 fps", "60 fps"], id: \.self) { Text($0) } }
                Picker("Максимальное разрешение", selection: $resolution) { ForEach(["1080p", "1440p", "4K"], id: \.self) { Text($0) } }
                Picker("Качество видео", selection: $quality) { ForEach(["CRF 18", "CRF 21", "CRF 24"], id: \.self) { Text($0) } }
                Picker("Битрейт аудио", selection: $bitrate) { ForEach(["128 kbps", "192 kbps", "256 kbps"], id: \.self) { Text($0) } }
            }.disabled(true)
            HMPanel("Папка записи") {
                Text(AppStoragePaths.standard.directory(for: .interviews).path).font(.system(.caption, design: .monospaced))
                Text("Папку приложения можно открыть в разделе «Хранилище».").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var speechPage: some View {
        @Bindable var speech = model.speech
        return VStack(spacing: 14) {
            HMPanel("Поведение и горячие клавиши") {
                Toggle("Пропускать блоки кода", isOn: $speech.skipCodeBlocks)
                Toggle("Автоматически озвучивать ответы", isOn: $speech.autoRead)
                shortcutRow("Озвучить или остановить последний ответ", "⌘ ⇧ S")
                shortcutRow("Включить автоматическую озвучку", "⌘ ⌥ S")
            }
            HMPanel("Озвучка ответов") {
                Picker("Язык", selection: $speech.language) { Text("Русский").tag("ru-RU"); Text("English").tag("en-US") }
                Picker("Голос", selection: $speech.voiceID) {
                    Text("Системный голос").tag("")
                    ForEach(speech.compatibleVoices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
                }
                settingSlider("Громкость", value: $speech.volume, range: 0...1, suffix: "\(Int(speech.volume * 100))%")
                settingSlider("Скорость", value: $speech.rate, range: 0...1, suffix: speech.rate.formatted(.number.precision(.fractionLength(1))) + "×")
                settingSlider("Баланс каналов", value: .constant(0.5), range: 0...1, suffix: "Центр")
                HStack { Button("Проверить голос", systemImage: "speaker.wave.2") { speech.speak("Проверка выбранного голоса") }; Button("Остановить") { speech.stop() } }
            }
        }
    }

    private var hotkeysPage: some View {
        @Bindable var preferences = model.overlay.preferences
        return VStack(spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск по названию…", text: $hotkeySearch).textFieldStyle(.plain)
            }.padding(10).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 9))
            HMPanel("Управление сочетаниями") {
                Toggle("Глобальные горячие клавиши", isOn: $preferences.shortcutsEnabled)
                Picker("Набор сочетаний", selection: $preferences.shortcutPreset) {
                    ForEach(ShortcutPreset.allCases) { Text($0.title).tag($0) }
                }
                Text("\(model.overlay.hotkeys.registeredCount) зарегистрировано")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.overlay.hotkeys.issues, id: \.self) { issue in
                    Text(issue).font(.caption).foregroundStyle(.orange)
                }
            }
            HMPanel("Горячие клавиши", subtitle: "Нажмите сочетание справа, чтобы переназначить команду") {
                ForEach(filteredHotkeys, id: \.rawValue) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Button { editingHotkey = action } label: {
                            Text(preferences.shortcutLabel(for: action))
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Изменить сочетание: \(action.title)")
                        .popover(isPresented: Binding(
                            get: { editingHotkey == action },
                            set: { if !$0 { editingHotkey = nil } }
                        )) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(action.title).font(.headline)
                                HotkeyBindingEditor(controller: model.overlay, action: action)
                                Button("Готово") { editingHotkey = nil }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }.padding(18).frame(width: 360)
                        }
                    }
                    if action != filteredHotkeys.last { Divider() }
                }
                if filteredHotkeys.isEmpty {
                    Text("Команды не найдены. Измените поисковый запрос.")
                        .foregroundStyle(.secondary)
                }
                Button("Сбросить всё по умолчанию", systemImage: "arrow.counterclockwise") {
                    model.overlay.preferences.resetAllHotkeys(); model.overlay.configureHotkeys()
                }.frame(maxWidth: .infinity)
            }
        }
        .onChange(of: preferences.shortcutsEnabled) { _, _ in model.overlay.configureHotkeys() }
        .onChange(of: preferences.shortcutPreset) { _, _ in model.overlay.configureHotkeys() }
    }

    private var modelsPage: some View {
        let settings = model.providerSettings
        let busy = model.isGenerating || model.conversation.isLoading
        return VStack(spacing: 14) {
            HMPanel("Переключение моделей") {
                LabeledContent("Текущий API", value: settings.configuration.mode == .demo ? "Демо без сети" : settings.configuration.baseURL)
                LabeledContent("Модель ответа", value: settings.configuration.mode == .demo ? "Локальный учебный пример" : settings.configuration.textModel)
                shortcutRow("Следующий модельный слот", model.overlay.preferences.shortcutLabel(for: .cycleModels))
                Button("Следующий настроенный слот", systemImage: "arrow.triangle.2.circlepath") { settings.cycleModelSlot() }
                    .disabled(busy || !settings.modelSlots.keys.contains(where: settings.isSlotAvailable))
                Text("Переключаются слоты текущего API. Выбор модели сохраняется и действует на следующий запрос. Адрес API, ключ и настройки распознавания остаются текущими.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HMPanel("Слоты моделей") {
                ForEach(1...5, id: \.self) { slot in
                    HStack {
                        Text("Слот \(slot)").frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(settings.modelSlots[slot]?.name ?? "Не настроен").font(.callout.weight(.semibold))
                            if let preset = settings.modelSlots[slot] {
                                Text(preset.model).font(.caption).foregroundStyle(.secondary)
                                if !settings.isSlotAvailable(slot) { Text("Настроен для другого API").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Spacer()
                        if settings.activeSlotNumber == slot { HMStatusPill(text: "Выбрано", color: DesignTokens.success) }
                        Button("Выбрать") { settings.activateModelSlot(slot) }
                            .disabled(busy || !settings.isSlotAvailable(slot))
                        Button("Настроить") {
                            editingModelSlot = settings.modelSlots[slot] ?? ModelSlot(number: slot, name: "Модель \(slot)",
                                model: settings.configuration.textModel, supportsVision: settings.configuration.visionEnabled, providerIdentity: "")
                        }.disabled(busy || settings.configuration.mode != .remote || (try? settings.configuration.modelSlotProviderIdentity()) == nil)
                        Button("Очистить", systemImage: "xmark.circle") { settings.removeModelSlot(slot) }
                            .disabled(busy || settings.modelSlots[slot] == nil)
                    }
                }
                if !settings.message.isEmpty { Text(settings.message).font(.caption).foregroundStyle(.secondary) }
            }
            HMPanel("Доступность моделей", subtitle: "Имена и возможности моделей задаются по документации вашего API") {
                providerRow("Демонстрационный режим", "Доступен локально", true)
                Text("Каталог провайдера автоматически не загружается. Для слотов сначала укажите собственный API в разделе «Система».")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Настроить провайдера", systemImage: "slider.horizontal.3") { pane = .system }
            }
        }
    }

    private var metaKeysPage: some View {
        VStack(spacing: 14) {
            HMPanel("Блокировать одиночные meta-клавиши", subtitle: "Комбинации с обычными клавишами продолжают работать") {
                Toggle("Включить блокировку", isOn: $blocksMetaKeys)
                    .disabled(true)
                HStack(spacing: 12) {
                    ForEach(["Control", "Shift", "Option", "Command"], id: \.self) { key in
                        Text(key).font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                HMStatusPill(text: "Не поддерживается в текущей сборке", color: .secondary)
            }
            HMPanel("Как работает фильтр") {
                HStack { Image(systemName: "keyboard").font(.largeTitle).foregroundStyle(DesignTokens.accent); Text("Фильтр клавиш не подключён. Приложение не блокирует одиночные системные клавиши; глобальные сочетания настраиваются отдельно.").foregroundStyle(.secondary) }
            }
        }
    }

    private var cursorPage: some View {
        VStack(spacing: 14) {
            HMPanel("Виртуальный курсор при снимке области") {
                Toggle("Автоматически включать виртуальный курсор", isOn: .constant(false)).disabled(true)
                Text("Виртуальный курсор не подключён. Для снимка области используется просмотр и обрезка захваченного изображения.").font(.caption).foregroundStyle(.secondary)
                Picker("Область", selection: .constant("Экран")) { Text("Экран"); Text("Выбор области") }.disabled(true)
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(DesignTokens.elevated).frame(height: 190)
                    RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.accent, lineWidth: 2).frame(width: 170, height: 110)
                    Image(systemName: "cursorarrow").font(.system(size: 34)).offset(x: 48, y: 28)
                    Text("420 × 280").font(.caption2).padding(5).background(DesignTokens.accent, in: Capsule()).offset(y: 72)
                }
            }
            HMPanel("Защита курсора") {
                Toggle("Защита курсора", isOn: .constant(false)).disabled(true)
                Text("Сохранение вида курсора другого приложения не поддерживается. Пропуск кликов рабочего окна можно переключать независимо.").font(.caption).foregroundStyle(.secondary)
                Picker("Курсор", selection: .constant("Стрелка")) { Text("Стрелка"); Text("Точка"); Text("Скрытый") }.disabled(true)
                HStack { Text("Панель ввода"); Spacer(); Button("Показать") { model.overlay.focusInput() } }
            }
        }
    }

    private var quickActionsPage: some View {
        @Bindable var preferences = model.overlay.preferences
        return VStack(spacing: 14) {
            HMPanel("Пять быстрых действий", subtitle: "Настройка каждого слота сохраняется локально") {
                ForEach(model.quickActions.actions) { action in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Image(systemName: action.slot == 1 ? "text.magnifyingglass" : "bolt.circle")
                            .frame(width: 28, height: 28).background(DesignTokens.accentSoft, in: Circle()).foregroundStyle(DesignTokens.accent)
                        VStack(alignment: .leading) { Text(action.name).font(.callout.weight(.semibold)); Text(action.profileID.title).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(preferences.quickActionShortcutLabel(slot: action.slot)).font(.system(.caption, design: .monospaced)); Button("Настроить") { editingQuickAction = action }
                    }.padding(8).background(DesignTokens.elevated.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            HMPanel("Скрытые элементы") {
                Text("Скрытие отдельных действий ещё не подключено. Ниже можно скрыть всю строку быстрых действий.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HMPanel { Toggle("Показывать быстрые действия над полем ввода", isOn: $preferences.showsQuickActions) }
        }
    }

    private var appearancePage: some View {
        @Bindable var preferences = model.overlay.preferences
        return VStack(spacing: 14) {
            HMPanel("Тема оформления") {
                Picker("Тема", selection: $model.theme) { ForEach(AppTheme.allCases) { Text($0.title).tag($0) } }
                ColorPicker("Акцентный цвет", selection: accentBinding, supportsOpacity: false)
                HStack {
                    ForEach(accentOptions, id: \.color) { option in
                        Button { model.preferences.accent = option.color } label: {
                            Circle().fill(DesignTokens.color(for: option.color)).frame(width: 24, height: 24)
                                .overlay(Circle().stroke(.primary.opacity(model.preferences.accent == option.color ? 1 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Акцент: \(option.name)")
                        .accessibilityAddTraits(model.preferences.accent == option.color ? .isSelected : [])
                    }
                }
                Button("Цвет по умолчанию") { model.preferences.accent = .defaultColor }
                    .disabled(model.preferences.accent == .defaultColor)
                settingSlider("Непрозрачность окна встречи", value: $preferences.opacity, range: 0.35...1, suffix: "\(Int(preferences.opacity * 100))%")
            }
            HMPanel("Предпросмотр") {
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.75), customAccent.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Image(systemName: "sparkles"); Image(systemName: "waveform"); Spacer(); HMStatusPill(text: "Активно", color: customAccent) }
                        Text("Транскрипция звука").font(.caption).foregroundStyle(.secondary)
                        Text("Разделяю задачу на шаги и формирую краткий ответ.").font(.callout)
                    }.padding(18).frame(width: 430).background(DesignTokens.card.opacity(preferences.opacity), in: RoundedRectangle(cornerRadius: 14))
                }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HMPanel("Перемещение и размер окна", subtitle: "Шаги для горячих клавиш и кнопок рабочего окна, в пунктах macOS") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Шаг перемещения"); Spacer(); Text("\(Int(preferences.moveStep)) пт").monospacedDigit() }
                    Slider(value: $preferences.moveStep, in: 10...200, step: 5)
                        .accessibilityLabel("Шаг перемещения")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Шаг изменения размера"); Spacer(); Text("\(Int(preferences.resizeStep)) пт").monospacedDigit() }
                    Slider(value: $preferences.resizeStep, in: 10...200, step: 5)
                        .accessibilityLabel("Шаг изменения размера")
                }
                Text("Параметры сохраняются автоматически. Окно остаётся в видимой области дисплея.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HMPanel("Индикатор состояния окна") {
                Toggle("Показывать индикатор", isOn: $preferences.showsStatusIndicator)
                Picker("Расположение", selection: $preferences.statusCorner) {
                    ForEach(OverlayStatusCorner.allCases) { Text($0.title).tag($0) }
                }.disabled(!preferences.showsStatusIndicator)
                Text("Показывает запрос исключения из захвата, доступность защиты курсора, режим кликов и количество подключённых дисплеев. Настройки сохраняются.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: preferences.opacity) { _, _ in model.overlay.applyOpacity() }
    }

    private var meetingPanelPage: some View {
        @Bindable var preferences = model.overlay.preferences
        return VStack(spacing: 14) {
            HStack {
                Text("Перетащите инструмент между панелями или выберите место в его меню.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Сбросить") { preferences.resetPanelLayout() }
            }
            HMPanel("Предпросмотр панели встречи") {
                panelLayoutZone(.header)
                Divider()
                Text("Сообщение").font(.caption).foregroundStyle(.secondary)
                Text("Как бы вы спроектировали этот сервис?").padding(10).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                if preferences.showsQuickActions {
                    HStack {
                        ForEach(model.quickActions.actions.filter { $0.profileID == model.profile }) {
                            Text($0.name).font(.caption).padding(8).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Text("Сообщение или вопрос…").foregroundStyle(.secondary)
                panelLayoutZone(.input)
            }
            HMPanel { panelLayoutZone(.hidden) }
            HMPanel { Toggle("Показывать быстрые действия", isOn: $preferences.showsQuickActions) }
        }
    }

    private func panelLayoutZone(_ zone: MeetingPanelZone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(zone.title).font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.overlay.preferences.panelLayout[zone]) { tool in
                        Menu {
                            ForEach(MeetingPanelZone.allCases) { destination in
                                Button(destination.title) { model.overlay.preferences.movePanelTool(tool, to: destination) }
                            }
                        } label: {
                            Label(tool.title, systemImage: tool.icon).font(.caption)
                                .padding(8).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .draggable(tool.rawValue)
                        .dropDestination(for: String.self) { values, _ in movePanelTool(values, to: zone, before: tool) }
                        .help("Перетащите инструмент или выберите другую панель")
                    }
                    if model.overlay.preferences.panelLayout[zone].isEmpty {
                        Label("Перетащите инструмент сюда", systemImage: zone == .hidden ? "eye.slash" : "plus")
                            .font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }.padding(6)
            }.frame(minHeight: 52)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.secondary.opacity(0.4), style: StrokeStyle(dash: [5])))
        .dropDestination(for: String.self) { values, _ in movePanelTool(values, to: zone) }
    }

    private func movePanelTool(_ values: [String], to zone: MeetingPanelZone, before target: MeetingPanelTool? = nil) -> Bool {
        guard values.count == 1, let value = values.first, let tool = MeetingPanelTool(rawValue: value) else { return false }
        model.overlay.preferences.movePanelTool(tool, to: zone, before: target)
        return true
    }

    private var teleprompterPage: some View {
        @Bindable var settings = model.overlay.teleprompter.settings
        @Bindable var colors = settings.appearance
        return VStack(spacing: 14) {
            HMPanel("Текст телесуфлёра") {
                TextEditor(text: $settings.text).frame(minHeight: 120)
                HStack {
                    Text("\(settings.words.isEmpty ? 0 : settings.activeWordIndex + 1) / \(settings.words.count) слов").font(.caption).monospacedDigit()
                    Spacer()
                    Button(settings.isPlaying ? "Пауза" : "Продолжить") { settings.togglePlayback() }.disabled(settings.words.isEmpty)
                    Button("Сначала") { settings.reset() }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(DesignTokens.color(for: colors.background)).frame(height: 150)
                    HStack(spacing: 10) {
                        ForEach(Array(settings.words.enumerated()).dropFirst(max(0, settings.activeWordIndex - 2)).prefix(5), id: \.offset) { index, word in
                            Text(word).font(.system(size: min(34, settings.fontSize), weight: index == settings.activeWordIndex ? .bold : .regular))
                                .foregroundStyle(DesignTokens.color(for: index == settings.activeWordIndex ? colors.active : colors.neighbor))
                        }
                        if settings.words.isEmpty { Text("Введите текст для предпросмотра").foregroundStyle(DesignTokens.color(for: colors.neighbor)) }
                    }.padding(12).frame(maxWidth: .infinity).clipped()
                }
                Picker("Источник", selection: $settings.source) { ForEach(TeleprompterContentSource.allCases) { Text($0.title).tag($0) } }
                Button(model.overlay.teleprompter.isVisible ? "Скрыть телесуфлёр" : "Показать телесуфлёр", systemImage: "text.viewfinder") { model.overlay.teleprompter.toggle() }.buttonStyle(HMPrimaryButtonStyle())
            }
            HMPanel("Внешний вид и прокрутка") {
                settingSlider("Прозрачность окна", value: $settings.opacity, range: 0.35...1, suffix: "\(Int(settings.opacity * 100))%")
                settingSlider("Размер текста", value: $settings.fontSize, range: 18...72, suffix: "\(Int(settings.fontSize)) пт")
                settingSlider("Скорость", value: $settings.speed, range: 30...300, suffix: "\(Int(settings.speed)) сл/мин")
                Picker("Расположение", selection: $settings.position) { ForEach(TeleprompterPosition.allCases) { Text($0.title).tag($0) } }
                HMColorPicker(title: "Цвет фона", value: $colors.background)
                HMColorPicker(title: "Соседние слова", value: $colors.neighbor)
                HMColorPicker(title: "Активное слово", value: $colors.active)
                Button("Сбросить цвета") { colors.reset() }
            }
        }
    }

    private var chatPage: some View {
        @Bindable var preferences = model.overlay.preferences
        @Bindable var uiPreferences = model.preferences
        return VStack(spacing: 14) {
            HMPanel("Отображение сообщений") {
                Picker("Порядок сообщений", selection: $uiPreferences.messageOrder) {
                    ForEach(MessageOrder.allCases) { Text($0.title).tag($0) }
                }
                settingSlider("Размер текста сообщений", value: $uiPreferences.messageFontSize, range: 11...22, suffix: uiPreferences.messageFontSize.formatted(.number.precision(.fractionLength(1))) + " пт")
                Picker("Тема подсветки кода", selection: $uiPreferences.codeTheme) {
                    ForEach(CodeColorTheme.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Подсвечивать синтаксис Go", isOn: $uiPreferences.syntaxHighlighting)
                AnswerTextView(text: chatPreview)
            }
            HMPanel("Прокрутка и группы") {
                Toggle("Умная автопрокрутка", isOn: $preferences.smartAutoScroll)
                settingSlider("Скорость автопрокрутки", value: $preferences.autoScrollSpeed, range: 0.25...2,
                              suffix: "\(Int((preferences.autoScrollSpeed * 100).rounded()))%")
                    .disabled(!preferences.smartAutoScroll)
                Toggle("Автоматически сворачивать расшифровки", isOn: $uiPreferences.collapseTranscripts)
                Toggle("Сворачивать последнюю группу расшифровок", isOn: $uiPreferences.collapseLatestTranscript)
                    .disabled(!uiPreferences.collapseTranscripts)
                Toggle("Автоматически сворачивать ответы", isOn: $uiPreferences.collapseAnswers)
                Toggle("Сворачивать последний ответ", isOn: $uiPreferences.collapseLatestAnswer)
                    .disabled(!uiPreferences.collapseAnswers)
            }
            HMPanel("Компактность") {
                Toggle("Компактные быстрые действия", isOn: $preferences.compactQuickActions)
                Toggle("Лупа для встроенных схем", isOn: .constant(false)).disabled(true)
                Toggle("Отменять генерацию при повторной отправке", isOn: $uiPreferences.cancelGenerationOnSend)
                Picker("Ручная отмена", selection: $uiPreferences.retainCancelledAnswer) {
                    Text("Сохранить полученный текст").tag(true)
                    Text("Отменить без сохранения").tag(false)
                }
            }
        }
    }

    private var systemPage: some View {
        VStack(spacing: 14) {
            HMPanel("Язык и защита") {
                Picker("Язык", selection: .constant("Русский")) { Text("Русский"); Text("English") }.disabled(true)
                LabeledContent("Исключение окон из захвата", value: "Запрошено у macOS")
                Text("Главное окно, рабочее окно и телесуфлёр используют системное исключение из захвата. Совместимость программы трансляции проверяется отдельно в диагностике.").font(.caption).foregroundStyle(.secondary)
            }
            HMPanel("Прокси") {
                Text("Прокси не подключён. Приложение использует прямое соединение с указанным API; отдельные данные доступа к прокси здесь не запрашиваются.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Button("Проверить", systemImage: "antenna.radiowaves.left.and.right") {}.disabled(true); Button("Сохранить", systemImage: "square.and.arrow.down") {}.disabled(true) }
            }
            HMPanel("Обновления") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Текущая версия")
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Не указана") · сборка \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Не указана")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Button("Проверить обновления", systemImage: "arrow.clockwise") {}.disabled(true)
                }
                Text("Автоматическое обновление приложения ещё не подключено.").font(.caption).foregroundStyle(.secondary)
            }
            HMPanel("AI-провайдер") {
                ProviderConfigurationView(settings: model.providerSettings)
                SecureField("API-ключ — только macOS Keychain", text: $secretInput)
                HStack {
                    Button("Сохранить в Keychain") { model.saveSecret(secretInput); secretInput = "" }.disabled(secretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Удалить ключ", role: .destructive) { model.deleteSecret(); secretInput = "" }
                }
            }
            HMPanel("Обучение") { Button("Сбросить обучение", systemImage: "arrow.counterclockwise") { model.showOnboarding = true } }
        }
    }

    private var storagePage: some View {
        VStack(spacing: 14) {
            HMPanel("Занято на диске") {
                HStack {
                    Image(systemName: "internaldrive").font(.title)
                    VStack(alignment: .leading) {
                        Text("Локальные файлы приложения")
                        if let snapshot = storageSnapshot {
                            Text("\(snapshot.fileCount) файлов · \(snapshot.inspectedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(storageSnapshot.map { storageSize($0.totalBytes) } ?? "—").font(.title2.bold())
                }
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(StorageArea.allCases) { area in
                            storageColor(area).frame(width: geometry.size.width * (storageSnapshot?.fraction(for: area) ?? 0))
                        }
                    }
                }.frame(height: 8).background(DesignTokens.elevated).clipShape(Capsule()).accessibilityHidden(true)
                ForEach(StorageArea.allCases) { area in
                    storageLegend(area.title, storageSnapshot.map { storageSize($0.bytes[area, default: 0]) } ?? "—", storageColor(area))
                }
                HStack {
                    if storageIsLoading { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Обновить", systemImage: "arrow.clockwise") { Task { await refreshStorage() } }
                        .disabled(storageIsLoading)
                }
                if let snapshot = storageSnapshot, snapshot.unreadableCount > 0 {
                    Text("Не удалось прочитать \(snapshot.unreadableCount) элементов. Общий размер может быть неполным.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let storageIssue { Text(storageIssue).font(.caption).foregroundStyle(.orange) }
                Text("Объём файлов в папке приложения. Данные в памяти и кэш сборки не учитываются; ссылки пропускаются.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HMPanel("Папки") {
                ForEach(StorageArea.allCases) { area in folderRow(area) }
            }
        }
        .task { await refreshStorage() }
    }

    private var disguisePage: some View {
        VStack(spacing: 14) {
            HMPanel("Отдельная копия приложения", subtitle: "Создайте локальную копию с выбранным именем и значком") {
                TextField("Имя приложения", text: $disguiseName)
                Picker("Значок", selection: $disguiseIcon) {
                    Label("Работа", systemImage: "briefcase.fill").tag("briefcase.fill")
                    Label("Заметки", systemImage: "note.text").tag("note.text")
                    Label("Календарь", systemImage: "calendar").tag("calendar")
                    Label("Чат", systemImage: "bubble.left.and.bubble.right").tag("bubble.left.and.bubble.right")
                }
                HStack {
                    ZStack { RoundedRectangle(cornerRadius: 14).fill(DesignTokens.accent); Image(systemName: disguiseIcon).font(.title).foregroundStyle(.white) }.frame(width: 64, height: 64)
                    VStack(alignment: .leading) { Text(disguiseName.isEmpty ? "HireMate" : disguiseName).font(.headline); Text("Предпросмотр значка и имени").font(.caption).foregroundStyle(.secondary) }
                }
                HStack { Spacer(); Button("Создать локальную копию", systemImage: "doc.on.doc") {}.buttonStyle(HMPrimaryButtonStyle()) }
            }
        }
    }

    private var filteredHotkeys: [GlobalHotkeyService.Action] {
        let query = hotkeySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return GlobalHotkeyService.Action.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var customAccent: Color { DesignTokens.color(for: model.preferences.accent) }

    private var chatPreview: String {
        """
        ### Предпросмотр
        Ответ и заметки используют выбранный размер текста. Длинный код прокручивается отдельно.
        ```go
        package main

        import "fmt"

        func sum(values []int) int {
            total := 0
            for _, value := range values {
                total += value
            }
            return total
        }

        func main() {
            examples := [][]int{
                nil,
                {},
                {1, 2, 3},
                {-2, 0, 2},
            }
            for _, values := range examples {
                fmt.Println(sum(values))
            }
        }
        ```
        """
    }

    private var accentOptions: [(name: String, color: AppAccent)] {
        [("Оранжевый", AppAccent(rgb: 0xFF9F0A)), ("Синий", AppAccent(rgb: 0x0A84FF)),
         ("Фиолетовый", AppAccent(rgb: 0xBF5AF2)), ("Зелёный", .defaultColor),
         ("Розовый", AppAccent(rgb: 0xFF375F)), ("Голубой", AppAccent(rgb: 0x64D2FF))]
    }

    private var accentBinding: Binding<Color> {
        DesignTokens.colorBinding(Binding(get: { model.preferences.accent }, set: { model.preferences.accent = $0 }))
    }

    private func sourceStep(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.caption.weight(.semibold))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(12).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.5)))
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(suffix).font(.caption).foregroundStyle(.secondary) }
            Slider(value: value, in: range).tint(DesignTokens.accent)
        }
    }

    private func settingSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(suffix).font(.caption).foregroundStyle(.secondary) }
            Slider(value: value, in: range).tint(DesignTokens.accent)
        }
    }

    private func shortcutRow(_ title: String, _ shortcut: String) -> some View {
        HStack { Text(title); Spacer(); Text(shortcut).font(.system(.caption, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 5).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 6)) }
    }

    private func providerRow(_ name: String, _ detail: String, _ active: Bool) -> some View {
        HStack { Circle().fill(active ? DesignTokens.success : Color.secondary).frame(width: 8, height: 8); VStack(alignment: .leading) { Text(name); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); HMStatusPill(text: active ? "Подключён" : "Не настроен", color: active ? DesignTokens.success : .secondary) }
    }

    private func storageLegend(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack { Circle().fill(color).frame(width: 8, height: 8); Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
    }

    private func folderRow(_ area: StorageArea) -> some View {
        HStack {
            Text(area.title)
            Spacer()
            Button("Открыть", systemImage: "folder") {
                Task {
                    do {
                        let url = try await storageInspector.prepareDirectory(for: area)
                        guard !Task.isCancelled else { return }
                        if !NSWorkspace.shared.open(url) { storageIssue = "Finder не смог открыть папку." }
                    } catch is CancellationError { }
                    catch { storageIssue = "Не удалось открыть папку: \(error.localizedDescription)" }
                }
            }.accessibilityLabel("Открыть папку: \(area.title)")
        }
    }

    private func refreshStorage() async {
        guard !storageIsLoading else { return }
        storageIsLoading = true; storageIssue = nil
        defer { storageIsLoading = false }
        do {
            let snapshot = try await storageInspector.snapshot()
            guard !Task.isCancelled else { return }
            storageSnapshot = snapshot
        } catch is CancellationError { }
        catch { storageIssue = "Не удалось рассчитать объём: \(error.localizedDescription)" }
    }

    private func storageSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func storageColor(_ area: StorageArea) -> Color {
        switch area {
        case .audio: .cyan
        case .interviews: .purple
        case .screenshots: .orange
        case .logs: .yellow
        case .database: DesignTokens.accent
        case .other: .secondary
        }
    }
}

private enum HMSettingsPane: String, CaseIterable, Identifiable {
    case audioCapture, interviewRecording, speech, hotkeys, models, metaKeys, cursor, quickActions
    case appearance, meetingPanel, teleprompter, chat, system, storage, disguise
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audioCapture: "Запись звука"
        case .interviewRecording: "Запись интервью"
        case .speech: "Озвучка ответов"
        case .hotkeys: "Горячие клавиши"
        case .models: "Клавиши моделей"
        case .metaKeys: "Meta-клавиши"
        case .cursor: "Мышь и курсор"
        case .quickActions: "Быстрые действия"
        case .appearance: "Окно"
        case .meetingPanel: "Панель встречи"
        case .teleprompter: "Телесуфлёр"
        case .chat: "Чат"
        case .system: "Система"
        case .storage: "Хранилище"
        case .disguise: "Маскировка"
        }
    }
    var subtitle: String {
        switch self {
        case .audioCapture: "Источник, буфер, VAD и ручной режим вопроса"
        case .interviewRecording: "Качество видео, аудиоканалы и место сохранения"
        case .speech: "Голос, скорость, громкость и автоматическое чтение"
        case .hotkeys: "Все команды приложения в одном списке"
        case .models: "Пять сохраняемых слотов для текущего API"
        case .metaKeys: "Контроль одиночных системных клавиш"
        case .cursor: "Виртуальный указатель и защита положения"
        case .quickActions: "Команды над полем ввода"
        case .appearance: "Тема, акцент и непрозрачность"
        case .meetingPanel: "Состав и порядок элементов рабочего окна"
        case .teleprompter: "Текст, вид, положение и прокрутка"
        case .chat: "Сообщения, код, группы и автопрокрутка"
        case .system: "Язык, защита, провайдер и обновления"
        case .storage: "Локальные файлы и занимаемое место"
        case .disguise: "Имя и значок отдельной локальной копии"
        }
    }
    var symbol: String {
        switch self {
        case .audioCapture: "waveform"
        case .interviewRecording: "video"
        case .speech: "speaker.wave.2"
        case .hotkeys: "command"
        case .models: "cpu"
        case .metaKeys: "keyboard"
        case .cursor: "cursorarrow"
        case .quickActions: "bolt"
        case .appearance: "macwindow"
        case .meetingPanel: "rectangle.3.group"
        case .teleprompter: "text.viewfinder"
        case .chat: "bubble.left.and.bubble.right"
        case .system: "gearshape"
        case .storage: "internaldrive"
        case .disguise: "theatermasks"
        }
    }
}

@MainActor
struct DiagnosticsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("Разрешения macOS") {
                LabeledContent("Микрофон", value: model.microphone.title)
                HStack {
                    Button("Запросить микрофон") { Task { await model.requestMicrophone() } }
                        .disabled(model.microphone != .notRequested)
                    Button("Открыть настройки микрофона") { openSettings(screen: false) }
                }
                LabeledContent("Экран и системный звук", value: model.screen.title)
                HStack {
                    Button("Запросить доступ к экрану") { model.requestScreen() }.disabled(model.screen == .granted)
                    Button("Открыть настройки экрана") { openSettings(screen: true) }
                }
                Button("Обновить статусы") { model.refreshPermissions() }
                Text("Системные настройки → Конфиденциальность и безопасность → Микрофон / Запись экрана и системного аудио. Отрицательный результат проверки экрана не позволяет отличить отказ от ещё не запрошенного доступа.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Что сейчас проверяется") {
                Text("Статусы разрешений, состояние рабочего окна и локальные метрики. Эти проверки не начинают захват звука или экрана.")
                Text("Реальный тест микрофона, системного звука и совместимости с трансляцией запускается вручную в соответствующих разделах.").foregroundStyle(.secondary)
            }
            Section("Рабочее окно") {
                LabeledContent("Окно подсказок", value: model.overlay.isVisible ? "Показано" : "Скрыто")
                LabeledContent("Пропуск кликов", value: model.overlay.isClickThrough ? "Включён" : "Выключен")
                LabeledContent("Непрозрачность", value: "\(Int(model.overlay.preferences.opacity * 100))%")
                LabeledContent("Глобальные сочетания", value: model.overlay.preferences.shortcutsEnabled
                               ? "\(model.overlay.hotkeys.registeredCount) зарегистрировано" : "Выключены")
                LabeledContent("Последняя глобальная команда",
                               value: model.overlay.hotkeys.lastTriggeredAction?.title ?? "Не получена")
                if let time = model.overlay.hotkeys.lastTriggeredAt {
                    LabeledContent("Время команды", value: time.formatted(date: .omitted, time: .standard))
                    Button("Очистить отметку команды") { model.overlay.hotkeys.clearLastTrigger() }
                }
                Text("Для ручной проверки оставьте этот экран открытым, перейдите в другое приложение и нажмите сочетание. Сохраняются только название команды и время в памяти; введённые символы не записываются.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.overlay.hotkeys.issues.isEmpty {
                    ForEach(model.overlay.hotkeys.issues, id: \.self) { issue in
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack {
                    Button(model.overlay.isVisible ? "Скрыть рабочее окно" : "Показать рабочее окно") {
                        model.overlay.toggle()
                    }
                    Button("Вернуть ввод") { model.overlay.focusInput() }
                    Button(model.overlay.isClickThrough ? "Принимать клики" : "Пропускать клики") {
                        model.overlay.toggleClickThrough()
                    }.disabled(!model.overlay.isVisible)
                }
                Divider()
                LabeledContent("Тест ScreenCaptureKit", value: model.overlay.compatibilityResult.title)
                Button(model.overlay.compatibilityResult == .running ? "Проверяем…" : "Проверить попадание окна в снимок") {
                    model.overlay.testCaptureCompatibility()
                }
                .disabled(model.overlay.compatibilityResult == .running || model.screen != .granted)
                if model.screen != .granted {
                    Text("Для теста нужен разрешённый доступ к записи экрана. Сам тест запускается только этой кнопкой.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Результат относится только к ScreenCaptureKit на этом Mac в момент проверки. Сторонние программы могут захватывать экран иначе; абсолютная невидимость не гарантируется.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Рабочее окно остаётся поверх обычных окон и может быть видно в трансляции экрана. Режим пропуска кликов переключается в настройках окна или глобальным сочетанием.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Локальная производительность") {
                latencyRows(title: "STT", first: model.transcription.lastFirstEventMilliseconds,
                            total: model.transcription.lastRequestMilliseconds,
                            queue: model.transcription.lastQueueWaitMilliseconds,
                            firstLabel: "первое событие",
                            succeeded: model.transcription.lastRequestSucceeded)
                latencyRows(title: "LLM", first: model.conversation.lastFirstTokenMilliseconds,
                            total: model.conversation.lastLLMRequestMilliseconds,
                            firstLabel: "первый токен",
                            succeeded: model.conversation.lastLLMRequestSucceeded)
                Button("Очистить измерения") {
                    model.transcription.clearLatencyMetrics()
                    model.conversation.clearLatencyMetrics()
                }
                .disabled((model.transcription.lastRequestMilliseconds == nil && model.conversation.lastLLMRequestMilliseconds == nil) ||
                          model.transcription.isBusy || model.conversation.isGenerating)
                Text("Значения хранятся только в памяти до очистки или перезапуска. Текст, аудио, изображения, URL и ключи в измерения не входят.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Локальная база") {
                if let result = model.databaseLatency {
                    LabeledContent("Количество чтений", value: "\(result.sampleCount)")
                    LabeledContent("Минимум", value: milliseconds(result.minimumMilliseconds))
                    LabeledContent("p95", value: milliseconds(result.p95Milliseconds))
                        .foregroundStyle(result.p95Milliseconds < 100 ? Color.primary : .orange)
                    LabeledContent("Максимум", value: milliseconds(result.maximumMilliseconds))
                    Text(result.p95Milliseconds < 100 ? "Текущий замер укладывается в целевой бюджет <100 мс." : "Текущий замер выше целевого бюджета <100 мс.")
                        .font(.caption).foregroundStyle(result.p95Milliseconds < 100 ? Color.secondary : .orange)
                } else {
                    Text("Замер ещё не запускался.").foregroundStyle(.secondary)
                }
                Button(model.isMeasuringDatabase ? "Измеряем…" : "Измерить 20 локальных чтений") {
                    Task { await model.measureDatabaseLatency() }
                }
                .disabled(model.isMeasuringDatabase)
                Text("Тест только читает список встреч активного профиля. Он не выводит содержимое записей и не использует сеть.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Этот Mac") {
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Оперативная память", value: "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) ГБ")
                Text("Серийный номер и идентификатор устройства не собираются.").font(.caption)
            }
        }.formStyle(.grouped).navigationTitle("Диагностика")
            .onAppear { model.refreshPermissions() }
    }
    private func openSettings(screen: Bool) {
        if !model.permissions.openSettings(screen: screen) {
            model.notice = "Откройте Системные настройки → Конфиденциальность и безопасность вручную."
        }
    }
    @ViewBuilder
    private func latencyRows(title: String, first: Int?, total: Int?, queue: Int? = nil,
                             firstLabel: String, succeeded: Bool?) -> some View {
        if let total {
            LabeledContent("\(title): результат", value: succeeded == true ? "Успешно" : "Не завершён")
            if let queue { LabeledContent("\(title): очередь", value: "\(queue) мс") }
            if let first { LabeledContent("\(title): \(firstLabel)", value: "\(first) мс") }
            LabeledContent("\(title): полностью", value: "\(total) мс")
        } else {
            LabeledContent(title, value: "Нет измерений")
        }
    }
    private func milliseconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3))) + " мс"
    }
}
