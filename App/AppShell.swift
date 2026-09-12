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
        case .home: "sun.max"
        case .meetings: "bubble.left.and.bubble.right"
        case .contexts: "rectangle.stack"
        case .notes: "note.text"
        case .practice: "figure.mind.and.body"
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
    @State private var selection: AppSection? = .home
    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .font(.system(size: 14)).padding(.vertical, 5).tag(section)
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
            .background(DesignTokens.sidebar)
            .navigationTitle("Моя подготовка")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Максим Машевский").font(.subheadline.weight(.semibold))
                    Text("Go Backend · Intern / Junior").font(.caption).foregroundStyle(.secondary)
                    Label(model.providerSettings.configuration.mode == .demo ? "Демо без сети" : "Собственный API", systemImage: model.providerSettings.configuration.mode == .demo ? "network.slash" : "network").font(.caption).foregroundStyle(DesignTokens.accent)
                }.padding()
            }
        } detail: {
            switch selection ?? .home {
            case .notes: NotesView(app: model)
            case .actions: QuickActionsView(app: model)
            case .screenshot: ScreenshotView(app: model)
            case .transcription: TranscriptionView(app: model)
            case .audio: AudioCaptureView(audio: model.audio)
            case .meetings: MeetingsView(app: model)
            case .home: DemoView(model: model)
            case .contexts: ContextEditorView(app: model)
            case .settings: SettingsView(model: model)
            case .diagnostics: DiagnosticsView(model: model)
            default:
                ContentUnavailableView(selection?.rawValue ?? "Раздел", systemImage: selection?.symbol ?? "clock",
                                       description: Text((selection ?? .meetings).milestone + "\nФункция ещё не реализована."))
            }
        }
        .toolbar {
            if model.speech.isSpeaking { Button("Стоп озвучивание") { model.speech.stop() } }
            if model.audio.isRunning {
                Label("Захват звука", systemImage: "mic.fill").foregroundStyle(.red)
                Button("Остановить звук") { Task { await model.audio.stop() } }
            }
            Button("Окно подсказок", systemImage: "macwindow") { model.overlay.toggle() }
        }
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
}
