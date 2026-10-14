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
| FX-TURNIN-001 | FX-TURNIN-001 peer drops stage-255 syncs for tasks it does not have | test_turnin.lua |
| FX-TURNIN-002 | FX-TURNIN-002 active task (task_info[id].t) still gets stage 255 | test_turnin.lua |
| FX-TURNIN-003 | FX-TURNIN-003 other stages pass through with all args and return values | test_turnin.lua |
| FX-TURNIN-004 | FX-TURNIN-004 host never filters | test_turnin.lua |
| FX-TURNIN-005 | manual | |
| FX-FETCH-001 | FX-FETCH-001 inventory_value matches the Tasks QoL formula; artefact class with eco type 3; weapon condition = mean of prt_w_* | test_fetch.lua |
| FX-FETCH-002 | FX-FETCH-002 belt items do not count; multiuse; sum below 50 raised to 50 | test_fetch.lua |
| FX-FETCH-003 | FX-FETCH-003 host items first; best peer avatar; no holder -> nominal; no fetch_reward_and_remove -> original | test_fetch.lua |
| FX-FETCH-004 | FX-FETCH-004 both completion calls pay > 0 from the same holder | test_fetch.lua |
| FX-FETCH-005, -006 | manual | |
| FX-LASER-001 | FX-LASER-001 saved_lasers_id declared as an item rider | test_laser.lua |
| FX-LASER-002 | FX-LASER-002 second install does not duplicate the key | test_laser.lua |
| FX-LASER-003 | FX-LASER-003 skipped without Laser Settings or without xrr_item_mdata | test_laser.lua |
| FX-LASER-004 | manual | |
| FX-BELT-001 | FX-BELT-001 beltMemory registered once, travels whole | test_belt.lua |
| FX-BELT-002 | FX-BELT-002 load_state normalizes keys in place; **EXPECTED-FAIL** FX-BELT-002 numeric outfit key: items/date normalized in place | test_belt.lua |
| FX-BELT-003 | FX-BELT-003 save_belt ignored for 10 s after first update in a session; solo: no grace | test_belt.lua |
| FX-BELT-004, -005 | manual | |
| FX-PARTS-001 | FX-PARTS-001 module spairs(nil) is an empty loop, logged once | test_parts.lua |
| FX-PARTS-002 | FX-PARTS-002 tables iterate exactly like the global spairs | test_parts.lua |
| FX-PARTS-003 | FX-PARTS-003 global spairs untouched, installed once | test_parts.lua |
| FX-PARTS-004, -005 | manual | |
| FX-WSAMMO-001 | FX-WSAMMO-001 fewer full boxes than needed: partials and ALL full boxes consumed | test_wsammo.lua |
| FX-WSAMMO-002 | FX-WSAMMO-002 enough full boxes: complexCraft left to the original | test_wsammo.lua |
| FX-WSAMMO-003 | FX-WSAMMO-003 newItemSize < 1: partials released, no remainder created | test_wsammo.lua |
| FX-WSAMMO-004 | FX-WSAMMO-004 craft not allowed / empty complexCraft: wrapper does nothing | test_wsammo.lua |
| FX-WSAMMO-005 | FX-WSAMMO-005 wrappers installed once per class | test_wsammo.lua |
| FX-WSAMMO-006 | manual | |
| FX-KILLTR-001 | FX-KILLTR-001 peer: actor kill without a hit is not recorded; skip log limited to 5 | test_killtr.lua |
| FX-KILLTR-002 | FX-KILLTR-002 hit within 60 s counts, mark cleared, after 60 s not; before_hit draftsman / monster callbacks | test_killtr.lua |
| FX-KILLTR-003 | FX-KILLTR-003 silent kill passes, flag reset after return and after error | test_killtr.lua |
| FX-KILLTR-004 | FX-KILLTR-004 host/solo and non-actor killers always reach the original | test_killtr.lua |
| FX-KILLTR-005 | FX-KILLTR-005 (a) mod registered first; (b) mod registers after the fix | test_killtr.lua |
| FX-KILLTR-006, -007 | manual | |

### MOD-LOOTCLAIM (Combined GAMMA NPC Loot Claim v.1.2) — test_lootclaim.lua

| Requirement | Test case(s) |
|---|---|
| MOD-LOOTCLAIM-001 | MCM page lists every DEFAULTS key with the same defaults; without MCM defaults apply, MCM enabled=false switches the mod off |
| MOD-LOOTCLAIM-002 | actor kill of a stalker; peer avatar and companion count as the player; no xrRazom; npc_loot_all + mutant victim |
| MOD-LOOTCLAIM-003 | free bodies (all six reasons); companion kill with companions_are_player=false |
| MOD-LOOTCLAIM-004 | NPC kill: claimed[victim] = killer |
| MOD-LOOTCLAIM-005 | Use blocked near a live killer; release rules (dead / not loaded / far); ignored keys and targets |
| MOD-LOOTCLAIM-006 | lock re-applied every 1000 ms |
| MOD-LOOTCLAIM-007 | own kill released after release_delay; scheduled once; release_after_loot=false |
| MOD-LOOTCLAIM-008 | enabled=false / npc_loot_all release every locked body |
| MOD-LOOTCLAIM-009 | NPC looting frees a claimed body; player kills untouched |
| MOD-LOOTCLAIM-010 | autolooter blocked / allowed / block_autolooter=false / module absent |
| MOD-LOOTCLAIM-011 | tip from a near killer, actor_menu text otherwise, show_messages=false |
| MOD-LOOTCLAIM-012 | save/load round trip, pending not saved |
| MOD-LOOTCLAIM-013 | level change clears all tables |
| MOD-LOOTCLAIM-014 | over 1000 entries the 100 oldest are dropped |
| MOD-LOOTCLAIM-015 | Semenov tissue counter |
| MOD-LOOTCLAIM-016 | manual (co-op on a real host) |

Mutation check (2026-10-14): disabling the Use block, inverting the distance check, removing the table cap, changing LOCK_VALUE
and disabling the release after NPC loot each made the matching cases fail.

## Expected failures

- **FX-BELT-002 (numeric outfit key)**: the requirement says every entry is normalized in place (`items` -> `{[number]=true}`,
  `date` -> number). `normalize()` loops over `dup_table(mem)`, and Anomaly's `dup_table` is a DEEP copy (`copy_table` recurses).
  An entry whose outfit key is already a number is normalized on the copy only, so the stored entry keeps string item ids and a
  string date. The spec's own example (string key `"101"`) passes because renamed entries store the copy.

## Notes on test seams

- File locals (`inventory_value`, `last_hit`, `in_silent`, `grace_until`) are checked through what they cause, not read directly.
  Examples: `inventory_value` through the `math.random` bounds of `calc_fetch_money`; `last_hit[500] == nil` through a second death
  of the same victim being dropped; `in_silent == false` through the next plain kill being filtered.
- `utils_data.string2hex`/`hex2string` and `marshal` are pure-Lua stand-ins. `hex2string` raises an error on non-hex input.
- `XRR_TEST_ROOT=<dir>` points the loader at another `mods/` tree. It was used once to confirm that a deliberately broken fix
  makes the matching case fail.
