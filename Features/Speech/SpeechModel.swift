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
    var language = "ru-RU" { didSet { if oldValue != language { stop(); chooseCompatibleVoice() } } }
    var voiceID = "" { didSet { if oldValue != voiceID { stop() } } }
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var autoRead = false
    var routingAcknowledged = false
    private(set) var voices: [AVSpeechSynthesisVoice] = []
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var status = "Озвучивание выключено"
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    override init() {
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
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { status = "Нет текста для озвучивания"; return }
        guard input.count <= 24_000 else { status = "Текст слишком длинный для озвучивания. Выберите более короткий ответ."; return }
        stop()
        guard let voice = compatibleVoices.first(where: { $0.identifier == voiceID }) else { status = "Для выбранного языка нет установленного голоса. Выберите его в системных настройках."; return }
        let utterance = AVSpeechUtterance(string: input)
        utterance.voice = voice; utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, rate))
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
}
