# Сборка и выпуск

Обновление 7 сентября: проверки возобновлены. Xcode-скрипты используют `scripts/build-paths.sh`: DerivedData и результаты XCTest находятся в `~/Library/Caches/dev.maxmashevsky.MaxInterviewCopilot/<hash-пути-проекта>`. Это исключает влияние File Provider/FinderInfo в Documents на codesign. Скрипт сборки выводит полный путь `.app`; старые артефакты не удаляются. Описание паузы ниже историческое.

Xcode 26.6 и Swift 6.3.3 уже установлены. Устанавливать Xcode повторно не требуется. По прямому поручению пользователя новые проверки приостановлены; этот документ предназначен для будущего возобновления.

После разрешения сначала выполните `./scripts/build.sh`, затем `./scripts/test.sh` и `./scripts/verify.sh`. SPM скачает exact GRDB 7.11.1 и создаст Package.resolved. Ошибки Swift 6/SDK/миграций нужно исправлять до runtime. `./scripts/build.sh --spm` — дополнительный путь SPM; старый --clt больше не поддерживается. Успешность текущего app не подтверждена.

При переносе на другой Mac полный Xcode берётся из Mac App Store или [Apple Downloads](https://developer.apple.com/download/all/). Версия должна подходить к macOS по [таблице Apple](https://developer.apple.com/xcode/system-requirements) и поддерживать Swift 6/macOS SDK 15+. First launch/лицензия выполняются владельцем Mac. Скрипты проекта сами toolchain не устанавливают и global developer selection не меняют.

Release позже: Developer ID, Hardened Runtime, минимальные entitlements, codesign nested artifacts, notarytool с локальным Keychain profile, staple, codesign verification, spctl, DMG/checksum/notes/rollback. Лицензия GRDB упаковывается в Resources/Licenses. Сертификаты и Apple ID пароли не передаются в чат. Notarization и удалённая публикация не выполнялись.
