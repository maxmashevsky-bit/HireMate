import Foundation
import OSLog

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Не пересылаем Authorization на другой endpoint, даже при redirect внутри того же host.
        completionHandler(nil)
    }
}

public actor NetworkClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.maxmashevsky.MaxInterviewCopilot", category: "network-metadata")
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    public func data(for request: URLRequest, kind: String, maximumBytes: Int = 2_000_000) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (bytes, response) = try await open(request, kind: kind)
                try Self.requireSuccess(response)
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < maximumBytes else { throw ProviderError.responseTooLarge }
                    data.append(byte)
                }
                logger.info("Ответ получен; bytes=\(data.count, privacy: .public)")
                return data
            } catch is CancellationError { throw CancellationError() }
            catch {
                if Task.isCancelled { throw CancellationError() }
                guard attempt < 2, let delay = Self.retryDelay(error: error, attempt: attempt) else {
                    if let known = error as? ProviderError { throw known }
                    throw ProviderError.transport
                }
                attempt += 1
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    public func open(_ request: URLRequest, kind: String) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        // Только тип данных/размер/статус. Не логируем endpoint, headers, ключ, prompt, model или body.
        logger.info("Отправка \(kind, privacy: .public); bytes=\(request.httpBody?.count ?? 0, privacy: .public)")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProviderError.malformedResponse }
            logger.info("HTTP \(http.statusCode, privacy: .public)")
            return (bytes, http)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let known = error as? ProviderError { throw known }
            throw ProviderError.transport
        }
    }
    public static func requireSuccess(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw ProviderError.http(response.statusCode, retryAfter: seconds.map { min(30, max(0, $0)) })
        }
    }
    private static func retryDelay(error: Error, attempt: Int) -> Double? {
        switch error {
        case ProviderError.http(429, let delay): min(30, (delay ?? pow(2, Double(attempt))) + Double.random(in: 0...0.3))
        case ProviderError.http(let code, _) where (500..<600).contains(code): pow(2, Double(attempt)) + Double.random(in: 0...0.3)
        default: nil // Network timeout у POST неоднозначен: без автоматического повторного списания.
        }
    }
}
