# tests/publish — coverage

Suite: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\publish\run.ps1 [-Filter 'PUB-012*'] [-KeepTemp] [-ShowOutput]`
(Windows PowerShell 5.1, git; python optional for the release-zip leg of SYS-002).
Test names start with the requirement IDs; `-Filter` is a wildcard on the full name. Expected failures: none.

Files: `run.ps1` (entry), `fixtures.ps1` (sandbox: bare origin + host/friend fake GAMMA roots with clones, process runner,
fake MO2 process, mutex holder), `cases_publish.ps1`, `cases_publish2.ps1`, `cases_installer.ps1`, `cases_system.ps1`.

## publish.md (PUB)

| ID | Test(s) |
|---|---|
| PUB-001 | `PUB-001 relative gamma_root ...`, `PUB-001 gamma_root without ModOrganizer.ini ...` |
| PUB-002 | `PUB-002 no .git / no commits / git missing in PATH` (the "git rev-parse does not work" branch is not covered: no practical way to break rev-parse while `.git` exists) |
| PUB-003 | `PUB-003 PUB-038 push=No / push=НЕТ ...` |
| PUB-004 | `PUB-004 PUB-044 mutex held ...`, `PUB-004 mutex taken after ini/.git/git checks ...`, `PUB-004 without -NoWait waits ...`, `PUB-004 abandoned mutex ...`; release on exit: `PUB-022 PUB-042 ...`, `PUB-028 PUB-030 PUB-042 ...` |
| PUB-005 | `PUB-005 profile from selected_profile=@ByteArray(...) ...` |
| PUB-006 | `PUB-006 separator ...` |
| PUB-007 | `PUB-007 PUB-034 L = "+" lines ...` |
| PUB-008 | `PUB-008 empty L ...` |
| PUB-009 | `PUB-009 unfinished merge / rebase` (MERGE_HEAD, rebase-merge; the other three markers use the same loop) |
| PUB-010 | `PUB-010 leftovers in repo mods/ and pack/ ...` |
| PUB-011 | `PUB-011 git fetch failure ...`, `PUB-011 no upstream -> R = origin/main; no origin/main -> R = HEAD` |
| PUB-012 | `PUB-012 PUB-031 unpushed local commit + remote change ...`, `PUB-012 no common history ...` |
| PUB-013 | `PUB-013 dirty tracked file outside mods/pack ...` |
| PUB-014 | `PUB-014 PUB-031 byte-identical CRLF content ...`, `PUB-014 one byte / line endings differ ...` |
| PUB-015 | `PUB-015 PUB-018 R folder not in pack.json ...`, `PUB-015 PUB-021 PUB-027 no pack.json in R ...` |
| PUB-016 | `PUB-016 PUB-021 PUB-029 statuses ...`, `PUB-016 removed on GitHub + modified locally ...`, `PUB-016 only in B ...`; conflict row: `PUB-022 ...`, `SYS-006 ...` |
| PUB-017 | six `PUB-017 ...` cases (TakeRemote name / on local mod / TakeLocal list / TakeLocal * / TakeRemote * / both + unknown name) |
| PUB-018 | `PUB-015 PUB-018 ...`, `PUB-020 PUB-018 ...`, `PUB-033 ...` |
| PUB-019 | `PUB-019 PUB-035 ...`, `PUB-019 PUB-022 order conflict ...`, `PUB-019 order conflict + -TakeLocal * ...`, `PUB-019 additions and removals ...` |
| PUB-020 | three `PUB-020 ...` cases (spec examples 1–3) |
| PUB-021 | `PUB-021 report header ...` + report lines asserted in PUB-007/015/016/019/027/028 cases |
| PUB-022 | `PUB-022 PUB-042 two conflicts ...`, `PUB-019 PUB-022 ...`, `PUB-017 PUB-022 ...` |
| PUB-023 | `PUB-023 PUB-029 PUB-031 remote change outside mods/pack ...`, `PUB-019 PUB-035 PUB-021 PUB-023 ...` |
| PUB-024 | `PUB-024 PUB-044 SYS-009 ...`, `PUB-024 blocking process does not matter ...`, `PUB-024 -NoPrompt without -NoWait polls ...` (interactive Enter loop: manual) |
| PUB-025 | `PUB-025 PUB-026 PUB-028 PUB-029 temp package ...` (installer replaced by a capturing stub), `PUB-032 PUB-025 ...` (robocopy exit >= 8 branch not covered) |
| PUB-026 | `PUB-025 PUB-026 ...` |
| PUB-027 | `PUB-027 mod removed on GitHub ...`, `PUB-015 PUB-021 PUB-027 ...` |
| PUB-028 | `PUB-025 PUB-026 PUB-028 ...`, `PUB-028 PUB-030 PUB-042 installer exit 2 / 1 / 5 ...` |
| PUB-029 | `PUB-025 ...` (installed=2), `PUB-016 ...`, `PUB-023 ...` (no line in normal mode; installed=0 in -SyncOnly) |
| PUB-030 | `PUB-028 PUB-030 PUB-042 ...` |
| PUB-031 | `PUB-012 PUB-031 ...`, `PUB-014 PUB-031 ...`, `PUB-023 ... HEAD = R`, `PUB-031 -SyncOnly with unpushed commit ...`, `PUB-031 rebase conflict ...`, `PUB-031 ff-only failure ...` |
| PUB-032 | `PUB-032 PUB-025 -SyncOnly ...`, `SYS-011 ...` |
| PUB-033 | `PUB-033 new mod with -NoPrompt ...`, `PUB-033 interactive confirmation (y/N) from stdin` (answers `y` / Enter; Cyrillic answers not automated: stdin encoding) |
| PUB-034 | `PUB-034 SYS-013 ...`, `PUB-007 PUB-034 ...`, `SYS-005 SYS-007 PUB-034 ...` |
| PUB-035 | `PUB-019 PUB-035 ...` (only pack.json, exact bytes), `PUB-006 ...` (section from config) |
| PUB-036 | `PUB-036 summary ...`, `PUB-007 ...` (auto message) |
| PUB-037 | `PUB-037 PUB-039 push rejected ...` (resend + "Изменений нет" without push) |
| PUB-038 | `PUB-003 PUB-038 ...` |
| PUB-039 | `PUB-037 PUB-039 ...` (origin pre-receive hook rejects), `PUB-039 friend pushes between fetch and push ...` and `PUB-039 pull --rebase conflict ...` (race simulated by a post-commit hook that pushes the friend's commit) |
| PUB-040 | manual (needs gh + GitHub). The suite's origin is a local path, so publish prints the fallback URL and exits 0. |
| PUB-041 | `PUB-041 Cyrillic mod name ...` (+ `zz Фикс Y` in many cases) |
| PUB-042 | `PUB-022 PUB-042 ...` (code 3), `PUB-028 PUB-030 PUB-042 ...` (codes 1, 2, 5), `PUB-024 PUB-044 SYS-009 ...` (code 2) |
| PUB-043 | `PUB-043 publish.bat passes args ...` (via `cmd /c`, stdin closed so `pause` returns) |
| PUB-044 | `PUB-004 PUB-044 ...`, `PUB-024 PUB-044 SYS-009 ...`, `PUB-044 ... blocker and mutex held ...` |

## installer.md (INS)

| ID | Test(s) |
|---|---|
| INS-001 | manual |
| INS-002 | `INS-002 install.ps1 UTF-8 BOM ...` (BOM, PS 5.1 parser, install.bat ASCII + CRLF) |
| INS-003 | `INS-003 -GammaRoot with trailing \ ...`, `INS-003 -GammaRoot without ModOrganizer.exe/mods ...` |
| INS-004 | `INS-004 discovery: valid saved path ...`, `INS-004 INS-005 discovery: stale saved path ...`, `INS-030 INS-004 ...`; steps 3 (drive scan) and 4 (folder dialog): not covered (would scan real drives and could hit a real GAMMA on a dev machine / needs UI) — printed as SKIP |
| INS-005 | `INS-004 INS-005 ...`, `INS-005 INS-007 ...` |
| INS-006 | `INS-006 XRRFIX_BLOCK_PROCS parsing ...` (uses a fake `ModOrganizer.exe` copy of PING.EXE for the default list) |
| INS-007 | `INS-005 INS-007 ...` |
| INS-008 | manual |
| INS-009 | `INS-009 pack.txt ...` |
| INS-010 | `INS-010 no [mod] lines ...` |
| INS-011 | `INS-011 INS-012 ...` |
| INS-012 | `INS-011 INS-012 ...`, `INS-009 ...` |
| INS-013 | `INS-013 separator folder ...` |
| INS-014 | `INS-014 profile ...` |
| INS-015 | `INS-015 INS-027 ...` |
| INS-016 | `INS-016 INS-019 section bounds ...` |
| INS-017 | `INS-017 INS-029 ...` |
| INS-018 | `INS-018 our mods in the section ...` |
| INS-019 | `INS-019 foreign mods in the section ...`, `INS-016 INS-019 ...` |
| INS-020 | `INS-020 legacy "zz xrRazom Fixes" ...` |
| INS-021 | `INS-021 INS-028 SYS-004 ...` |
| INS-022 | `INS-022 result assembly (spec example)`, `INS-022 "#" lines go first, empty lines dropped` |
| INS-023 | `INS-023 no separator line ...` |
| INS-024 | `INS-024 no modlist.txt ...` |
| INS-025 | `INS-025 modlist read as UTF-8 ...` |
| INS-026 | manual (messages are visible in `-ShowOutput`) |
| INS-027 | `INS-015 INS-027 ...` |
| INS-028 | `INS-021 INS-028 SYS-004 ...`, `INS-019 ...` |
| INS-029 | `INS-017 INS-029 ...` |
| INS-030 | `INS-030 INS-004 legacy call ...` (`powershell -File install.ps1 -NoWait`) |

## overview.md (SYS) — publish/installer related

| ID | Test(s) |
|---|---|
| SYS-001 | via CI-016, CI-017 (tests/python: zip holds only listed mods, in pack order) |
| SYS-002 | `SYS-002 byte-exact ...` (MO2 → repo → peer catch-up, and repo → `build_pack.py build` zip → installer; zip leg skipped with a note if python is missing) |
| SYS-003 | `SYS-003 only enabled mods of the section ...` |
| SYS-004 | `INS-021 INS-028 SYS-004 ...` |
| SYS-005 | `SYS-005 SYS-007 PUB-034 ...` |
| SYS-006 | `SYS-006 conflict ...` |
| SYS-007 | `SYS-005 SYS-007 PUB-034 ...` |
| SYS-008 | manual |
| SYS-009 | `PUB-024 PUB-044 SYS-009 ...` (publish side; installer side: `INS-005 INS-007 ...`; agent side: tests/agent) |
| SYS-010 | manual |
| SYS-011 | `SYS-011 (publish side) ...`; the agent tick itself: tests/agent (T3) |
| SYS-012 | via CI-005, CI-011 (tests/python: release steps after validation; Lua syntax error stops the build) |
| SYS-013 | `PUB-034 SYS-013 ...` |
| SYS-014 | tests/python `test_repo_014_no_secrets` (docstring names SYS-014) |
