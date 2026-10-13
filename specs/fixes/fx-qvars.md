# FX-QVARS: синхронизация табличных переменных заданий
Статус: действует        Мод: `zz xrRazom Fix - Quest Vars Sync`        Скрипт: `gamedata/scripts/zz_xrrfix_quest_vars.script`
Где ставить: оба (хост и каждый пир)        Зависит от: xrRazom Co-op 1.4 (`xrr_quest_serialize`), `marshal` (Anomaly), `utils_data.string2hex` / `utils_data.hex2string`        Лог-маркер: `[XRRFIX] serializer: patched (tables via marshal+hex)`

## Проблема
У пира задания с табличным состоянием (охота за головами — данные цели, прочие `task_id`-таблицы) показывают устаревшие данные:
цель/описание от предыдущего прохождения того же повторяемого задания, либо ничего. У хоста всё верно.

## Причина
- Хост собирает переменные задания в `xrr_quest_serialize.collect_task_variables(task_id, out)` (pstor актёра с префиксом `task_id`,
  `<task_id>_fetch`, `<task_id>_fetch_count` и таблицу `load_var(db.actor, task_id)` с добавленным `target_position`).
- `xrr_quest_serialize.serialize_quest_vars` кодирует табличное значение через `pcall(utils_data.write_to_ini_str, v)`,
  а `deserialize_quest_vars` — через `pcall(utils_data.read_from_ini_str, val)` (тип строки `t`).
  Функций `write_to_ini_str` / `read_from_ini_str` нет ни в одном установленном моде (проверено поиском по `D:\Games\Gamma\mods`;
  по истории — нет и в Anomaly). `pcall` проглатывает ошибку, строка `t` не формируется — таблица молча не уходит к пиру.
- Пир применяет только то, что пришло (`OnQuestListResponse` → `deserialize_quest_vars(var_blob)` в `xrr_patch_quests.script`),
  поэтому в его pstor остаются таблицы от прошлых запусков задания.
- Дополнительно: строки с `\t`, `\n`, `\r` или `\3` ломают формат — строки блоба разделены `\n`, поля — `\t`,
  секции `serialize_quest_data` — `\3` (ETX). Исходный код такие строки не экранирует.

## Решение
В `on_game_start` (под `pcall`) заменяются поля модуля `xrr_quest_serialize.serialize_quest_vars` и `deserialize_quest_vars`.
`serialize_quest_data` вызывает `serialize_quest_vars` как глобал модуля, т.е. через таблицу модуля, поэтому замена действует и там.

Формат строки: `key \t <тип> \t value`, строки разделены `\n`.

| Тип | Значение | Кодирование |
|---|---|---|
| `s` | строка без управляющих символов | как есть |
| `H` | строка, содержащая `[\t\n\r\3]` | `utils_data.string2hex(v)` |
| `n` | число | `tostring(v)` |
| `b` | boolean | `1` / `0` |
| `M` | таблица | `string2hex(marshal.encode(v))`; `marshal.encode` под `pcall` |

- Ключ с управляющим символом пропускается целиком.
- Таблица, которую `marshal.encode` не смог закодировать, пропускается с логом `serialize: table <key> not encodable: <err>`.
- Десериализация: `M` → `marshal.decode(hex2string(val))` под `pcall`; при успехе и `type == "table"` — `utils_data.save_var(db.actor, key, tbl)`
  (id внутри — общие id хоста, без трансляции, как в исходном коде). Ошибка — лог `deserialize: table <key> failed: <err>`.
- Типы `s`/`n`/`b` обрабатываются как в оригинале; неизвестный тип (в т.ч. старый `t`) игнорируется.
- Если применена хотя бы одна таблица — лог `deserialize: <n> table var(s) applied`.

## Требования
### FX-QVARS-001 Табличная переменная доходит до пира  [auto]
Сериализатор ДОЛЖЕН передавать табличные значения так, что после десериализации пир получает равную по содержимому таблицу.
- Дано `vars = { t1 = { target_id = 123, nested = { a = "x" } } }` и рабочие `marshal`, `string2hex`/`hex2string`
  Когда `deserialize_quest_vars(serialize_quest_vars(vars))` выполняется на заглушке `utils_data.save_var`
  Тогда `save_var` вызван с ключом `t1` и таблицей, глубоко равной исходной.

### FX-QVARS-002 Скаляры совместимы с исходным форматом  [auto]
Строки без управляющих символов, числа и boolean ДОЛЖНЫ кодироваться теми же типами `s`/`n`/`b`, что и в xrRazom.
- Дано `vars = { a = "abc", b = 1.5, c = true, d = false }`
  Когда выполняется `serialize_quest_vars(vars)`
  Тогда в результате есть строки `a\ts\tabc`, `b\tn\t1.5`, `c\tb\t1`, `d\tb\t0`, и round-trip даёт те же значения и типы.

### FX-QVARS-003 Строки с управляющими символами не ломают блоб  [auto]
Строка, содержащая `\t`, `\n`, `\r` или `\3`, ДОЛЖНА передаваться в hex (тип `H`) и восстанавливаться без искажений.
- Дано `vars = { s = "line1\nline2\tx\3y" }`
  Когда блоб пропущен через `serialize_quest_data({}, {}, vars, {})` и `deserialize_quest_data`, затем `deserialize_quest_vars`
  Тогда в блобе нет сырых `\n`/`\3` внутри значения, а `save_var` получает исходную строку побайтно.

### FX-QVARS-004 Непредставимые данные пропускаются, остальное доходит  [auto]
Ключ с управляющим символом и таблица, которую не кодирует `marshal`, НЕ ДОЛЖНЫ прерывать сериализацию остальных переменных.
- Дано `vars = { ["bad\tkey"] = 1, ok = 2, f = { fn = function() end } }` и `marshal.encode`, бросающий ошибку на функции
  Когда выполняется `serialize_quest_vars(vars)`
  Тогда в результате есть только `ok\tn\t2`, в лог выведено `serialize: table f not encodable: ...`, исключения нет.

### FX-QVARS-005 Повреждённая строка не роняет приём  [auto]
Ошибка декодирования одной `M`-строки НЕ ДОЛЖНА мешать применению остальных строк блоба.
- Дано блоб `x\tM\tZZ\ny\tn\t5` (невалидный hex)
  Когда выполняется `deserialize_quest_vars`
  Тогда в лог выведено `deserialize: table x failed: ...`, `save_var("y", 5)` вызван.

### FX-QVARS-006 Пир видит актуальную цель повторяемого задания  [manual]
У пира данные табличного задания ДОЛЖНЫ совпадать с хостом после запроса списка заданий.
- Дано хост и пир с фиксом; у NPC доступно задание «охота за головами», которое пир уже выполнял ранее
  Когда пир открывает диалог заданий у этого NPC (или PDA Taskboard)
  Тогда описание/цель задания у пира совпадают с хостом, в логе пира — `[XRRFIX] deserialize: N table var(s) applied`.

## Безопасность
- Без `xrr_quest_serialize` (нет xrRazom) или без `marshal` — установка пропускается с логом
  `serializer: xrr_quest_serialize missing, skipped` / `serializer: marshal missing, skipped`. В соло функции не вызываются.
- Установка в `pcall`; ошибка установки — `[XRRFIX] install error: ...`.
- Повторный `on_game_start` просто заново присваивает те же функции — идемпотентно.
- Смешанная установка: пир без фикса игнорирует строки `M`/`H` (неизвестный тип) — поведение как до фикса; хост без фикса
  таблиц не шлёт вовсе. Полный эффект — только когда фикс есть и у хоста, и у пира.

## Вне области / известные ограничения
- Наличие `utils_data.string2hex` / `hex2string` подтверждено логами (2026-10-13): у пира 60 строк
  `[XRRFIX] deserialize: N table var(s) applied` (работает `hex2string`), хост их отправлял (`string2hex`). Но проверено только по факту работы в игре: `utils_data.script` лежит в архивах Anomaly
  и поиском по модам не найден. Фикс НЕ проверяет их наличие при установке. Если их нет, `hex(...)` бросит ошибку прямо в
  `serialize_quest_vars` (вне `pcall`), и её поймает внешний `pcall` в `OnQuestListRequest` хоста: тогда не уйдёт весь список
  заданий, а не только таблицы. Предложение: добавить проверку при установке.
- Числа идут через `tostring` (≈14 значащих цифр), как и в оригинале.
- Пользовательские данные (`userdata`, `CTime`) внутри таблиц `marshal` не кодирует — такая переменная пропускается (с логом).
- Фикс не вычищает у пира старые таблицы задания, которые хост больше не присылает (например, когда у хоста переменная уже `nil`).

## Проверка в игре
1. Хост и пир запускают игру с фиксом. В логе обоих: `[XRRFIX] serializer: patched (tables via marshal+hex)`.
2. Пир подходит к NPC с табличным заданием (охота, «найти тайник» и т.п.) и открывает список заданий.
3. Лог хоста: `[xrRazom][quest] OnQuestListRequest -> SendResponse blob=<N> ...`, без `OnQuestListRequest ERROR`.
4. Лог пира: `[xrRazom][quest] OnQuestListResponse ... vars=<N>` и `[XRRFIX] deserialize: <n> table var(s) applied`.
5. Пир берёт задание — метка цели и текст совпадают с тем, что видит хост для того же задания.
