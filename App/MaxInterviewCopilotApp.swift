import AppKit
import SwiftUI

@main
@MainActor
struct MaxInterviewCopilotApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("HireMate", id: "main") {
            AppShell(model: model)
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(model.theme == .system ? nil : (model.theme == .dark ? .dark : .light))
                .tint(DesignTokens.accent)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    lifecycle.model = model
                }
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .help) {
                Button("Открыть знакомство с приложением") { model.showOnboarding = true }
            }
        }
        Settings { SettingsView(model: model).frame(width: 1120, height: 760) }
        MenuBarExtra("HireMate", systemImage: "bubble.left.and.text.bubble.right") {
            MenuContent(model: model)
        }
    }
}

@MainActor
private struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.providerSettings.configuration.mode == .demo ? "Локальное демо • без сети" : "Собственный API • отправка по команде")
        Button("Открыть главное окно") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        if model.audio.isRunning {
            Text("Захват звука включён")
            Button("Остановить захват звука") { Task { await model.audio.stop() } }
        }
        Button(model.overlay.isVisible ? "Скрыть окно подсказок" : "Показать окно подсказок") { model.overlay.toggle() }
        Button("Вернуть ввод в окне подсказок") { model.overlay.focusInput() }
        Button("Остановить ответ") { model.stop() }.disabled(!model.isGenerating)
        if model.speech.isSpeaking { Button("Остановить озвучивание") { model.speech.stop() } }
        Divider()
        Button("Завершить приложение") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
