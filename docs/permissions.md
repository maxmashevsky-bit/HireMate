# Разрешения
Микрофон: AVCaptureDevice.authorizationStatus(.audio), requestAccess только кнопкой. Screen/system audio: CGPreflightScreenCaptureAccess для read-only проверки; отрицательный bool означает «доступ не подтверждён», а не доказанный отказ. Request screen только кнопкой, будущий capture через ScreenCaptureKit. Accessibility и Input Monitoring не требуются для shell, не запрашиваются.

System Settings → Privacy & Security → Microphone / Screen & System Audio Recording. Кнопки предлагают открыть раздел; если deep link не сработает, путь показан текстом. После возврата — обновить статусы. Не повторять запросы автоматически и не сбрасывать TCC.

Phase 1 проверяет диагностику, но реальный sound test относится к Phase 3. Onboarding честно предлагает пропустить hardware check в демо. Отдельная кнопка звукового теста появится вместе с capture; UI-заглушка не выдаётся за готовый тест.

Официальные API: https://developer.apple.com/documentation/AVFoundation/AVCaptureDevice/authorizationStatus(for:)
https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()

Горячие клавиши Phase 2 используют Carbon RegisterEventHotKey. Accessibility/Input Monitoring не запрашиваются. Secure Input проверяется в callback; поведение ещё не проверено на устройстве. Захват клавиатуры или парольных полей не реализуется.
