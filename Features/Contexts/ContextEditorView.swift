import SwiftUI
import CopilotCore

@MainActor
struct ContextEditorView: View {
    @Bindable var app: AppModel
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
    var body: some View {
        Form {
            Section("Активный контекст") {
                Picker("Профиль", selection: $app.profile) {
                    ForEach(ProfileID.allCases) { Text($0.title).tag($0) }
                }.disabled(dirty)
                Text("Профили и их история разделены. При изменённом тексте сначала сохраните или отмените правки.").font(.caption)
                TextField("Название", text: $edited.name)
                TextField("Целевая роль", text: $edited.role)
                TextField("Язык ответа", text: $edited.responseLanguage)
                TextField("Темы и технологии через запятую", text: $technologies)
                Toggle("Первое лицо — только по подтверждённым фактам", isOn: $edited.firstPerson)
            }
            Section("Локальные заметки") {
                Toggle("Искать подходящие фрагменты для ответа AI", isOn: $edited.usesNotes)
                TextField("Теги заметок (пусто — все разрешённые)", text: $noteTags)
                Text("Учитываются только заметки этого профиля с включённым AI-доступом, максимум четыре фрагмента. Архив исключён.").font(.caption)
            }
            Section("Формат ответа") { TextEditor(text: $edited.answerFormat).frame(minHeight: 90) }
            Section("Компания и вакансия") { TextEditor(text: $edited.companyInfo).frame(minHeight: 70) }
            Section("Дополнительные инструкции") { TextEditor(text: $edited.additionalInstructions).frame(minHeight: 70) }
            Section("Подтверждённые факты опыта — один на строку") {
                TextEditor(text: $facts).frame(minHeight: 100)
                Toggle("Подтверждаю достоверность перечисленных фактов", isOn: $factsConfirmed)
                Text("Навыки, Rapid, стаж и метрики не добавляются автоматически. Пустой список допустим.").font(.caption)
            }
            HStack {
                Button("Сохранить контекст") { Task { await save() } }
                    .disabled(!facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !factsConfirmed)
                Button("Отменить правки") { load() }
                Text(saveMessage).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Контексты")
            .task { await app.conversation.loadLibrary(); load() }
            .onChange(of: app.profile) { _, _ in load() }
            .onChange(of: facts) { _, _ in factsConfirmed = false }
    }
    private func load() {
        edited = app.conversation.profiles.first { $0.id == app.profile } ?? ContextProfile(id: app.profile)
        technologies = edited.technologies.joined(separator: ", "); facts = edited.verifiedFacts.joined(separator: "\n")
        baseline = edited; noteTags = (edited.selectedNoteTags ?? []).joined(separator: ", "); factsConfirmed = false; saveMessage = ""
    }
    private func save() async {
        guard !edited.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, edited.name.count <= 100,
              edited.role.count <= 200, edited.responseLanguage.count <= 80, technologies.count <= 2_000, edited.answerFormat.count <= 8_000, edited.additionalInstructions.count <= 8_000,
              edited.companyInfo.count <= 8_000, facts.count <= 16_000 else { saveMessage = "Сократите слишком длинные поля."; return }
        guard noteTags.count <= 2_000 else { saveMessage = "Сократите список тегов."; return }
        edited.selectedNoteTags = noteTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        edited.technologies = technologies.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        edited.verifiedFacts = facts.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        do { try await app.conversation.saveProfile(edited); baseline = edited; noteTags = (edited.selectedNoteTags ?? []).joined(separator: ", "); technologies = edited.technologies.joined(separator: ", "); facts = edited.verifiedFacts.joined(separator: "\n"); saveMessage = "Сохранено локально" }
        catch { saveMessage = "Не удалось сохранить. Правки остаются на экране." }
    }
}
