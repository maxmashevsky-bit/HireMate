import AppKit
import ScreenCaptureKit
import CopilotCore

struct CaptureSource: Identifiable, Equatable {
    enum Kind: Equatable { case display(CGDirectDisplayID), window(CGWindowID) }
    let id: String
    let label: String
    let kind: Kind
}

enum ScreenCaptureError: Error, LocalizedError {
    case permission, missingSource, emptyImage, captureFailed, invalidRegion
    var errorDescription: String? {
        switch self {
        case .permission: "Нет доступа к записи экрана. Разрешение запрашивается отдельно в настройках приложения."
        case .missingSource: "Источник больше не доступен. Обновите список дисплеев и окон."
        case .emptyImage: "Не удалось подготовить изображение."
        case .captureFailed: "Снимок не получен. Проверьте доступ и выбранный источник."
        case .invalidRegion: "Выделите прямоугольник внутри изображения."
        }
    }
}

@MainActor
protocol ScreenCaptureService {
    func sources() async throws -> [CaptureSource]
    func capture(_ source: CaptureSource) async throws -> CGImage
}

@MainActor
final class NativeScreenCapture: ScreenCaptureService {
    func sources() async throws -> [CaptureSource] {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let displays = content.displays.enumerated().map { index, display in
            CaptureSource(id: "d:\(display.displayID)", label: "Дисплей \(index + 1) · \(display.width)×\(display.height)", kind: .display(display.displayID))
        }
        // Названия документов/окон не нужны для захвата и не собираются.
        let windows = content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.frame.width > 1 && $0.frame.height > 1 }
            .enumerated().map { index, window in
                CaptureSource(id: "w:\(window.windowID)", label: "\(window.owningApplication?.applicationName ?? "Приложение") · окно \(index + 1)", kind: .window(window.windowID))
            }
        return displays + windows
    }
    func capture(_ source: CaptureSource) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenCaptureError.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        switch source.kind {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw ScreenCaptureError.missingSource }
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw ScreenCaptureError.missingSource }
            filter = SCContentFilter(desktopIndependentWindow: window)
        }
        let config = SCStreamConfiguration()
        let size = filter.contentRect.size
        let scale = min(CGFloat(filter.pointPixelScale), 4096 / max(max(size.width, size.height), 1))
        config.width = max(1, Int(size.width * scale)); config.height = max(1, Int(size.height * scale))
        config.showsCursor = false; config.capturesAudio = false
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            return image
        } catch is CancellationError { throw CancellationError() }
        catch { throw ScreenCaptureError.captureFailed }
    }
}
