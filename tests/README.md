# Тесты

Каждый тест называется по ID требования из `specs/` (например `PUB-012 ...`); карта покрытия — `COVERAGE.md` в папке набора.

| Набор | Что проверяет | Запуск (из корня репозитория) | CI |
|---|---|---|---|
| `tests/python` | `.github/scripts/build_pack.py`, workflow-файлы, статика репозитория, `tools/spec_check.py` (CI-*, REPO-*, CHK-*) | `python -m unittest discover -s tests/python -v` | ubuntu |
| `tests/lua` | десять фиксов на заглушках игровых API (FX-*, MOD-*) | `luajit tests/lua/run.lua` или локально `python tests/lua/run_local.py` (`pip install lupa`) | ubuntu |
| `tests/publish` | `host/publish.ps1` и `installer/install.ps1` (PUB-*, INS-*, SYS-*) | `powershell -NoProfile -ExecutionPolicy Bypass -File tests\publish\run.ps1` | windows |
| `tests/agent` | агент автообновления, включая сквозной сценарий хост/друг (AGT-*) | `powershell -NoProfile -ExecutionPolicy Bypass -File tests\agent\run.ps1` | windows |

Наборы PowerShell принимают `-Filter '<маска>'` (например `-Filter 'PUB-02*'`) и `-KeepTemp`.
Всё работает во временных папках с фейковыми GAMMA, git-репозиториями и локальным HTTP-сервером: реальные моды, `%LOCALAPPDATA%\xrrfix`,
Планировщик заданий и GitHub не затрагиваются. `tests/publish` и `tests/agent` не запускать одновременно на одной машине (общий мьютекс публикации).

**EXPECTED-FAIL** — тест проверяет спецификацию, а код пока ей не соответствует; прогон не валит, но в отчёте виден.
Сейчас такой один: `FX-BELT-002` (нормализация ключей памяти пояса при числовом ID костюма).

GitHub Actions: `.github/workflows/tests.yml` — на каждый push и pull request; сборка релиза (`release.yml`) вызывает его первым и без зелёных тестов релиз не создаёт.
