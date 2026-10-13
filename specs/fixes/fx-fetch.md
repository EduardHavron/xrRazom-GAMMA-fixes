# FX-FETCH: честная награда за задания «принеси»
Статус: действует        Мод: `zz xrRazom Fix - Fetch Reward`        Скрипт: `gamedata/scripts/zz_xrrfix_fetch_reward.script`
Где ставить: хост (на пире безвреден — там `calc_fetch_money` не вызывается)        Зависит от: xrRazom Co-op 1.4 (`xrr_quest_reward.calc_fetch_money`, `XrrPlayers`), Tasks QoL Pack (`tasks_fetch.script`, `xr_effects.fetch_reward_and_remove`)        Лог-маркер: `[XRRFIX] fetch: calc_fetch_money patched (host reads peer avatars)`

## Проблема
В кооперативе награда за fetch-задания (шкуры, части мутантов, нашивки, оружие…) в 5–20 раз выше, чем в соло.
Промежуточные версии фикса давали обратные перекосы: другу 16k вместо ~50k за ТОЗ-34 («охотник на химер»),
хосту — ничего за сданные им задания (simulation_task_23/97/91).

## Причина
- Хост в `task_manager.task_callback` (`xrr_patch_quests.script`, ветка `state == task.completed`) ДО повтора `on_complete`
  дважды вызывает `xrr_quest_reward.calc_fetch_money(id)`:
  1. `reward_fetch` — доля пиров, уходит в `xrr_quest_reward.broadcast` → `SendQuestReward`;
  2. `fetch_money` — кредит самого хоста, `dialogs.relocate_money(db.actor, fetch_money, "in")` только при `> 0`.
  Вызовы идут до `_orig_task_callback` и до `XrrAlife():ConsumePartyItems(...)` — предметы ещё у владельцев.
- `calc_fetch_money` (`xrr_quest_reward.script`) считает `cost * count * get_eco_factor("rewards") * mult ±10%`,
  игнорируя то, что делает действующий `xr_effects.fetch_reward_and_remove` (Tasks QoL Pack, `tasks_fetch.script`):
  `cost / multiuse`, `condition²` (для оружия — среднее состояние деталей `prt_w_*` / 100), предметы на поясе не учитываются,
  минимум 50, для артефактов (шкуры в GAMMA — артефакт-класса) множитель `0.4 / 0.5 / 0.6` по `get_eco_factor("type")`.
  Отсюда переплата.
- Ванильная выплата при этом заглушена: обёртка `fetch_reward_and_remove` в `xrr_patch_quest_story_effects.script`
  взводит «мьют», и следующий `reward_random_money` вне condlist логирует
  `[xrRazom][quest] fetch vanilla pay muted (task_callback grant is the payment)` и ничего не платит.
  Значит, кредит хоста из второго вызова — его единственная оплата.
- История версий фикса:
  - v1: пиры публиковали свою оценку в peer vars `xrrfix_fv_<task>` — упёрлись в лимит PeerVar
    (`var cap reached ... dropped`), а Autocomplete Tasks сдаёт задание сразу при взятии, раньше 2-секундной публикации →
    резервные 25% (16k вместо ~50k).
  - v2: хост читает реальный инвентарь аватара пира; но при сдаче хостом кредит хоста ставился 0 в расчёте на ванильную
    выплату, которая заглушена → хост не получал ничего. Исправлено: оба вызова считают от стоимости у держателя.

## Решение
В `on_game_start` (под `pcall`) заменяется `xrr_quest_reward.calc_fetch_money(task_id)`:
1. `fetch_info(task_id)`: из `task_manager.task_ini` `on_complete` парсится `fetch_reward_and_remove(<var>[:<mult>])`;
   `sec = load_var(db.actor, var)` (строка, существующая секция), `count = load_var(var .. "_count") or 1`, `mult = tonumber or 1`.
   Нет данных — вызывается оригинал.
2. Стоимость у держателя `inventory_value(fi, owner)` — та же формула, что в `tasks_fetch.fetch_reward_and_remove`, без ±10%:
   `cost = ini.cost / max_use`; `use_con = max_use == 1 и не device и не battery`; перебор инвентаря, кроме пояса;
   на предмет `cost * cnt * con² * mult` (`cnt` — оставшиеся использования для multiuse, иначе 1; `con` — среднее `prt_w_*`/100
   для оружия, иначе `condition()`); набирается до `count`; не хватило — `nil`; минимум 50; артефакт (по последнему предмету) —
   множитель eco.
3. Порядок источников (каждый под `pcall`):
   - инвентарь хоста (`db.actor`) → лог `fetch: <task> host items <sec> x<count> -> <v>`;
   - лучшая стоимость среди аватаров пиров (`XrrPlayers():GetPeerLocalIdAt(i)` → `level.object_by_id`), у которых хватает
     предметов → лог `fetch: <task> items of <nick> <sec> x<count> -> <v>`;
   - номинал `cost * count * mult` (×eco для секций с `class` на `ART`), минимум 50 → лог
     `fetch: <task> no holder reachable, nominal <sec> x<count> -> <v>`;
   - если и номинал не посчитался — оригинал.
4. Результат — `roll(v)`: целое в `[floor(v - floor(0.1v)), floor(v + floor(0.1v))]`. Каждый из двух вызовов катит отдельно.

## Требования
### FX-FETCH-001 Формула совпадает с Tasks QoL  [auto]
`inventory_value` ДОЛЖНА давать ту же сумму, что `fetch_reward_and_remove` до броска ±10%.
- Дано заглушки: секция `cost=1000`, не multiuse, не артефакт; в инвентаре 2 предмета `condition 0.5` и `1.0`; `count=2`, `mult=1`
  Когда вызывается `inventory_value(fi, owner)`
  Тогда результат `1000*0.25 + 1000*1 = 1250`.
- Дано та же секция артефакт-класса и `get_eco_factor("type") == 3`
  Тогда результат `1250 * 0.4 = 500`.
- Дано оружие с `parts = { prt_w_a = 80, prt_w_b = 60, other = 10 }`
  Тогда `con = 0.7`, вклад `cost * 0.49`.

### FX-FETCH-002 Пояс, multiuse, минимум и нехватка  [auto]
Предметы на поясе НЕ ДОЛЖНЫ учитываться; для multiuse ДОЛЖНЫ учитываться оставшиеся использования и `cost / max_use`;
сумма ниже 50 ДОЛЖНА подниматься до 50; при нехватке предметов результат ДОЛЖЕН быть `nil`.
- Дано `count=2`, в инвентаре один подходящий предмет и один такой же на поясе
  Когда вызывается `inventory_value`
  Тогда результат `nil`.
- Дано multiuse `max_use=3`, `cost=300`, один предмет с 2 использованиями, `count=2`
  Тогда результат `max(300/3*2, 50) = 200` (без condition).

### FX-FETCH-003 Порядок источников  [auto]
Обёртка ДОЛЖНА брать стоимость сначала у хоста, затем у лучшего аватара пира, затем номинал, затем оригинал.
- Дано у хоста предметов хватает (`inventory_value(db.actor) = 1000`) и у пира тоже (`2000`)
  Когда вызывается `calc_fetch_money`
  Тогда результат в `[900, 1100]`, лог `host items`.
- Дано у хоста не хватает, у пиров A=800 и B=1200
  Тогда результат в `[1080, 1320]`, лог `items of B`.
- Дано нет держателя
  Тогда результат — бросок от номинала, лог `no holder reachable, nominal`.
- Дано `on_complete` без `fetch_reward_and_remove`
  Тогда вызван оригинал и возвращён его результат.

### FX-FETCH-004 Кредит хоста не нулевой  [auto]
Оба вызова за одно завершение ДОЛЖНЫ возвращать положительную сумму от одного и того же источника; кредит хоста НЕ ДОЛЖЕН быть 0.
- Дано держатель найден, `v = 500`
  Когда `calc_fetch_money` вызывается дважды подряд для одного задания
  Тогда оба результата в `[450, 550]` (могут различаться), ни один не 0.

### FX-FETCH-005 Пир получает реальную стоимость своих предметов  [manual]
Пир, сдающий fetch-задание своими предметами, ДОЛЖЕН получить сумму, соответствующую соло-формуле для его предметов.
- Дано пир держит ТОЗ-34 для задания «охотник на химер», у хоста такого предмета нет; Autocomplete Tasks включён
  Когда задание завершается (в т.ч. сразу при взятии)
  Тогда лог хоста `fetch: <task> items of <ник пира> wpn_toz34... -> <v>`, пир получает долю порядка соло-награды (~50k), а не 25%.

### FX-FETCH-006 Хост получает оплату за свои сдачи  [manual]
При сдаче хостом задания своими предметами хост ДОЛЖЕН получить деньги ровно один раз.
- Дано хост держит предметы fetch-задания и сдаёт его
  Когда задание завершено
  Тогда лог хоста: `fetch: <task> host items ...`, `[xrRazom][quest] giving host fetch_money=<N>` с `N > 0`,
  `fetch vanilla pay muted`; баланс хоста вырос на `N`.

## Безопасность
- Нет `xrr_quest_reward.calc_fetch_money` — лог `fetch: xrr_quest_reward.calc_fetch_money missing, skipped`.
- Пир и соло: оба вызова `calc_fetch_money` стоят внутри `if XrrIsHosted()` — на пире и в соло фикс не исполняется.
  В соло задание оплачивает ванильный `fetch_reward_and_remove` (мьют взводится только при `XrrIsHosted()`).
- Все внешние обращения под `pcall`; любая ошибка ведёт к следующему источнику, в конце — к оригиналу.
- Защиты от повторной установки нет; двойная обёртка вернёт результат внутренней (лишний лог, тот же порядок источников).

## Вне области / известные ограничения
- Если нужное количество разделено между держателями (часть у хоста, часть у пира, или у двух пиров), ни один не «держит
  достаточно» → номинал (полное состояние), т.е. возможна переплата за изношенные предметы.
- Номинал не учитывает `multiuse` (`cost * count`, без деления на `max_use`).
- Предполагается (по устройству xrRazom, не проверено в C++), что аватар пира на хосте содержит реальный инвентарь пира
  и пояс читается через `iterate_belt` (под `pcall`; если не читается — пояс не исключается).
- Множитель `get_eco_factor("rewards")`, который применял xrRazom, не применяется — как и в соло-формуле Tasks QoL.
- Артефакт в контейнере (ванильная распаковка `_lead_box` и т.п.) не учитывается: ищется только секция `sec`.
- Peer vars `xrrfix_fv_<task>` от v1 остались у друга; очистить их нельзя (нет API удаления), они просто не читаются.

## Проверка в игре
1. Хост запускает игру. Лог: `[XRRFIX] fetch: calc_fetch_money patched (host reads peer avatars)`.
2. Пир берёт fetch-задание на части мутантов, собирает их и сдаёт.
3. Лог хоста: две строки `[XRRFIX] fetch: <task> items of <ник> <sec> x<n> -> <v>` (по одной на вызов), затем
   `[xrRazom][quest] giving host fetch_money=<v2>`, `fetch vanilla pay muted`, `broadcast_quest_reward id=<task> money=<...>`.
4. Сумма пира сопоставима с соло-наградой за те же предметы (с учётом состояния и eco), без пятикратной переплаты.
5. Хост сдаёт своё fetch-задание: строки `host items`, `giving host fetch_money=<N>` с `N > 0`, деньги пришли.
