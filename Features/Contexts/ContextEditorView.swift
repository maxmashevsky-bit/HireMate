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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Контексты").font(.title3.bold()).padding(.bottom, 5)
                ForEach(ProfileID.allCases) { profile in
                    Button {
                        if !dirty { app.profile = profile }
                    } label: {
                        HStack {
                            Image(systemName: profile == app.profile ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 2) { Text(profile.title).font(.callout.weight(.semibold)); Text(profile == app.profile ? "Активный" : "Отдельная история").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                        }.padding(9).background(profile == app.profile ? DesignTokens.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(profile == app.profile ? DesignTokens.accent : .primary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button("Новый контекст", systemImage: "plus") { saveMessage = "Пользовательские контексты будут добавлены отдельным сохранением." }
                    .buttonStyle(HMPrimaryButtonStyle())
            }.padding(14).frame(width: 218).background(DesignTokens.sidebar)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            HMSectionHeader(title: edited.name, subtitle: "Настройка языка, формата ответа и локального контекста")
                            Spacer()
                            HMStatusPill(text: "Используется")
                            Button("Копия", systemImage: "doc.on.doc") {}
                            Button("Протестировать", systemImage: "play") { app.requestedSection = .home }
                            Button { } label: { Image(systemName: "trash") }.help("Удалить контекст")
                        }
                        HMPanel("Основные параметры") {
                            TextField("Название", text: $edited.name)
                            TextField("Целевая роль", text: $edited.role)
                            Picker("Язык ответа", selection: $edited.responseLanguage) { Text("Русский"); Text("English") }
                            TextField("Темы и технологии через запятую", text: $technologies)
                            Toggle("Первое лицо — только по подтверждённым фактам", isOn: $edited.firstPerson)
                        }
                        HMPanel("Контекст") {
                            TextEditor(text: $edited.companyInfo).frame(minHeight: 95)
                            Text("Компания, вакансия и информация, которую можно учитывать в ответах.").font(.caption).foregroundStyle(.secondary)
                        }
                        HMPanel("Язык и структура ответа") {
                            TextEditor(text: $edited.answerFormat).frame(minHeight: 105)
                        }
                        HMPanel("Локальные заметки") {
                            Toggle("Использовать подходящие фрагменты заметок", isOn: $edited.usesNotes)
                            TextField("Теги заметок", text: $noteTags)
                        }
                        HMPanel("Дополнительные инструкции") { TextEditor(text: $edited.additionalInstructions).frame(minHeight: 85) }
                        HMPanel("Подтверждённые факты опыта") {
                            TextEditor(text: $facts).frame(minHeight: 100)
                            Toggle("Подтверждаю достоверность перечисленных фактов", isOn: $factsConfirmed)
                        }
                    }.padding(22).frame(maxWidth: 980)
                }
                Divider()
                HStack {
                    Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Отменить правки") { load() }
                    Button("Сохранить") { Task { await save() } }.buttonStyle(HMPrimaryButtonStyle())
                        .disabled(!facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !factsConfirmed)
                }.padding(14).background(DesignTokens.sidebar)
            }
        }.background(DesignTokens.canvas)
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
