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
    @State private var modelCycle = "Текущий провайдер"
    @State private var blocksMetaKeys = false
    @State private var cursorEnabled = true
    @State private var cursorProtection = true
    @State private var interfaceOpacity = 1.0
    @State private var customAccent = DesignTokens.accent
    @State private var showQuickActions = true
    @State private var messageOrder = "Новые снизу"
    @State private var chatFontSize = 13.5
    @State private var codeTheme = "GitHub Dark"
    @State private var smartScroll = true
    @State private var collapseGroups = true
    @State private var compactActions = true
    @State private var codeMagnifier = true
    @State private var screenProtection = true
    @State private var proxyURL = ""
    @State private var disguiseName = "HireMate"
    @State private var disguiseIcon = "briefcase.fill"
    @State private var settingsSearch = ""

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
                Button { } label: { Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                Button { } label: { Label("Закрыть", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
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
        return VStack(spacing: 14) {
            HMPanel("Источник звука", subtitle: "Выберите, что попадёт в локальную расшифровку") {
                Picker("Источник", selection: $audio.inputMode) { ForEach(AudioInputMode.allCases) { Text($0.title).tag($0) } }
                Picker("Режим записи", selection: $audio.questionMode) { ForEach(AudioQuestionMode.allCases) { Text($0.title).tag($0) } }
            }
            HMPanel("Схема записи") {
                HStack(spacing: 10) {
                    sourceStep("Буфер", "4 сек", "waveform.path", .blue)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    sourceStep("Старт / стоп", "вопрос", "bolt.fill", DesignTokens.accent)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    sourceStep("Запись", audio.isRunning ? "идёт" : "готова", "record.circle", DesignTokens.success)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    sourceStep("Отправка", "вручную", "paperplane", .orange)
                }
                HStack {
                    Button(audio.isRunning ? "Остановить" : "Начать захват") {
                        if audio.isRunning { Task { await audio.stop() } } else { audio.start() }
                    }.buttonStyle(HMPrimaryButtonStyle()).disabled(!audio.consent)
                    Toggle("Согласие участников получено", isOn: $audio.consent)
                }
            }
            HMPanel("Микрофон и буфер") {
                Picker("Микрофон", selection: .constant("По умолчанию")) { Text("По умолчанию") }
                settingSlider("Длина буфера", value: $audio.configuration.preRoll, range: 0...15, suffix: "\(Int(audio.configuration.preRoll)) сек")
                Toggle("Отправлять подготовленный снимок вместе со звуком", isOn: .constant(false))
                DisclosureGroup("Расширенные настройки") {
                    settingSlider("One-Shot", value: $audio.configuration.oneShot, range: 5...60, suffix: "\(Int(audio.configuration.oneShot)) сек")
                    settingSlider("Порог речи", value: $audio.configuration.threshold, range: 0.001...0.1, suffix: audio.configuration.threshold.formatted(.number.precision(.fractionLength(3))))
                }
            }
        }
    }

    private var recordingPage: some View {
        VStack(spacing: 14) {
            HMPanel("Запись интервью", subtitle: "Видео и два независимых аудиоканала") {
                Toggle("Записывать интервью в файл", isOn: $recordingEnabled)
                Toggle("Системный звук", isOn: $recordSystemAudio)
                HStack {
                    Button(recordingEnabled ? "Остановить запись" : "Начать запись", systemImage: "record.circle") { recordingEnabled.toggle() }
                        .buttonStyle(HMPrimaryButtonStyle())
                    Button("Записать 5 секунд", systemImage: "waveform") {}
                    Spacer(); HMStatusPill(text: recordingEnabled ? "Запись идёт" : "Готово", color: recordingEnabled ? .red : DesignTokens.success)
                }
            }
            HMPanel("Параметры файла") {
                Picker("Частота кадров", selection: $fps) { ForEach(["24 fps", "30 fps", "60 fps"], id: \.self) { Text($0) } }
                Picker("Максимальное разрешение", selection: $resolution) { ForEach(["1080p", "1440p", "4K"], id: \.self) { Text($0) } }
                Picker("Качество видео", selection: $quality) { ForEach(["CRF 18", "CRF 21", "CRF 24"], id: \.self) { Text($0) } }
                Picker("Битрейт аудио", selection: $bitrate) { ForEach(["128 kbps", "192 kbps", "256 kbps"], id: \.self) { Text($0) } }
            }
            HMPanel("Папка записи") {
                HStack { Text("~/Library/Application Support/HireMate/Recordings").font(.system(.caption, design: .monospaced)); Spacer(); Button("Выбрать", systemImage: "folder") {}; Button("Сбросить") {} }
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
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск по названию…", text: $hotkeySearch).textFieldStyle(.plain)
            }.padding(10).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 9))
            HMPanel("Горячие клавиши", subtitle: "Нажмите сочетание справа, чтобы переназначить команду") {
                ForEach(filteredHotkeys, id: \.rawValue) { action in
                    shortcutRow(action.title, model.overlay.preferences.shortcutLabel(for: action))
                    if action != filteredHotkeys.last { Divider() }
                }
                Button("Сбросить всё по умолчанию", systemImage: "arrow.counterclockwise") {
                    model.overlay.preferences.resetAllHotkeys(); model.overlay.configureHotkeys()
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var modelsPage: some View {
        VStack(spacing: 14) {
            HMPanel("Переключение моделей") {
                Picker("Какие модели переключать", selection: $modelCycle) { Text("Текущий провайдер"); Text("Все подключённые") }
                shortcutRow("Горячая клавиша", "Отключено")
            }
            HMPanel("Слоты моделей") {
                ForEach(1...5, id: \.self) { slot in
                    HStack {
                        Text("Слот \(slot)").frame(width: 64, alignment: .leading)
                        Picker("Модель", selection: .constant(slot == 1 ? model.providerSettings.configuration.textModel : "Модель не выбрана")) {
                            Text(model.providerSettings.configuration.textModel).tag(model.providerSettings.configuration.textModel)
                            Text("Модель не выбрана").tag("Модель не выбрана")
                            Text("Локальная демо-модель").tag("Локальная демо-модель")
                        }.labelsHidden()
                        HMStatusPill(text: slot == 1 ? "Активно" : "Отключено", color: slot == 1 ? DesignTokens.success : .red)
                    }
                }
            }
            HMPanel("Каталог моделей", subtitle: "Модели сгруппированы по подключённым провайдерам") {
                providerRow("Демонстрационный режим", "Доступен локально", true)
                providerRow("OpenAI-совместимый API", model.providerSettings.configuration.baseURL, model.providerSettings.configuration.mode == .remote)
                Button("Настроить провайдера", systemImage: "slider.horizontal.3") { pane = .system }
            }
        }
    }

    private var metaKeysPage: some View {
        VStack(spacing: 14) {
            HMPanel("Блокировать одиночные meta-клавиши", subtitle: "Комбинации с обычными клавишами продолжают работать") {
                Toggle("Включить блокировку", isOn: $blocksMetaKeys)
                HStack(spacing: 12) {
                    ForEach(["Control", "Shift", "Option", "Command"], id: \.self) { key in
                        Text(key).font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                HMStatusPill(text: blocksMetaKeys ? "Блокировка включена" : "Выключено", color: blocksMetaKeys ? DesignTokens.success : .secondary)
            }
            HMPanel("Как работает фильтр") {
                HStack { Image(systemName: "keyboard").font(.largeTitle).foregroundStyle(DesignTokens.accent); Text("Одиночное нажатие выбранной клавиши не передаётся системе. Сочетания остаются доступными для команд приложения.").foregroundStyle(.secondary) }
            }
        }
    }

    private var cursorPage: some View {
        VStack(spacing: 14) {
            HMPanel("Виртуальный курсор при снимке области") {
                Toggle("Автоматически включать виртуальный курсор", isOn: $cursorEnabled)
                Picker("Область", selection: .constant("Экран")) { Text("Экран"); Text("Выбор области") }
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(DesignTokens.elevated).frame(height: 190)
                    RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.accent, lineWidth: 2).frame(width: 170, height: 110)
                    Image(systemName: "cursorarrow").font(.system(size: 34)).offset(x: 48, y: 28)
                    Text("420 × 280").font(.caption2).padding(5).background(DesignTokens.accent, in: Capsule()).offset(y: 72)
                }
            }
            HMPanel("Защита курсора") {
                Toggle("Защита курсора всегда включена", isOn: $cursorProtection)
                Picker("Курсор", selection: .constant("Стрелка")) { Text("Стрелка"); Text("Точка"); Text("Скрытый") }
                HStack { Text("Панель ввода"); Spacer(); Button("Показать") {} }
            }
        }
    }

    private var quickActionsPage: some View {
        VStack(spacing: 14) {
            HMPanel("Пять быстрых действий", subtitle: "Перетащите элементы, чтобы изменить порядок") {
                ForEach(model.quickActions.actions) { action in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        Image(systemName: action.slot == 1 ? "text.magnifyingglass" : "bolt.circle")
                            .frame(width: 28, height: 28).background(DesignTokens.accentSoft, in: Circle()).foregroundStyle(DesignTokens.accent)
                        VStack(alignment: .leading) { Text(action.name).font(.callout.weight(.semibold)); Text(action.profileID.title).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text("⌘ \(action.slot)").font(.system(.caption, design: .monospaced)); Button("Настроить") {}
                    }.padding(8).background(DesignTokens.elevated.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            HMPanel("Скрытые элементы") {
                Label("Перетащите сюда действие, чтобы скрыть", systemImage: "eye.slash")
                    .frame(maxWidth: .infinity, minHeight: 70).foregroundStyle(.secondary)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.4), style: StrokeStyle(dash: [6])))
            }
            HMPanel { Toggle("Показывать быстрые действия над полем ввода", isOn: $showQuickActions) }
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 14) {
            HMPanel("Тема оформления") {
                Picker("Тема", selection: $model.theme) { ForEach(AppTheme.allCases) { Text($0.title).tag($0) } }
                ColorPicker("Акцентный цвет", selection: $customAccent, supportsOpacity: false)
                HStack { ForEach([Color.orange, .blue, .purple, .green, .pink, .cyan], id: \.self) { color in Circle().fill(color).frame(width: 24, height: 24).overlay(Circle().stroke(.white.opacity(color == customAccent ? 1 : 0), lineWidth: 2)).onTapGesture { customAccent = color } } }
                settingSlider("Непрозрачность интерфейса", value: $interfaceOpacity, range: 0.35...1, suffix: "\(Int(interfaceOpacity * 100))%")
            }
            HMPanel("Предпросмотр") {
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.75), customAccent.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Image(systemName: "sparkles"); Image(systemName: "waveform"); Spacer(); HMStatusPill(text: "Активно", color: customAccent) }
                        Text("Транскрипция звука").font(.caption).foregroundStyle(.secondary)
                        Text("Разделяю задачу на шаги и формирую краткий ответ.").font(.callout)
                    }.padding(18).frame(width: 430).background(DesignTokens.card.opacity(interfaceOpacity), in: RoundedRectangle(cornerRadius: 14))
                }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var meetingPanelPage: some View {
        VStack(spacing: 14) {
            HMPanel("Предпросмотр панели встречи") {
                HStack { Image(systemName: "sparkles").foregroundStyle(DesignTokens.accent); Image(systemName: "mic"); Spacer(); Text(model.providerSettings.configuration.textModel); Image(systemName: "note.text"); Image(systemName: "house") }
                Divider()
                Text("Сообщение").font(.caption).foregroundStyle(.secondary)
                Text("Как бы вы спроектировали этот сервис?").padding(10).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
                HStack { ForEach(["Анализ экрана", "Что сказать", "Резюме"], id: \.self) { Button($0) {} }; Spacer(); Button { } label: { Image(systemName: "arrow.up.circle.fill") } }
                HStack { ForEach(["bold", "textformat", "bolt", "camera", "note.text", "speaker.wave.2"], id: \.self) { Image(systemName: $0).frame(width: 28, height: 28).background(DesignTokens.elevated, in: Circle()) } }
                Label("Скрытые элементы", systemImage: "eye.slash").frame(maxWidth: .infinity, minHeight: 62)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(.secondary.opacity(0.4), style: StrokeStyle(dash: [5])))
            }
            HMPanel { Toggle("Показывать быстрые действия", isOn: $showQuickActions) }
        }
    }

    private var teleprompterPage: some View {
        @Bindable var settings = model.overlay.teleprompter.settings
        return VStack(spacing: 14) {
            HMPanel("Текст телесуфлёра") {
                TextEditor(text: $settings.text).frame(minHeight: 120)
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(DesignTokens.elevated).frame(height: 150)
                    VStack { Text("экрана").foregroundStyle(.secondary); Text("во"); Text("время").font(.title.bold()) }.font(.title2)
                }
                Picker("Источник", selection: $settings.source) { ForEach(TeleprompterContentSource.allCases) { Text($0.title).tag($0) } }
                Button(model.overlay.teleprompter.isVisible ? "Скрыть телесуфлёр" : "Показать телесуфлёр", systemImage: "text.viewfinder") { model.overlay.teleprompter.toggle() }.buttonStyle(HMPrimaryButtonStyle())
            }
            HMPanel("Внешний вид и прокрутка") {
                settingSlider("Прозрачность окна", value: $settings.opacity, range: 0.35...1, suffix: "\(Int(settings.opacity * 100))%")
                settingSlider("Размер текста", value: $settings.fontSize, range: 18...72, suffix: "\(Int(settings.fontSize)) пт")
                settingSlider("Скорость", value: $settings.speed, range: 30...300, suffix: "\(Int(settings.speed)) сл/мин")
                Picker("Расположение", selection: $settings.position) { ForEach(TeleprompterPosition.allCases) { Text($0.title).tag($0) } }
            }
        }
    }

    private var chatPage: some View {
        VStack(spacing: 14) {
            HMPanel("Отображение сообщений") {
                Picker("Порядок сообщений", selection: $messageOrder) { Text("Новые снизу"); Text("Новые сверху") }
                settingSlider("Размер текста сообщений", value: $chatFontSize, range: 11...22, suffix: chatFontSize.formatted(.number.precision(.fractionLength(1))) + " пт")
                Picker("Тема подсветки кода", selection: $codeTheme) { ForEach(["GitHub Dark", "Xcode Dark", "Monokai"], id: \.self) { Text($0) } }
                Toggle("Подсвечивать синтаксис", isOn: .constant(true))
            }
            HMPanel("Прокрутка и группы") {
                Toggle("Умная автопрокрутка", isOn: $smartScroll)
                settingSlider("Скорость автопрокрутки", value: .constant(1), range: 0.25...2, suffix: "100%")
                Toggle("Автоматически сворачивать расшифровки", isOn: $collapseGroups)
                Toggle("Автоматически сворачивать ответы", isOn: $collapseGroups)
            }
            HMPanel("Компактность") {
                Toggle("Компактные быстрые действия", isOn: $compactActions)
                Toggle("Лупа для встроенных схем", isOn: $codeMagnifier)
                Toggle("Отменять генерацию с сохранением полученного текста", isOn: .constant(true))
            }
        }
    }

    private var systemPage: some View {
        VStack(spacing: 14) {
            HMPanel("Язык и защита") {
                Picker("Язык", selection: .constant("Русский")) { Text("Русский"); Text("English") }
                Toggle("Защита от записи экрана", isOn: $screenProtection)
            }
            HMPanel("Прокси") {
                TextField("https://login:password@host:port", text: $proxyURL)
                HStack { Button("Проверить", systemImage: "antenna.radiowaves.left.and.right") {}; Button("Сохранить", systemImage: "square.and.arrow.down") {} }
            }
            HMPanel("Обновления") {
                HStack { VStack(alignment: .leading) { Text("Текущая версия"); Text("Локальная сборка").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Проверить обновления", systemImage: "arrow.clockwise") {} }
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
                HStack { Image(systemName: "internaldrive").font(.title); VStack(alignment: .leading) { Text("Локальные данные приложения"); Text("Размер рассчитывается при открытии папки").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("—").font(.title2.bold()) }
                ProgressView(value: 0.42).tint(DesignTokens.accent)
                storageLegend("Аудиозаписи", "—", .cyan)
                storageLegend("Записи собеседований", "—", .purple)
                storageLegend("Скриншоты", "—", .orange)
                storageLegend("Логи приложения", "—", .yellow)
            }
            HMPanel("Папки") {
                folderRow("Аудиозаписи")
                folderRow("Записи собеседований")
                folderRow("Скриншоты")
                folderRow("Логи приложения")
            }
        }
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

    private func folderRow(_ title: String) -> some View {
        HStack { Text(title); Spacer(); Button("Открыть", systemImage: "folder") {} }
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
        case .models: "Пять слотов и каталог доступных моделей"
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
