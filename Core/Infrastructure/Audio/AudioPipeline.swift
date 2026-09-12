import Foundation

public struct AudioPipelineUpdate: Sendable {
    public let source: AudioSource
    public let level: Float
    public let state: VoiceState
    public let bufferedSeconds: Double
    public let segment: AudioSegment?
}

public actor AudioPipeline {
    private var configuration = AudioPipelineConfiguration()
    private var mode: AudioQuestionMode = .manual
    private var buffers: [AudioSource: AudioRingBuffer] = [:]
    private var detectors: [AudioSource: EnergyVoiceActivityDetector] = [:]
    private var active: [AudioSource: [AudioFrame]] = [:]
    private var manualActive = false
    private var converter = AudioFormatConverter()
    private var sequence: [AudioSource: UInt64] = [:]
    private var lastTimestamp: [AudioSource: Double] = [:]
    private var lastFrameEnd: [AudioSource: Double] = [:]
    public init() {}

    public func configure(_ configuration: AudioPipelineConfiguration, mode: AudioQuestionMode) {
        self.configuration = configuration.bounded(); self.mode = mode
        clear()
    }

    public func process(_ raw: AudioFrame) throws -> AudioPipelineUpdate {
        // Разрыв доставки > 500 мс не является записанной тишиной.
        // Не склеиваем несмежные участки речи в один STT-фрагмент.
        if let end = lastFrameEnd[raw.source], raw.timestamp - end > 0.5 {
            throw AudioPipelineError.interrupted
        }
        let next = (sequence[raw.source] ?? 0) + 1
        sequence[raw.source] = next
        let frame = try converter.convert(raw, sequence: next)
        if let previous = lastTimestamp[frame.source], frame.timestamp < previous { throw AudioPipelineError.invalidFormat }
        lastTimestamp[frame.source] = frame.timestamp
        lastFrameEnd[raw.source] = raw.endTime
        var ring = buffers[frame.source] ?? AudioRingBuffer()
        ring.append(frame)
        buffers[frame.source] = ring
        var detector = detectors[frame.source] ?? EnergyVoiceActivityDetector()
        let transition = detector.process(frame, configuration: configuration)
        detectors[frame.source] = detector
        var completed: AudioSegment?
        if mode == .automatic {
            if transition.start && active[frame.source] == nil {
                active[frame.source] = ring.recent(seconds: max(configuration.preRoll, configuration.minSpeech))
            } else if active[frame.source] != nil { active[frame.source]?.append(frame) }
            if transition.end { completed = finish(source: frame.source, reason: "Пауза или предел фрагмента") }
        } else if mode == .manual && manualActive {
            active[frame.source, default: []].append(frame)
            // Даже забытый ручной сегмент ограничен 60 секундами, raw audio никогда не пишется на диск.
            if Double(active[frame.source, default: []].reduce(0) { $0 + $1.samples.count }) / 16_000 >= 60 {
                completed = finish(source: frame.source, reason: "Достигнут предел 60 секунд")
            }
        }
        return AudioPipelineUpdate(source: frame.source, level: frame.rms, state: detector.state,
                                   bufferedSeconds: Double(ring.sampleCount) / 16_000, segment: completed)
    }

    public func beginManual() {
        manualActive = true
        for source in AudioSource.allCases { active[source] = buffers[source]?.recent(seconds: configuration.preRoll) ?? [] }
    }
    public func finishManual() -> [AudioSegment] {
        manualActive = false
        return AudioSource.allCases.compactMap { finish(source: $0, reason: "Завершено вручную") }
    }
    public func oneShot() -> [AudioSegment] {
        let result = AudioSource.allCases.compactMap { source -> AudioSegment? in
            guard let frames = buffers[source]?.recent(seconds: configuration.oneShot) else { return nil }
            return segment(from: frames, source: source, reason: "Последние \(Int(configuration.oneShot)) секунд")
        }
        if configuration.clearAfterOneShot { clear() }
        return result
    }
    public func clear() {
        buffers.removeAll(); active.removeAll(); detectors.removeAll()
        converter.reset(); sequence.removeAll(); lastTimestamp.removeAll(); lastFrameEnd.removeAll(); manualActive = false
    }
    private func finish(source: AudioSource, reason: String) -> AudioSegment? {
        let frames = active.removeValue(forKey: source) ?? []
        return segment(from: frames, source: source, reason: reason)
    }
    private func segment(from frames: [AudioFrame], source: AudioSource, reason: String) -> AudioSegment? {
        guard let first = frames.first else { return nil }
        if configuration.speechCheck && !frames.contains(where: { $0.rms >= configuration.threshold }) { return nil }
        let samples = Array(frames.flatMap(\.samples).prefix(960_000))
        guard samples.count >= 800 else { return nil }
        return AudioSegment(source: source, startedAt: first.timestamp, samples: samples, reason: reason)
    }
}
