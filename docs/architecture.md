# Архитектура
Целевая платформа macOS 15+, Swift 6, SwiftUI + AppKit; Swift Package Manager и отдельный Xcode app target для bundle/TCC. Observation выбран последовательно для UI-state. Сервисы платформы изолируются MainActor; обработка аудио, DB и сеть — actors/async streams вне UI.

Presentation: App shell/menu bar/sidebar, onboarding/diagnostics/settings, далее overlay/meetings/contexts/notes/mock/analysis/resume/vacancies.
Application: use cases начала встречи, capture, генерации, поиска заметок, записи, анализа, mock, PDF и vacancies. Fake preview первого среза имеет ограниченный контекст одного выбранного профиля и отменяется при переключении.
Domain: value types ContextProfile/Meeting/Subchat/Message/AudioFrame/Transcript/Attachment/Note/Resume/Mock/Analysis/Vacancy/Company/Event/Action/ModelConfiguration.
Infrastructure: GRDB/SQLite repositories/migrations, Keychain, file store, ScreenCaptureKit, AVAudioEngine/AVFoundation, PDFKit, URLSession, OSLog.

Минимальные контракты будущих срезов: AudioCaptureService, VoiceActivityDetector, TranscriptionService, LLMProvider, EmbeddingProvider, TextToSpeechService, ScreenCaptureService, MeetingRecorder, ContextAssembler, NoteSearchService, SecureSecretStore, MeetingRepository, NoteRepository, ResumeRepository, VacancyRepository, PermissionService. В код добавляются при появлении работающего потребителя; пустые реализации не создаются.

UI не вызывает DB или provider endpoint. Composition root внедряет platform adapters и Fake Provider. Ключей в доменных структурах нет. Конкретный внешний провайдер не выбран. SQLite — доменные данные, файлы — media, UserDefaults — несекретные язык/тема/onboarding/profile selection и параметры overlay. Core не требует Xcode UI для unit tests.

Поток будущей встречи: PCM → bounded ring → VAD → STT → корректировка → assembler(profile + verified facts + selected notes + current subchat + input) → budget → provider stream → UI → repository. Cancel распространяется до источника; устаревший stream не обновляет новый профиль. Сетевые действия требуют явного пользователя; очередь не отправляется автоматически после reconnect.

## Текущий toolchain и режим работы
Xcode 26.6 и Swift 6.3.3 установлены. Xcode target задаёт SWIFT_VERSION=6.0, deployment 15.0, Debug ONLY_ACTIVE_ARCH=YES. Пользователь распорядился продолжать код без проверок: Phase 1–7 verification отложены, Phase 8 IN_PROGRESS. Успешность текущей сборки не заявляется.

## Окно подсказок
AppModel владеет OverlayController, который создаёт NSPanel с NSHostingView. Слабая ссылка controller → model не продлевает lifetime модели; окно закрывается и callbacks снимаются при shutdown. OverlayView читает тот же активный профиль и отменяемый Fake stream. OverlayPreferences хранит только opacity/shortcut configuration/geometry. GlobalHotkeyService регистрирует фиксированный набор Carbon hotkeys без глобального перехвата ввода. Пользователь может отключить регистрацию, сменить modifiers и видеть ошибки. Mouse click-through сбрасывается при запуске. NSPanel не исключается из стороннего screen sharing, о чём явно сказано в UI.


## Подключённые срезы Phase 3–8 (не проверены)
AppModel внедряет единственный GRDBMeetingRepository в ConversationModel и NotesModel. Он владеет DatabaseQueue и миграциями v1/v2. Модели представления MainActor, capture callbacks копируют PCM, обработка аудио и хранилище вынесены в actors. UI не читает ключ, не формирует HTTP и не исполняет SQL.

AudioSessionModel управляет native capture и AudioPipeline. TranscriptionModel выполняет явное распознавание выбранного фрагмента. NetworkClient централизует ephemeral transport, bounded response и safe status. ConversationModel собирает изолированный запрос и принимает typed LLM events; незавершённый stream не меняет другой поддиалог. FakeStreamingProvider остаётся отдельным адаптером поверх детерминированных fixtures.

ScreenshotModel использует NativeScreenCapture и ImagePreparation, хранит конечные image bytes для preview/attachment. QuickActionStore хранит пять слотов; действие не переключает профиль и не захватывает screenshot. SpeechModel использует AVSpeechSynthesizer с ручным управлением и auto-read opt-in.

NotesModel: импорт-preview/editor → GRDB transaction → paragraph chunks + FTS5. ContextAssembler получает максимум четыре разрешённых фрагмента только текущего профиля; источники и факт включения отображаются рядом с ответом. EmbeddingProvider и semantic retrieval пока не созданы. Подробнее: implementation-progress.md.
