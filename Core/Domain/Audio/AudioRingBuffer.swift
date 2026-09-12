import Foundation

/// Владелец — AudioPipeline actor. Реальный bounded ring, без очереди removeFirst на каждый frame.
public struct AudioRingBuffer: Sendable {
    private var slots: [AudioFrame?]
    private var head = 0
    private var count = 0
    private(set) public var sampleCount = 0
    public let maxSamples: Int
    public init(seconds: Double = 60, sampleRate: Double = 16_000, capacity: Int = 8_192) {
        slots = Array(repeating: nil, count: max(1, capacity))
        maxSamples = Int(min(60, max(0, seconds)) * sampleRate)
    }
    public mutating func append(_ frame: AudioFrame) {
        guard !frame.samples.isEmpty else { return }
        while count > 0 && (count == slots.count || sampleCount + frame.samples.count > maxSamples) { removeOldest() }
        guard frame.samples.count <= maxSamples else { return }
        slots[(head + count) % slots.count] = frame
        count += 1; sampleCount += frame.samples.count
    }
    public func recent(seconds: Double) -> [AudioFrame] {
        guard count > 0, let last = slots[(head + count - 1) % slots.count] else { return [] }
        let cutoff = last.endTime - max(0, seconds)
        var result: [AudioFrame] = []
        for offset in 0..<count {
            guard let frame = slots[(head + offset) % slots.count], frame.endTime > cutoff else { continue }
            if frame.timestamp >= cutoff { result.append(frame) }
            else {
                let skip = min(frame.samples.count, max(0, Int((cutoff - frame.timestamp) * frame.sampleRate)))
                result.append(AudioFrame(timestamp: frame.timestamp + Double(skip) / frame.sampleRate,
                                         source: frame.source, sampleRate: frame.sampleRate,
                                         sequenceNumber: frame.sequenceNumber, samples: Array(frame.samples.dropFirst(skip))))
            }
        }
        return result
    }
    public mutating func clear() {
        while count > 0 { removeOldest() }
        head = 0
    }
    private mutating func removeOldest() {
        guard count > 0 else { return }
        sampleCount -= slots[head]?.samples.count ?? 0
        slots[head] = nil
        head = (head + 1) % slots.count
        count -= 1
    }
}

public struct EnergyVoiceActivityDetector: Sendable {
    public private(set) var state: VoiceState = .idle
    private var speechDuration: Double = 0
    private var silenceDuration: Double = 0
    private var segmentDuration: Double = 0
    public init() {}
    public mutating func process(_ frame: AudioFrame, configuration c: AudioPipelineConfiguration) -> (start: Bool, end: Bool) {
        let hasSpeech = frame.rms >= c.threshold
        let silenceLimit = frame.source == .microphone ? c.micSilence : c.systemSilence
        var started = false
        if state == .finalizing { reset() }
        if hasSpeech {
            silenceDuration = 0
            speechDuration += frame.duration
            if state == .idle { state = .possibleSpeech; segmentDuration = 0 }
            if state == .possibleEnd { state = .speech }
            if state == .possibleSpeech && speechDuration >= c.minSpeech { state = .speech; started = true }
        } else {
            silenceDuration += frame.duration
            if state == .possibleSpeech { reset(); return (false, false) }
            if state == .speech { state = .possibleEnd }
        }
        if state == .speech || state == .possibleEnd { segmentDuration += frame.duration }
        let ended = (state == .possibleEnd && silenceDuration >= silenceLimit) || segmentDuration >= c.chunkSeconds
        if ended { state = .finalizing }
        return (started, ended)
    }
    public mutating func reset() { state = .idle; speechDuration = 0; silenceDuration = 0; segmentDuration = 0 }
}
