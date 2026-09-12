import Foundation

public struct FakeStreamingProvider: StreamingLLMProvider {
    public init() {}
    public func stream(_ request: GenerationRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started(request.id))
                    for try await text in FakeLLMProvider().stream(DemoRequest(profile: request.profileID, question: request.currentQuestion)) {
                        try Task.checkCancellation(); continuation.yield(.textDelta(text))
                    }
                    continuation.yield(.completed); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

/// SSE на bytes: разорванный UTF-8 сохраняется до окончания строки; bounded line/event buffers.
public struct SSEDecoder: Sendable {
    private var line = Data()
    private var eventLines: [String] = []
    private var eventBytes = 0
    private var afterCarriageReturn = false
    private var firstLine = true
    public init() {}
    public mutating func consume(_ byte: UInt8) throws -> String? {
        if afterCarriageReturn {
            afterCarriageReturn = false
            if byte == 10 { return nil }
        }
        if byte != 10 && byte != 13 {
            guard line.count < 262_144 else { throw ProviderError.responseTooLarge }
            line.append(byte); return nil
        }
        afterCarriageReturn = byte == 13
        guard var text = String(data: line, encoding: .utf8) else { throw ProviderError.malformedResponse }
        if firstLine {
            firstLine = false
            if text.first == "\u{FEFF}" { text.removeFirst() }
        }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty {
            defer { eventLines.removeAll(keepingCapacity: true); eventBytes = 0 }
            return eventLines.isEmpty ? nil : eventLines.joined(separator: "\n")
        }
        if text == "data" || text.hasPrefix("data:") {
            var data = text == "data" ? "" : String(text.dropFirst(5))
            if data.first == " " { data.removeFirst() }
            eventBytes += data.utf8.count + 1
            guard eventBytes <= 1_048_576, eventLines.count < 16_384 else { throw ProviderError.responseTooLarge }
            eventLines.append(data)
        }
        return nil
    }
}

public struct OpenAICompatibleLLMProvider: StreamingLLMProvider {
    private let configuration: ModelConfiguration
    private let secrets: any SecureSecretStore
    private let network: NetworkClient
    public init(configuration: ModelConfiguration, secrets: any SecureSecretStore, network: NetworkClient) {
        self.configuration = configuration; self.secrets = secrets; self.network = network
    }
    public func stream(_ request: GenerationRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(512)) { continuation in
            let task = Task {
                do {
                    try configuration.validate()
                    guard request.attachments.isEmpty || configuration.visionEnabled else { throw ProviderError.unsupportedFeature }
                    guard request.attachments.count <= 1 else { throw ProviderError.responseTooLarge }
                    guard let key = try await secrets.read(), !key.isEmpty else { throw ProviderError.keyMissing }
                    struct Body: Encodable {
                        let model: String
                        let messages: [WireMessage]
                        let stream = true
                        let max_tokens: Int
                    }
                    var http = URLRequest(url: try configuration.endpoint("chat/completions"))
                    http.httpMethod = "POST"; http.timeoutInterval = configuration.timeoutSeconds
                    http.httpBody = try JSONEncoder().encode(Body(model: configuration.textModel, messages: request.messages.enumerated().map { index, message in
                        WireMessage(message: message, images: index == request.messages.count - 1 ? request.attachments : [])
                    }, max_tokens: configuration.reservedOutputTokens))
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    http.setValue(request.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
                    let (bytes, response) = try await network.open(http, kind: "text")
                    try NetworkClient.requireSuccess(response)
                    let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
                    guard contentType.contains("text/event-stream") else { throw ProviderError.malformedResponse }
                    continuation.yield(.started(request.id))
                    var decoder = SSEDecoder()
                    var total = 0
                    var done = false
                    var hasText = false
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        total += 1
                        guard total <= 8_388_608 else { throw ProviderError.responseTooLarge }
                        guard let event = try decoder.consume(byte) else { continue }
                        if event == "[DONE]" { done = true; break }
                        guard let data = event.data(using: .utf8), let chunk = try? JSONDecoder().decode(Chunk.self, from: data), chunk.error == nil else {
                            throw ProviderError.malformedResponse
                        }
                        if let usage = chunk.usage { continuation.yield(.usage(input: usage.prompt_tokens, output: usage.completion_tokens)) }
                        for choice in chunk.choices ?? [] {
                            if let text = choice.delta?.content, !text.isEmpty {
                                hasText = true
                                if case .dropped = continuation.yield(.textDelta(text)) { throw ProviderError.responseTooLarge }
                            }
                            if let calls = choice.delta?.tool_calls, !calls.isEmpty { throw ProviderError.unsupportedFeature }
                            if choice.finish_reason != nil { done = true }
                        }
                    }
                    guard done else { throw ProviderError.incompleteStream }
                    guard hasText else { throw ProviderError.emptyResponse }
                    continuation.yield(.completed); continuation.finish()
                } catch {
                    if Task.isCancelled { continuation.finish(throwing: CancellationError()) }
                    else if let known = error as? ProviderError { continuation.finish(throwing: known) }
                    else { continuation.finish(throwing: ProviderError.transport) }
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    private struct WireMessage: Encodable {
        let message: PromptMessage
        let images: [ImageAttachment]
        enum CodingKeys: String, CodingKey { case role, content }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message.role, forKey: .role)
            if images.isEmpty { try container.encode(message.content, forKey: .content) }
            else {
                var content = container.nestedUnkeyedContainer(forKey: .content)
                try content.encode(TextPart(type: "text", text: message.content))
                for image in images { try content.encode(ImagePart(type: "image_url", image_url: .init(url: image.dataURL, detail: "high"))) }
            }
        }
        struct TextPart: Encodable { let type: String; let text: String }
        struct ImagePart: Encodable {
            let type: String; let image_url: ImageURL
            struct ImageURL: Encodable { let url: String; let detail: String }
        }
    }
    private struct Chunk: Decodable {
        let choices: [Choice]?
        let usage: Usage?
        let error: ErrorPayload?
        struct ErrorPayload: Decodable { let message: String? }
        struct Usage: Decodable { let prompt_tokens: Int?; let completion_tokens: Int? }
        struct Choice: Decodable {
            let delta: Delta?
            let finish_reason: String?
            struct Delta: Decodable {
                let content: String?
                let tool_calls: [ToolCall]?
                struct ToolCall: Decodable { let index: Int? }
            }
        }
    }
}
