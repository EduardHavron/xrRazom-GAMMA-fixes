# tests/python: coverage

Suite: stdlib `unittest` for `.github/scripts/build_pack.py`, static repo checks, and `.github/workflows/release.yml`.

```
python -m unittest discover -s tests/python -v          # from the repo root
python -m unittest discover -s tests/python -k ci_017   # filter by requirement id
BP_TESTS_KEEP_TEMP=1 ...                                # keep the temp fixtures
```

| File | Content |
|---|---|
| `bp_helpers.py` | fixture repo builder, subprocess runner, fake `luajit`/`xmllint` shims (`.cmd` on Windows, shebang script on POSIX), PATH filtering |
| `test_validate.py` | `validate`: pack.json schema, mod folders, Lua check (fake + real luajit), XML warnings |
| `test_build.py` | `build`: zip layout, pack.txt, notes.md, installer/agent files, errors |
| `test_repo_static.py` | real checkout: pack.json, `.gitattributes`, tracked files, encodings |
| `test_workflow.py` | `release.yml` text/YAML checks; on POSIX with bash+jq, runs the real Notify Discord script against a fake `curl` |

Environment notes:
- `build_pack.py` runs as a subprocess with `CI`/`GITHUB_ACTIONS` removed, unless a test sets them. PATH has every directory containing a
  real `luajit`/`xmllint` removed. Fake tools sit first on PATH.
- `RealLuajitTests` run only when a real `luajit` is on PATH (CI ubuntu). `WorkflowYamlTests` need PyYAML.
  `NotifyStepExecutionTests` run only on POSIX with `bash` and `jq`; otherwise they are skipped.
- Every method name starts with `test_<req id>` and every docstring starts with the requirement ID(s).

Expected failures: none. (CI-016 in-mod file order was a spec error; the spec was corrected to the actual sorted order.)

## ci-release.md

| ID | Tag | Tests |
|---|---|---|
| CI-001 | manual | `test_workflow`: `test_ci_001_repo_016_paths_listed`, `test_repo_016_ci_001_push_paths_filter` (static filter check; the GitHub trigger itself is manual) |
| CI-002 | manual | `test_ci_002_workflow_dispatch_without_inputs` (static) |
| CI-003 | manual | `test_ci_003_permissions_contents_write_only` (static) |
| CI-004 | manual | `test_ci_004_concurrency` (static; queueing behaviour is manual) |
| CI-005 | manual | `test_ci_005_step_order_and_runner` (static: relative order, no continue-on-error, only Notify has `if`) |
| CI-006 | manual | `test_ci_006_tools_install` (static) |
| CI-007 | auto | `test_validate.PackJsonSchemaTests`: `test_ci_007_*` (missing, invalid JSON, invalid UTF-8, non-object, empty/whitespace/non-string section, mods empty/not array, bad element, duplicate, case-sensitive duplicate, `/ \ . ..`, extra keys ignored, BOM, GHA annotation format) |
| CI-008 | auto | `test_ci_008_errors_accumulate`, `test_ci_008_mods_error_stops_immediately`, `test_ci_011_pack_errors_stop_before_lua` |
| CI-009 | auto | `test_ci_009_repo_003_missing_mod_dir`, `test_ci_009_empty_mod_dir`, `test_ci_009_nested_file_is_enough` |
| CI-010 | auto | `test_ci_010_repo_007_unlisted_mod_warns`, `test_ci_010_unlisted_warning_gha_format` |
| CI-011 | auto | `test_validate.LuaCheckTests.test_ci_011_*` (fake luajit: error annotation with the real path and the temp path replaced, GHA `file=` + `%0A`, BOM stripped, `-b src out` compile only, all `*.script` case-insensitive incl. unlisted folders, each failure reported, Cyrillic/apostrophe names, summary line); `RealLuajitTests` (real luajit: syntax error, BOM, `error("x")` not executed) |
| CI-012 | auto | `test_ci_012_ci_true_without_luajit_fails` (`true`/`TRUE`/`True`), `test_ci_012_local_without_luajit_warns`, `test_ci_012_ci_true_with_luajit_runs_check` |
| CI-013 | auto | `test_validate.XmlCheckTests.test_ci_013_*` (python parser + suffix, fake xmllint first line only, GHA file=, exit code unaffected, unlisted folders) |
| CI-014 | auto | `test_build.BuildErrorTests.test_ci_014_*` (each installer file missing gives exit 1 and no zip, GHA annotation, pack.json re-validated, missing `--version` gives exit 2, build does not run the Lua check) |
| CI-015 | manual | `test_ci_015_repo_012_version_expression`, `test_ci_015_ci_019_build_step` (static) |
| CI-016 | auto | `test_build.ZipLayoutTests.test_ci_016_*` (exact entry list and order, listed mods only in pack order, top-level agent files sorted without subfolders, no agent dir, DEFLATE, byte-exact incl. CRLF/BOM/binary, overwrite, out dir created, empty dirs skipped, special names); in-mod file order (sorted like pack.txt, spec corrected) |
| CI-017 | auto | `test_build.PackTxtTests.test_ci_017_*` (exact spec example, header/order, UTF-8 no BOM/LF/final LF/no blank lines between mods, section verbatim, sha16 = sha256[:16] lowercase, `\`-path ordinal sort, `<out>/pack.txt` identical, unlisted excluded) |
| CI-018 | auto | `test_build.NotesTests`: `test_ci_018_without_git`, `test_ci_018_with_commit_message`, `test_ci_018_git_without_commits` |
| CI-019 | manual | `test_ci_019_built_line_counts_mod_files` (the `Built ...` line), `test_ci_015_ci_019_build_step` (static log markers) |
| CI-020 | manual | `test_ci_020_repo_012_create_release` (static; the real release is manual) |
| CI-021 | manual | manual (needs GitHub) |
| CI-022 | manual | `test_ci_022_notify_always` (static), `test_ci_024_success_payload` (exactly one POST) |
| CI-023 | manual | `test_ci_023_secret_name_and_skip_message` (static), `test_ci_023_no_secret_skips` (runs the script, POSIX) |
| CI-024 | manual | `test_ci_024_ci_025_payload_shape` (static), `test_ci_024_success_payload` (POSIX), `test_repo_006_discord_mods_list_reads_bom` |
| CI-025 | manual | `test_ci_024_ci_025_payload_shape`, `test_ci_025_failure_payload` (failure + cancelled, POSIX) |
| CI-026 | manual | `test_ci_026_manual_build_text` (static), `test_ci_026_manual_build` (POSIX) |
| CI-027 | manual | `test_ci_027_curl_failure_is_warning` (static), `test_ci_027_curl_failure_warns` (POSIX) |
| CI-028 | manual | `test_ci_028_no_expressions_in_scripts` (static), `test_ci_028_commit_message_not_executed` (POSIX, injection attempt) |
| CI-029 | manual | manual (re-run on GitHub) |
| CI-030 | manual | manual (repository settings) |
| CI-031 | manual | manual (release run waits for the tests job; see `test_ci_005_step_order_and_runner` for the gate step) |
| Open questions 7, 8, 9 | n/a | skipped placeholders `test_known_ci_7_*`, `test_known_ci_8_*`, `test_known_ci_9_*` (not asserted) |

## repo-layout.md

| ID | Tag | Tests |
|---|---|---|
| REPO-001 | auto | via PUB-010 (tests/publish: leftovers in mods/ and pack/ are reset) |
| REPO-002 | auto | `test_repo_002_repo_014_no_top_level_meta_or_marker` (static part: nothing tracked). The publish part is in tests/publish (T2). |
| REPO-003 | auto | `test_ci_007_repo_003_empty_mods`, `test_ci_007_repo_003_duplicate_name`, `test_ci_009_repo_003_missing_mod_dir`, `test_repo_003_real_pack_json_schema`, `test_repo_003_real_repo_validate_passes` |
| REPO-004 | auto | via PUB-019, PUB-020 (tests/publish: pack order follows the section) |
| REPO-005 | auto | `test_repo_005_real_pack_json_format` (committed file matches the serialisation), `test_repo_005_serialiser_example`. The writing side is in tests/publish (T2). |
| REPO-006 | auto | `test_ci_007_repo_006_bom_accepted`, `test_repo_006_build_accepts_bom_copy_of_real_pack`, `test_repo_006_discord_mods_list_reads_bom` (CI Discord one-liner). The publish side is in T2. |
| REPO-007 | auto | `test_ci_010_repo_007_unlisted_mod_warns`, `test_ci_016_repo_007_entries_and_order`, `test_ci_017_only_listed_mods`. The 3-way side is in T2. |
| REPO-008 | auto | `test_repo_008_gitattributes_star_minus_text`, `test_repo_008_text_attribute_unset_for_mod_files`, `test_repo_008_worktree_bytes_equal_blobs`, `test_repo_008_publish_git_calls_disable_autocrlf` (static). The clone round-trip is in T2. |
| REPO-009 | auto | `test_ci_017_repo_009_header_and_mod_order`, plus all of CI-017 |
| REPO-010 | auto | via PUB-014, PUB-027, INS-011 (marker ignored by compare; written on removal and by the installer) |
| REPO-011 | auto | via PUB-014 (top-level meta.ini not published or compared). GAP: catch-up keeping the local meta.ini has no test |
| REPO-012 | auto | `test_ci_015_repo_012_version_expression`, `test_ci_020_repo_012_create_release` (static workflow checks) |
| REPO-013 | auto | via PUB-034, PUB-045 (mods commit holds only mods/ and pack/, docs commit only doc paths, host/publish.ini stays uncommitted). Staged-index variant not tested separately |
| REPO-014 | auto | `test_repo_002_repo_014_no_top_level_meta_or_marker`, `test_repo_014_no_build_artifacts_profiles_agent_state`, `test_repo_014_no_secrets`. These check `git ls-files` outside `tests/`, so test fixtures are allowed. |
| REPO-015 | auto | `test_repo_015_ps1_and_publish_ini_have_bom`, `test_repo_015_cyrillic_txt_has_bom`, `test_repo_015_bat_ascii`; skipped placeholder `test_known_repo_2_bat_crlf` |
| REPO-016 | auto | `test_repo_016_ci_001_push_paths_filter`, `test_ci_001_repo_016_paths_listed` |
| REPO-017 | auto | `test_repo_017_in_sync`, `test_repo_017_missing_and_stale` (parser on synthetic docs); `test_repo_017_real_docs_list_pack` (real docs; mismatch = `::warning` + skip, never a failure) |

## CHK (specs/system/spec-check.md) — test_spec_check.py

| Requirement | Mode | Test(s) |
|---|---|---|
| CHK-001 | auto | `test_chk_001_clean_repo_has_no_findings`, `test_chk_001_auto_without_test_is_error`, `test_chk_001_via_and_gap`, `test_chk_001_test_name_forms` |
| CHK-002 | auto | `test_chk_002_unknown_and_deleted_ids` |
| CHK-003 | auto | `test_chk_003_coverage_missing_and_unknown` |
| CHK-004 | auto | `test_chk_004_verdict` |
| CHK-005 | auto | `test_chk_005_docs_vs_pack`; the same function backs REPO-017 in test_repo_static.py |
| CHK-006 | auto | `test_chk_006_unverified_markers_are_notes` |
| CHK-007 | auto | `test_chk_007_read_only_exit_codes_json` |
| CHK-008 | auto | `test_chk_008_real_repository` |
| CHK-009 | manual | manual (the /spec-check skill) |

Found while writing these tests: the python test-name pattern used `\b` before the area prefix, which never matches after `_`,
so IDs in function names (`test_repo_017_…`) were ignored. Fixed to `(?:^|_)`; `test_chk_001_test_name_forms` covers it.
