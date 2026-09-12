import AppKit
import Observation
import CopilotCore

@MainActor @Observable
final class ScreenshotModel {
    private(set) var sources: [CaptureSource] = []
    var selectedSourceID: String?
    var format: ScreenshotEncoding = .png
    var selection: CGRect?
    var reviewed = false
    private(set) var attachment: ImageAttachment?
    private(set) var isBusy = false
    private(set) var status = "Снимок создаётся только по кнопке и не записывается на диск."
    private let service: any ScreenCaptureService
    private var operation: Task<Void, Never>?
    private var operationID = UUID()
    init(service: (any ScreenCaptureService)? = nil) { self.service = service ?? NativeScreenCapture() }
    func loadSources() {
        cancelOperation(); isBusy = true
        let id = operationID
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { isBusy = false; operation = nil } }
            do {
                let result = try await service.sources(); try Task.checkCancellation()
                guard operationID == id else { return }
                sources = result
                if !result.contains(where: { $0.id == selectedSourceID }) { selectedSourceID = result.first?.id }
                status = result.isEmpty ? "Нет доступных источников." : "Выберите источник и нажмите «Сделать снимок»."
            } catch { if operationID == id { status = (error as? ScreenCaptureError)?.localizedDescription ?? "Не удалось получить список источников." } }
        }
    }
    func capture() {
        guard let source = sources.first(where: { $0.id == selectedSourceID }) else { status = "Выберите источник."; return }
        cancelOperation(); attachment = nil; reviewed = false; selection = nil; isBusy = true
        let id = operationID; let encoding = format
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == id { isBusy = false; operation = nil } }
            do {
                let image = try await service.capture(source); try Task.checkCancellation()
                guard operationID == id else { return }
                attachment = try ImagePreparation.encode(image, format: encoding)
                status = "Просмотрите снимок. Можно выделить область для обрезки или закрашивания."
            } catch { if operationID == id { status = (error as? LocalizedError)?.errorDescription ?? "Снимок не получен." } }
        }
    }
    func applyCrop() { transform { try ImagePreparation.crop($0, normalized: $1) } }
    func applyRedaction() { transform { try ImagePreparation.redact($0, normalized: $1) } }
    private func transform(_ action: (CGImage, CGRect) throws -> CGImage) {
        guard let attachment, let selection else { return }
        do {
            let image = try action(ImagePreparation.decode(attachment), selection)
            self.attachment = try ImagePreparation.encode(image, format: format)
            self.selection = nil; reviewed = false
            status = "Изменения применены к отправляемым данным. Исходное изображение больше не хранится."
        } catch { status = "Не удалось изменить снимок. Предыдущее изображение сохранено в памяти." }
    }
    func changeEncoding() {
        guard let attachment else { return }
        do { self.attachment = try ImagePreparation.encode(ImagePreparation.decode(attachment), format: format); reviewed = false }
        catch { status = "Изображение слишком большое для выбранного формата. Обрежьте его или выберите JPEG." }
    }
    func clear() {
        cancelOperation(); attachment = nil; selection = nil; reviewed = false
        status = "Снимок удалён из памяти приложения."
    }
    private func cancelOperation() { operationID = UUID(); operation?.cancel(); operation = nil; isBusy = false }
}
