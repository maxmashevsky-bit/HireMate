import AppKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var finishing = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !finishing else { return .terminateLater }
        finishing = true
        Task {
            model.transcription.cancel()
            model.speech.stop()
            await model.conversation.finishForTermination()
            await model.notes.waitForPendingSave()
            let hasDraft = model.notes.hasEdits || !model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasDraft || model.conversation.unsavedMessageCount > 0 {
                let alert = NSAlert()
                alert.messageText = "Есть несохранённые данные"
                alert.informativeText = "Черновики или ответы, которые не удалось записать на диск, будут потеряны при выходе. Можно остаться, сохранить их или экспортировать встречу."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Остаться в приложении")
                alert.addButton(withTitle: "Завершить без сохранения")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() != .alertSecondButtonReturn {
                    finishing = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            model.screenshot.clear()
            await model.audio.shutdown()
            model.overlay.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
