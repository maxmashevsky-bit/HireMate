# План проверок
## Gates
Только один этап IN_PROGRESS. Phase 0: checksum обоих источников; все [x] приложения A имеют строку, все содержательные строки мастер-ТЗ представлены, IDs уникальны, статусы валидны, документы присутствуют. Phase 1: Xcode Swift 6 Debug build, unit tests settings/presets/permission gating/fake stream cancellation, запуск .app, sidebar, menu bar, onboarding repeat, persisted settings, отсутствие автоматических permission/network calls. CLT fallback отдельно от Xcode gate.

Phase 2: global hotkeys вне app, focus/click-through, opacity/frame restore, display/Retina/fullscreen, compatibility truth test.
Phase 3: fixtures ring buffer/VAD/timestamps, pre-roll, silence, cancel/device change/denial, CPU/memory.
Phase 4: STT fake server batch/partial/final ordering, duplicates, Unicode, malformed, 401/429/5xx, cancel/redacted logs.
Phase 5: stream fragmented UTF-8/SSE, retry/cancel, capabilities, budget/current question, no cross-subchat/profile leak, DB migration empty/upgrade, secret exclusion.
Phase 6: preview=sent bytes, crop/high-DPI, redaction, temp cleanup, no-vision reject before network.
Phase 7: slots/actions/screenshot opt-in, TTS play/stop/language/system routing.
Phase 8: note import/export Unicode, deterministic chunks, FTS5 offline, stale embeddings/reindex, cascade delete, visible sources/exclude secret notes.
Phase 9: synthetic MP4, QuickTime, A/V sync, finalize, low disk, disconnect, sleep, consent/no auto upload.
Phase 10: fake mock single-question/followups, no fabricated facts, rubric version, transcript correction/export.
Phase 11: canvas save/load, undo/redo, delete no orphan edges, readable exports, explicit Apply.
Phase 12: separate source speaker attribution; no fake single-track precision, stale analysis invalidation, cancel cleanup/export/version/delete.
Phase 13: PDF source untouched, editor round-trip, selectable Cyrillic A4 links/multipage, assumptions Apply/Discard/no invented metrics.
Phase 14: own-bank preview/provenance, duplicate detection, import validation/Unicode/export/stats.
Phase 15: offline Kanban/filter/timeline/funnel/salary sample size, dedupe, extraction preview, connector approval/no cookies.
Phase 16: local mentor history only, no external publication/payments.

## Manual matrix
Каждый результат фиксируется в verification.md: hardware/OS, 1/2 displays, scaled/Retina, fullscreen Spaces, light/dark, allow/deny/revoke microphone/screen, headphones/device change, sleep/wake, network loss, long session, low disk, QuickTime, screen share. Непроведённое = NOT_TESTED, не VERIFIED.

## Performance
Цели до измерения: idle CPU <3%, memory <250 MB, 60 FPS, main thread stall <100 ms, DB p95 <100 ms, bounded long-meeting memory. STT и LLM latency раздельно. Unit/integration: XCTest. UI automation/manual результаты не подменяют unit. Нет paid API в тестах.

Автоматизированный baseline длительной аудиосессии прогоняет 10 минут синтетических mono/16 kHz кадров: ring buffer не превышает 60 секунд, ручные сегменты не превышают 960 000 samples/60 секунд, one-shot читает только настроенное недавнее окно. Это проверка алгоритмических границ без устройства и не заменяет runtime-проверку dropouts/памяти.

Долгая история диалога проверяется отдельно: активное окно содержит не более 200 последних сообщений и 1 000 000 символов, один потоковый ответ — не более 256 000 символов, а кэш — не более восьми поддиалогов. Интеграционный тест создаёт 205 сообщений в сохраняемой встрече, ожидает 200 в UI-окне и все 205 в JSON-экспорте из SQLite. Для полного M-1248 ещё нужен runtime-замер памяти под одновременной аудио/STT/LLM нагрузкой.

Ручной DB benchmark выполняет 20 последовательных чтений списка встреч активного профиля, считает p95 методом nearest-rank и показывает минимум/максимум. Runtime 12 сентября 2026 на личной базе: min 0.198 мс, p95 0.360 мс, max 8.697 мс. Замер не изменяет данные и не выводит их содержимое.
