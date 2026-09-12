import AppKit
import Observation
import CopilotCore

@MainActor @Observable
final class AudioSessionModel {
    var inputMode: AudioInputMode = .microphone
    var questionMode: AudioQuestionMode = .manual
    var configuration = AudioPipelineConfiguration()
    var consent = false
    private(set) var isRunning = false
    private(set) var isStarting = false
    private(set) var isStopping = false
    private(set) var isPreparingSegment = false
    private(set) var isClearing = false
    private(set) var isManualQuestion = false
    private(set) var levels: [AudioSource: Float] = [:]
    private(set) var states: [AudioSource: VoiceState] = [:]
    private(set) var buffered: [AudioSource: Double] = [:]
    private(set) var segments: [AudioSegment] = []
    private(set) var elapsed: Double = 0
    var status = "Захват выключен"
    var selectedSegmentID: UUID?
    private let capture: any AudioCaptureService
    private let pipeline = AudioPipeline()
    private var work: Task<Void, Never>?
    private var opening: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    private var runID = UUID()
    private var bufferID = UUID()
    private var sleepObserver: NSObjectProtocol?
    private var firstTimestamp: Double?
    private var lastUIUpdate: [AudioSource: Double] = [:]
    var onSegment: ((AudioSegment) -> Void)?

    init(capture: (any AudioCaptureService)? = nil) {
        self.capture = capture ?? NativeAudioCapture()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.stop(reason: "Mac переходит в сон. Возобновите захват вручную.") }
        }
    }
    var selectedSegment: AudioSegment? { segments.first { $0.id == selectedSegmentID } }
    func start() {
        guard consent, !isStarting, !isRunning, !isStopping, !isClearing else { return }
        let id = UUID(); runID = id
        isStarting = true; status = "Открываем выбранные источники…"
        let mode = inputMode; let questionMode = questionMode; let config = configuration
        opening = Task { [weak self] in
            guard let self else { return }
            do {
                await pipeline.configure(config, mode: questionMode)
                try Task.checkCancellation()
                guard runID == id else { return }
                let frames = try await capture.start(mode: mode)
                try Task.checkCancellation()
                guard runID == id else { return }
                isStarting = false; isRunning = true
                firstTimestamp = nil; lastUIUpdate = [:]; elapsed = 0
                status = "Звук захватывается локально. Файлы не записываются."
                opening = nil
                work = Task { [weak self] in await self?.consume(frames, run: id) }
            } catch {
                guard runID == id else { return }
                opening = nil
                let reason = (error as? AudioPipelineError)?.localizedDescription ?? "Захват прерван"
                // Завершение не ждёт свою собственную startup-задачу.
                Task { [weak self] in
                    guard let self, runID == id else { return }
                    await stop(reason: reason)
                }
            }
        }
    }
    private func consume(_ frames: AsyncThrowingStream<AudioFrame, Error>, run id: UUID) async {
            do {
                for try await frame in frames {
                    try Task.checkCancellation()
                    guard runID == id else { return }
                    guard !isClearing else { continue }
                    let buffer = bufferID
                    let update = try await pipeline.process(frame)
                    guard runID == id else { return }
                    guard bufferID == buffer, !isClearing else { continue }
                    if firstTimestamp == nil { firstTimestamp = frame.timestamp }
                    if frame.timestamp - (lastUIUpdate[frame.source] ?? -.infinity) >= 0.08 {
                        levels[update.source] = update.level; states[update.source] = update.state
                        buffered[update.source] = update.bufferedSeconds
                        elapsed = max(elapsed, frame.timestamp - (firstTimestamp ?? frame.timestamp))
                        lastUIUpdate[frame.source] = frame.timestamp
                    }
                    if let segment = update.segment { accept(segment) }
                }
                if runID == id { await stop(reason: "Источник завершил захват") }
            } catch is CancellationError {
                if runID == id { await stop(reason: "Захват остановлен") }
            } catch {
                if runID == id { await stop(reason: (error as? AudioPipelineError)?.localizedDescription ?? "Захват прерван") }
            }
    }
    func stop(reason: String = "Захват остановлен") async {
        if let closing { await closing.value; return }
        isStopping = true; status = "Останавливаем захват…"
        runID = UUID(); work?.cancel(); work = nil
        bufferID = UUID()
        let startup = opening; opening = nil; startup?.cancel()
        isStarting = false; isManualQuestion = false
        let task = Task { [capture, pipeline] in
            await capture.stop()
            // Не допускаем новый запуск, пока старый start не вернулся из системного API.
            await startup?.value
            await pipeline.clear()
        }
        closing = task
        await task.value
        closing = nil; isStopping = false; isRunning = false
        levels.removeAll(); buffered.removeAll(); states.removeAll()
        lastUIUpdate.removeAll()
        status = reason
    }
    func toggleManualQuestion() async {
        guard isRunning, !isStopping, !isPreparingSegment, !isClearing else { return }
        isPreparingSegment = true
        defer { isPreparingSegment = false }
        let run = runID; let buffer = bufferID
        if isManualQuestion {
            let result = await pipeline.finishManual()
            guard runID == run, bufferID == buffer else { return }
            for segment in result { accept(segment) }
        } else {
            await pipeline.beginManual()
            guard runID == run, bufferID == buffer else { return }
        }
        isManualQuestion.toggle()
    }
    func captureOneShot() async {
        guard isRunning, !isStopping, !isPreparingSegment, !isClearing else { return }
        isPreparingSegment = true
        defer { isPreparingSegment = false }
        let run = runID; let buffer = bufferID
        let result = await pipeline.oneShot()
        guard runID == run, bufferID == buffer else { return }
        for segment in result { accept(segment) }
        if result.isEmpty { status = "В буфере нет фрагмента с достаточным уровнем речи." }
    }
    func clear() async {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        bufferID = UUID()
        let run = runID
        await pipeline.clear()
        guard runID == run else { return }
        segments.removeAll(); selectedSegmentID = nil; buffered.removeAll(); isManualQuestion = false
        levels.removeAll(); states.removeAll(); lastUIUpdate.removeAll()
    }
    func removeSegment(_ id: UUID) {
        segments.removeAll { $0.id == id }
        if selectedSegmentID == id { selectedSegmentID = nil }
    }
    private func accept(_ segment: AudioSegment) {
        segments.append(segment)
        // Максимум 6 × 60 секунд mono/16k Float32 — около 23 МБ независимо от длины встречи.
        if segments.count > 6 { segments.removeFirst(segments.count - 6) }
        selectedSegmentID = segment.id
        onSegment?(segment)
    }
    func shutdown() async {
        await stop()
        segments.removeAll()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
