import SwiftUI
import CopilotCore

@MainActor
struct ContextEditorView: View {
    @Bindable var app: AppModel
    var searchQuery = ""
    @State private var edited = ContextProfile(id: .liveCoding)
    @State private var technologies = ""
    @State private var facts = ""
    @State private var noteTags = ""
    @State private var factsConfirmed = false
    @State private var baseline = ContextProfile(id: .liveCoding)
    private var dirty: Bool {
        edited != baseline || technologies != baseline.technologies.joined(separator: ", ")
            || facts != baseline.verifiedFacts.joined(separator: "\n") || noteTags != (baseline.selectedNoteTags ?? []).joined(separator: ", ")
    }
    @State private var saveMessage = ""
    @State private var pendingProfile: ProfileID?
    @State private var isSaving = false
    @State private var loadID = UUID()
    private func name(for profile: ProfileID) -> String {
        app.conversation.profiles.first { $0.id == profile }?.name ?? profile.title
    }
    private var visibleProfiles: [ProfileID] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProfileID.allCases.filter { query.isEmpty || name(for: $0).localizedStandardContains(query) || $0.title.localizedStandardContains(query) }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if visibleProfiles.isEmpty { Text("Контексты не найдены").foregroundStyle(.secondary) }
                ForEach(visibleProfiles) { profile in
                    Button {
                        guard profile != app.profile else { return }
                        if dirty { pendingProfile = profile }
                        else { app.profile = profile }
                    } label: {
                        HStack {
                            Image(systemName: profile == app.profile ? "slider.horizontal.3" : "briefcase")
                            Text(name(for: profile)).font(.callout.weight(.semibold))
                            Spacer()
                        }.padding(10).background(profile == app.profile ? DesignTokens.elevated : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(profile == app.profile ? DesignTokens.accent : .primary)
                    }.buttonStyle(.plain).disabled(isSaving)
                }
                Spacer()
                Text("Доступны \(ProfileID.allCases.count) встроенных профиля. Создание отдельных контекстов ещё не подключено.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Новый контекст", systemImage: "plus") { }
                    .buttonStyle(.plain).font(.headline).disabled(true)
            }.padding(14).frame(width: 250).background(DesignTokens.sidebar)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(edited.name).font(.title2.bold())
                        HMPanel("Язык ответа", subtitle: "Применяется к следующим AI-ответам после сохранения профиля.") {
                            HStack {
                                Text(edited.responseLanguage)
                                    .font(.callout.weight(.semibold)).foregroundStyle(DesignTokens.accent)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(DesignTokens.accentSoft, in: Capsule())
                            }
                            Menu("Выбрать язык…") {
                                Button("Русский") { edited.responseLanguage = "Русский" }
                                Button("English") { edited.responseLanguage = "English" }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HMPanel("Контекст") {
                            TextEditor(text: $edited.companyInfo)
                                .font(.body).frame(minHeight: 300)
                                .overlay(alignment: .topLeading) {
                                    if edited.companyInfo.isEmpty {
                                        Text("Введите собственный контекст").foregroundStyle(.secondary).padding(7).allowsHitTesting(false)
                                    }
                                }
                        }
                        DisclosureGroup("Дополнительные параметры") {
                            VStack(spacing: 12) {
                                TextField("Название", text: $edited.name)
                                TextField("Целевая роль", text: $edited.role)
                                TextField("Темы и технологии через запятую", text: $technologies)
                                TextEditor(text: $edited.answerFormat).frame(minHeight: 90)
                                Toggle("Использовать подходящие фрагменты заметок", isOn: $edited.usesNotes)
                                TextField("Теги заметок", text: $noteTags)
                                TextEditor(text: $edited.additionalInstructions).frame(minHeight: 75)
                                TextEditor(text: $facts).frame(minHeight: 80)
                                Toggle("Подтверждаю достоверность фактов", isOn: $factsConfirmed)
                            }.padding(.top, 10)
                        }
                    }.padding(22).frame(maxWidth: 980).disabled(isSaving)
                }
                Divider()
                HStack(spacing: 10) {
                    Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(isSaving ? "Сохранение…" : "Сохранить") { Task { await save() } }.buttonStyle(HMPrimaryButtonStyle()).frame(minWidth: 200)
                        .disabled(isSaving || (!facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !factsConfirmed))
                    Button("Деактивировать") { }.disabled(true).help("Встроенный профиль нельзя деактивировать")
                    Button("Протестировать") { app.requestedSection = .home }.disabled(isSaving || dirty)
                        .help("Сначала сохраните правки. Откроется экран ручного вопроса.")
                    Button { } label: { Image(systemName: "doc.on.doc") }.disabled(true).help("Копирование контекста ещё не подключено")
                    Button { } label: { Image(systemName: "trash") }.disabled(true).help("Встроенный профиль нельзя удалить")
                }.padding(14).background(DesignTokens.sidebar)
            }
        }.background(DesignTokens.canvas)
            .task { await app.conversation.loadLibrary(); load() }
            .onChange(of: app.profile) { _, _ in load() }
            .onChange(of: facts) { _, _ in factsConfirmed = false }
            .confirmationDialog("Переключить профиль и отменить несохранённые правки?", isPresented: Binding(get: { pendingProfile != nil }, set: { if !$0 { pendingProfile = nil } })) {
                Button("Переключить и отменить правки", role: .destructive) {
                    if let profile = pendingProfile { app.profile = profile }
                    pendingProfile = nil
                }
                Button("Остаться", role: .cancel) { pendingProfile = nil }
            }
    }
    private func load() {
        loadID = UUID(); pendingProfile = nil
        edited = app.conversation.profiles.first { $0.id == app.profile } ?? ContextProfile(id: app.profile)
        technologies = edited.technologies.joined(separator: ", "); facts = edited.verifiedFacts.joined(separator: "\n")
        baseline = edited; noteTags = (edited.selectedNoteTags ?? []).joined(separator: ", "); factsConfirmed = false; saveMessage = ""
    }
    private func save() async {
        guard !isSaving else { return }
        guard !edited.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, edited.name.count <= 100,
              edited.role.count <= 200, edited.responseLanguage.count <= 80, technologies.count <= 2_000, edited.answerFormat.count <= 8_000, edited.additionalInstructions.count <= 8_000,
              edited.companyInfo.count <= 8_000, facts.count <= 16_000 else { saveMessage = "Сократите слишком длинные поля."; return }
        guard noteTags.count <= 2_000 else { saveMessage = "Сократите список тегов."; return }
        var snapshot = edited
        snapshot.name = snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.selectedNoteTags = noteTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        snapshot.technologies = technologies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        snapshot.verifiedFacts = facts.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let id = loadID
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.conversation.saveProfile(snapshot)
            guard loadID == id, app.profile == snapshot.id else { return }
            edited = snapshot; baseline = snapshot
            noteTags = (snapshot.selectedNoteTags ?? []).joined(separator: ", ")
            technologies = snapshot.technologies.joined(separator: ", ")
            facts = snapshot.verifiedFacts.joined(separator: "\n"); saveMessage = "Сохранено локально"
        } catch {
            if loadID == id, app.profile == snapshot.id { saveMessage = "Не удалось сохранить. Правки остаются на экране." }
        }
    }
}
