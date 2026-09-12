import Foundation

public struct RemoteTranscriptionService: TranscriptionService {
    private let configuration: ModelConfiguration
    private let secrets: any SecureSecretStore
    private let network: NetworkClient
    public init(configuration: ModelConfiguration, secrets: any SecureSecretStore, network: NetworkClient) {
        self.configuration = configuration; self.secrets = secrets; self.network = network
    }
    public func transcribe(_ segment: AudioSegment, language: TranscriptionLanguage,
                           vocabulary: [String]) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try configuration.validate(forTranscription: true)
                    guard let key = try await secrets.read(), !key.isEmpty else { throw ProviderError.keyMissing }
                    try Task.checkCancellation()
                    let boundary = "Copilot-" + UUID().uuidString
                    var body = Data()
                    func field(_ name: String, _ value: String) {
                        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
                    }
                    field("model", configuration.transcriptionModel)
                    field("response_format", "json")
                    if language != .automatic { field("language", language.rawValue) }
                    if !vocabulary.isEmpty { field("prompt", vocabulary.prefix(50).joined(separator: ", ").prefix(2_000).description) }
                    body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"segment.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
                    body.append(try WAVEncoder.encode(segment))
                    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
                    var request = URLRequest(url: try configuration.endpoint("audio/transcriptions"))
                    request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = configuration.timeoutSeconds
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    request.setValue(segment.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
                    let data = try await network.data(for: request, kind: "audio")
                    struct Response: Decodable { let text: String }
                    guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw ProviderError.malformedResponse }
                    let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw ProviderError.emptyResponse }
                    try Task.checkCancellation()
                    continuation.yield(.final(TranscriptResult(segment: segment, text: text, isDemo: false)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
