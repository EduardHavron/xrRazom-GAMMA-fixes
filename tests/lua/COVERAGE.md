# Lua fix tests: coverage (owner T4)

Entry: `luajit tests/lua/run.lua [filter]` (CI, ubuntu) or `python tests/lua/run_local.py [filter]` (local, lupa's LuaJIT).
Each case loads the REAL fix script from `mods/<mod>/gamedata/scripts/` into a fresh X-Ray-like environment (`harness.lua`).
Third-party modules are replaced by small stand-ins that copy the signatures and call shapes of the shipped code.

| Requirement | Test case(s) | File |
|---|---|---|
| FX-QVARS-001 | FX-QVARS-001 table var round-trips to an equal table via save_var | test_qvars.lua |
| FX-QVARS-002 | FX-QVARS-002 scalars keep the s/n/b types and round-trip | test_qvars.lua |
| FX-QVARS-003 | FX-QVARS-003 control chars travel as hex through serialize_quest_data | test_qvars.lua |
| FX-QVARS-004 | FX-QVARS-004 bad key and unencodable table are skipped, rest serialized | test_qvars.lua |
| FX-QVARS-005 | FX-QVARS-005 corrupt M line logged, other lines still applied | test_qvars.lua |
| FX-QVARS-006 | manual | |
| FX-TBOARD-001 | manual | |
| FX-TBOARD-002 | FX-TBOARD-002 card with local subtitle/body is left untouched | test_tboard.lua |
| FX-TBOARD-003 | FX-TBOARD-003 empty card gets subtitle/body/icon from the host preview | test_tboard.lua |
| FX-TBOARD-004 | FX-TBOARD-004 no change out of session / nil card / no preview / empty text | test_tboard.lua |
| FX-TBOARD-005 | FX-TBOARD-005 diagnostic line once per task_id per session | test_tboard.lua |
| FX-TURNIN-001 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-TURNIN-002 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-TURNIN-003 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-TURNIN-004 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-TURNIN-005 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-FETCH-001 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-FETCH-002 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-FETCH-003 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-FETCH-004 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-FETCH-005, -006 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-LASER-001 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-LASER-002 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-LASER-003 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-LASER-004 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-BELT-001 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-BELT-002 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-BELT-003 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-BELT-004, -005 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-PARTS-001 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-PARTS-002 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-PARTS-003 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-PARTS-004, -005 | removed: integrated into xrRazom 1.5 (spec status `удалено`) | — |
| FX-KILLTR-001 | FX-KILLTR-001 peer: actor kill without a hit is not recorded; skip log limited to 5 | test_killtr.lua |
| FX-KILLTR-002 | FX-KILLTR-002 hit within 60 s counts, mark cleared, after 60 s not; before_hit draftsman / monster callbacks | test_killtr.lua |
| FX-KILLTR-003 | FX-KILLTR-003 silent kill passes, flag reset after return and after error | test_killtr.lua |
| FX-KILLTR-004 | FX-KILLTR-004 host/solo and non-actor killers always reach the original | test_killtr.lua |
| FX-KILLTR-005 | FX-KILLTR-005 (a) mod registered first; (b) mod registers after the fix | test_killtr.lua |
| FX-KILLTR-006, -007 | manual | |
| FX-LEDGE-001 | FX-LEDGE-001 Anti-Lag updater checks on every update without jump held; stub sanity without the fix; repeated level loads do not register twice | test_ledge.lua |
| FX-LEDGE-002 | FX-LEDGE-002 updater calls the current module checkLedgeGrabbing | test_ledge.lua |
| FX-LEDGE-003 | FX-LEDGE-003 second on_game_start keeps the same updater and logs once | test_ledge.lua |
| FX-LEDGE-004 | FX-LEDGE-004 original Demonized script untouched; no Ledge Grabbing module | test_ledge.lua |
| FX-LEDGE-005 | FX-LEDGE-005 error while patching is caught and logged | test_ledge.lua |
| FX-LEDGE-006 | removed: xrRazom 1.5 no longer lowers jump_speed, the config was dropped | — |
| FX-LEDGE-007 | manual | |
| FX-LEDGE-008 | removed together with FX-LEDGE-006 | — |
| FX-QLIST-001 | FX-QLIST-001 force-loads xrr_patch_quests, wraps once, logs the marker; without the handler: logged and skipped | test_qlist.lua |
| FX-QLIST-002 | FX-QLIST-002 peer: every call passes straight through with all arguments | test_qlist.lua |
| FX-QLIST-003 | FX-QLIST-003 lone request on the host runs at once | test_qlist.lua |
| FX-QLIST-004 | FX-QLIST-004 burst: first runs, the rest wait for actor_on_update | test_qlist.lua |
| FX-QLIST-005 | FX-QLIST-005 budget: stops at 8 ms, at least one per update; os.clock fallback | test_qlist.lua |
| FX-QLIST-006 | FX-QLIST-006 duplicates of queued requests are dropped and counted | test_qlist.lua |
| FX-QLIST-007 | FX-QLIST-007 one summary line per drained burst | test_qlist.lua |
| FX-QLIST-008 | FX-QLIST-008 original error is logged, the queue keeps draining; level change drops the queue | test_qlist.lua |
| FX-QLIST-009 | manual | |
| FX-QLIST-010 | FX-QLIST-010 installs once around xrRazom's refresh; without Taskboard or quest sync: skipped | test_qlist_peer.lua |
| FX-QLIST-011 | FX-QLIST-011 refreshed NPCs' old lists cleared, others kept; nothing cleared when a batch is busy | test_qlist_peer.lua |
| FX-QLIST-012 | FX-QLIST-012 redraws at most every 500 ms while answers arrive, keeps the scroll | test_qlist_peer.lua |
| FX-QLIST-013 | FX-QLIST-013 final redraw after xrRazom's on_complete; empty NPC list completes at once | test_qlist_peer.lua |
| FX-QLIST-014 | FX-QLIST-014 host: wrappers pass through | test_qlist_peer.lua |
| FX-QLIST-015 | FX-QLIST-015 redraw errors logged once per refresh; destroyed tab is not redrawn | test_qlist_peer.lua |
| FX-QLIST-016 | FX-QLIST-016 log lines carry numbers with Anomaly's %s-only printf | test_qlist.lua |

## Expected failures

None.

## Notes on test seams

- File locals (`last_hit`, `in_silent`) are checked through what they cause, not read directly.
  Examples: `last_hit[500] == nil` through a second death of the same victim being dropped; `in_silent == false` through the
  next plain kill being filtered.
- `utils_data.string2hex`/`hex2string` and `marshal` are pure-Lua stand-ins. `hex2string` raises an error on non-hex input.
- `XRR_TEST_ROOT=<dir>` points the loader at another `mods/` tree. It was used once to confirm that a deliberately broken fix
  makes the matching case fail.
  FX-LEDGE was checked the same way: 6 mutations (no replacement, stale function reference, no pcall, no idempotency flag,
  jump 6.0, `[actor]` without DLTX `!`), each failed exactly its requirement's cases.
  FX-QLIST: 8 mutations (always immediate, no budget, no dedupe, LIFO, no pcall, no clear on level change, queueing on a
  peer, double wrap), each caught. Peer half: 9 mutations (no clear, no throttle, no dirty flag,
  no final redraw, no scroll restore, redraw of a destroyed tab, host not pass-through, double wrap, error log spam), each caught.
