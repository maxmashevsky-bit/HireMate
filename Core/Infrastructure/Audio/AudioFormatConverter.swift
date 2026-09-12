import AVFoundation

/// Синхронная нормализация на AudioPipeline actor, никогда в main actor или render callback.
struct AudioFormatConverter {
    private var converters: [AudioSource: AVAudioConverter] = [:]
    mutating func convert(_ frame: AudioFrame, sequence: UInt64) throws -> AudioFrame {
        guard frame.sampleRate.isFinite, (8_000...192_000).contains(frame.sampleRate),
              frame.timestamp.isFinite, !frame.samples.isEmpty, frame.samples.count <= 192_000 else {
            throw AudioPipelineError.invalidFormat
        }
        if frame.sampleRate == 16_000 {
            return AudioFrame(timestamp: frame.timestamp, source: frame.source, sampleRate: 16_000,
                              sequenceNumber: sequence, samples: frame.samples)
        }
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: frame.sampleRate, channels: 1, interleaved: false),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frame.samples.count)),
              let inputData = input.floatChannelData else { throw AudioPipelineError.invalidFormat }
        input.frameLength = AVAudioFrameCount(frame.samples.count)
        frame.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { inputData[0].update(from: base, count: samples.count) }
        }
        if converters[frame.source]?.inputFormat.sampleRate != frame.sampleRate {
            converters[frame.source] = AVAudioConverter(from: inputFormat, to: outputFormat)
        }
        guard let converter = converters[frame.source],
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                           frameCapacity: AVAudioFrameCount(ceil(Double(frame.samples.count) * 16_000 / frame.sampleRate) + 128)) else {
            throw AudioPipelineError.invalidFormat
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        guard status != .error, error == nil, let channels = output.floatChannelData else { throw AudioPipelineError.invalidFormat }
        return AudioFrame(timestamp: frame.timestamp, source: frame.source, sampleRate: 16_000,
                          sequenceNumber: sequence, samples: Array(UnsafeBufferPointer(start: channels[0], count: Int(output.frameLength))))
    }
    mutating func reset() { converters.removeAll() }
}
