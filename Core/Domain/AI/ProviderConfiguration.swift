import Foundation

public enum ProviderMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case demo, remote
    public var id: String { rawValue }
    public var title: String { self == .demo ? "Демо без сети" : "Собственный API" }
}

/// Ключа здесь нет: конфигурацию можно сериализовать и экспортировать.
public struct ModelConfiguration: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var mode: ProviderMode = .demo
    public var baseURL = ""
    public var textModel = ""
    public var transcriptionModel = ""
    public var supportsVision: Bool? = false
    public var visionEnabled: Bool { get { supportsVision ?? false } set { supportsVision = newValue } }
    public var maxContextTokens = 16_384
    public var reservedOutputTokens = 1_024
    public var timeoutSeconds: Double = 60
    public var allowLocalEndpoint = false
    public var secretReference = "ai.primary"
    public init() {}
    public func endpoint(_ route: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(),
              !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw ProviderError.invalidEndpoint }
        let local = host == "localhost" || host == "::1" || host == "[::1]" || host.hasPrefix("127.")
        let network = local || host.hasSuffix(".local") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") || Self.isPrivate172(host)
        guard scheme == "https" || (scheme == "http" && local && allowLocalEndpoint) else { throw ProviderError.insecureEndpoint }
        if network && !allowLocalEndpoint { throw ProviderError.localEndpointNotAllowed }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/" + route
        guard let url = components.url else { throw ProviderError.invalidEndpoint }
        return url
    }
    public func validate(forTranscription: Bool = false) throws {
        _ = try endpoint(forTranscription ? "audio/transcriptions" : "chat/completions")
        let model = forTranscription ? transcriptionModel : textModel
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.count <= 256, !model.contains("\r"), !model.contains("\n") else { throw ProviderError.modelMissing }
        guard (1_024...1_048_576).contains(maxContextTokens), reservedOutputTokens >= 128,
              reservedOutputTokens < maxContextTokens, (5...180).contains(timeoutSeconds) else { throw ProviderError.invalidBudget }
    }
    private static func isPrivate172(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts[0] == "172", let number = Int(parts[1]) else { return false }
        return (16...31).contains(number)
    }
}

public enum ProviderError: Error, LocalizedError, Sendable {
    case invalidEndpoint, insecureEndpoint, localEndpointNotAllowed, modelMissing, keyMissing, invalidBudget
    case malformedResponse, responseTooLarge, emptyResponse, unsupportedFeature, contextTooLarge
    case http(Int, retryAfter: Double?), transport, incompleteStream
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Укажите базовый URL API без логина, пароля, query и fragment. Например, адрес сервера с окончанием /v1."
        case .insecureEndpoint: "Нужен HTTPS. HTTP допускается только для явно разрешённого localhost."
        case .localEndpointNotAllowed: "Локальный адрес требует отдельного разрешения в настройках."
        case .modelMissing: "Введите корректное имя модели."
        case .keyMissing: "В Keychain нет ключа. Сохраните его в настройках."
        case .invalidBudget: "Проверьте лимит контекста, резерв ответа и таймаут."
        case .malformedResponse: "Сервер вернул ответ неподдерживаемого формата."
        case .responseTooLarge: "Ответ сервера превышает безопасный размер."
        case .emptyResponse: "Сервер вернул пустой результат."
        case .unsupportedFeature: "Эта возможность модели ещё не поддерживается адаптером."
        case .contextTooLarge: "Текущий вопрос и обязательные инструкции превышают бюджет. Сократите вопрос или увеличьте лимит контекста."
        case .http(let code, _):
            switch code {
            case 401, 403: "API отклонил доступ (\(code)). Проверьте ключ и права."
            case 429: "Достигнут лимит провайдера. Повторите запрос позже."
            default: "API вернул ошибку HTTP \(code). Содержимое ответа не записано в журнал."
            }
        case .transport: "Ошибка подключения. Проверьте сеть и адрес API."
        case .incompleteStream: "Поток оборвался до подтверждённого завершения. Полученный текст сохранён; автоматического повторения нет."
        }
    }
}
