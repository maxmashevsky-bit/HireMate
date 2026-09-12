import Foundation
import Observation
import OSLog
import CopilotCore

@MainActor @Observable
final class AppModel {
    let network = NetworkClient()
    let providerSettings = ProviderSettingsModel()
    let transcription: TranscriptionModel
    let audio = AudioSessionModel()
    let screenshot = ScreenshotModel()
    let quickActions = QuickActionStore()
    let speech = SpeechModel()
    var pendingQuickAction: QuickAction?
    var requestedSection: AppSection?
    let overlay = OverlayController()
    let preferences: PreferencesStore
    let permissions: any PermissionService
    let secrets: any SecureSecretStore
    let conversation: ConversationModel
    let notes: NotesModel
    private let logger = Logger(subsystem: "dev.maxmashevsky.MaxInterviewCopilot", category: "lifecycle")
    var theme: AppTheme { didSet { preferences.theme = theme } }
    var profile: ProfileID { didSet { preferences.profile = profile; transcription.reset(); screenshot.clear(); speech.stop(); pendingQuickAction = nil; notes.activateProfile(profile); conversation.activateProfile(profile)
        Task { await audio.stop(reason: "Профиль изменён. Захват остановлен."); await audio.clear() }
    } }
    var question: String { get { conversation.draft } set { conversation.draft = newValue } }
    var answer: String { conversation.answer }
    var isGenerating: Bool { conversation.isGenerating }
    var demoStatus: String { conversation.status }
    var showOnboarding: Bool
    var microphone: PermissionState = .unconfirmed
    var screen: PermissionState = .unconfirmed
    var notice: String?

    init(preferences: PreferencesStore? = nil,
         permissions: (any PermissionService)? = nil,
         secrets: (any SecureSecretStore)? = nil) {
        let resolvedPreferences = preferences ?? PreferencesStore()
        self.preferences = resolvedPreferences
        self.permissions = permissions ?? MacPermissionService()
        self.secrets = secrets ?? KeychainSecretStore()
        self.transcription = TranscriptionModel(secrets: self.secrets, network: network)
        let repository = GRDBMeetingRepository()
        self.notes = NotesModel(profile: resolvedPreferences.profile, repository: repository)
        self.conversation = ConversationModel(profileID: resolvedPreferences.profile, repository: repository, secrets: self.secrets, network: network, noteSearch: repository)
        theme = resolvedPreferences.theme
        profile = resolvedPreferences.profile
        showOnboarding = !resolvedPreferences.onboardingCompleted
        refreshPermissions()
        overlay.connect(model: self)
        audio.onSegment = { [weak self] segment in
            self?.transcription.enqueueLive(segment)
        }
        conversation.onCompletedAnswer = { [weak self] text in
            guard let self, speech.autoRead else { return }
            if audio.isRunning && !speech.routingAcknowledged {
                notice = "Авточтение пропущено: захват звука включён. Подтвердите предупреждение о системном звуке в настройках озвучивания."
            } else { speech.speak(text) }
        }
        providerSettings.onConfigurationChange = { [weak self] in
            guard let self else { return }
            conversation.cancel(); conversation.remoteConsent = false; pendingQuickAction = nil; speech.stop()
            transcription.cancel(); transcription.remoteConsent = false
        }
        logger.notice("Приложение запущено")
    }

    func refreshPermissions() {
        microphone = permissions.microphoneStatus()
        screen = permissions.screenStatus()
    }
    func requestMicrophone() async {
        await permissions.requestMicrophone()
        refreshPermissions()
    }
    func requestScreen() { permissions.requestScreen(); refreshPermissions() }
    func finishOnboarding() { preferences.onboardingCompleted = true; showOnboarding = false }
    func send() { speech.stop(); conversation.send(configuration: providerSettings.configuration) }
    func stop() { conversation.cancel(); speech.stop() }
    func requestQuickAction(slot: Int) {
        guard let action = quickActions.actions.first(where: { $0.slot == slot }) else { return }
        guard action.profileID == profile else { notice = "Для действия «\(action.name)» выберите профиль «\(action.profileID.title)»."; return }
        guard !conversation.isGenerating else { notice = "Остановите текущий ответ перед новым действием."; return }
        if action.requiresConfirmation { pendingQuickAction = action }
        else { runQuickAction(action) }
    }
    func runQuickAction(_ action: QuickAction) {
        pendingQuickAction = nil
        guard action.profileID == profile else { return }
        var configuration = providerSettings.configuration
        if !action.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration.textModel = action.selectedModel
            // Возможности другой модели не наследуются автоматически.
            if action.selectedModel != providerSettings.configuration.textModel { configuration.visionEnabled = false }
        }
        speech.stop(); conversation.send(configuration: configuration, action: action)
    }
    func speakAnswer() {
        guard !audio.isRunning || speech.routingAcknowledged else {
            notice = "Озвучивание может попасть в системный захват. Подтвердите это в настройках озвучивания или остановите захват звука."; return
        }
        speech.speak(answer)
    }
    func saveSecret(_ value: String) {
        do { try secrets.save(value); notice = "Ключ сохранён в macOS Keychain. Демо его не использует." }
        catch { notice = error.localizedDescription }
    }
    func deleteSecret() {
        do { try secrets.delete(); notice = "Ключ удалён из macOS Keychain." }
        catch { notice = error.localizedDescription }
    }
}
