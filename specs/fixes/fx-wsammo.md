# FX-WSAMMO: верстак списывает все коробки-материалы
Статус: действует        Мод: `zz Workshop Ammo Material Fix`        Скрипт: `gamedata/scripts/zz_workshop_ammo_fix.script`
Где ставить: у каждого, кто крафтит (хост, пир, соло; от xrRazom не зависит)        Зависит от: Serious Workshop optimization (`ui_workshop.UIWorkshopCraft`), Craft From Stashes (переопределяет `UpdateItem` и `Craft`)        Лог-маркер: `[WSFIX] workshop: ammo material consumption patched`

## Проблема
При крафте, где материал — патроны (коробки), верстак иногда не списывает одну полную коробку: игрок получает результат,
а одна из требуемых коробок остаётся в инвентаре/тайнике. Воспроизводится и в соло.

## Причина
- `UIWorkshopCraft:UpdateItem` (действующая версия — Craft From Stashes, `zzzzzz_ui_workshop_nearby_stashes.script`,
  поверх `zzzz_serious_ui_workshop.script`) для материала-патронов:
  - считает полные коробки (`size >= box_size`) в `full_ammo`;
  - две неполные коробки, в сумме ≥ полной, считает за +1 полную и добавляет в `self.complexCraft`
    `{ id1, id2, section, newItemSize = size1 + size2 - box_size }`;
  - все неполные убирает из `parts_id`, поэтому в `self.craft_item[n]` попадают только полные коробки (не больше `amount`).
- `UIWorkshopCraft.Craft` (`zz_ui_workshop_keep_crafting_window_open.script`, Craft From Stashes): для каждой записи
  `complexCraft` удаляет обе неполные, создаёт остаток `newItemSize` и помечает секцию в `complexCraftingSections`;
  затем при освобождении `craft_item` ПРОПУСКАЕТ одну полную коробку этой секции (считая, что её «заменила» пара неполных).
- Это верно, только когда полных коробок уже хватало (`#craft_item[n] == amount`). Если полных меньше (нужно 3: 2 полные +
  пара неполных), в `craft_item[n]` лишь 2 коробки, и пропуск одной из них оставляет требуемую коробку несписанной.

## Решение
Установка на `actor_on_first_update` (после всех `on_game_start`, где несколько модов собирают цепочку `Craft`), под `pcall`,
однократно по флагу класса `__xrrfix_wrapped`:
1. `UpdateItem` оборачивается: при `result == false` запоминает `self.__xrrfix_need[n] = { sec, amount }`, затем вызывает оригинал.
2. `Craft` оборачивается: перед оригиналом (внутри `pcall`), если `craft_allow_r` и `complexCraft` непуст, для каждой записи
   `cc` (с конца) ищется строка `n` с `need.sec == cc.section` и `#craft_item[n] < need.amount`. Для такой:
   `alife_release_id(cc.id1)`, `alife_release_id(cc.id2)`, при `newItemSize >= 1` — `alife_create_item(cc.section, <тайник верстака или актёр>, { ammo = newItemSize })`,
   запись удаляется из `complexCraft`, лог `workshop: <sec> merged partials handled, <picked>/<amount> full boxes consumed normally`.
   Затем вызывается оригинал `Craft`, который освобождает все полные коробки этой секции (пометки в `complexCraftingSections` больше нет).
   Записи, где полных хватало, не трогаются — их обрабатывает оригинал.

## Требования
### FX-WSAMMO-001 Полных меньше нужного — списываются все  [auto]
Если полных коробок выбрано меньше требуемого, `Craft` ДОЛЖЕН освободить обе неполные, создать остаток и освободить ВСЕ выбранные полные коробки.
- Дано заглушки: `__xrrfix_need[1] = { sec = "ammo_x", amount = 3 }`, `craft_item[1] = { 11, 12 }`,
  `complexCraft = { { id1 = 21, id2 = 22, section = "ammo_x", newItemSize = 5 } }`, `craft_allow_r = true`, заглушка оригинального `Craft`, повторяющая логику `complexCraftingSections` из Craft From Stashes
  Когда вызывается `Craft()`
  Тогда освобождены id 21, 22, 11, 12; создан `ammo_x` с `ammo = 5`; запись удалена из `complexCraft` до вызова оригинала.

### FX-WSAMMO-002 Полных хватает — поведение оригинала  [auto]
Если `#craft_item[n] >= amount`, обёртка НЕ ДОЛЖНА трогать запись `complexCraft`.
- Дано `amount = 2`, `craft_item[1] = { 11, 12 }`, та же запись `complexCraft`
  Когда вызывается `Craft()`
  Тогда `complexCraft` передан в оригинал без изменений, лог `[WSFIX] ... merged partials handled` отсутствует.

### FX-WSAMMO-003 Остаток не создаётся при нулевом размере  [auto]
При `newItemSize < 1` ДОЛЖНЫ освобождаться обе неполные коробки без создания новой.
- Дано как в FX-WSAMMO-001, но `newItemSize = 0`
  Тогда `alife_create_item` не вызван, id 21 и 22 освобождены.

### FX-WSAMMO-004 Без разрешения крафта — ничего  [auto]
При `craft_allow_r` ложном или пустом `complexCraft` обёртка НЕ ДОЛЖНА ничего освобождать/создавать.
- Дано `craft_allow_r = false`
  Когда вызывается `Craft()`
  Тогда обёртка ничего не делает, вызывается оригинал (который сам выходит).

### FX-WSAMMO-005 Однократная установка  [auto]
Обёртки ДОЛЖНЫ ставиться на класс один раз.
- Дано `actor_on_first_update` сработал дважды (две загрузки в одной VM)
  Тогда `UpdateItem`/`Craft` обёрнуты один раз (флаг `__xrrfix_wrapped`).

### FX-WSAMMO-006 Крафт с недостатком полных коробок в игре  [manual]
Крафт ДОЛЖЕН списывать ровно требуемое количество патронов-материала.
- Дано рецепт требует 3 коробки патронов X; у игрока 2 полные и 2 неполные (в сумме ≥ 1 коробки)
  Когда игрок крафтит
  Тогда исчезли обе полные и обе неполные, появилась одна коробка с остатком; лог `[WSFIX] workshop: X merged partials handled, 2/3 full boxes consumed normally`.

## Безопасность
- Нет `ui_workshop.UIWorkshopCraft` с `Craft`/`UpdateItem` — лог `workshop: UIWorkshopCraft missing, skipped`.
- Работа предобработки в `pcall`: её ошибка не мешает оригинальному `Craft`.
- Не зависит от xrRazom; в коопе выполняется на той машине, где открыт верстак.
- `__xrrfix_need` пополняется при каждом `UpdateItem`; старые строки от прошлого рецепта безопасны — `craft_item`
  сбрасывается в `{}` при выборе рецепта (`ui_workshop.script`), и `picked == nil` их отсекает.

## Вне области / известные ограничения
- Учитывается только первая подходящая строка рецепта для секции; два ингредиента одной секции патронов в одном рецепте не разбираются.
- `UpdateItem` формирует не более одной пары неполных на секцию; три и более неполных коробки — как в оригинале.
- Если другой мод после установки фикса снова переопределит `UpdateItem`/`Craft`, фикс окажется внутри и может перестать работать.
- В коопе удаление/создание предметов идёт через `alife_*`; синхронизация — забота xrRazom.

## Проверка в игре
1. Запустить игру (соло или кооп). Лог: `[WSFIX] workshop: ammo material consumption patched` после загрузки уровня.
2. Подготовить рецепт с материалом-патронами, где полных коробок меньше нужного, но есть две неполные, добирающие одну.
3. Скрафтить. Лог: `[WSFIX] workshop: <sec> merged partials handled, <k>/<n> full boxes consumed normally`.
4. В инвентаре (и тайнике верстака) не осталось ни одной из выбранных полных коробок; есть одна коробка с остатком.
