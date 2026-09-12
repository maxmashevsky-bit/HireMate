# Модель хранения

В исходники добавлен GRDB 7.11.1 / SQLite. `GRDBMeetingRepository` — actor, также реализующий NoteRepository и NoteSearchService. Одна DatabaseQueue создаётся лениво. Миграции учитывает штатная таблица **grdb_migrations**, отдельной самодельной schema_migrations нет. foreign_keys и secure_delete включены. Миграции ещё не запускались.

## Текущая схема

| Миграция | Таблицы | Данные |
|---|---|---|
| v1_profiles_and_meetings | context_profiles, meetings, subchats, messages | UUID/идентификатор профиля, FK, даты, Codable JSON payload |
| v2_notes_fts | notes, note_chunks, note_fts | Владелец-профиль, pin/archive/AI flags, даты, payload, FTS5 unicode61 |

ContextProfile → Meeting → Subchat → Message. Загрузка истории проверяет meetingID и subchatID; удаление meeting каскадное. Эфемерная встреча существует только в памяти. Сообщения помечены complete/cancelled/failed и demo; незавершённые/демонстрационные ответы не включаются в историю реального запроса.

Note → chunks. Hash отражает текущий Markdown; отдельно хранится hash оригинального импортированного файла и локальный source path. Сохранение, пересоздание chunks и FTS — одна транзакция. Удаление заметки удаляет FTS и каскадно chunks. Retrieval проверяет профиль, allowAI, архив и sourceHash. Метаданные фрагментов включают название/теги/index/hash; score BM25 рассчитывается запросом, embeddings отсутствуют.

Database/copilot.sqlite находится в Application Support/dev.maxmashevsky.MaxInterviewCopilot. Каталог создаётся с 0700, база — 0600. Отдельное шифрование SQLite не реализовано; защита зависит от учётной записи/прав и системного диска. Ни секреты Keychain, ни image/audio bytes в базе не сохраняются.

UserDefaults: тема/профиль/onboarding, overlay preferences, Codable несекретная конфигурация API и пять быстрых действий. Настройки TTS/согласия на сеть не переживают перезапуск. Снимки, аудиобуфер и расшифровка остаются в памяти. JSON-экспорт встречи сохраняет тексты, Markdown-экспорт заметки — только Markdown; экспорт не является полной резервной копией приложения.

## Следующие схемы

Resumes/sections, recordings, mock_sessions/answers, analysis_runs/items, questions/livecode_tasks, vacancies/events, companies/contacts, consent_records/background_jobs, embedding_indexes. Они пока не созданы. Версия rubric/model и invalidation, backup/restore, объёмы/retention и полный reset — отдельные срезы.
