# MOD-LOOTCLAIM: Loot Claim — Software Design Description
Статус: действует        Проверка в игре: не проводилась        Мод: `Combined GAMMA NPC Loot Claim v.1.2.1` (имя папки — как в `pack.json`, тесты берут его оттуда)        Скрипты: `gamedata/scripts/grok_loot_claim.script`, `gamedata/scripts/grok_loot_claim_mcm.script`, заглушки `npc_loot_claim.script`, `zz_npc_loot_claim_softcore.script`
Где ставить: оба (через секцию «xrRazom Sync»)        Зависит от: `G.A.M.M.A. NPC Loot Claim Remade` (ниже по приоритету), MCM, xrRazom, `z_auto_looter` (все необязательны)        Лог-маркер: `[grok_loot_claim] LOADED ...` (только при `debug`)

| | |
|---|---|
| Версия | 1.2.1 |
| Платформа | S.T.A.L.K.E.R. Anomaly / G.A.M.M.A. 0.9.5 (Monolith), Lua 5.1 |
| Файлы | `grok_loot_claim.script`, `grok_loot_claim_mcm.script`, `ui_mcm_grok_loot_claim.xml` (rus, eng) |
| Заменяет | `grok_loot_claim.script` из «G.A.M.M.A. NPC Loot Claim Remade» |

## 1. Назначение

«Клейм» трупов сталкеров между игроком и НПС:

- **Киллы игрока** (ГГ, компаньоны, пир xRazom) лутает только игрок, НПС — нет.
- **Киллы НПС** лутают НПС (как в ванили), игрок — нет.
- Труп открывается для всех, когда: он облутан, убийца мёртв или далеко (настраивается).

Все правила переключаются в MCM; без MCM действуют значения по умолчанию из таблицы `DEFAULTS`.

## 2. Область и допущения

- Скрипты `npc_loot_claim.script` и `zz_npc_loot_claim_softcore.script` остаются пустыми заглушками из базового мода (отключают оригинальный loot claim). В этот архив они **не входят**.
- Скрипт ставится поверх `G.A.M.M.A. NPC Loot Claim Remade` (перезаписывает `grok_loot_claim.script`).
- Моды 311 «NPC Stop Looting Dead Bodies», Alife Plus «Loot Rights» и опция Useful Idiots «Only Companions Can Loot» должны быть выключены, иначе НПС не лутают вообще. Дистанция лута НПС в опциях игры = 0.

## 3. Зависимости

| Модуль | Для чего | Если нет |
|---|---|---|
| `xr_corpse_detection` (ванильный) | `set_valuable_loot`, поле `corpse_already_selected` | Лок киллов игрока не работает |
| `ui_mcm` | Чтение опций | Берутся `DEFAULTS` |
| `z_auto_looter` (Autolooter) | Обёртка `get_actor` / `auto_looter` | Хук пропускается |
| `XrrPlayers` (xRazom) | `IsPlayerDummy` — аватар пира | Проверка пропускается |
| `ui_inventory` (ванильный GAMMA) | Шлюз `ui_inventory.start`, страховка `GUI:Close()` / `GetPartner()` / `mode` | Шлюз и страховка пропускаются, остаётся блок Use |
| `dynamic_news_helper`, `actor_menu`, `game` | Сообщения при блоке | — |

## 4. Архитектура

### 4.1 Колбэки

| Колбэк | Обработчик | Назначение |
|---|---|---|
| `npc_on_death_callback`, `monster_on_death_callback` | `npc_on_death_callback` | Классификация трупа при смерти |
| `on_before_key_press` | `on_before_key_press` | Блок клавиши Use для игрока |
| `npc_on_get_all_from_corpse` | `npc_on_get_all_from_corpse` | НПС залутал труп: снять клейм |
| `actor_on_update` | `actor_on_update` | Раз в 1 с: лок киллов игрока, отложенный релиз, статистика |
| `GUI_on_show` | `GUI_on_show` | Страховка: на следующем тике проверяет открытое окно лута (`loot_window_guard`) |
| `save_state` / `load_state` | — | Сохранение таблиц |
| `on_level_changing` | `on_level_changing` | Очистка при смене уровня |

### 4.2 Структуры данных

| Имя | Тип | Смысл |
|---|---|---|
| `claimed` | `victim_id → killer_id` | Киллы НПС: игрок заблокирован |
| `player_kills` | `victim_id → true` | Киллы игрока: НПС заблокированы |
| `pending` | `victim_id → time` | Когда кил игрока освободится для НПС |
| `claimed_seq`, `player_seq`, `seq_counter` | порядок вставки | Выброс только **самых старых** записей при `MAX_TRACKED` (1000) |
| `last_blocked` | `victim_id → time_global()` | Когда Use по трупу был заблокирован в последний раз (диагностика обхода, не сохраняется) |

Сохраняются в сейв: `claimed`, `player_kills`, `loot_claim_seq {c, p, n}`.

### 4.3 Константы

`MSG_DISTANCE = 25` м (подсказка от убийцы), `LOCK_INTERVAL = 1000` мс, `STATS_INTERVAL = 120000` мс, `MAX_TRACKED = 1000`, `LOCK_VALUE = 0` (id актёра, не совпадает с id НПС).

## 5. Правила

### 5.1 Классификация при смерти

Порядок проверок:

1. Счётчик тканей мутантов для Семёнова (кил игрока по мутанту): всегда, независимо от опций.
2. `enabled = false` → выход.
3. **Убийца на стороне игрока**: `db.actor`, аватар пира xRazom или компаньон (`npcx_is_companion`) при `companions_are_player`.
   - жертва — сталкер: при `npc_loot_all = false` попадает в `player_kills` и блокируется для НПС;
   - жертва — не сталкер: ничего.
4. **Свободные трупы** (не клеймятся): нет убийцы или суицид; сюжетный НПС; убийца `zombied`; убийца-компаньон при `companions_are_player = false`; убийца не сталкер (мутант и т.д.); жертва-мутант при `claim_mutants = false`.
5. Иначе → `claimed[victim] = killer` (игрок заблокирован).

### 5.2 Блок игрока (`check_claim`)

Порядок: `enabled=false` или `player_loot_all` → свободно; нет в `claimed` → свободно; убийца мёртв и `release_killer_dead` → свободно (запись удаляется); `release_killer_far`: убийца не загружен → свободно, жив и дальше `far_distance` → свободно; иначе **блок**.

При блоке: `flags.ret_value = false`, плюс при `show_messages` подсказка от убийцы (≤ 25 м, жив) либо сообщение `st_npc_loot_claim_far`. Автолутер: `z_auto_looter.get_actor` возвращает `nil`, `auto_looter` не вызывается (опция `block_autolooter`).

### 5.3 Лок киллов игрока для НПС

Для `player_kills` раз в секунду: `xr_corpse_detection.set_valuable_loot(id, nil)` и `db.storage[id].corpse_already_selected = 0`. Ванильный выбор трупа требует `HasValuableLoot` и `corpse_already_selected == nil`, поэтому НПС такие трупы не выбирают.

### 5.4 Открытие трупа

| Событие | Эффект | Условие |
|---|---|---|
| НПС взял вещи (`npc_on_get_all_from_corpse`) | запись из `claimed` удаляется | `release_after_loot` |
| Игрок открыл свой кил (Use/Autolooter) | через `release_delay` с кил выходит из `player_kills`, лок снимается, `set_valuable_loot(id, true)` | `release_after_loot` |
| `enabled = false` или `npc_loot_all = true` | все киллы игрока освобождаются (≤ 1 с) | — |
| Смена уровня | очищаются все таблицы | всегда |

### 5.5 Шлюз открытия окна лута (с 1.2.1)

Блока на клавише Use недостаточно: окно лута открывается через `ui_inventory.start("loot", тело)`, которое вызывают колбэк движка `ActorMenu_on_before_init_mode`, меню компаньонов и другие моды. `flags.ret_value = false` на Use перекрывает только клавишу. Поэтому защита двухуровневая:

1. **Основной шлюз.** `ui_inventory.start` обёрнута (`hook_ui_inventory`, ставится при `on_game_start`). Для режима `loot` и мёртвого сталкера/мутанта (не актёра) вызывается `check_claim`:
   - блок → окно не открывается, показывается сообщение (если Use не показал его менее 500 мс назад), в лог `LOOT WINDOW REFUSED`;
   - не блок → `on_player_opens(id)` (отложенный релиз своего кила работает при любом пути открытия, а не только с Use), затем вызов оригинальной `start`.
2. **Страховка.** По `GUI_on_show` на следующем тике (партнёр окна задаётся после показа) `loot_window_guard` проверяет: режим `loot`, партнёр мёртв, труп заклеймен. Если да — `GUI:Close()` (запасной вариант `level.start_stop_menu`), сообщение, в лог `BYPASS`. Срабатывает, только если окно всё же открылось мимо шлюза.

Решение о блоке везде одно и то же — `check_claim`, поэтому правила освобождения (раздел 5.2 и 5.4) действуют одинаково на всех путях.

## 6. Опции MCM (`grok_loot_claim/<id>`)

| id | Тип | По умолч. | Смысл |
|---|---|---|---|
| `enabled` | check | вкл | Весь мод; выкл = все лутают всех |
| `player_loot_all` | check | выкл | ГГ лутает всех (НПС не клеймят) |
| `npc_loot_all` | check | выкл | НПС лутают всех (ГГ не клеймит) |
| `companions_are_player` | check | вкл | Киллы компаньонов = киллы игрока |
| `claim_mutants` | check | вкл | Мутанты, убитые НПС, клеймятся |
| `release_killer_dead` | check | вкл | Можно лутать, если убийца мёртв |
| `release_killer_far` | check | вкл | Можно лутать, если убийца далеко/не загружен |
| `far_distance` | slider 10–150 | 35 м | Порог «далеко» |
| `release_after_loot` | check | вкл | Облутанный труп открывается для всех |
| `release_delay` | slider 0–60 | 10 с | Задержка до открытия кила игрока для НПС |
| `block_autolooter` | check | вкл | Autolooter подчиняется клейму |
| `show_messages` | check | вкл | Сообщения при блоке |
| `debug` | check | выкл | Лог `[grok_loot_claim]` |

Локализация: название страницы — `ui_mcm_menu_grok_loot_claim`; опции — `ui_mcm_grok_loot_claim_<id>` и `_desc`; заголовки групп — `ui_mcm_grok_loot_claim_header_*`.

## 7. Отладка

При `debug` в `xray_*.log` пишутся строки `[grok_loot_claim]`: `LOADED` (значения опций, модули), `DEATH ... -> PLAYER_KILL | CLAIMED | FREE (причина)`, `USE on <труп> -> BLOCKED | ALLOWED (причина)`, `NPC LOOT ... was_player_kill=true <-- LOCK FAILED`, `AUTOLOOTER ... BLOCKED`, `LOOT WINDOW REFUSED` (шлюз; `Use hook blocked it N ms ago` / `never` показывает, видел ли Use этот путь), `BYPASS` (страховка закрыла уже открытое окно), `USE ray hit a LIVING object` (луч Use попал в живого, труп не проверялся), `UI HOOK: ui_inventory.start wrapped`, `RELEASE`, `LOAD`/`SAVE`, `STATS` раз в 2 минуты.

## 8. Ограничения и непроверенные допущения

- Лок опирается на внутренности ванильного `xr_corpse_detection`: `HasValuableLoot`, `corpse_already_selected`, `set_valuable_loot`. Они проверены по ванильному файлу из G.A.M.M.A. 0.9.5, но могут отличаться в другой сборке.
- Ванильный `HasValuableLoot` не сохраняется: после загрузки НПС игнорируют трупы, умершие до загрузки.
- Киллы НПС лутает **любой** НПС, не только убийца.
- «Игрок облутал» определяется нажатием Use/Autolooter на своём киле, а не реальным взятием предмета.
- Пустой труп (нет предметов) не вызывает `npc_on_get_all_from_corpse` и остаётся закрытым для игрока.
- Имена `z_auto_looter.get_actor` и `auto_looter` взяты из кода мода «Looting takes time»; сам `z_auto_looter` не проверялся.
- xRazom: аватар пира распознаётся через `IsPlayerDummy` (подтверждено логом хоста); отложенный релиз киллов пира срабатывает только на нажатие Use у хоста.
- Шлюз (`ui_inventory.start`) и страховка (`GUI_on_show`) проверены только по коду `ui_inventory.script` и `zzzz_loot_searching.script`, в игре не запускались. Работа шлюза предполагает, что вызовы `start(...)` внутри `ui_inventory` и `ui_companion_inv` ищут функцию в таблице модуля (тот же приём использует «Looting takes time» для `z_auto_looter`).
- Моды, забирающие вещи без окна лута (программный перенос предметов) и без `z_auto_looter`, клейм обходят.
- Поведение по умолчанию мягче оригинального «Remade»: освобождение по `release_after_loot` и по дальности `release_killer_far` (35 м) в оригинале отсутствует. Оригинал блокирует, пока убийца загружен, жив и является сталкером. Любой НПС, взявший вещи с НПС-кила, снимает клейм для игрока; НПС берут только ценное, хлам остаётся. Это задумано, но игроки могут воспринимать как утечку; для поведения, близкого к оригиналу, выключить `release_after_loot` и `release_killer_far`. Отдельной опции «освобождать только свои киллы» нет.
- Причина, по которой окно лута открывалось при заблокированном Use (случай «убийца рядом, пришло сообщение, окно открылось»), не установлена: подозреваются обход `flags.ret_value` другим путём открытия или несовпадение луча `ray_pick` с целью движка. С 1.2.1 путь закрыт шлюзом вне зависимости от причины; строки `LOOT WINDOW REFUSED` / `BYPASS` в `debug`-логе покажут, какой путь был.

## 9. План проверки

| # | Сценарий | Ожидание |
|---|---|---|
| 1 | Игрок убил сталкера, рядом НПС | НПС не лутает, пока игрок не откроет труп (+ `release_delay`) |
| 2 | НПС убил НПС, убийца жив рядом, Use | Блок + подсказка |
| 3 | То же, убийца мёртв | Лут разрешён (`release_killer_dead`) |
| 4 | То же, убийца дальше `far_distance` | Лут разрешён, при возвращении убийцы снова блок |
| 5 | НПС залутал свой кил | Игрок может лутать (`release_after_loot`) |
| 6 | Мутант убит НПС | Блок при `claim_mutants`, иначе свободно |
| 7 | F5/F9 | Клеймы и локи сохраняются |
| 8 | Смена уровня | Таблицы пусты |
| 9 | Autolooter на клейме | Блок по клавише и по близости |
| 10 | xRazom: кил пира | Лок для НПС (`player_side=true`) |
| 11 | `enabled = false` | Все лутают всех, локи сняты за ≤ 1 с |
| 12 | НПС убил НПС, убийца рядом и жив; Use по трупу (в т.ч. сразу после смены локации) | Окно не открывается; при обходе Use — `LOOT WINDOW REFUSED` в логе |
| 13 | Окно лута на заклейменном трупе открывается другим способом | Шлюз отказывает; если окно всё же открылось — страховка закрывает его (`BYPASS`) |
| 14 | Игрок открывает свой кил не через Use | Через `release_delay` кил освобождается для НПС (`on_player_opens` из шлюза) |
| 15 | Мёртвый сталкер без клейма / свободный труп | Окно открывается как обычно |

## 10. История версий

- 1.0 — оригинальный Grok: игрок лутает всех, клейм по живому убийце.
- 1.1 — киллы игрока закрыты для НПС (`corpse_already_selected`), освобождение после лута, аватар пира xRazom.
- 1.1.3–1.1.5 — исправлен сброс клеймов при загрузке; обёртка Autolooter; выброс старых записей и очистка при смене уровня.
- 1.2.0 — MCM, интеграция диагностики, опции дальности и задержки.
- 1.2.1 — шлюз `ui_inventory.start` и страховка `GUI_on_show` (закрытие обхода блока Use), релиз своих киллов при любом пути открытия, диагностика обхода; опции MCM и XML не менялись.

## 11. Требования (ID для тестов)

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

Шлюз окна лута 1.2.1 (раздел 5.5) пока не описан требованиями с ID и не покрыт автотестами; требования 001–016 проверены тестами `tests/lua/test_lootclaim.lua` на скрипте 1.2.1.
