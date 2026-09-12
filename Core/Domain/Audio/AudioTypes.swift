import Foundation

public enum AudioSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case microphone, system
    public var id: String { rawValue }
    public var title: String { self == .microphone ? "Микрофон" : "Системный звук" }
}

public enum AudioInputMode: String, CaseIterable, Sendable, Identifiable {
    case microphone, system, combined
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .microphone: "Микрофон"
        case .system: "Системный звук"
        case .combined: "Микрофон + система"
        }
    }
    public var sources: [AudioSource] {
        switch self {
        case .microphone: [.microphone]
        case .system: [.system]
        case .combined: [.microphone, .system]
        }
    }
}

public enum AudioQuestionMode: String, CaseIterable, Sendable, Identifiable {
    case manual, oneShot, automatic
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .manual: "Начать / завершить вопрос"
        case .oneShot: "Последние секунды"
        case .automatic: "По паузам речи"
        }
    }
}

/// PCM mono Float32; monotonic timestamp не содержит wall-clock/PII.
public struct AudioFrame: Sendable {
    public let timestamp: TimeInterval
    public let source: AudioSource
    public let sampleRate: Double
    public let sequenceNumber: UInt64
    public let samples: [Float]
    public var channelCount: Int { 1 }
    public var duration: TimeInterval { Double(samples.count) / sampleRate }
    public var endTime: TimeInterval { timestamp + duration }
    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
    }
    public init(timestamp: TimeInterval, source: AudioSource, sampleRate: Double,
                sequenceNumber: UInt64 = 0, samples: [Float]) {
        self.timestamp = timestamp
        self.source = source
        self.sampleRate = sampleRate
        self.sequenceNumber = sequenceNumber
        self.samples = samples
    }
}

public struct AudioSegment: Identifiable, Sendable {
    public let id: UUID
    public let source: AudioSource
    public let startedAt: TimeInterval
    public let sampleRate: Double
    public let samples: [Float]
    public let reason: String
    public var duration: TimeInterval { Double(samples.count) / sampleRate }
    public init(id: UUID = UUID(), source: AudioSource, startedAt: TimeInterval,
                sampleRate: Double = 16_000, samples: [Float], reason: String) {
        self.id = id; self.source = source; self.startedAt = startedAt
        self.sampleRate = sampleRate; self.samples = samples; self.reason = reason
    }
}

public struct AudioPipelineConfiguration: Sendable {
    public var preRoll: Double = 4
    public var oneShot: Double = 20
    public var chunkSeconds: Double = 7
    public var micSilence: Double = 0.5
    public var systemSilence: Double = 1
    public var threshold: Float = 0.015
    public var minSpeech: Double = 0.15
    public var speechCheck = true
    public var clearAfterOneShot = true
    public init() {}
    public func bounded() -> Self {
        var result = self
        result.preRoll = preRoll.isFinite ? min(15, max(0, preRoll)) : 4
        result.oneShot = oneShot.isFinite ? min(60, max(5, oneShot)) : 20
        result.chunkSeconds = chunkSeconds.isFinite ? min(15, max(5, chunkSeconds)) : 7
        result.micSilence = micSilence.isFinite ? min(5, max(0.5, micSilence)) : 0.5
        result.systemSilence = systemSilence.isFinite ? min(5, max(0.5, systemSilence)) : 1
        result.threshold = threshold.isFinite ? min(0.3, max(0.001, threshold)) : 0.015
        result.minSpeech = min(1, max(0.05, minSpeech))
        return result
    }
}

public enum VoiceState: String, Sendable {
    case idle = "Тишина", possibleSpeech = "Возможна речь", speech = "Речь"
    case possibleEnd = "Пауза", finalizing = "Завершение"
}

public enum AudioPipelineError: Error, LocalizedError, Sendable {
    case permission, deviceUnavailable, invalidFormat, overflow, interrupted, alreadyRunning
    public var errorDescription: String? {
        switch self {
        case .permission: "Доступ к выбранному источнику не подтверждён. Откройте диагностику разрешений."
        case .deviceUnavailable: "Выбранный источник звука недоступен."
        case .invalidFormat: "Не удалось обработать формат аудио."
        case .overflow: "Обработка звука не успевает за захватом. Захват остановлен; запустите его снова."
        case .interrupted: "Захват прерван системой. Возобновите его вручную."
        case .alreadyRunning: "Захват уже запущен."
        }
    }
}
