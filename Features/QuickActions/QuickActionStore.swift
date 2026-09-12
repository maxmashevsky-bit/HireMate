import Foundation
import Observation
import CopilotCore

@MainActor @Observable
final class QuickActionStore {
    private(set) var actions: [QuickAction]
    private let defaults: UserDefaults
    var message = ""
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: "actions.v1"), let saved = try? JSONDecoder().decode([QuickAction].self, from: bytes),
           saved.count == 5, saved.allSatisfy(\.isValid), Set(saved.map(\.slot)) == Set(1...5) {
            actions = saved.sorted { $0.slot < $1.slot }
        } else { actions = QuickAction.defaults }
    }
    func save(_ action: QuickAction) {
        guard action.isValid, let index = actions.firstIndex(where: { $0.id == action.id }), actions[index].slot == action.slot else {
            message = "Название — 1–15 символов, инструкция — 1–4000; допустимы только слоты 1–5."; return
        }
        var next = actions; next[index] = action
        do { let data = try JSONEncoder().encode(next); defaults.set(data, forKey: "actions.v1"); actions = next; message = "Действие сохранено" }
        catch { message = "Не удалось сохранить действие" }
    }
}
