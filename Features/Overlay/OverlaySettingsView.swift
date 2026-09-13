import SwiftUI

@MainActor
struct OverlaySettingsView: View {
    @Bindable var controller: OverlayController
    @State private var selectedAction: GlobalHotkeyService.Action = .toggle
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
            DisclosureGroup("Переназначить команду") {
                Picker("Команда", selection: $selectedAction) {
                    ForEach(GlobalHotkeyService.Action.allCases, id: \.rawValue) { action in
                        Text(action.title).tag(action)
                    }
                }
                Picker("Клавиша", selection: Binding(
                    get: { effectiveOverride.key },
                    set: { saveOverride(key: $0, usesShift: effectiveOverride.usesShift) }
                )) {
                    ForEach(HotkeyKey.allCases) { key in Text(key.title).tag(key) }
                }
                Toggle("Добавить Shift", isOn: Binding(
                    get: { effectiveOverride.usesShift },
                    set: { saveOverride(key: effectiveOverride.key, usesShift: $0) }
                ))
                HStack {
                    Text("Текущее сочетание: \(effectiveShortcut)")
                    Spacer()
                    Button("По умолчанию") {
                        controller.preferences.setHotkeyOverride(nil, for: selectedAction)
                        controller.configureHotkeys()
                    }
                    .disabled(controller.preferences.hotkeyOverride(for: selectedAction) == nil)
                }
                .font(.caption)
                Text("Если сочетание совпадёт с другой командой или занято системой, оно появится ниже как незарегистрированное.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Control + Option может конфликтовать с VoiceOver. Можно отключить горячие клавиши и использовать меню приложения.")
                .font(.caption).foregroundStyle(.secondary)
            if !controller.hotkeys.issues.isEmpty {
                ForEach(controller.hotkeys.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
            Text(captureNotice)
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: controller.preferences.opacity) { _, _ in controller.applyOpacity() }
        .onChange(of: controller.preferences.shortcutsEnabled) { _, _ in controller.configureHotkeys() }
        .onChange(of: controller.preferences.shortcutPreset) { _, _ in controller.configureHotkeys() }
    }

    private var effectiveOverride: HotkeyOverride {
        controller.preferences.hotkeyOverride(for: selectedAction)
            ?? HotkeyOverride(key: selectedAction.defaultKey, usesShift: selectedAction.needsShift)
    }

    private var captureNotice: String {
        switch controller.compatibilityResult {
        case .excluded:
            "Последний тест ScreenCaptureKit не увидел окно. Это не гарантирует скрытие в сторонних программах трансляции."
        case .captured:
            "Последний тест ScreenCaptureKit увидел окно. Считайте его видимым участникам трансляции."
        case .running:
            "Сейчас выполняется проверка ScreenCaptureKit."
        case .failed(let message):
            "Проверка ScreenCaptureKit не завершена: \(message)"
        case .notTested:
            "Окно исключается из ScreenCaptureKit публичным API, но сторонние программы могут захватывать его иначе. Проверьте результат в «Диагностике»."
        }
    }

    private var effectiveShortcut: String {
        let alternate = selectedAction.needsAlternateBase
            ? (controller.preferences.shortcutPreset == .commandOption ? "⌃" : "⌘") : ""
        return controller.preferences.shortcutPreset.symbols + alternate
            + (effectiveOverride.usesShift ? "⇧" : "") + effectiveOverride.key.title
    }

    private func saveOverride(key: HotkeyKey, usesShift: Bool) {
        controller.preferences.setHotkeyOverride(HotkeyOverride(key: key, usesShift: usesShift), for: selectedAction)
        controller.configureHotkeys()
    }
}
