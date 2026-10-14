# MOD-LOOTCLAIM: право на лут (Combined GAMMA NPC Loot Claim)
Статус: действует        Мод: `Combined GAMMA NPC Loot Claim v.1.2` (версия скрипта 1.2.0; имя папки — как в `pack.json`, тесты берут его оттуда)        Скрипты: `gamedata/scripts/grok_loot_claim.script`, `gamedata/scripts/grok_loot_claim_mcm.script`, тексты: `gamedata/configs/text/{eng,rus}/ui_mcm_grok_loot_claim.xml`
Где ставить: оба (через секцию «xrRazom Sync»)        Зависит от: `G.A.M.M.A. NPC Loot Claim Remade` (ниже по приоритету), MCM (необязательно), xrRazom (необязательно), `z_auto_looter` (необязательно)        Лог-маркер: `[grok_loot_claim] LOADED v1.2.0 | ...` (только при `debug`)

Сторонний мод, а не фикс xrRazom: целиком заменяет `grok_loot_claim.script` базового мода и добавляет поддержку коопа.
Платформа: S.T.A.L.K.E.R. Anomaly / G.A.M.M.A. 0.9.5, Lua 5.1. Документ объединяет описание устройства от автора мода
(SDD, раньше лежал в папке мода как `SDD.md`) и требования с ID для тестов; при расхождении с кодом правится документ.

## Проблема
«Клейм» трупов между игроком и NPC:
- **убийства игрока** (сам игрок, компаньоны, пир xrRazom) обыскивает только игрок, NPC — нет;
- **убийства NPC** обыскивают NPC, как в ванили, игрок — нет;
- тело открывается для всех, когда его обыскали, убийца мёртв или далеко (настраивается).

В G.A.M.M.A. «право на лут» дают `npc_loot_claim` / `zz_npc_loot_claim_softcore` / `grok_loot_claim` из базового мода, но без
настроек, без защиты своих убийств от NPC, без автолутера и без учёта пира xrRazom. Все правила этого мода переключаются в MCM;
без MCM действуют значения `DEFAULTS`.

## Причина (как устроено в базе)
- `G.A.M.M.A. NPC Loot Claim Remade`: `npc_loot_claim.script` и `zz_npc_loot_claim_softcore.script` — заглушки (`printf(...)`),
  они отключают оригинальный loot claim и **должны оставаться заглушками**; в этот мод не входят. Там же строки
  `st_npc_loot_claim_last_1..5`, `st_npc_loot_claim_far` (eng/rus) и собственный `grok_loot_claim.script` (3,5 КБ), который
  этот мод перекрывает (стоит выше по приоритету MO2).
- Выбор трупа NPC для обыска (ванильный `xr_corpse_detection`) берёт только тела с `HasValuableLoot` и
  `corpse_already_selected == nil` в `db.storage[id]` — на этом построена блокировка NPC. Проверено автором по ванильному
  файлу из G.A.M.M.A. 0.9.5.
- У хоста xrRazom персонаж пира — «player dummy» (`XrrPlayers():IsPlayerDummy(id)`), а не `db.actor` (подтверждено логом хоста).

## Решение

### Зависимости
| Модуль | Для чего | Если нет |
|---|---|---|
| `xr_corpse_detection` (ванильный) | `set_valuable_loot`, поле `corpse_already_selected` | блокировка своих убийств не работает |
| `ui_mcm` | чтение настроек | берутся `DEFAULTS` |
| `z_auto_looter` (Autolooter) | обёртки `get_actor` / `auto_looter` | обёртки не ставятся |
| `XrrPlayers` (xrRazom) | `IsPlayerDummy` — персонаж пира | проверка пропускается |
| `dynamic_news_helper`, `actor_menu`, `game` | сообщения при блоке | — |

### Колбэки
Регистрируются в `on_game_start`; там же (под `pcall`) ставятся обёртки автолутера.

| Колбэк | Обработчик | Назначение | Требования |
|---|---|---|---|
| `npc_on_death_callback`, `monster_on_death_callback` | `npc_on_death_callback` | классификация тела при смерти | 002–004, 015 |
| `on_before_key_press` | `on_before_key_press` | блок Use для игрока | 005, 007, 011 |
| `npc_on_get_all_from_corpse` | `npc_on_get_all_from_corpse` | NPC обыскал тело — снять претензию | 009 |
| `actor_on_update` | `actor_on_update` | раз в 1 с: блокировка своих убийств, отложенное снятие, статистика | 006–008 |
| `save_state` / `load_state` | — | сохранение таблиц | 012 |
| `on_level_changing` | `on_level_changing` | очистка при смене уровня | 013 |

### Данные
| Имя | Тип | Смысл |
|---|---|---|
| `claimed` | `victim_id → killer_id` | убийства NPC: игроку нельзя |
| `player_kills` | `victim_id → true` | убийства игрока: NPC нельзя |
| `pending` | `victim_id → time` | когда своё убийство откроется для NPC (не сохраняется) |
| `claimed_seq`, `player_seq`, `seq_counter` | порядок вставки | при `MAX_TRACKED` выбрасываются **самые старые** записи (014) |

В сейв пишутся `claimed`, `player_kills`, `loot_claim_seq = {c, p, n}`.

Константы: `MSG_DISTANCE = 25` м (подсказка от убийцы), `LOCK_INTERVAL = 1000` мс, `STATS_INTERVAL = 120000` мс,
`MAX_TRACKED = 1000`, `LOCK_VALUE = 0` (id актёра, с id NPC не совпадает).

### Порядок правил
1. Смерть: счётчик тканей для Семёнова (всегда, 015) → `enabled=false` — выход → сторона игрока (002) → свободное тело (003)
   → иначе `claimed[victim] = killer` (004).
2. Use / автолутер: `check_claim` — `enabled=false` или `player_loot_all` → свободно; нет в `claimed` → свободно; убийца мёртв
   (`release_killer_dead`) → свободно, запись удаляется; `release_killer_far`: убийца не загружен или дальше `far_distance` →
   свободно; иначе блок (005, 010, 011).
3. Блокировка своих убийств для NPC: `set_valuable_loot(id, nil)` и `corpse_already_selected = 0`, раз в секунду (006).

### Когда тело открывается
| Событие | Эффект | Условие | Требование |
|---|---|---|---|
| NPC обыскал тело (`npc_on_get_all_from_corpse`) | запись из `claimed` удаляется | `release_after_loot` | 009 |
| Игрок открыл своё убийство (Use / автолутер) | через `release_delay` с тело выходит из `player_kills`, `set_valuable_loot(id, true)` | `release_after_loot` | 007 |
| `enabled = false` или `npc_loot_all = true` | все свои убийства отдаются NPC за ≤ 1 с | — | 008 |
| Смена уровня | все таблицы очищаются | всегда | 013 |

### Настройки MCM (`grok_loot_claim/<id>`)
| id | Тип | По умолч. | Смысл |
|---|---|---|---|
| `enabled` | check | вкл | весь мод; выкл = все обыскивают всех |
| `player_loot_all` | check | выкл | игрок обыскивает всех (NPC не претендуют) |
| `npc_loot_all` | check | выкл | NPC обыскивают всех (игрок не претендует) |
| `companions_are_player` | check | вкл | убийства компаньонов = убийства игрока |
| `claim_mutants` | check | вкл | мутанты, убитые NPC, под претензией |
| `release_killer_dead` | check | вкл | можно обыскать, если убийца мёртв |
| `release_killer_far` | check | вкл | можно обыскать, если убийца далеко или не загружен |
| `far_distance` | slider 10–150 | 35 м | порог «далеко» |
| `release_after_loot` | check | вкл | обысканное тело открывается для всех |
| `release_delay` | slider 0–60 | 10 с | задержка, после которой своё убийство открывается для NPC |
| `block_autolooter` | check | вкл | автолутер подчиняется претензии |
| `show_messages` | check | вкл | сообщения при блоке |
| `debug` | check | выкл | лог `[grok_loot_claim]` |

Тексты: страница `ui_mcm_menu_grok_loot_claim`, опции `ui_mcm_grok_loot_claim_<id>` и `_desc`, заголовки групп
`ui_mcm_grok_loot_claim_header_{who,release,misc,debug}` (eng и rus).

### Отладка
При `debug` в `xray_*.log` пишутся строки `[grok_loot_claim]`: `LOADED v1.2.0 | <настройки>`, `DEATH ... -> PLAYER_KILL | CLAIMED |
FREE (<причина>)`, `USE on <тело> -> BLOCKED | ALLOWED (<причина>)`, `NPC LOOT ... was_player_kill=true  <-- LOCK FAILED`
(NPC обыскал убийство игрока — блокировка не сработала), `AUTOLOOTER (key|proximity) BLOCKED`, `LOCK`, `RELEASE`,
`SAVE`/`LOAD`, `LEVEL CHANGE`, `HEARTBEAT`, `STATS` раз в 2 минуты.

## Требования

### MOD-LOOTCLAIM-001 Настройки  [auto]
Каждая настройка ДОЛЖНА читаться как `ui_mcm.get("grok_loot_claim/<key>")`, а при отсутствии MCM или значении `nil` — из `DEFAULTS`
скрипта. Страница MCM (`grok_loot_claim_mcm.script`, id `grok_loot_claim`) ДОЛЖНА содержать все 13 ключей `DEFAULTS` с теми же
значениями по умолчанию: `enabled=true, player_loot_all=false, npc_loot_all=false, claim_mutants=true, release_killer_dead=true,
release_killer_far=true, far_distance=35 (10..150), release_after_loot=true, release_delay=10 (0..60), show_messages=true,
companions_are_player=true, block_autolooter=true, debug=false`.
- Дано MCM нет. Тогда используются `DEFAULTS`. Дано MCM вернул `false` для `enabled`. Тогда мод выключен.

### MOD-LOOTCLAIM-002 Убийство стороной игрока  [auto]
Убийца — сторона игрока, если это `db.actor`, или персонаж пира (`XrrPlayers():IsPlayerDummy(id)`; без xrRazom или при ошибке —
не пир), или компаньон (`has_info("npcx_is_companion")`) при `companions_are_player`. Если жертва — сталкер, она ДОЛЖНА попасть
в `player_kills` и сразу заблокироваться для NPC (MOD-LOOTCLAIM-006), кроме случая `npc_loot_all` (тогда ничего не делается).
Жертва-мутант от стороны игрока НЕ ДОЛЖНА ни блокироваться, ни попадать в `claimed`.
- Дано пир (dummy) убил сталкера. Тогда тело в `player_kills`, у тела `corpse_already_selected=0`, `HasValuableLoot` снят.

### MOD-LOOTCLAIM-003 Свободные тела  [auto]
Смерть НЕ ДОЛЖНА ничего регистрировать (тело свободно для всех), если, в этом порядке: нет убийцы или это самоубийство;
у жертвы есть story id; убийца — `zombied`; убийца — компаньон (при выключенном `companions_are_player`); убийца не сталкер
(мутант, аномалия-объект); жертва — мутант и `claim_mutants=false`.
- Дано зомбированный убил сталкера. Тогда `claimed` пуст.

### MOD-LOOTCLAIM-004 Убийство другим NPC  [auto]
Если ни 002, ни 003 не сработали (убийца — живой сталкер не со стороны игрока), жертва ДОЛЖНА попасть в `claimed[victim]=killer`.
- Дано сталкер 7 убил сталкера 5. Тогда `claimed[5]=7`.

### MOD-LOOTCLAIM-005 Блок обыска для игрока  [auto]
При нажатии Use (`key_bindings.kUSE`) на мёртвого сталкера или мутанта в пределах 10 м луча из камеры мод ДОЛЖЕН проверить
претензию и при блокировке выставить `flags.ret_value = false`. Претензии нет (обыск разрешён), если: мод выключен или
`player_loot_all`; тела нет в `claimed`; `release_killer_dead` и убийца загружен и мёртв (претензия при этом удаляется);
`release_killer_far` и убийца не загружен; `release_killer_far` и живой убийца дальше `far_distance` от игрока.
Другие клавиши, живые цели, не сталкеры/мутанты и промах луча игнорируются.
- Дано `claimed[5]=7`, убийца жив в 10 м. Когда Use. Тогда `ret_value=false`.
- Дано убийца жив в 40 м (`far_distance=35`). Тогда обыск разрешён.

### MOD-LOOTCLAIM-006 Блокировка NPC на своих убийствах  [auto]
Блокировка тела ДОЛЖНА: вызвать `xr_corpse_detection.set_valuable_loot(id, nil)` и выставить
`db.storage[id].corpse_already_selected = 0` (если запись есть). Пока мод включён и `npc_loot_all` выключен, `actor_on_update`
ДОЛЖЕН повторять блокировку всех тел из `player_kills` не чаще раза в 1000 мс.
- Дано NPC сбросил `corpse_already_selected=nil`. Когда прошло ≥1000 мс. Тогда значение снова 0.

### MOD-LOOTCLAIM-007 Снятие блокировки после своего обыска  [auto]
Когда игрок открывает своё убийство (Use или автолутер разрешили) и `release_after_loot` включён, мод ДОЛЖЕН запланировать
снятие через `release_delay` секунд (один раз). По наступлении времени `actor_on_update` ДОЛЖЕН снять блокировку: убрать тело
из `player_kills` и `pending`, `corpse_already_selected = nil`, `set_valuable_loot(id, true)`.
- Дано своё убийство 5, `release_delay=10`. Когда Use в момент t. Тогда до t+10 с тело заблокировано, после — свободно для NPC.

### MOD-LOOTCLAIM-008 Выключение отдаёт тела NPC  [auto]
Если `enabled=false` или `npc_loot_all=true`, следующий тик `actor_on_update` ДОЛЖЕН снять блокировку со всех тел `player_kills`
(как в 007), а новые смерти при `enabled=false` НЕ ДОЛЖНЫ регистрироваться.

### MOD-LOOTCLAIM-009 Обыск NPC снимает претензию  [auto]
`npc_on_get_all_from_corpse(npc, corpse, ...)` при `release_after_loot` ДОЛЖЕН удалить тело из `claimed` (теперь его может
обыскать и игрок). На `player_kills` это не влияет.

### MOD-LOOTCLAIM-010 Автолутер  [auto]
Если модуль `z_auto_looter` существует и `block_autolooter` включён: обёртка `get_actor` ДОЛЖНА возвращать `nil` для тела под
претензией (с сообщением `st_npc_loot_claim_far` при `show_messages`), обёртка `auto_looter(key, body)` ДОЛЖНА не вызывать
оригинал для такого тела. Для разрешённого тела — вызывать оригинал и планировать снятие как в 007. При `block_autolooter=false`
обёртки ДОЛЖНЫ пропускать всё. Без `z_auto_looter` мод работает без обёрток.

### MOD-LOOTCLAIM-011 Сообщение при блоке  [auto]
При блоке и `show_messages`: если убийца жив, сталкер и не дальше 25 м — подсказка `dynamic_news_helper.send_tip` с текстом
`st_npc_loot_claim_last_<1..5>` от имени убийцы; иначе — `actor_menu.set_msg(1, st_npc_loot_claim_far, 5)`.

### MOD-LOOTCLAIM-012 Сохранение  [auto]
`save_state` ДОЛЖЕН записать `m_data.claimed`, `m_data.player_kills` и `m_data.loot_claim_seq = {c, p, n}`; `load_state` ДОЛЖЕН
восстановить их (отсутствующее → пустые таблицы, счётчик 0). `pending` НЕ сохраняется.

### MOD-LOOTCLAIM-013 Смена уровня  [auto]
`on_level_changing` ДОЛЖЕН очистить `claimed`, `player_kills`, `pending` и служебные таблицы.

### MOD-LOOTCLAIM-014 Ограничение таблиц  [auto]
Когда в `claimed` или `player_kills` становится больше 1000 записей, ДОЛЖНЫ удаляться 100 самых старых (по порядку добавления),
а не вся таблица.

### MOD-LOOTCLAIM-015 Счётчик заданий Семёнова  [auto]
Независимо от настроек: если `db.actor` убил мутанта, существует story-объект `yan_ecolog_semenov` и переменная
`yan_ecolog_semenov_task_1_tissue_need` > 0, мод ДОЛЖЕН увеличить `yan_ecolog_semenov_task_1_tissue_count` на 1.

### MOD-LOOTCLAIM-016 Кооп: убийства пира у хоста  [manual]
У хоста тело, убитое пиром, ДОЛЖНО быть закрыто для NPC и открыто для обоих игроков (оно не попадает в `claimed`).

## Безопасность
- Без MCM — значения по умолчанию; без xrRazom — `is_peer_avatar` всегда `false`; без `z_auto_looter` — обёрток нет.
- Обёртки автолутера ставятся один раз при `on_game_start` (под `pcall`).
- Мод не меняет предметы — только флаги выбора тела у NPC и разрешение на Use.

## Вне области / известные ограничения
- Моды «311 NPC Stop Looting Dead Bodies», Alife Plus «Loot Rights» и опция Useful Idiots «Only Companions Can Loot» должны быть
  выключены, а дистанция лута NPC в опциях игры = 0, иначе NPC не обыскивают тела вообще.
- Блокировка опирается на внутренности ванильного `xr_corpse_detection` (`HasValuableLoot`, `corpse_already_selected`,
  `set_valuable_loot`); в другой сборке они могут отличаться.
- `HasValuableLoot` не сохраняется: после загрузки NPC игнорируют тела, умершие до загрузки.
- Убийство NPC может обыскать **любой** NPC, не только убийца.
- «Игрок обыскал» = нажатие Use / срабатывание автолутера на своём убийстве, а не реальное взятие предмета.
- Пустое тело не вызывает `npc_on_get_all_from_corpse` и остаётся закрытым для игрока.
- Имена `z_auto_looter.get_actor` и `auto_looter` взяты из кода мода «Looting takes time»; сам `z_auto_looter` не проверялся.
- Моды, забирающие вещи без Use и без `z_auto_looter`, претензию обходят.
- xrRazom: отложенное снятие блокировки с убийств пира срабатывает только на нажатие Use у хоста.
- **Пир считает правила сам.** Мод работает на каждой машине независимо. У пира трупы приходят «зеркалами», и (по наблюдениям
  для FX-KILLTR, не проверено для этого мода) колбэк смерти приходит с убийцей = персонаж пира. Тогда у пира почти любое тело
  попадает в `player_kills`, а `claimed` пуст — пир не блокируется на чужих убийствах, в отличие от хоста. Блокировка NPC
  у пира ни на что не влияет: ИИ работает на хосте.
- Счётчик Семёнова у хоста считает только убийства хоста (`db.actor`); у пира, по той же причине, может считать каждое
  тело-зеркало мутанта. Значения пира в итоге перезаписываются хостом (задания ведёт хост) — не проверено.
- Имена ключей `m_data.claimed` и `m_data.player_kills` общие и могут совпасть с ключами других модов.
- Претензия на тело с незагруженным убийцей остаётся в `claimed` (разрешение временное, по расстоянию).
- После загрузки сохранения запланированные снятия (`pending`) теряются: своё тело остаётся закрытым для NPC до повторного
  открытия игроком.

## Проверка в игре

### Сценарии
План автора мода; в последнем столбце — требования, которые покрывают строку.

| # | Сценарий | Ожидание | Требование |
|---|---|---|---|
| 1 | Игрок убил сталкера, рядом NPC | NPC не обыскивает, пока игрок не откроет тело (+ `release_delay`) | 002, 006, 007 |
| 2 | NPC убил NPC, убийца жив рядом, Use | блок + подсказка от убийцы | 004, 005, 011 |
| 3 | То же, убийца мёртв | обыск разрешён (`release_killer_dead`) | 005 |
| 4 | То же, убийца дальше `far_distance` | обыск разрешён; вернулся убийца — снова блок | 005 |
| 5 | NPC обыскал своё убийство | игрок может обыскать (`release_after_loot`) | 009 |
| 6 | Мутант убит NPC | блок при `claim_mutants`, иначе свободно | 003, 004 |
| 7 | F5/F9 | претензии и блокировки сохраняются | 012 |
| 8 | Смена уровня | таблицы пусты | 013 |
| 9 | Автолутер на теле под претензией | блок по клавише и по близости | 010 |
| 10 | xrRazom: убийство пира | у хоста тело закрыто для NPC (`PLAYER_KILL`) | 002, 016 |
| 11 | `enabled = false` | все обыскивают всех, блокировки сняты за ≤ 1 с | 008 |

### Быстрая проверка по логу
1. MCM → `grok_loot_claim` → включить `debug`.
2. Дождаться, когда NPC убьёт сталкера рядом; Use на теле → обыск не открывается, подсказка от убийцы; в логе
   `DEATH ... -> CLAIMED` и `USE on ... -> BLOCKED`.
3. Отойти дальше 35 м от убийцы → Use открывает обыск (`ALLOWED (killer is farther than far_distance)`).
4. Убить сталкера самому → `PLAYER_KILL (NPCs locked out)`, NPC тело не обыскивают; открыть его — через 10 с
   `RELEASE player kill id=... now lootable by NPCs`.
5. В коопе у хоста: пир убивает сталкера → в логе хоста `player_side=true`.

## История версий
- 1.0 — оригинальный Grok: игрок обыскивает всех, претензия по живому убийце.
- 1.1 — убийства игрока закрыты для NPC (`corpse_already_selected`), снятие после обыска, персонаж пира xrRazom.
- 1.1.3–1.1.5 — исправлен сброс претензий при загрузке; обёртка автолутера; выброс старых записей и очистка при смене уровня.
- 1.2.0 — MCM, диагностика, настройки дальности и задержки.
- В репозитории: опубликован как `v.1.2` (6725f8b); переименован в `v.1.2.1` с `SDD.md` (f342073); опубликован снова как `v.1.2`
  (23f28bd). Игровые файлы во всех трёх коммитах побайтно одинаковы; содержимое `SDD.md` перенесено в этот документ.
