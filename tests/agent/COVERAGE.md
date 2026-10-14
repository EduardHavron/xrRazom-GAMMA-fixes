# tests/agent — coverage of specs/system/agent.md

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\agent\run.ps1 [-Filter 'AGT-03*'] [-KeepTemp] [-ShowOutput]`
(Windows PowerShell 5.1; needs `git` and `python` on PATH; the fake GitHub is `fixtures\fake_github.py` on 127.0.0.1).

Files: `run.ps1` (entry, isolation, summary), `fixtures.ps1` (helpers, stubs, release builder, process runner),
`cases_setup.ps1`, `cases_common.ps1`, `cases_peer.ps1`, `cases_host.ps1`, `cases_selfupdate.ps1`, `cases_e2e.ps1`,
`fixtures\fake_github.py`.

Expected failures (EXPECTED-FAIL): none — every [auto] requirement matched the code at the time of writing.

| Requirement | Kind | Test(s) |
|---|---|---|
| AGT-001 | auto | `AGT-001 setup copies the six agent files byte-exact and unblocks them`; `AGT-001 setup without xrrfix_agent.ps1 fails and creates no agent folder`; `AGT-001 setup started from <home>\agent does not copy` |
| AGT-002 | auto | `AGT-002 -GammaRoot without mods throws ...`; `AGT-002 saved <home>\gamma_root.txt is offered and confirmed via stdin (no dialog)`; `AGT-002 %LOCALAPPDATA%\xrrfix\gamma_root.txt is the second source`; `AGT-002 setup inside <gamma>\tools\agent finds the GAMMA root by walking up`. Not covered: drive scan (step 4, would hit real disks), folder dialog / cancel (GUI) — manual |
| AGT-003 | auto | `AGT-003 setup saves gamma_root.txt and deletes failed_version.txt` |
| AGT-004 | auto | `AGT-004 setup from a clone with the right origin ...`; `... foreign origin prints the skip line ...`; `AGT-004 XRRFIX_REPO=none ...`; `AGT-004 setup with a clone but no git on PATH ...`; `AGT-004 AGT-007 setup -DryRun in a clone ...` |
| AGT-005 | manual | — (would register a real scheduled task) |
| AGT-006 | manual | — |
| AGT-007 | auto | `AGT-007 setup -DryRun (peer) changes nothing and prints the task definition`; `AGT-007 test-mode setup copies files but does not register the scheduled task`; `AGT-004 AGT-007 setup -DryRun in a clone ...` |
| AGT-008 | manual | — (desktop shortcut; tests always pass -NoShortcut) |
| AGT-009 | auto | `AGT-009 setup without -NoRun runs the agent once and installs the release` |
| AGT-010 | auto | `AGT-010 agent creates a missing <home> and logs the test-mode line first` |
| AGT-011 | auto | `AGT-011 held mutex: ...`; `AGT-011 abandoned mutex counts as acquired`. Not covered: `-PauseAtEnd` wait (interactive) |
| AGT-012 | auto | `AGT-012 AGT-015 clone beside GAMMA (ssh origin) ...`; `AGT-012 clone inside the GAMMA folder ...`; `AGT-012 XRRFIX_REPO=none ...`; `AGT-012 XRRFIX_REPO pointing to a non-clone folder ...`; `AGT-012 repo_root.txt candidate has priority ...` |
| AGT-013 | auto | `AGT-013 first candidate with the right origin wins ...`; `AGT-013 folder without agent\xrrfix_agent.ps1 is not a clone` (git not called is inferred: plain `peer` key, no origin note); `AGT-013 .git as a file and a case-insensitive origin marker ...`; `AGT-013 only foreign origins ...`. Not covered: 60 s git timeout |
| AGT-014 | auto | `AGT-014 no git on PATH: peer mode with a note, API queried, publish not run` |
| AGT-015 | auto | `AGT-012 AGT-015 clone beside GAMMA ...`; `AGT-015 invalid repo_root.txt is replaced ...`; `AGT-015 XRRFIX_REPO neither creates nor changes repo_root.txt`; `AGT-015 invalid repo_root.txt is kept when no clone is found` |
| AGT-016 | auto | `AGT-016 mode line logged only on change; mode.txt keys; -Interactive prints it every run` |
| AGT-017 | auto | `AGT-017 200 stores ETag and body; next run sends If-None-Match; -Force does not`; `AGT-017 200 without ETag deletes api_etag.txt` |
| AGT-018 | auto | `AGT-018 304 takes the release from api_latest.json and downloads its asset` |
| AGT-019 | auto | `AGT-019 AGT-045 404/403/429/offline: ...` |
| AGT-020 | auto | `AGT-020 empty tag_name: logged, exit 0`; `AGT-020 AGT-045 installed version equals tag (v/V stripped) ...` |
| AGT-021 | auto | `AGT-021 failed version younger than 60 min is skipped, older is retried` |
| AGT-022 | auto | `AGT-022 AGT-045 running blocker (mask) defers before download` |
| AGT-023 | auto | `AGT-023 AGT-046 wrong GAMMA root: ...` |
| AGT-024 | auto | `AGT-024 AGT-045 release without the asset ...` |
| AGT-025 | auto | `AGT-025 AGT-045 download error: dl cleared, exit 0, no failed_version, retried next run` (the `.part` name itself is not observed) |
| AGT-026 | auto | `AGT-026 AGT-046 corrupt archive ...`; `AGT-026 zip without install.ps1 ...`; `AGT-026 package in a single subfolder ...; pack.txt version mismatch ...` |
| AGT-027 | auto | `AGT-027 installer stdout/stderr logged with "  | ", -NoWait passed, child LOCALAPPDATA = parent of <home>`. Not covered: 10-min timeout / taskkill (code 124) — impractical runtime |
| AGT-028 | auto | `AGT-028 AGT-044 success: ...` |
| AGT-029 | auto | `AGT-029 AGT-045 installer exit 2 defers ...` |
| AGT-030 | auto | `AGT-030 AGT-039 installer exit 5 ...` |
| AGT-031 | auto | `AGT-031 -Force reinstalls the installed version and ignores the failure pause`; `AGT-031 -Force still defers on a blocker and still checks the GAMMA root` |
| AGT-032 | auto | `AGT-032 sync runs publish.ps1 -SyncOnly -NoWait -NoPrompt in the clone ...`; E2E `AGT-032 AGT-034 E2E friend publishes with the real publish.ps1 ...`. Not covered: 10-min timeout |
| AGT-033 | auto | `AGT-033 AGT-045 installed=0 (or no installed=) keeps agent.log silent`; `AGT-033 last XRRFIX_SYNC_RESULT line wins ...` |
| AGT-034 | auto | `AGT-034 AGT-044 installed>0 notifies ...`; E2E |
| AGT-035 | auto | `AGT-035 AGT-045 exit 2 defers silently ...` |
| AGT-036 | auto | `AGT-036 AGT-037 conflict: ...`; `AGT-036 conflict without the machine line ...` |
| AGT-037 | auto | `AGT-036 AGT-037 conflict: ...` (same sha, -Interactive, new sha); `AGT-038 AGT-037 sync error: ...` |
| AGT-038 | auto | `AGT-038 AGT-037 sync error: exit 1 twice, notified once, host_state = error <sha>` |
| AGT-039 | auto | `AGT-039 host: clone agent\ changes are copied after any sync outcome (0, 1, 2, 3)`; `AGT-030 AGT-039 ...` (peer failure: no update); `AGT-039 AGT-042 peer: zip without agent\ ...` |
| AGT-040 | auto | `AGT-040 only changed/new top-level .ps1/.bat/.txt are copied ...`; `AGT-040 no <home>\agent: nothing is copied`. Not covered: source == `<home>\agent` (needs `<home>` = clone root) |
| AGT-041 | auto | `AGT-041 a syntax-broken .ps1 blocks the whole update` |
| AGT-042 | auto | `AGT-039 AGT-042 peer: ... updates it in finally, dl emptied, task command runs it` (runs the scheduled-task command line `conhost --headless powershell ... -File <home>\agent\xrrfix_agent.ps1`); `AGT-042 a self-update exception is logged and does not change the exit code`. Not covered: self-update after an unexpected exception in Main (no reachable trigger without code changes) |
| AGT-043 | manual | — (tray balloon) |
| AGT-044 | auto | `AGT-044 XRRFIX_NO_NOTIFY=1 outside test mode: no notification at all`; `AGT-044 test mode: notification becomes a log line; -Interactive echoes [title] text`; plus every notification assertion |
| AGT-045 | auto | asserted inside the AGT-019/020/022/024/025/029/033/035 cases (names carry AGT-045) |
| AGT-046 | auto | `AGT-046 repeated failure of the same version: ...`; `AGT-023 AGT-046 ...`; `AGT-026 AGT-046 ...` |
| AGT-047 | auto | `AGT-047 agent.log records are "yyyy-MM-dd HH:mm:ss msg", CRLF, UTF-8 with BOM; -Interactive echoes them` |
| AGT-048 | auto | `AGT-048 a log over 600 lines is trimmed to the last 500 ...`; `AGT-048 a log of exactly 600 lines after the run is not trimmed` |
| AGT-049 | auto | `AGT-049 unexpected exception (corrupt cache + 304): exit 1, logged, next run works`; exit-code table checked across all cases |
| AGT-050 | manual | — (windows/focus) |
| AGT-051 | manual | — (real task + shortcut) |
| AGT-052 | auto | `AGT-052 uninstall -RemoveFiles keeps only gamma_root.txt and installed_version.txt, task untouched`; `AGT-052 uninstall -DryRun deletes nothing`; `AGT-052 uninstall question: default (Enter) keeps files, "д" deletes them` |

Known limitations from the spec ("Открытые вопросы") are not asserted.

Safety: the run snapshots the real `%LOCALAPPDATA%\xrrfix` and the `xrRazom fixes updater` task before and after and fails if
either changed. setup/uninstall are only ever started with `XRRFIX_HOME=<temp>\...\xrrfix` that differs from the child's
`LOCALAPPDATA\xrrfix` (test mode), and every `XRRFIX_API` must start with `http://127.0.0.1:`.
