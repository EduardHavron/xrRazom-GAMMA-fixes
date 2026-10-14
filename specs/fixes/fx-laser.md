# FX-LASER: состояние лазеров пира после переподключения
Статус: действует        Проверка в игре: не записана        Мод: `zz xrRazom Fix - Laser State`        Скрипт: `gamedata/scripts/zz_xrrfix_laser.script`
Где ставить: оба (в заголовке скрипта — «каждый пир», но приём/выдача райдера идут и через хост, см. «Причина»)        Зависит от: xrRazom Co-op 1.4 (`xrr_item_mdata.declare`), Laser Settings (`zzz_bas_laser_control`)        Лог-маркер: `[XRRFIX] laser: saved_lasers_id declared as per-item rider`

## Проблема
Пир включает ЛЦУ на оружии, выходит и снова подключается — лазеры на всём его оружии выключены.

## Причина
- Laser Settings (`465- Laser Settings - Borksy/.../zzz_bas_laser_control.script`) хранит вкл/выкл в локальной таблице
  `saved_lasers[weapon_id]`; `save_state` публикует её как `m_data.saved_lasers_id`, `load_state` читает обратно.
  Тот же ключ в других версиях модуля (BAS, Tacticool scopes).
- Пир никогда не сохраняется; его `m_data` при каждом подключении собирается из данных хоста. Поканальные «райдеры»
  предметов xrRazom (`xrr_item_mdata.script`) переносят только ключи из своего `manifest`; встроенные — `exo_devices`,
  `mark_switch_current_marks`, `scripted_canted_irons`, `magnifier_switch_bone_states`, `expiration_table`, `pouches`,
  `speed_loaders`. `saved_lasers_id` среди них нет, поэтому у пира после подключения таблица пуста — лазеры выключены.
- Механизм райдера (проверено в `xrr_item_mdata.script`): `xrr_item_mdata_capture(id)` упаковывает в блоб предмета значения
  `m_data[key][id]` по манифесту; `xrr_item_mdata_apply(id, set)` принимает и для незадекларированного ключа пишет
  `![xrRazom][ItemMData] inbound key <key> is not declared here — dropped`; `poll` раз в секунду помечает предмет «грязным»
  при изменении сигнатуры райдеров. Следовательно, ключ должен быть задекларирован на обеих сторонах: пир — чтобы отправить
  и принять, хост — чтобы принять, хранить и вернуть при подключении [НЕ ПРОВЕРЕНО] (вывод по Lua-коду; C++-хранилище хоста не проверялось).

## Решение
В `on_game_start` (под `pcall`): если загружен `zzz_bas_laser_control` и есть `xrr_item_mdata.declare` —
`xrr_item_mdata.declare("saved_lasers_id")`. Дальше всё делает xrRazom: при `prime` вызывается `save_state`, после чего
`m_data.saved_lasers_id` — та же таблица, что `saved_lasers` мода; изменения видит `poll`; при входе `ensure_tables` и
`load_state` дают моду таблицу, куда пишут райдеры.

## Требования
### FX-LASER-001 Ключ задекларирован как райдер  [auto]
При наличии Laser Settings и xrRazom ключ `saved_lasers_id` ДОЛЖЕН быть в `xrr_item_mdata.manifest`.
- Дано заглушки `zzz_bas_laser_control = {}` и `xrr_item_mdata` с реальной `declare`
  Когда вызывается `on_game_start` фикса
  Тогда в `manifest` ровно один элемент с `key == "saved_lasers_id"`, лог `laser: saved_lasers_id declared as per-item rider`.

### FX-LASER-002 Идемпотентность  [auto]
Повторная установка НЕ ДОЛЖНА дублировать ключ в манифесте.
- Дано `on_game_start` фикса вызван дважды
  Когда проверяется `manifest`
  Тогда `saved_lasers_id` встречается один раз (гарантируется `declare`).

### FX-LASER-003 Пропуск без зависимостей  [auto]
Без Laser Settings или без `xrr_item_mdata.declare` фикс НЕ ДОЛЖЕН ничего декларировать и ДОЛЖЕН залогировать пропуск.
- Дано `zzz_bas_laser_control == nil`
  Тогда лог `laser: Laser Settings not installed, skipped`, `declare` не вызван.
- Дано Laser Settings есть, `xrr_item_mdata == nil`
  Тогда лог `laser: xrr_item_mdata.declare missing, skipped`.

### FX-LASER-004 Лазер пира переживает переподключение  [manual]
Включённый пиром лазер ДОЛЖЕН оставаться включённым после выхода и повторного подключения.
- Дано пир включил лазер на оружии в слоте, подождал ≥ 2 с (опрос райдеров раз в секунду)
  Когда пир отключается и подключается снова, берёт это оружие
  Тогда лазер включён; в логе обеих сторон нет `inbound key saved_lasers_id is not declared here — dropped`.

## Безопасность
- Соло: декларация безвредна — `actor_on_update` райдеров выходит без сессии, `prime` (и его лог) только в сессии.
- Хост без Laser Settings: ключ не декларируется (иначе каждый блоб предмета нёс бы пустой ключ — xrRazom по той же причине
  гейтит свои встроенные декларации).
- Установка в `pcall`; ошибка — `[XRRFIX] install error: ...`.

## Вне области / известные ограничения
- Если фикс стоит только у пира, хост отбросит входящий ключ (`inbound key ... dropped`) и не вернёт его при подключении —
  нужно ставить на обе стороны.
- Переносится только вкл/выкл (`saved_lasers_id`); настройки цвета/яркости Laser Settings хранит в своём ltx-кеше пользователя
  (локально у каждого), фикс их не касается.
- Изменение, сделанное менее чем за ~1 с до отключения, может не успеть уйти (период опроса `POLL_MS = 1000`).

## Проверка в игре
1. Хост и пир запускают игру. Лог обоих: `[XRRFIX] laser: saved_lasers_id declared as per-item rider`.
2. В сессии у обоих: `[xrRazom][ItemMData] primed on [..., saved_lasers_id]`.
3. Пир включает лазер на оружии, ждёт пару секунд, выходит, подключается снова.
4. Лазер на этом оружии включён. В логах нет `inbound key saved_lasers_id is not declared here — dropped`.
