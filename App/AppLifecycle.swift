import AppKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var finishing = false

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, !finishing else { return false }
        guard let model else { return true }
        model.overlay.openMain()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !finishing else { return .terminateLater }
        finishing = true
        Task {
            model.transcription.cancel()
            model.speech.stop()
            await model.conversation.finishForTermination()
            await model.notes.waitForPendingSave()
            await model.transcription.waitForPendingHistoryWrites()
            let hasDraft = model.notes.hasEdits || !model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasDraft || model.conversation.unsavedMessageCount > 0 || model.transcription.unsavedTranscriptCount > 0 {
                let alert = NSAlert()
                alert.messageText = "Есть несохранённые данные"
                alert.informativeText = "Черновики, ответы или расшифровки, которые не удалось записать на диск, будут потеряны при выходе. Можно остаться и повторить сохранение."
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
