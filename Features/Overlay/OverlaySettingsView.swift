import SwiftUI

@MainActor
struct OverlaySettingsView: View {
    @Bindable var controller: OverlayController
    @State private var selectedAction: GlobalHotkeyService.Action = .toggle
    @State private var hotkeySearch = ""
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
            LabeledContent("Шаг перемещения") {
                HStack {
                    Slider(value: $preferences.moveStep, in: 10...200, step: 5)
                    Text("\(Int(preferences.moveStep)) пт").monospacedDigit().frame(width: 55)
                }
            }
            LabeledContent("Шаг изменения размера") {
                HStack {
                    Slider(value: $preferences.resizeStep, in: 10...200, step: 5)
                    Text("\(Int(preferences.resizeStep)) пт").monospacedDigit().frame(width: 55)
                }
            }
            Toggle("Глобальные горячие клавиши", isOn: $preferences.shortcutsEnabled)
            Picker("Набор сочетаний", selection: $preferences.shortcutPreset) {
                ForEach(ShortcutPreset.allCases) { Text($0.title).tag($0) }
            }
            TextField("Найти команду", text: $hotkeySearch)
            DisclosureGroup("Все текущие сочетания") {
                ForEach(filteredActions, id: \.rawValue) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Text(preferences.shortcutLabel(for: action)).monospaced()
                    }.font(.caption)
                }
            }
            DisclosureGroup("Переназначить команду") {
                Picker("Команда", selection: $selectedAction) {
                    ForEach(GlobalHotkeyService.Action.allCases, id: \.rawValue) { action in
                        Text(action.title).tag(action)
                    }
                }
                HotkeyBindingEditor(controller: controller, action: selectedAction)
            }
            Button("Сбросить все сочетания по умолчанию") {
                preferences.resetAllHotkeys()
                controller.configureHotkeys()
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

    private var filteredActions: [GlobalHotkeyService.Action] {
        let query = hotkeySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return GlobalHotkeyService.Action.allCases }
        return GlobalHotkeyService.Action.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
}

@MainActor
struct HotkeyBindingEditor: View {
    @Bindable var controller: OverlayController
    let action: GlobalHotkeyService.Action

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Команда включена", isOn: Binding(
                get: { controller.preferences.isHotkeyEnabled(action) },
                set: {
                    controller.preferences.setHotkeyEnabled($0, for: action)
                    controller.configureHotkeys()
                }
            ))
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
                Text(controller.preferences.shortcutLabel(for: action)).monospaced()
                Spacer()
                Button("По умолчанию") {
                    controller.preferences.setHotkeyOverride(nil, for: action)
                    controller.preferences.setHotkeyEnabled(true, for: action)
                    controller.configureHotkeys()
                }
                .disabled(controller.preferences.hotkeyOverride(for: action) == nil
                          && controller.preferences.isHotkeyEnabled(action))
            }
            if !controller.preferences.shortcutsEnabled {
                Text("Глобальные горячие клавиши отключены.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if controller.preferences.isHotkeyEnabled(action),
                      !controller.hotkeys.registeredActions.contains(action) {
                Text("Сочетание не зарегистрировано. Выберите другую клавишу или набор сочетаний.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var effectiveOverride: HotkeyOverride {
        controller.preferences.hotkeyOverride(for: action)
            ?? HotkeyOverride(key: action.defaultKey, usesShift: action.needsShift)
    }

    private func saveOverride(key: HotkeyKey, usesShift: Bool) {
        controller.preferences.setHotkeyOverride(HotkeyOverride(key: key, usesShift: usesShift), for: action)
        controller.configureHotkeys()
    }
}
