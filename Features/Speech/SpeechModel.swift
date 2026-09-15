import AVFoundation
import Foundation
import Observation

@MainActor
protocol TextToSpeechService {
    func speak(_ text: String)
    func pause()
    func resume()
    func stop()
}

@MainActor @Observable
final class SpeechModel: NSObject, TextToSpeechService, AVSpeechSynthesizerDelegate {
    private let defaults: UserDefaults
    var language: String { didSet { defaults.set(language, forKey: "speech.language"); if oldValue != language { stop(); chooseCompatibleVoice() } } }
    var voiceID: String { didSet { defaults.set(voiceID, forKey: "speech.voiceID"); if oldValue != voiceID { stop() } } }
    var rate: Float { didSet { defaults.set(rate, forKey: "speech.rate") } }
    var volume: Float { didSet { defaults.set(volume, forKey: "speech.volume") } }
    var skipCodeBlocks: Bool { didSet { defaults.set(skipCodeBlocks, forKey: "speech.skipCodeBlocks") } }
    var autoRead: Bool { didSet { defaults.set(autoRead, forKey: "speech.autoRead") } }
    var routingAcknowledged = false
    private(set) var voices: [AVSpeechSynthesisVoice] = []
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var status = "Озвучивание выключено"
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: "speech.language") ?? "ru-RU"
        voiceID = defaults.string(forKey: "speech.voiceID") ?? ""
        let storedRate = defaults.object(forKey: "speech.rate") as? NSNumber
        rate = storedRate?.floatValue ?? AVSpeechUtteranceDefaultSpeechRate
        let storedVolume = defaults.object(forKey: "speech.volume") as? NSNumber
        volume = storedVolume.map { min(1, max(0, $0.floatValue)) } ?? 1
        skipCodeBlocks = defaults.object(forKey: "speech.skipCodeBlocks") == nil
            ? true : defaults.bool(forKey: "speech.skipCodeBlocks")
        autoRead = defaults.bool(forKey: "speech.autoRead")
        super.init()
        synthesizer.delegate = self
        reloadVoices()
    }
    var compatibleVoices: [AVSpeechSynthesisVoice] { voices.filter { $0.language.hasPrefix(language.prefix(2)) } }
    func reloadVoices() {
        voices = AVSpeechSynthesisVoice.speechVoices().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        chooseCompatibleVoice()
    }
    private func chooseCompatibleVoice() {
        if !compatibleVoices.contains(where: { $0.identifier == voiceID }) { voiceID = compatibleVoices.first?.identifier ?? "" }
    }
    func speak(_ text: String) {
        let prepared = skipCodeBlocks ? Self.removingFencedCode(from: text) : text
        let input = prepared.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { status = "Нет текста для озвучивания"; return }
        guard input.count <= 24_000 else { status = "Текст слишком длинный для озвучивания. Выберите более короткий ответ."; return }
        stop()
        guard let voice = compatibleVoices.first(where: { $0.identifier == voiceID }) else { status = "Для выбранного языка нет установленного голоса. Выберите его в системных настройках."; return }
        let utterance = AVSpeechUtterance(string: input)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
        utterance.volume = min(1, max(0, volume))
        activeUtterance = utterance; isSpeaking = true; isPaused = false; status = "Озвучивание через системный аудиовыход"
        synthesizer.speak(utterance)
    }
    func pause() { if synthesizer.pauseSpeaking(at: .immediate) { isPaused = true; status = "Пауза" } }
    func resume() { if synthesizer.continueSpeaking() { isPaused = false; status = "Озвучивание" } }
    func stop() {
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false; isPaused = false; status = "Озвучивание остановлено"
    }
    // Delegate callbacks не переносят non-Sendable utterance между actors.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(identifier) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(identifier) }
    }
    private func finished(_ identifier: ObjectIdentifier) {
        guard let activeUtterance, ObjectIdentifier(activeUtterance) == identifier else { return }
        self.activeUtterance = nil; isSpeaking = false; isPaused = false; status = "Озвучивание завершено"
    }

    static func removingFencedCode(from markdown: String) -> String {
        var fence: Character?
        var fenceLength = 0
        var output: [Substring] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let marker = trimmed.first
            let run = marker.map { character in trimmed.prefix(while: { $0 == character }).count } ?? 0
            let isFence = (marker == "`" || marker == "~") && run >= 3
            if let open = fence {
                if isFence, marker == open, run >= fenceLength { fence = nil; fenceLength = 0 }
                continue
            }
            if isFence {
                fence = marker
                fenceLength = run
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }
}
