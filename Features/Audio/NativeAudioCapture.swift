import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CopilotCore

@MainActor
protocol AudioCaptureService: AnyObject {
    func start(mode: AudioInputMode) async throws -> AsyncThrowingStream<AudioFrame, Error>
    func stop() async
}

/// На callback только копирование PCM в value type; normalizing/VAD выполняются actor pipeline.
@MainActor
final class NativeAudioCapture: AudioCaptureService {
    private var engine: AVAudioEngine?
    private var stream: SCStream?
    private var output: SystemAudioOutput?
    private var microphoneOutput: MicrophoneAudioOutput?
    private var continuation: AsyncThrowingStream<AudioFrame, Error>.Continuation?
    private var starting = false
    private var closing: Task<Void, Never>?
    private var generation = UUID()
    private var deviceObserver: NSObjectProtocol?
    private let audioQueue = DispatchQueue(label: "dev.maxmashevsky.copilot.system-audio", qos: .userInitiated)

    func start(mode: AudioInputMode) async throws -> AsyncThrowingStream<AudioFrame, Error> {
        guard !starting, continuation == nil, closing == nil else { throw AudioPipelineError.alreadyRunning }
        if mode.sources.contains(.microphone), AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { throw AudioPipelineError.permission }
        if mode.sources.contains(.system), !CGPreflightScreenCaptureAccess() { throw AudioPipelineError.permission }
        starting = true
        let run = UUID(); generation = run
        let pair = AsyncThrowingStream<AudioFrame, Error>.makeStream(bufferingPolicy: .bufferingNewest(96))
        continuation = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                await self.stop()
            }
        }
        do {
            if mode.sources.contains(.system) {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try Task.checkCancellation()
                guard generation == run, let display = content.displays.first else { throw AudioPipelineError.deviceUnavailable }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48_000
                config.channelCount = 2
                config.width = 2; config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.queueDepth = 3
                // Только audio output: кадры не обрабатываются, не сохраняются и не отправляются.
                let sink = SystemAudioOutput(continuation: pair.continuation)
                let stream = SCStream(filter: filter, configuration: config, delegate: sink)
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: audioQueue)
                self.output = sink; self.stream = stream
                try await stream.startCapture()
                try Task.checkCancellation()
                guard generation == run else { throw CancellationError() }
            }
            if mode.sources.contains(.microphone) {
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioPipelineError.deviceUnavailable }
                // AVAudioEngine вызывает tap на своей realtime-очереди. Явный @Sendable
                // callback не наследует MainActor от NativeAudioCapture и не падает
                // на runtime-проверке Swift 6 при получении первого PCM-буфера.
                let sink = MicrophoneAudioOutput(continuation: pair.continuation)
                let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, when in
                    sink.consume(buffer, at: when)
                }
                input.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
                microphoneOutput = sink
                self.engine = engine
                deviceObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
                    pair.continuation.finish(throwing: AudioPipelineError.interrupted)
                }
                engine.prepare()
                try engine.start()
            }
            starting = false
            return pair.stream
        } catch {
            // Ошибка старого start не должна остановить уже другой stream.
            if generation == run { await stop() }
            if error is CancellationError { throw CancellationError() }
            if let known = error as? AudioPipelineError { throw known }
            throw AudioPipelineError.deviceUnavailable
        }
    }

    func stop() async {
        if let closing { await closing.value; return }
        generation = UUID(); starting = false
        let oldContinuation = continuation; continuation = nil
        let oldStream = stream; stream = nil
        let oldOutput = output; output = nil
        let oldMicrophoneOutput = microphoneOutput; microphoneOutput = nil
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        deviceObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        let task = Task {
            if let oldStream {
                do { try await oldStream.stopCapture() }
                catch { oldContinuation?.finish(throwing: AudioPipelineError.interrupted) }
            }
            withExtendedLifetime((oldOutput, oldMicrophoneOutput)) { oldContinuation?.finish() }
        }
        closing = task
        await task.value
        closing = nil
    }
}

/// Неизолированный получатель tap: AVAudioEngine доставляет PCM не на MainActor.
private final class MicrophoneAudioOutput: Sendable {
    private let continuation: AsyncThrowingStream<AudioFrame, Error>.Continuation

    init(continuation: AsyncThrowingStream<AudioFrame, Error>.Continuation) {
        self.continuation = continuation
    }

    nonisolated func consume(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let mono = PCMReader.mono(buffer) else {
            continuation.finish(throwing: AudioPipelineError.invalidFormat)
            return
        }
        let timestamp = time.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: time.hostTime)
            : ProcessInfo.processInfo.systemUptime
        let frame = AudioFrame(
            timestamp: timestamp,
            source: .microphone,
            sampleRate: buffer.format.sampleRate,
            samples: mono
        )
        if case .dropped = continuation.yield(frame) {
            continuation.finish(throwing: AudioPipelineError.overflow)
        }
    }
}

private enum PCMReader {
    static func mono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let count = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard count > 0, count <= 192_000, channels > 0, channels <= 32,
              let source = buffer.floatChannelData else { return nil }
        var mono = [Float](repeating: 0, count: count)
        for index in 0..<count {
            var sum: Float = 0
            for channel in 0..<channels {
                let value = buffer.format.isInterleaved ? source[0][index * channels + channel] : source[channel][index]
                sum += value.isFinite ? max(-1, min(1, value)) : 0
            }
            mono[index] = sum / Float(channels)
        }
        return mono
    }
}

private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let continuation: AsyncThrowingStream<AudioFrame, Error>.Continuation
    init(continuation: AsyncThrowingStream<AudioFrame, Error>.Continuation) { self.continuation = continuation }
    func stream(_ stream: SCStream, didStopWithError error: Error) { continuation.finish(throwing: AudioPipelineError.interrupted) }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, buffer.isValid, let description = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return }
        let channels = Int(format.channelCount)
        guard channels > 0, channels <= 32 else { continuation.finish(throwing: AudioPipelineError.invalidFormat); return }
        let size = MemoryLayout<AudioBufferList>.size + (channels - 1) * MemoryLayout<AudioBuffer>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(buffer, bufferListSizeNeededOut: nil,
            bufferListOut: list, bufferListSize: size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: &block)
        guard status == noErr, let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list),
              let mono = PCMReader.mono(pcm) else { continuation.finish(throwing: AudioPipelineError.invalidFormat); return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        let frame = AudioFrame(timestamp: timestamp, source: .system, sampleRate: format.sampleRate, samples: mono)
        if case .dropped = continuation.yield(frame) { continuation.finish(throwing: AudioPipelineError.overflow) }
        withExtendedLifetime(block) {}
    }
}
