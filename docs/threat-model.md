# Модель угроз
| Угроза | Мера | Проверка |
|---|---|---|
| Кража API key, logs/crash/export | Только Keychain, очищать поле ввода, запрет содержимого в OSLog | fake secret store + leak/export scan; реальный Keychain manual |
| Prompt injection/LLM-команды | Внешний контент как данные, никакого исполнения ответа | adversarial fixtures |
| Утечка screen/transcript | opt-in, preview, indicator, no auto upload, ephemeral mode | capture/network spies |
| Local account access | 0700/0600, Keychain, объяснить что DB не full encryption | POSIX tests |
| Подмена зависимости/update | pin, license/hash audit; unsigned update запрещён | lockfile/artifact checks |
| Path traversal/unsafe scheme/oversize | whitelist URL schemes, standardized path boundary, лимиты | malicious import fixtures |
| Malformed media/PDF/Markdown | validated type/size, cancellation, renderer isolation | malformed fixtures |
| Endpoint SSRF | validated HTTPS, localhost/private warning, no automatic redirect of secrets | URLProtocol tests |
| Replay/дубликаты | request IDs, bounded retry, idempotency | 401/429/5xx fixtures |
| Ошибки внешних откликов | draft-only + approval, denylist, stop on unknown, kill switch | connector spies |
| Неизвестный TCC status | fail-closed, никогда auto capture | permission state tests |

Privacy hiding — только ручное или best-effort public API с compatibility test. Не обещается невидимость. Без private API, SIP/TCC/Gatekeeper bypass, process spoofing, cursor/focus подмены. Реальные разрешения не меняются диагностикой.
