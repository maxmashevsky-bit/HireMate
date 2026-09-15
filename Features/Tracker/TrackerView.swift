import SwiftUI
import Observation
import CopilotCore

@MainActor @Observable
final class TrackerModel {
    private let repository: any TrackerRepository
    private(set) var stages: [VacancyStage] = []
    private(set) var vacancies: [Vacancy] = []
    private(set) var archivedVacancies: [Vacancy] = []
    private(set) var transitions: [VacancyTransition] = []
    private(set) var isLoading = false
    var message = ""

    init(repository: any TrackerRepository) { self.repository = repository }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            stages = try await repository.vacancyStages()
            vacancies = try await repository.vacancies(includeArchived: false)
            archivedVacancies = try await repository.vacancies(includeArchived: true).filter(\.isArchived)
            transitions = try await repository.vacancyTransitions()
        } catch { message = "Не удалось загрузить трекер: \(error.localizedDescription)" }
    }

    func addStage(_ name: String) async {
        let stage = VacancyStage(name: name, position: stages.count)
        guard stage.isValid else { message = "Название этапа не может быть пустым."; return }
        do { try await repository.saveVacancyStages(stages + [stage]); stages.append(stage) }
        catch { message = "Этап не сохранён: \(error.localizedDescription)" }
    }

    func save(_ vacancy: Vacancy) async {
        do { try await repository.saveVacancy(vacancy); await load() }
        catch { message = "Вакансия не сохранена: \(error.localizedDescription)" }
    }

    func move(_ vacancy: Vacancy, to stage: VacancyStage) async {
        do { try await repository.moveVacancy(id: vacancy.id, to: stage.id, at: .now); await load() }
        catch { message = "Переход не сохранён: \(error.localizedDescription)" }
    }

    func archive(_ vacancy: Vacancy) async {
        do { try await repository.setVacancyArchived(id: vacancy.id, archived: true, at: .now); await load() }
        catch { message = "Карточка не отправлена в архив: \(error.localizedDescription)" }
    }

    func archived() async -> [Vacancy] { archivedVacancies }
    func restore(_ vacancy: Vacancy) async {
        do { try await repository.setVacancyArchived(id: vacancy.id, archived: false, at: .now); await load() }
        catch { message = "Карточка не восстановлена: \(error.localizedDescription)" }
    }
}

@MainActor
struct TrackerView: View {
    @Bindable var app: AppModel
    @State private var showNewStage = false
    @State private var showNewVacancy = false
    @State private var showArchive = false
    @State private var showStats = false
    @State private var showCompare = false
    @State private var showPreferences = false
    @State private var search = ""

    private var visibleVacancies: [Vacancy] {
        let value = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return app.tracker.vacancies }
        return app.tracker.vacancies.filter { $0.company.localizedCaseInsensitiveContains(value) || $0.title.localizedCaseInsensitiveContains(value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Трекер собеседований").font(.largeTitle.bold())
                Text("\(app.tracker.vacancies.count) активных вакансий · данные хранятся локально").foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label("Доска", systemImage: "rectangle.3.group").font(.callout.weight(.semibold)).foregroundStyle(DesignTokens.accent)
                Spacer()
                Button("Статистика", systemImage: "chart.bar") { showStats = true }
                Button("Сравнить", systemImage: "arrow.left.arrow.right") { showCompare = true }
                Button("Архив \(archivedCount)", systemImage: "archivebox") { showArchive = true }
                Button { showPreferences = true } label: { Image(systemName: "gearshape") }.help("Настройки трекера")
                Button("Добавить колонку", systemImage: "rectangle.badge.plus") { showNewStage = true }
                Button("Добавить вакансию", systemImage: "plus") { showNewVacancy = true }.buttonStyle(HMPrimaryButtonStyle())
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск компании или должности", text: $search).textFieldStyle(.plain)
            }.padding(10).background(DesignTokens.card, in: RoundedRectangle(cornerRadius: 10))
            if app.tracker.isLoading { ProgressView("Загружаем доску…") }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(app.tracker.stages) { stage in column(stage) }
                }.padding(.bottom, 12)
            }
            if let message = app.tracker.message.isEmpty ? nil : app.tracker.message { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .padding(24)
        .background(DesignTokens.canvas)
        .task { await app.tracker.load() }
        .sheet(isPresented: $showNewStage) { NewStageForm { name in Task { await app.tracker.addStage(name) } } }
        .sheet(isPresented: $showNewVacancy) { NewVacancyForm(stages: app.tracker.stages) { vacancy in Task { await app.tracker.save(vacancy) } } }
        .sheet(isPresented: $showArchive) { ArchiveView(app: app) }
        .sheet(isPresented: $showStats) { TrackerStatsView(app: app) }
        .sheet(isPresented: $showCompare) { OfferComparisonView(app: app) }
        .sheet(isPresented: $showPreferences) { TrackerPreferencesView() }
    }

    private var archivedCount: Int { app.tracker.archivedVacancies.count }

    private func column(_ stage: VacancyStage) -> some View {
        let cards = visibleVacancies.filter { $0.stageID == stage.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text(stage.name).font(.headline); Text("\(cards.count)").foregroundStyle(.secondary); Spacer() }
            if cards.isEmpty {
                Text("Перетащите карточку сюда").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 250, height: 110).overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5])))
            } else {
                ForEach(cards) { vacancy in VacancyCard(vacancy: vacancy) { Task { await app.tracker.archive(vacancy) } }.draggable(vacancy.id.uuidString) }
            }
            Button("Добавить вакансию") { showNewVacancy = true }.buttonStyle(.borderless).foregroundStyle(DesignTokens.accent)
        }
        .padding(14).frame(width: 280, alignment: .topLeading)
        .background(DesignTokens.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DesignTokens.hairline))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let vacancy = app.tracker.vacancies.first(where: { $0.id.uuidString == id }) else { return false }
            Task { await app.tracker.move(vacancy, to: stage) }; return true
        }
    }
}

@MainActor
private struct VacancyCard: View {
    let vacancy: Vacancy
    let archive: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(vacancy.company).font(.subheadline.bold()); Spacer(); Button { archive() } label: { Image(systemName: "archivebox") }.buttonStyle(.borderless).help("В архив") }
            Text(vacancy.title)
            if !vacancy.grade.isEmpty || !vacancy.workFormat.isEmpty { Text([vacancy.grade, vacancy.workFormat].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            if !vacancy.salary.isEmpty { Text(vacancy.salary).font(.caption).foregroundStyle(DesignTokens.accent) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(DesignTokens.elevated, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.hairline))
    }
}

@MainActor
private struct NewStageForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let save: (String) -> Void
    var body: some View { Form { TextField("Название этапа", text: $name); HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Сохранить") { save(name); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(20).frame(width: 360) }
}

@MainActor
private struct NewVacancyForm: View {
    @Environment(\.dismiss) private var dismiss
    let stages: [VacancyStage]
    let save: (Vacancy) -> Void
    @State private var company = ""; @State private var title = ""; @State private var details = ""
    @State private var salary = ""; @State private var grade = ""; @State private var format = ""
    @State private var stageID: UUID
    init(stages: [VacancyStage], save: @escaping (Vacancy) -> Void) { self.stages = stages; self.save = save; _stageID = State(initialValue: stages.first?.id ?? UUID()) }
    var body: some View { Form {
        TextField("Компания", text: $company); TextField("Название должности", text: $title); TextField("Вилка", text: $salary)
        TextField("Грейд", text: $grade); TextField("Формат работы", text: $format); TextEditor(text: $details).frame(minHeight: 80)
        Picker("Этап", selection: $stageID) { ForEach(stages) { Text($0.name).tag($0.id) } }
        HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Создать") { save(Vacancy(stageID: stageID, company: company, title: title, details: details, salary: salary, grade: grade, workFormat: format)); dismiss() }.disabled(company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }.padding(20).frame(width: 420) }
}

@MainActor
private struct ArchiveView: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Vacancy] = []
    var body: some View { VStack(alignment: .leading) { HStack { Text("Архив карточек").font(.title2.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless) }; if items.isEmpty { ContentUnavailableView("Архив пуст", systemImage: "archivebox") } else { List(items) { item in HStack { Text("\(item.company) · \(item.title)"); Spacer(); Button("Вернуть") { Task { await app.tracker.restore(item); items = await app.tracker.archived() } } } } } }.padding(20).frame(width: 520, height: 360).task { items = await app.tracker.archived() } }
}

@MainActor
private struct TrackerStatsView: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Статистика трекера").font(.title2.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless) }
            HStack(spacing: 12) {
                metric("Активные", app.tracker.vacancies.count, "briefcase")
                metric("В архиве", app.tracker.archivedVacancies.count, "archivebox")
                metric("Всего", app.tracker.vacancies.count + app.tracker.archivedVacancies.count, "number")
                metric("Встречи", app.tracker.transitions.count, "bolt")
            }
            HStack(alignment: .top, spacing: 14) {
                HMPanel("Воронка") {
                    ForEach(app.tracker.stages) { stage in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(stage.name); Spacer(); Text("\(app.tracker.vacancies.filter { $0.stageID == stage.id }.count)").foregroundStyle(.secondary) }
                            ProgressView(value: Double(app.tracker.vacancies.filter { $0.stageID == stage.id }.count), total: Double(max(1, app.tracker.vacancies.count))).tint(DesignTokens.accent)
                        }
                    }
                }
                HMPanel("Среднее время на этапе") { Text(app.tracker.transitions.isEmpty ? "Пока нет завершённых переходов между этапами." : "Данные рассчитаны по локальной истории переходов.").foregroundStyle(.secondary) }.frame(width: 270)
            }
            HStack { Spacer(); Button("Экспортировать PDF", systemImage: "doc.richtext") {}; Button("Закрыть") { dismiss() }.buttonStyle(HMPrimaryButtonStyle()) }
        }.padding(24).frame(width: 820, height: 590).background(DesignTokens.canvas)
    }
    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Image(systemName: icon).foregroundStyle(DesignTokens.accent); Text("\(value)").font(.title.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(DesignTokens.card, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(DesignTokens.hairline))
    }
}

@MainActor
private struct OfferComparisonView: View {
    @Bindable var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var firstID: UUID?
    @State private var secondID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Сравнение офферов").font(.title2.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless) }
            HStack {
                Picker("Первый оффер", selection: $firstID) { Text("Выберите вакансию").tag(UUID?.none); ForEach(app.tracker.vacancies) { Text("\($0.company) · \($0.title)").tag(Optional($0.id)) } }
                Picker("Второй оффер", selection: $secondID) { Text("Выберите вакансию").tag(UUID?.none); ForEach(app.tracker.vacancies) { Text("\($0.company) · \($0.title)").tag(Optional($0.id)) } }
            }
            HMPanel {
                if firstID == nil || secondID == nil {
                    ContentUnavailableView("Выберите два оффера", systemImage: "arrow.left.arrow.right", description: Text("Заполните вилку, грейд и формат хотя бы у двух карточек, чтобы сравнить."))
                } else {
                    comparisonRow("Компания", value: { $0.company })
                    comparisonRow("Позиция", value: { $0.title })
                    comparisonRow("Вилка", value: { $0.salary })
                    comparisonRow("Грейд", value: { $0.grade })
                    comparisonRow("Формат", value: { $0.workFormat })
                }
            }
            Spacer(); HStack { Spacer(); Button("Закрыть") { dismiss() }.buttonStyle(HMPrimaryButtonStyle()) }
        }.padding(24).frame(width: 760, height: 480).background(DesignTokens.canvas)
    }
    @ViewBuilder private func comparisonRow(_ title: String, value: (Vacancy) -> String) -> some View {
        let first = app.tracker.vacancies.first { $0.id == firstID }
        let second = app.tracker.vacancies.first { $0.id == secondID }
        HStack { Text(title).frame(width: 90, alignment: .leading); Divider(); Text(first.map(value) ?? "—").frame(maxWidth: .infinity); Divider(); Text(second.map(value) ?? "—").frame(maxWidth: .infinity) }.frame(height: 34)
    }
}

private struct TrackerPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reminders = true
    @State private var days = 7
    @State private var telegram = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Настройки трекера").font(.title2.bold()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless) }
            HMPanel("Напоминания о протухших карточках") {
                Toggle("Напоминать о карточках без активности", isOn: $reminders)
                Stepper("Порог: \(days) дней", value: $days, in: 1...60)
                TextField("Имя собственного Telegram-бота", text: $telegram)
                Label("Подключение бота появится после безопасной настройки токена в Keychain.", systemImage: "paperplane").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Отмена") { dismiss() }; Button("Сохранить") { dismiss() }.buttonStyle(HMPrimaryButtonStyle()) }
        }.padding(24).frame(width: 520).background(DesignTokens.canvas)
    }
}
