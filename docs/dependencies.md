# Зависимости и модели

Текущая основа — Swift 6, SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, Security/Keychain, ImageIO, CryptoKit и системный SQLite. Минимальная macOS 15; Swift 5.9 после подключения GRDB больше не поддерживается.

Единственная сторонняя runtime-зависимость: [GRDB 7.11.1](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1), exact version в Package.swift. Нужна для migrations, транзакций и FTS repositories. [MIT LICENSE этого тега](https://github.com/groue/GRDB.swift/blob/v7.11.1/LICENSE) скопирована в `Resources/Licenses/GRDB-MIT.txt` и включена в ресурсы app target.

Package resolve/build/download пакета не запускались по команде пользователя. Скачан только текст лицензии. Package.resolved не создан этим продолжением. Размер зависимости и совместимость на установленном Swift 6.3.3 должны быть подтверждены следующей разрешённой сборкой. Exact version сама по себе не доказывает корректность интеграции.

Energy VAD и FTS5 не требуют внешних моделей. Silero, WhisperKit/whisper.cpp/Core ML, embeddings не загружены. До выбора нужна запись source/license/checksum/size/RAM/realtime factor и согласие на крупную загрузку. Semantic RAG и local STT пока не реализованы.

TTS использует установленные системные голоса, без собственного download. FFmpeg не добавлен; сначала native recording PoC. Markdown preview — SwiftUI Text. SwiftLint/SwiftFormat не установлены и не имитируются. Sparkle остаётся будущим P2-срезом.
