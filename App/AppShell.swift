import SwiftUI
import CopilotCore

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Сегодня", meetings = "Встречи", contexts = "Контексты", notes = "Заметки"
    case practice = "Тренировки", analysis = "Анализ", resume = "Резюме", vacancies = "Вакансии"
    case audio = "Звук", transcription = "Расшифровка", screenshot = "Снимок экрана"
    case actions = "Быстрые действия", settings = "Настройки", diagnostics = "Диагностика"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .actions: "bolt"
        case .screenshot: "camera.viewfinder"
        case .transcription: "text.bubble"
        case .audio: "waveform"
        case .home: "house"
        case .meetings: "clock.arrow.circlepath"
        case .contexts: "sparkles"
        case .notes: "doc.text"
        case .practice: "rectangle.stack"
        case .analysis: "chart.bar.doc.horizontal"
        case .resume: "doc.text"
        case .vacancies: "briefcase"
        case .settings: "gearshape"
        case .diagnostics: "checkmark.shield"
        }
    }
    var milestone: String {
        switch self {
        case .meetings: "Встречи и история появятся с сохраняемыми поддиалогами в Phase 5."
        case .notes: "Редактор заметок и локальный поиск запланированы в Phase 8."
        case .practice: "Тренировочные интервью и обратная связь запланированы в Phase 10."
        case .analysis: "Разбор записей и расшифровок запланирован в Phase 12."
        case .resume: "Редактор и PDF-экспорт запланированы в Phase 13."
        case .vacancies: "Личный трекер вакансий запланирован в Phase 15."
        default: "Раздел пока не реализован."
        }
    }
}

@MainActor
struct AppShell: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var selection: AppSection = .meetings
    @State private var search = ""
    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DesignTokens.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .tint(DesignTokens.accent)
        .onAppear {
            let opener = openWindow
            model.overlay.openMainWindow = { opener(id: "main") }
            if let next = model.requestedSection { selection = next; model.requestedSection = nil }
        }
        .onChange(of: model.requestedSection) { _, next in
            if let next { selection = next; model.requestedSection = nil }
        }
        .sheet(item: $model.pendingQuickAction) { action in QuickActionConfirmation(app: model, action: action) }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView(model: model) }
        .alert("Настройки", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("Понятно") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            VStack(spacing: 7) {
                ForEach([AppSection.meetings, .vacancies, .contexts, .notes, .practice]) { section in
                    navigationButton(section)
                }
            }
            Spacer(minLength: 16)
            navigationButton(.diagnostics)
            navigationButton(.settings)
        }
        .padding(.vertical, 9)
        .frame(width: 58)
        .background(DesignTokens.sidebar)
    }

    private func navigationButton(_ section: AppSection) -> some View {
        Button { selection = section } label: {
            Image(systemName: section.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(selection == section ? DesignTokens.accent : .primary)
                .background(selection == section ? DesignTokens.accentSoft : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if selection == section {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(DesignTokens.accent.opacity(0.65), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.primary)
                TextField("Поиск…", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 11).frame(width: 360, height: 31)
            .background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Spacer()
                Button("Продолжить", systemImage: "play.fill") { model.overlay.toggle() }
                    .buttonStyle(HMTopBarButtonStyle(accented: false))
                Circle().fill(DesignTokens.accent.opacity(0.22)).frame(width: 30, height: 30)
                    .overlay(Text("ММ").font(.system(size: 10, weight: .bold)).foregroundStyle(DesignTokens.accent))
            }
        }
        .padding(.leading, 80).padding(.trailing, 12).frame(height: 44)
        .background(DesignTokens.sidebar)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .notes: NotesView(app: model)
        case .actions: QuickActionsView(app: model)
        case .screenshot: ScreenshotView(app: model)
        case .transcription: TranscriptionView(app: model)
        case .audio: AudioCaptureView(audio: model.audio)
        case .meetings: MeetingsView(app: model)
        case .vacancies: TrackerView(app: model)
        case .home: DemoView(model: model)
        case .contexts: ContextEditorView(app: model)
        case .settings: SettingsView(model: model)
        case .diagnostics: DiagnosticsView(model: model)
        case .practice: PracticeDashboard(model: model)
        case .analysis: AnalysisDashboard()
        case .resume: ResumeDashboard()
        }
    }
}

private struct HMTopBarButtonStyle: ButtonStyle {
    let accented: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accented ? DesignTokens.accent : Color.primary)
            .padding(.horizontal, 11).frame(height: 29)
            .background(accented ? DesignTokens.accentSoft : DesignTokens.elevated,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(accented ? DesignTokens.accent.opacity(0.7) : DesignTokens.hairline))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct PracticeDashboard: View {
    @Bindable var model: AppModel
    @State private var difficulty = "Junior"
    @State private var duration = 30.0
    @State private var focus = "Go и стандартная библиотека"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HMSectionHeader(title: "Тренировки", subtitle: "Настройте пробное собеседование под выбранный профиль")
                HStack(alignment: .top, spacing: 16) {
                    HMPanel("Новая тренировка", subtitle: "Вопросы формируются отдельно для каждого профиля") {
                        Picker("Профиль", selection: $model.profile) { ForEach(ProfileID.allCases) { Text($0.title).tag($0) } }
                        Picker("Сложность", selection: $difficulty) { ForEach(["Intern", "Junior", "Middle"], id: \.self) { Text($0) } }
                        TextField("Главная тема", text: $focus)
                        LabeledContent("Длительность", value: "\(Int(duration)) мин")
                        Slider(value: $duration, in: 15...90, step: 15)
                        Toggle("Показывать подсказки после ответа", isOn: .constant(true))
                        Button("Начать тренировку", systemImage: "play.fill") { model.overlay.toggle() }.buttonStyle(HMPrimaryButtonStyle())
                    }
                    HMPanel("Последние результаты") {
                        metric("Структура ответа", "—")
                        metric("Техническая точность", "—")
                        metric("Коммуникация", "—")
                        Divider()
                        Text("После первой тренировки здесь появятся оценки и рекомендации.").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 330)
                }
            }.padding(24).frame(maxWidth: DesignTokens.contentWidth)
        }.background(DesignTokens.canvas)
    }
    private func metric(_ name: String, _ value: String) -> some View { HStack { Text(name); Spacer(); Text(value).foregroundStyle(.secondary) } }
}

private struct AnalysisDashboard: View {
    @State private var detailLevel = "Подробно"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HMSectionHeader(title: "Анализ интервью", subtitle: "Разберите запись, расшифровку или сохранённую встречу")
                HMPanel("Источник") {
                    HStack {
                        Button("Выбрать встречу", systemImage: "bubble.left.and.bubble.right") {}
                        Button("Загрузить расшифровку", systemImage: "doc.text") {}
                        Button("Выбрать запись", systemImage: "video") {}
                    }
                    Picker("Глубина анализа", selection: $detailLevel) { ForEach(["Кратко", "Подробно", "По компетенциям"], id: \.self) { Text($0) } }
                    Toggle("Выделить сильные ответы и зоны роста", isOn: .constant(true))
                    Button("Запустить анализ", systemImage: "sparkles") {}.buttonStyle(HMPrimaryButtonStyle())
                }
                HStack(spacing: 16) {
                    HMPanel("Сильные стороны") { Text("Результаты появятся после выбора источника.").foregroundStyle(.secondary) }
                    HMPanel("Зоны роста") { Text("Здесь будут конкретные рекомендации.").foregroundStyle(.secondary) }
                }
                HStack { Spacer(); Button("Экспортировать PDF", systemImage: "square.and.arrow.up") {} }
            }.padding(24).frame(maxWidth: DesignTokens.contentWidth)
        }.background(DesignTokens.canvas)
    }
}

private struct ResumeDashboard: View {
    @State private var role = "Go Backend Developer"
    @State private var summary = ""
    @State private var language = "Русский"
    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HMSectionHeader(title: "Резюме", subtitle: "Подготовьте версию под конкретную вакансию")
                    HMPanel("Основное") {
                        TextField("Целевая роль", text: $role)
                        Picker("Язык", selection: $language) { Text("Русский"); Text("English") }
                        TextEditor(text: $summary).frame(minHeight: 140)
                    }
                    HMPanel("Разделы") {
                        Button("Опыт", systemImage: "briefcase") {}
                        Button("Навыки", systemImage: "hammer") {}
                        Button("Образование", systemImage: "graduationcap") {}
                        Button("Проекты", systemImage: "shippingbox") {}
                    }
                    HStack { Button("Сохранить") {}; Button("Экспортировать PDF", systemImage: "doc.richtext") {}.buttonStyle(HMPrimaryButtonStyle()) }
                }.padding(24)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Предпросмотр").font(.headline)
                Text(role).font(.title.bold())
                Text("Максим Машевский").font(.title3)
                Divider()
                Text(summary.isEmpty ? "Добавьте краткое описание опыта и целей." : summary).foregroundStyle(.secondary)
                Spacer()
            }.padding(28).frame(minWidth: 380).background(DesignTokens.card)
        }.background(DesignTokens.canvas)
    }
}
