# FX-PARTS: вылет пира на подсказке оружия из трупа
Статус: действует        Проверка в игре: не записана        Мод: `zz xrRazom Fix - Weapon Parts Tooltip`        Скрипт: `gamedata/scripts/zz_xrrfix_parts_tooltip.script`
Где ставить: пир (на хосте и в соло безвреден)        Зависит от: Momopate's Barrel Condition Effects Display (`zzzz_arti_jamming_repairs`), `item_parts`        Лог-маркер: `[XRRFIX] parts tooltip: nil-safe spairs installed`

## Проблема
У друга (пира) игра вылетает при обыске трупа — при наведении на оружие в окне лута:
```
_g_patches.script:817: bad argument #1 to 'pairs' (table expected, got nil)
```
ошибка переброшена через `siss_util` (Seamless Inventory Sort) из `UICellContainer` Update.

## Причина
- `zzzz_arti_jamming_repairs.script` (Momopate's Barrel Condition Effects Display) переопределяет `ui_item.build_desc_header`:
  для оружия с деталями берёт `parts = item_parts.get_parts_con(obj, nil, true)` и делает `for k,v in spairs(parts, sort_parts)`
  без проверки на `nil`. `spairs` из `_g_patches.script` (GAMMA) делает `pairs(t)` → падает на `nil`.
- `item_parts.get_parts_con` (`Fermuto's Part Disassembly Fix/.../item_parts.script`) возвращает `se_load_var(id, nil, "parts")`.
  `se_save_var` (`_g.script`) при отсутствии записи создаёт её только если `alife_object(id)` существует, иначе молча выходит.
- На пире предметы трупа сначала — локальные копии без серверного объекта (в логе `alife():object(id) ! invalid id specified`),
  поэтому `evaluate_parts` не может сохранить детали, `get_parts_con` возвращает `nil`.
- Тот же шаблон `spairs(parts, sort_parts)` без проверки — ещё в 6 местах модуля: `custom_disassembly_weapon`,
  `has_suitable_kit`, `init_maintenance_menu`, `has_parts_fieldstrip`, `init_fieldstrip_menu`, `act_fieldstrip`
  (всего 7 активных вызовов; ещё 2 закомментированы).

## Решение
В `on_game_start` (под `pcall`): если модуль `zzzz_arti_jamming_repairs` загружен и на нём нет флага `__xrrfix_spairs`,
в таблицу модуля ставится поле `spairs`:
- `t == nil` → возвращается пустой итератор (цикл не выполняется); первый такой случай за сессию — лог
  `parts tooltip: nil parts table skipped (logged once)`;
- иначе — вызов глобального `spairs(t, order)`.
Глобальные имена внутри скрипта Anomaly сначала ищутся в таблице модуля, поэтому замена действует только на этот модуль
(включая функции, объявленные в нём как `ui_item.build_desc_header`), глобальный `spairs` остальных модов не меняется.
После установки ставится `__xrrfix_spairs = true`.

## Требования
### FX-PARTS-001 nil-safe spairs  [auto]
`spairs` модуля ДОЛЖЕН на `nil` возвращать итератор, который сразу завершается, без ошибки.
- Дано установленный фикс на заглушке модуля
  Когда выполняется `for k, v in m.spairs(nil, f) do n = n + 1 end`
  Тогда `n == 0`, исключения нет, лог `nil parts table skipped (logged once)` ровно один раз даже при повторных вызовах.

### FX-PARTS-002 Обычная таблица — как раньше  [auto]
Для таблицы `spairs` модуля ДОЛЖЕН возвращать ровно то же, что глобальный `spairs(t, order)`.
- Дано `t = { b = 2, a = 1 }` и функция порядка
  Когда собираются пары из `m.spairs(t, order)` и из `spairs(t, order)`
  Тогда последовательности совпадают.

### FX-PARTS-003 Замена локальна для модуля  [auto]
Фикс НЕ ДОЛЖЕН менять глобальный `_G.spairs` и ДОЛЖЕН ставиться один раз.
- Дано `on_game_start` фикса вызван дважды
  Тогда `_G.spairs` прежний, `m.spairs` установлен один раз (вторая установка вышла по флагу `__xrrfix_spairs`, без второго лога).

### FX-PARTS-004 Нет вылета при наведении на оружие из трупа  [manual]
Пир ДОЛЖЕН видеть подсказку оружия из трупа без вылета.
- Дано пир в сессии, рядом свежий труп NPC с оружием, ещё не синхронизированным с сервером
  Когда пир открывает лут и наводит курсор на оружие
  Тогда подсказка показана (возможно, без строк состояния деталей), игра не падает;
  в логе может быть `[XRRFIX] parts tooltip: nil parts table skipped (logged once)`.

### FX-PARTS-005 Контекстные меню не падают на nil  [manual]
ПКМ по такому оружию (обслуживание, полевая разборка) НЕ ДОЛЖЕН вызывать вылет из-за `spairs(nil)`.
- Дано то же оружие без записи деталей
  Когда пир открывает контекстное меню
  Тогда меню открывается; пунктов обслуживания/разборки может не быть.

## Безопасность
- Без мода — лог `parts tooltip: Momopate's Barrel Condition Effects Display not installed, skipped`.
- Хост и соло: у объектов есть серверные записи, `parts` обычно не `nil` — поведение идентично оригиналу.
- Идемпотентно по флагу `__xrrfix_spairs` (через `rawget`).

## Вне области / известные ограничения
- Не закрыта индексация `parts[part_name]` в `act_fieldstrip` (`if part_name and parts[part_name] then`) — при `nil`-деталях и
  указанной детали будет `attempt to index a nil value`. Туда же `item_parts.set_parts_con(id, nil)` в конце этой функции.
  На практике пункт меню разборки при `nil` не строится (`has_parts_fieldstrip`/`init_fieldstrip_menu` получают пустой цикл),
  но прямой вызов возможен.
- Другие моды, вызывающие `spairs(get_parts_con(...))` без проверки, не покрыты.
- Состояние деталей для таких предметов не показывается, пока предмет не получит серверный объект (например, после подбора).

## Проверка в игре
1. Пир запускает игру. Лог: `[XRRFIX] parts tooltip: nil-safe spairs installed`.
2. Пир в сессии убивает (или находит) NPC с оружием, сразу открывает лут.
3. Наводит курсор на оружие — вылета нет.
4. В логе пира возможна однократная строка `[XRRFIX] parts tooltip: nil parts table skipped (logged once)` рядом с
   `alife():object(id) ! invalid id specified`.
5. После подбора оружия подсказка показывает состояние деталей как обычно.
