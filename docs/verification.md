# Протокол проверки — 6 сентября 2026

## Исторический результат первого среза
Phase 0 завершена. Phase 1 IN_PROGRESS с внешним toolchain blocker. **Рабочий .app не собран и не запущен.** Исходный UI прошёл только синтаксический разбор, не typecheck/link/runtime. Не утверждается отсутствие будущих Swift 6/SDK/UI ошибок. 10 portable проверок используют реальные файлы core, а не переписанную тестовую реализацию.

## Диагностика (read-only)
| Параметр | Результат |
|---|---|
| uname -m | arm64 |
| sw_vers | macOS 26.6.2, build 25G83 |
| system_profiler, allowlist | MacBook Air / MacBookAir10,1; Apple M1; 8 GB; 8 cores (4+4) |
| swift --version | Apple Swift 5.9.2 (swiftlang-5.9.2.2.56 clang-1500.1.0.2.5) |
| xcrun --find swiftc | /Library/Developer/CommandLineTools/usr/bin/swiftc |
| xcode-select -p | /Library/Developer/CommandLineTools |
| xcodebuild -version | exit 1; requires Xcode, active developer directory is a command line tools instance |
| xcrun --show-sdk-version | 14.2 |
| Другие SDK | 12.3, 13.1, 13.3, 14.2; во всех отсутствует CoreFoundation.framework/Headers/CFBase.h |
| XCTest | недоступен; xcrun не находит PlatformPath |

Серийный номер не выводился и не сохранялся. Источники и workspace не были git repositories; git status вернул exit 128 / fatal: not a git repository. Git не инициализировался; remote не создан; публикаций/commits нет.

## Выполненные проверки
| Команда | Exit | Результат |
|---|---:|---|
| rg --files (Desktop/HireMate) | 0 | Оба TXT найдены |
| rg --files (Documents/ChatGPT/HireMate до работы) | 1 | Папка пуста |
| wc -lc + последовательное чтение обоих TXT | 0 | 2423/156517 и 1899/78038 строк/байт; усечённый вывод перечитан блоками |
| python3 scripts/check-project.py | 0 | 133/133 функций приложения A, 1385 содержательных строк мастер-ТЗ, 1518 уникальных IDs, документы, SHA-256, статусы, ограниченный secret scan |
| swiftc -frontend -parse (каждый Swift-файл) | 0 | Синтаксис; НЕ компиляция с SDK |
| plutil -lint Resources/Info.plist MaxInterviewCopilot.xcodeproj/project.pbxproj | 0 | Оба plist корректны |
| scripts/test.sh --portable | 0 | 10/10 тестов реального ядра |
| scripts/verify.sh --source-only | 0 | Только source/portable gates проходят |
| scripts/build.sh | 1 | xcodebuild требует полного Xcode |
| scripts/test.sh | 1 | XCTest target не запущен: xcodebuild требует полного Xcode |
| swift test | 1 | error: XCTest not available |
| swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors | 1 | Нет CoreFoundation/CFBase.h; Foundation не собирается, compiler также сообщает SDK mismatch |
| scripts/build.sh --clt (после правок) | 1 | Та же ошибка Foundation; .app не создан |
| scripts/verify.sh | 1 | Source gates PASS, затем xcodebuild requires Xcode |

Точные штатные команды:

```sh
xcodebuild -project MaxInterviewCopilot.xcodeproj -scheme MaxInterviewCopilot -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData SWIFT_VERSION=6.0 CODE_SIGN_IDENTITY=- build
xcodebuild -project MaxInterviewCopilot.xcodeproj -scheme MaxInterviewCopilot -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData -resultBundlePath build/TestResults-<время>.xcresult SWIFT_VERSION=6.0 CODE_SIGN_IDENTITY=- test
swift test
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swiftc -parse-as-library -target arm64-apple-macosx15.0 -strict-concurrency=complete -warnings-as-errors Core/Domain/ContextProfile.swift Core/Domain/InputPolicy.swift Core/Infrastructure/FakeLLMProvider.swift Tests/Portable/CoreSmoke.swift -o build/core-smoke
./build/core-smoke
```

Локальные логи находятся в build/logs (не предназначены для Git). Скрипты сохраняют nonzero exit через pipefail. Никакие предупреждения compiler глобально не подавляются. .swiftformat — только конфигурация; внешний formatter не запускался.

## 10 portable проверок
1. Три различных профиля и формата.
2. Пустой ввод и Unicode whitespace запрещены.
3. Граница 4000/4001 символов кириллицы.
4. Только granted разрешает capture; unknown fail-closed.
5. Множественные streaming chunks и структура учебного Go-примера.
6. Одновременные запросы HR/technical не смешивают данные.
7. HR требует подтверждённые факты, использует незаполненные поля.
8. Инструкция во вводе не исполняется Fake Provider и не попадает в образец.
9. Пустой ввод отклоняется самим provider, а не только кнопкой UI.
10. Отмена останавливает получение stream до полного ответа.

Созданы также 6 XCTest методов: preferences round trip/allowlist, corrupt preference fallback, permission policy, Unicode/bounds, distinct fake streams, invalid input. **Они не запускались**, потому что XCTest отсутствует. Их наличие не даёт VERIFIED.

## Manual / performance
NOT_TESTED: запуск/навигация/menu bar/onboarding, сохранение темы после relaunch, Keychain round trip, TCC request/deny/revoke, light/dark, retina/multi-display/Spaces, capture/audio/headphones/sleep/wake, long meeting, CPU/RAM/FPS/DB latency. Запись/overlay/реальный provider ещё не реализованы. Performance budgets остаются целями, измерений приложения нет.

## Следующий шаг
Установить полный совместимый Xcode по docs/release.md, затем выполнить scripts/verify.sh, исправить реальные Swift 6/typecheck/runtime ошибки, запустить .app и заполнить Phase 1 manual checklist. Лишь после успешного gate переходить к Phase 2 (NSPanel и глобальные hotkeys).


## Продолжение после установки Xcode и запрета проверок
Установлены Xcode 26.6 (17F113) и Swift 6.3.3. Первый build выявил architecture mismatch app/package; Debug получил ONLY_ACTIVE_ARCH=YES. Повторный build стартовал до запрета проверок; его результат не просматривался. Старый раздел «Следующий шаг» выше относится к первой диагностике, а не текущей системе.

Затем пользователь явно поручил писать код без проверок. Добавлены исходники Phase 2–8 и exact GRDB 7.11.1. **Новые build/test/typecheck/UI/HTTP/SQLite/performance проверки не запускались.** Генератор обновляет только Xcode project и не является проверкой. Ни один прежний PASS не распространяется автоматически на новые файлы или dependency graph. Текущий статус и ограничения — STATUS.md / implementation-progress.md.
