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
                ForEach(ProfileID.allCases) { profile in
                    Button {
                        if !dirty { app.profile = profile }
                    } label: {
                        HStack {
                            Image(systemName: profile == app.profile ? "slider.horizontal.3" : "briefcase")
                            Text(profile.title).font(.callout.weight(.semibold))
                            Spacer()
                        }.padding(10).background(profile == app.profile ? DesignTokens.elevated : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(profile == app.profile ? DesignTokens.accent : .primary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button("Новый контекст", systemImage: "plus") { saveMessage = "Создание пользовательского контекста пока доступно только как макет." }
                    .buttonStyle(.plain).font(.headline)
            }.padding(14).frame(width: 250).background(DesignTokens.sidebar)
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(edited.name).font(.title2.bold())
                        HMPanel("Языки ответа", subtitle: "Первый язык в списке — на нём модель генерирует ответ. Второй и третий — машинный перевод этого текста.") {
                            HStack {
                                Text(edited.responseLanguage)
                                    .font(.callout.weight(.semibold)).foregroundStyle(DesignTokens.accent)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(DesignTokens.accentSoft, in: Capsule())
                                Image(systemName: "xmark").font(.caption).foregroundStyle(DesignTokens.accent)
                            }
                            Menu("Добавить язык…") {
                                Button("Русский") { edited.responseLanguage = "Русский" }
                                Button("English") { edited.responseLanguage = "English" }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Выбрано 1 из 3").font(.caption).foregroundStyle(.secondary)
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
                    }.padding(22).frame(maxWidth: 980)
                }
                Divider()
                HStack(spacing: 10) {
                    Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Сохранить") { Task { await save() } }.buttonStyle(HMPrimaryButtonStyle()).frame(minWidth: 300)
                        .disabled(!facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !factsConfirmed)
                    Button("Деактивировать") { }
                    Button("Протестировать") { app.requestedSection = .home }
                    Button { } label: { Image(systemName: "doc.on.doc") }.help("Создать копию")
                    Button { } label: { Image(systemName: "trash") }.help("Удалить контекст")
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
