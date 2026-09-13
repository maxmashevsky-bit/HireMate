import SwiftUI

@MainActor
struct OverlaySettingsView: View {
    @Bindable var controller: OverlayController
    var body: some View {
        @Bindable var preferences = controller.preferences
        Section("Окно подсказок") {
            HStack {
                Button(controller.isVisible ? "Скрыть окно" : "Показать окно") { controller.toggle() }
                Button("Вернуть ввод мышью") { controller.focusInput() }
            }
            Slider(value: $preferences.opacity, in: 0.35...1) {
                Text("Непрозрачность")
            }
            Toggle("Глобальные горячие клавиши", isOn: $preferences.shortcutsEnabled)
            Picker("Набор сочетаний", selection: $preferences.shortcutPreset) {
                ForEach(ShortcutPreset.allCases) { Text($0.title).tag($0) }
            }
            Text("\(controller.preferences.shortcutPreset.symbols)B — показать/скрыть; W — пропускать клики; D — ввод; G — стоп; [ / ] — прозрачность. Стрелки — перемещение; Shift + стрелки — размер. Цифры 1–5 — быстрые действия.")
                .font(.caption).foregroundStyle(.secondary)
            Text("H / ⇧H — снимок дисплея / области; N — заметки; Return / ⇧Return — отправить со снимком / без него; ⇧K/L — поддиалоги; P / ⇧P — новый / список; ⇧X — сброс; R — звук; ⇧A — вопросы по паузам. Для прокрутки к набору добавляется третья клавиша-модификатор.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Control + Option может конфликтовать с VoiceOver. Можно отключить горячие клавиши и использовать меню приложения.")
                .font(.caption).foregroundStyle(.secondary)
            if !controller.hotkeys.issues.isEmpty {
                ForEach(controller.hotkeys.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
            Text("Скрытие из трансляции не реализовано. Считайте окно видимым другим участникам, пока совместимость не проверена.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: controller.preferences.opacity) { _, _ in controller.applyOpacity() }
        .onChange(of: controller.preferences.shortcutsEnabled) { _, _ in controller.configureHotkeys() }
        .onChange(of: controller.preferences.shortcutPreset) { _, _ in controller.configureHotkeys() }
    }
}
