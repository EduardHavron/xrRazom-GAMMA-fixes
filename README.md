# xrRazom GAMMA fixes

Локальные фиксы для кооператива [xrRazom](https://www.moddb.com/mods/xrrazom-stalker-anomaly-co-op) 1.4 на сборке S.T.A.L.K.E.R. G.A.M.M.A.
Хост публикует фиксы сюда, GitHub Actions проверяет и собирает релиз, у пира фоновый агент сам ставит новые версии.

## Как это устроено

```
хост: MO2, секция "xrRazom Sync"  ──host/publish.bat──▶  main (mods/, pack/pack.json)
                                                             │ GitHub Actions: проверка Lua + сборка
                                                             ▼
                                                   Release vГГГГ.ММ.ДД-N (xrRazom_fixes.zip)
                                                             │ каждые 10 минут
                                                             ▼
пир: агент (Планировщик заданий) ──installer/install.ps1──▶ MO2 пира, только секция "xrRazom Sync"
```

- В пакет идут **только включённые моды из секции-разделителя** «xrRazom Sync» в профиле хоста.
- У пира установщик пересобирает **только эту секцию**. Чужие и тестовые моды не трогаются: если такой мод оказался
  внутри секции, он сохраняет своё состояние и переносится сразу под разделитель. Наши старые фиксы, которых больше нет
  в пакете, выключаются.
- xrRazom всё равно сверяет набор модов хоста и пира при входе, так что расхождение будет сразу видно.

## Хост

1. В MO2: правый клик → *Create Separator* → `xrRazom Sync`, перетащить в него фиксы (`zz ...`).
2. После любых изменений фиксов: `host\publish.bat` — скопирует секцию в `mods/`, сделает коммит и push.
3. Через минуту-две в [Releases](https://github.com/EduardHavron/xrRazom-GAMMA-fixes/releases) появится новая версия.
   Если проверка Lua упала — релиза не будет, ошибка видна в [Actions](https://github.com/EduardHavron/xrRazom-GAMMA-fixes/actions).

## Пир

Один раз: скачать репозиторий (*Code → Download ZIP*), распаковать, запустить `agent\setup_agent.bat`.
Дальше обновления ставятся сами, когда Mod Organizer и игра закрыты. Подробнее — `agent\README.txt`.

Без агента: скачать `xrRazom_fixes.zip` из последнего релиза, распаковать, закрыть MO2, запустить `install.bat`.

## Фиксы

| Мод | Что чинит |
|---|---|
| zz xrRazom Fix - Quest Vars Sync | табличные переменные заданий не доходили до пира |
| zz xrRazom Fix - Taskboard Peer Details | у пира пустые карточки в PDA Taskboard Redesign |
| zz xrRazom Fix - Turned-in Task Sync | пир заново получал уже сданные повторяемые задания |
| zz xrRazom Fix - Fetch Reward | неверная награда за задания «принеси» (переплата/недоплата) |
| zz xrRazom Fix - Laser State | лазеры пира выключались после переподключения |
| zz xrRazom Fix - Remember Belt | Remember Outfit Belt терял пояс у пира после переподключения |
| zz xrRazom Fix - Weapon Parts Tooltip | вылет пира при наведении на оружие в трупе (Momopate's Barrel Condition) |
| zz Workshop Ammo Material Fix | верстак не списывал одну коробку материала (не xrRazom, работает и в соло) |
| zz xrRazom Fix - Kill Tracker Mirror Corpses | Milspec PDA помечал все трупы-зеркала как убитые пиром |
