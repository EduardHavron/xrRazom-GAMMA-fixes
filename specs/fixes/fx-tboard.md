# FX-TBOARD: текст карточек PDA Taskboard Redesign у пира
Статус: действует        Проверка в игре: не записана        Мод: `zz xrRazom Fix - Taskboard Peer Details`        Скрипт: `gamedata/scripts/zz_xrrfix_taskboard.script`
Где ставить: пир (на хосте безвреден)        Зависит от: xrRazom Co-op 1.4 (`xrr_patch_quests`: `xrr_peer_task_offer_preview`), PDA Taskboard Redesign v1.3 (`pda_taskboard`, `pda_taskboard_utils`)        Лог-маркер: `[XRRFIX] taskboard: get_task_card patched for peers`

## Проблема
У пира в PDA Taskboard (Redesign) карточки заданий показывают только заголовок: нет подзаголовка и текста задания
(у хоста карточки полные).

## Причина
- Пир не может сам сформировать описание задания: исходный taskboard «разговаривает» с каждым NPC, чего пир не делает.
  xrRazom (`xrr_patch_pda_taskboard.script`) поэтому оборачивает `pda_taskboard.get_details`: у пира при отсутствии локальных
  деталей возвращает захваченное хостом предложение `xrr_peer_task_offer_preview(task_id)` (caption/text/icon).
- В Redesign v1.3 `get_details` — только «адаптер совместимости» (`pda_taskboard.script`, `function get_details`).
  UI (`ui_pda_taskboard_tab.script`) строит карточки через `self.backend.get_task_card(...)`, где `backend` — таблица модуля
  `pda_taskboard`.
- `get_task_card` → `pda_taskboard_cards.build_task_card(task_info, task_card_options())`, а текст берётся из
  `opts.captured_legacy_details(task_info)`. `captured_legacy_details` — локальная переменная файла
  (`local captured_legacy_details = nil` с последующим `function captured_legacy_details(...)`), её нельзя подменить снаружи.
  Обёртка xrRazom над `get_details` на этом пути не вызывается.
- У пира `captured_legacy_details` возвращает `nil`/пусто (нет `details_id` и igi-кеша), `split_legacy_details(nil)` даёт
  `nil, nil` → в карточке пустые `subtitle` и `body`.
- Хостовый захват при этом у пира есть: `OnQuestListResponse` кладёт сообщения в `_G.xrr_task_offer_msgs[tid]`.

## Решение
В `on_game_start` (под `pcall`) оборачивается публичная `pda_taskboard.get_task_card`:
1. Вызывается оригинал. Если карточки нет, нет `task_info` или `XrrIsConnected()` ложно — карточка возвращается как есть.
2. Если в карточке уже есть непустой `subtitle` или `body` (локальные детали) — карточка не трогается.
3. Иначе берётся `xrr_peer_task_offer_preview(task_info.task_id)`; при непустом `text`:
   `card.subtitle, card.body = pda_taskboard_utils.split_legacy_details(m.text)`; при непустом `icon` — `card.icon = m.icon`.
4. Для каждого `task_id` один раз за сессию пишется диагностическая строка (см. ниже).

Обёртка вызывается при каждом построении карточки, т.к. UI ищет функцию в таблице модуля в момент вызова.

## Требования
### FX-TBOARD-001 Карточка пира получает текст хоста  [manual]
У пира карточка задания без локальных деталей ДОЛЖНА показывать подзаголовок и текст из захвата хоста.
- Дано пир в сессии, хост прислал предложение для задания T (`_G.xrr_task_offer_msgs[T]` с непустым `text`)
  Когда пир открывает PDA Taskboard и видит карточку T
  Тогда у карточки есть подзаголовок и тело, совпадающие с текстом у хоста (с учётом локали пира).

### FX-TBOARD-002 Локальные детали приоритетнее  [auto]
Обёртка НЕ ДОЛЖНА изменять карточку, у которой уже есть непустой `subtitle` или `body`.
- Дано заглушка `orig` возвращает `{ subtitle = "S", body = "" }`, `XrrIsConnected = true`, превью с текстом есть
  Когда вызывается `get_task_card(task_info)`
  Тогда возвращена та же карточка с `subtitle == "S"`; `xrr_peer_task_offer_preview` не вызывался.

### FX-TBOARD-003 Подстановка превью  [auto]
При пустых деталях и наличии превью карточка ДОЛЖНА получить `subtitle`/`body` из `split_legacy_details(m.text)` и `icon` из `m.icon`.
- Дано `orig` возвращает `{ title = "T" }`, превью `{ text = "Sub\\nBody", icon = "ui\\x" }`, заглушка `split_legacy_details` → `"Sub", "Body"`
  Когда вызывается `get_task_card`
  Тогда `card.subtitle == "Sub"`, `card.body == "Body"`, `card.icon == "ui\\x"`, `card.title == "T"`.

### FX-TBOARD-004 Вне сессии и без данных — без изменений  [auto]
Обёртка НЕ ДОЛЖНА менять карточку вне сессии, при `nil`-карточке или при отсутствии/пустом тексте превью.
- Дано (а) `XrrIsConnected() == false`; (б) `orig` вернул `nil`; (в) превью `nil`; (г) превью с `text == ""`
  Когда вызывается `get_task_card`
  Тогда возвращается результат `orig` без изменений, ошибок нет.

### FX-TBOARD-005 Диагностика один раз на задание  [auto]
Обёртка ДОЛЖНА писать строку `taskboard: task=... local_details=... host_msg=... preview_text=...` не более одного раза на `task_id` за сессию.
- Дано `get_task_card` вызван трижды для одного и того же `task_id` в сессии
  Когда считаем строки лога с этим `task_id`
  Тогда строка ровно одна.

## Безопасность
- Нет Redesign (нет `pda_taskboard.get_task_card` или `pda_taskboard_utils.split_legacy_details`) — лог
  `taskboard: get_task_card absent (not the Redesign), skipped`, ничего не меняется.
- Соло: `XrrIsConnected()` ложно — карточка не трогается.
- Хост: превью берётся из `_G.xrr_task_offer_msgs`, которое заполняет только `OnQuestListResponse` (на хосте он сразу выходит),
  поэтому подстановка не происходит.
- Защиты от повторной установки нет: повторный `on_game_start` обернёт обёртку; результат тот же (вторая обёртка видит уже
  заполненную карточку), лишь лишняя строка установки в логе.

## Вне области / известные ограничения
- Если `build_task_card` вернул `nil` (заголовок не разрешился или содержит `$var`), карточки нет вовсе — фикс её не создаёт.
- Задания без хостового сообщения (igi-задания, категории без iconed-сообщения) остаются только с заголовком — захвата нет.
- `card.extra_details`, `reward_text`, `description` не трогаются.
- Обёртка xrRazom над `get_details` остаётся (используется старым кодом и `legacy_details_from_card`), фикс её не меняет.

## Проверка в игре
1. Пир запускает игру. Лог: `[XRRFIX] taskboard: get_task_card patched for peers` (и xrRazom: `[xrRazom][taskboard] patch applied`).
2. Пир в сессии открывает PDA → Taskboard, жмёт «Обновить».
3. Лог пира для каждого показанного задания один раз:
   `[XRRFIX] taskboard: task=<id> local_details=false host_msg=true preview_text=true`.
4. Карточки показывают подзаголовок и текст, совпадающие с карточками у хоста.
5. Если в строке `host_msg=false` — хост не прислал захват для этого задания (ограничение, не ошибка фикса).
