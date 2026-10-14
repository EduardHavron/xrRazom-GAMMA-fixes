# MOD-LOOTCLAIM: право на лут (Combined GAMMA NPC Loot Claim v1.2.x)
Статус: действует        Мод: `Combined GAMMA NPC Loot Claim v.1.2` (версия в имени папки; тесты берут имя из `pack.json`)        Скрипты: `gamedata/scripts/grok_loot_claim.script`, `gamedata/scripts/grok_loot_claim_mcm.script`
Где ставить: оба (через секцию «xrRazom Sync»)        Зависит от: `G.A.M.M.A. NPC Loot Claim Remade` (ниже по приоритету), MCM (необязательно), xrRazom (необязательно), `z_auto_looter` (необязательно)        Лог-маркер: `[grok_loot_claim] ...` (только при `debug`)

Сторонний мод, а не фикс xrRazom: целиком заменяет `grok_loot_claim.script` базового мода и добавляет поддержку коопа.
Авторское описание устройства (SDD, план проверки, история версий) было в папке мода `v.1.2.1` и при публикации `v.1.2` (коммит 23f28bd) из репозитория ушло; копия в истории: [SDD.md @ 3f1d61e](https://github.com/EduardHavron/xrRazom-GAMMA-fixes/blob/3f1d61e/mods/Combined%20GAMMA%20NPC%20Loot%20Claim%20v.1.2.1/SDD.md). Этот документ — требования с ID для тестов; при расхождении с SDD сверяться с кодом и править оба.

## Проблема
В G.A.M.M.A. «право на лут» обеспечивают `npc_loot_claim` / `zz_npc_loot_claim_softcore` / `grok_loot_claim` из базового мода.
Нужны: настраиваемые правила (MCM), «свои убийства обыскивает только игрок, а NPC — нет», «чужие убийства игрок не обыскивает,
пока убийца жив и рядом», блокировка автолутера и учёт убийств пира xrRazom как убийств игрока.

## Причина (как устроено в базе)
- `G.A.M.M.A. NPC Loot Claim Remade`: `npc_loot_claim.script` и `zz_npc_loot_claim_softcore.script` — заглушки (`printf(...)`),
  строки `st_npc_loot_claim_last_1..5`, `st_npc_loot_claim_far` (eng/rus), собственный `grok_loot_claim.script` (3,5 КБ),
  который v1.2 перекрывает (стоит выше по приоритету MO2).
- Выбор трупа NPC для обыска (`xr_corpse_detection`) берёт только тела с `HasValuableLoot` и `corpse_already_selected == nil`
  в `db.storage[id]` — на этом построена блокировка NPC.
- У хоста xrRazom персонаж пира — «player dummy» (`XrrPlayers():IsPlayerDummy(id)`), а не `db.actor`.

## Решение
Колбэки (регистрируются в `on_game_start`): `npc_on_death_callback` и `monster_on_death_callback` → классификация смерти;
`npc_on_get_all_from_corpse` → снятие претензии после обыска NPC; `on_before_key_press` (Use) → блок игрока;
`actor_on_update` (раз в 1000 мс) → удержание/снятие блокировки NPC; `save_state`/`load_state`; `on_level_changing` → сброс.
Плюс обёртки `z_auto_looter.get_actor` и `z_auto_looter.auto_looter`. Таблицы: `claimed[victim]=killer` (игроку нельзя),
`player_kills[victim]=true` (NPC нельзя), `pending[victim]=время снятия`.

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
- Из SDD автора: моды «311 NPC Stop Looting Dead Bodies», Alife Plus «Loot Rights» и опция Useful Idiots «Only Companions Can Loot»
  должны быть выключены, а дистанция лута NPC в опциях игры = 0, иначе NPC не обыскивают тела вообще.
- Из SDD автора: `HasValuableLoot` не сохраняется — после загрузки NPC игнорируют тела, умершие до загрузки; чужое убийство может
  обыскать любой NPC, не только убийца; «игрок облутал» = нажатие Use/автолутера, а не взятие предмета; пустое тело не вызывает
  `npc_on_get_all_from_corpse` и остаётся закрытым для игрока; моды, забирающие вещи без Use и без `z_auto_looter`, обходят претензию.
- В текущей папке мода `SDD.md` нет (см. ссылку на историю в начале документа).
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
1. MCM → `grok_loot_claim` → включить `debug`.
2. Дождаться, когда NPC убьёт сталкера рядом; Use на теле → обыск не открывается, подсказка от убийцы; в логе
   `DEATH ... -> CLAIMED` и `USE on ... -> BLOCKED`.
3. Отойти дальше 35 м от убийцы → Use открывает обыск (`ALLOWED (killer is farther than far_distance)`).
4. Убить сталкера самому → `PLAYER_KILL (NPCs locked out)`, NPC тело не обыскивают; открыть его — через 10 с
   `RELEASE player kill id=... now lootable by NPCs`.
5. В коопе у хоста: пир убивает сталкера → в логе хоста `player_side=true`.
