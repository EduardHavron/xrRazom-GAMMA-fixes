"""build_pack.py validate: pack.json schema, mod folders, Lua check (fake luajit), XML warnings.

Spec: specs/system/ci-release.md (CI-007..CI-013), specs/system/repo-layout.md (REPO-003, REPO-006, REPO-007).
"""
import json
import os
import shutil
import unittest

import bp_helpers as H

GOOD_MOD = {"gamedata/scripts/a.script": b"local x = 1\n"}


class PackJsonSchemaTests(H.TempTestCase):
    """CI-007 / CI-008 / CI-009 / REPO-003: pack.json errors exit 1 with error annotations."""

    def run_pack(self, pack_raw=None, mods=None, pack_mods=None, section="S", gha=False):
        H.make_repo(self.repo, mods if mods is not None else {"A": GOOD_MOD},
                    pack_mods=pack_mods, section=section, pack_raw=pack_raw)
        return self.validate(self.env_no_tools(gha=gha))

    def test_ci_007_missing_pack_json(self):
        """CI-007: pack/pack.json absent -> exit 1, 'not found'."""
        res = self.run_pack(pack_mods="absent")
        self.assertRc(res, 1)
        self.assertOut(res, "ERROR: pack/pack.json not found")

    def test_ci_007_invalid_json(self):
        """CI-007: unparsable JSON -> exit 1."""
        res = self.run_pack(pack_raw=b'{"section": "S", "mods": [')
        self.assertRc(res, 1)
        self.assertOut(res, "ERROR: pack/pack.json does not parse")

    def test_ci_007_invalid_utf8(self):
        """CI-007: not UTF-8 -> exit 1 (parse error)."""
        res = self.run_pack(pack_raw=b'{"section": "\xff\xfe", "mods": ["A"]}')
        self.assertRc(res, 1)
        self.assertOut(res, "does not parse")

    def test_ci_007_top_level_not_object(self):
        """CI-007: top level array -> exit 1."""
        res = self.run_pack(pack_raw=b'["A"]')
        self.assertRc(res, 1)
        self.assertOut(res, "top level must be an object")

    def test_ci_007_empty_section(self):
        """CI-007: section '' -> exit 1, "'section' must be a non-empty string"."""
        res = self.run_pack(section="")
        self.assertRc(res, 1)
        self.assertOut(res, "'section' must be a non-empty string")

    def test_ci_007_whitespace_and_non_string_section(self):
        """CI-007: whitespace-only section and non-string section -> exit 1."""
        for raw in (b'{"section": "   ", "mods": ["A"]}', b'{"section": 5, "mods": ["A"]}',
                    b'{"mods": ["A"]}'):
            with self.subTest(raw=raw):
                if os.path.isdir(self.repo):
                    H.rmtree(self.repo)
                res = self.run_pack(pack_raw=raw)
                self.assertRc(res, 1)
                self.assertOut(res, "'section' must be a non-empty string")

    def test_ci_007_repo_003_empty_mods(self):
        """CI-007 / REPO-003: mods [] -> exit 1, "'mods' must be a non-empty array"."""
        res = self.run_pack(pack_mods=[])
        self.assertRc(res, 1)
        self.assertOut(res, "'mods' must be a non-empty array")

    def test_ci_007_mods_not_array(self):
        """CI-007: mods is a string / missing -> exit 1."""
        for raw in (b'{"section": "S", "mods": "A"}', b'{"section": "S"}'):
            with self.subTest(raw=raw):
                if os.path.isdir(self.repo):
                    H.rmtree(self.repo)
                res = self.run_pack(pack_raw=raw)
                self.assertRc(res, 1)
                self.assertOut(res, "'mods' must be a non-empty array")

    def test_ci_007_mod_name_not_string_or_empty(self):
        """CI-007: mod element not a string / empty / whitespace -> exit 1."""
        for bad in (5, "", "  ", None):
            with self.subTest(bad=bad):
                if os.path.isdir(self.repo):
                    H.rmtree(self.repo)
                res = self.run_pack(pack_mods=["A", bad])
                self.assertRc(res, 1)
                self.assertOut(res, "mod name must be a non-empty string")

    def test_ci_007_repo_003_duplicate_name(self):
        """CI-007 / REPO-003: ["A","A"] -> exit 1, "duplicate mod name 'A'"."""
        res = self.run_pack(pack_mods=["A", "A"])
        self.assertRc(res, 1)
        self.assertOut(res, "duplicate mod name 'A'")

    def test_ci_007_duplicate_is_case_sensitive(self):
        """CI-007: names differing only by case are not duplicates (case-sensitive compare)."""
        mods = {"A": GOOD_MOD, "a": GOOD_MOD}
        if os.path.normcase("A") == os.path.normcase("a"):
            # case-insensitive FS (Windows): both names resolve to the same folder
            mods = {"A": GOOD_MOD}
        res = self.run_pack(mods=mods, pack_mods=["A", "a"])
        self.assertNotOut(res, "duplicate mod name")
        self.assertRc(res, 0)

    def test_ci_007_invalid_names(self):
        """CI-007: names with '/', '\\', '.', '..' -> exit 1, "invalid mod name"."""
        for bad in ("../x", "a/b", "a\\b", ".", ".."):
            with self.subTest(bad=bad):
                if os.path.isdir(self.repo):
                    H.rmtree(self.repo)
                res = self.run_pack(pack_mods=[bad])
                self.assertRc(res, 1)
                self.assertOut(res, "invalid mod name '%s'" % bad)

    def test_ci_007_extra_keys_ignored(self):
        """CI-007: unknown top-level keys are ignored."""
        raw = json.dumps({"section": "S", "mods": ["A"], "comment": 1, "x": [None]})
        res = self.run_pack(pack_raw=raw)
        self.assertRc(res, 0)
        self.assertOut(res, "pack.json OK")

    def test_ci_007_repo_006_bom_accepted(self):
        """CI-007 / REPO-006: pack.json with UTF-8 BOM is accepted -> 'pack.json OK'."""
        raw = H.BOM + json.dumps({"section": "S", "mods": ["A"]}).encode("utf-8")
        res = self.run_pack(pack_raw=raw)
        self.assertRc(res, 0)
        self.assertOut(res, "pack.json OK")

    def test_ci_007_gha_annotation_has_file(self):
        """CI-007: under GITHUB_ACTIONS the error is '::error file=pack/pack.json::...'."""
        res = self.run_pack(pack_mods=["A", "A"], gha=True)
        self.assertRc(res, 1)
        self.assertOut(res, "::error file=pack/pack.json::pack/pack.json: duplicate mod name 'A'")

    def test_ci_008_errors_accumulate(self):
        """CI-008: empty section + two missing mods -> three error annotations, exit 1."""
        res = self.run_pack(mods={}, pack_mods=["X", "Y"], section="")
        self.assertRc(res, 1)
        errs = [l for l in res.out.splitlines() if l.startswith("ERROR:")]
        self.assertEqual(len(errs), 3, res)
        self.assertOut(res, "lists 'X' but mods/X/ does not exist")
        self.assertOut(res, "lists 'Y' but mods/Y/ does not exist")

    def test_ci_008_mods_error_stops_immediately(self):
        """CI-008: a 'mods' type error ends the check right away (section error printed before it, nothing after)."""
        res = self.run_pack(pack_raw=b'{"section": "", "mods": 3}')
        self.assertRc(res, 1)
        errs = [l for l in res.out.splitlines() if l.startswith("ERROR:")]
        self.assertEqual(len(errs), 2, res)
        self.assertNotOut(res, "Lua check")

    def test_ci_009_repo_003_missing_mod_dir(self):
        """CI-009 / REPO-003: listed mod without folder -> exit 1."""
        res = self.run_pack(mods={"A": GOOD_MOD}, pack_mods=["A", "B"])
        self.assertRc(res, 1)
        self.assertOut(res, "pack/pack.json lists 'B' but mods/B/ does not exist")

    def test_ci_009_empty_mod_dir(self):
        """CI-009: mod folder with only empty subfolders -> 'mods/A/ is empty', exit 1."""
        res = self.run_pack(mods={"A": {"gamedata/scripts/": None}})
        self.assertRc(res, 1)
        self.assertOut(res, "mods/A/ is empty")

    def test_ci_009_nested_file_is_enough(self):
        """CI-009: a single deeply nested file makes the folder non-empty."""
        res = self.run_pack(mods={"A": {"a/b/c/d.txt": b"x"}})
        self.assertRc(res, 0)

    def test_ci_010_repo_007_unlisted_mod_warns(self):
        """CI-010 / REPO-007: unlisted mods/Old/ -> warning, exit 0."""
        res = self.run_pack(mods={"A": GOOD_MOD, "Old": GOOD_MOD}, pack_mods=["A"])
        self.assertRc(res, 0)
        self.assertOut(res, "WARNING: mods/Old/ is not listed in pack/pack.json and will NOT be released")

    def test_ci_010_unlisted_warning_gha_format(self):
        """CI-010: GHA format of the unlisted-folder warning."""
        res = self.run_pack(mods={"A": GOOD_MOD, "Old": GOOD_MOD}, pack_mods=["A"], gha=True)
        self.assertRc(res, 0)
        self.assertOut(res, "::warning::mods/Old/ is not listed in pack/pack.json and will NOT be released")


class LuaCheckTests(H.TempTestCase):
    """CI-011 / CI-012: LuaJIT compile-only check through a fake `luajit` on PATH."""

    SCRIPT = "gamedata/scripts/x.script"

    def test_ci_011_syntax_error_annotated_with_repo_path(self):
        """CI-011: broken script -> error annotation naming mods/<path> (temp path replaced), exit 1."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: b"local a = \n"}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 1)
        self.assertOut(res, "ERROR: Lua syntax error in mods/A/gamedata/scripts/x.script:")
        self.assertOut(res, "mods/A/gamedata/scripts/x.script:1: unexpected symbol near '<eof>'")
        self.assertNotOut(res, "chunk.lua")
        self.assertOut(res, "Lua check: 1 .script file(s), 1 failed")

    def test_ci_011_gha_annotation_file_and_newline_escape(self):
        """CI-011: GHA annotation carries file=mods/<path>, newlines encoded as %0A."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: b"local a = \n"}})
        res = self.validate(self.env_fake_luajit(gha=True))
        self.assertRc(res, 1)
        line = [l for l in res.out.splitlines() if l.startswith("::error")]
        self.assertEqual(len(line), 1, res)
        self.assertTrue(line[0].startswith(
            "::error file=mods/A/gamedata/scripts/x.script::Lua syntax error in mods/A/gamedata/scripts/x.script:%0A"),
            res)
        self.assertIn("mods/A/gamedata/scripts/x.script:1:", line[0])

    def test_ci_011_bom_stripped_before_compile(self):
        """CI-011: a valid script with UTF-8 BOM passes (BOM removed before luajit sees it)."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: H.BOM + b"local x = 1\n"}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 0)
        calls = self.luajit_calls()
        self.assertEqual(len(calls), 1)
        self.assertNotEqual(calls[0]["head"], "efbbbf")
        self.assertEqual(calls[0]["len"], len(b"local x = 1\n"))

    def test_ci_011_compile_only_invocation(self):
        """CI-011: luajit is invoked as `luajit -b <src> <out>` (compile only, never executed)."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: b'error("x")\n'}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 0)
        calls = self.luajit_calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["args"][0], "-b")
        self.assertEqual(len(calls[0]["args"]), 3)

    def test_ci_011_all_scripts_incl_unlisted_and_uppercase_ext(self):
        """CI-011: every mods/**/*.script (case-insensitive ext, also unlisted folders) is checked; unlisted error fails."""
        H.make_repo(self.repo, {
            "A": {"gamedata/scripts/a.script": b"local a = 1\n", "gamedata/scripts/B.SCRIPT": b"local b = 2\n",
                  "gamedata/scripts/notes.lua": b"local broken =\n", "gamedata/configs/x.ltx": b"[s]\n"},
            "Old": {"gamedata/scripts/old.script": b"local broken =\n"},
        }, pack_mods=["A"])
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 1)
        self.assertEqual(len(self.luajit_calls()), 3)
        self.assertOut(res, "Lua syntax error in mods/Old/gamedata/scripts/old.script")
        self.assertOut(res, "Lua check: 3 .script file(s), 1 failed")

    def test_ci_011_every_failure_reported(self):
        """CI-011: each failing file gets its own annotation."""
        H.make_repo(self.repo, {"A": {"s/a.script": b"x =\n", "s/b.script": b"y =\n", "s/c.script": b"z = 1\n"}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 1)
        self.assertOut(res, "Lua syntax error in mods/A/s/a.script")
        self.assertOut(res, "Lua syntax error in mods/A/s/b.script")
        self.assertOut(res, "Lua check: 3 .script file(s), 2 failed")

    def test_ci_011_mod_name_with_spaces_and_cyrillic(self):
        """CI-011: annotation path keeps the real mod folder name (spaces, apostrophe, Cyrillic)."""
        name = "zz Мод's Fix"
        H.make_repo(self.repo, {name: {self.SCRIPT: b"local a =\n"}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 1)
        self.assertOut(res, "mods/%s/gamedata/scripts/x.script:1:" % name)

    def test_ci_011_ok_summary(self):
        """CI-011: clean scripts -> 'Lua check: n .script file(s), 0 failed', exit 0."""
        H.make_repo(self.repo, {"A": {"s/a.script": b"local a = 1\n", "s/b.script": b"return 2\n"}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 0)
        self.assertOut(res, "pack.json OK")
        self.assertOut(res, "Lua check: 2 .script file(s), 0 failed")

    def test_ci_011_pack_errors_stop_before_lua(self):
        """CI-011 / CI-008: pack.json errors exit before the Lua check runs."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: b"local a =\n"}}, pack_mods=["A", "A"])
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 1)
        self.assertEqual(self.luajit_calls(), [])

    def test_ci_012_ci_true_without_luajit_fails(self):
        """CI-012: CI=true and no luajit on PATH -> error 'luajit not found (required in CI)', exit 1."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: b"local a = 1\n"}})
        for ci in ("true", "TRUE", "True"):
            with self.subTest(ci=ci):
                res = self.validate(self.env_no_tools(ci=ci))
                self.assertRc(res, 1)
                self.assertOut(res, "ERROR: luajit not found (required in CI)")

    def test_ci_012_local_without_luajit_warns(self):
        """CI-012: CI unset (or not 'true') and no luajit -> warning with file count, exit 0."""
        H.make_repo(self.repo, {"A": {"s/a.script": b"local a =\n", "s/b.script": b"x"}})
        for ci in (None, "false", "1"):
            with self.subTest(ci=ci):
                res = self.validate(self.env_no_tools(ci=ci))
                self.assertRc(res, 0)
                self.assertOut(res, "WARNING: luajit not found - skipping Lua syntax check of 2 .script file(s)")

    def test_ci_012_ci_true_with_luajit_runs_check(self):
        """CI-012: CI=true with luajit available -> normal check."""
        H.make_repo(self.repo, {"A": {self.SCRIPT: b"local a = 1\n"}})
        res = self.validate(self.env_fake_luajit(ci="true"))
        self.assertRc(res, 0)
        self.assertOut(res, "Lua check: 1 .script file(s), 0 failed")


@unittest.skipUnless(shutil.which("luajit"), "real luajit not on PATH")
class RealLuajitTests(H.TempTestCase):
    """CI-011 with the real LuaJIT (runs in CI where luajit is installed)."""

    def env(self):
        return H.base_env(self.tmp, path=os.environ.get("PATH", ""))

    def test_ci_011_real_syntax_error(self):
        """CI-011 (real luajit): `local a = ` -> error annotation for mods/<path>, exit 1."""
        H.make_repo(self.repo, {"A": {"gamedata/scripts/x.script": b"local a = \n"}})
        res = self.validate(self.env())
        self.assertRc(res, 1)
        self.assertOut(res, "Lua syntax error in mods/A/gamedata/scripts/x.script")
        self.assertOut(res, "mods/A/gamedata/scripts/x.script:")

    def test_ci_011_real_bom_ok(self):
        """CI-011 (real luajit): valid script with BOM -> no errors."""
        H.make_repo(self.repo, {"A": {"gamedata/scripts/x.script": H.BOM + b"local a = 1\n"}})
        res = self.validate(self.env())
        self.assertRc(res, 0)

    def test_ci_011_real_not_executed(self):
        """CI-011 (real luajit): top-level error("x") is not executed -> no errors."""
        H.make_repo(self.repo, {"A": {"gamedata/scripts/x.script": b'error("x")\nos.exit(5)\n'}})
        res = self.validate(self.env())
        self.assertRc(res, 0)


class XmlCheckTests(H.TempTestCase):
    """CI-013: XML well-formedness is warning-only."""

    BAD = b'#include "gamedata\\configs\\x.xml"\n<a/>\n'

    def test_ci_013_python_parser_warning(self):
        """CI-013: without xmllint -> python parser, warning per bad file, exit code unaffected."""
        H.make_repo(self.repo, {"A": {"gamedata/configs/ui/bad.xml": self.BAD, "gamedata/configs/ui/ok.xml": b"<a><b/></a>",
                                      "s/a.script": b"local a = 1\n"}})
        res = self.validate(self.env_no_tools())
        self.assertRc(res, 0)
        self.assertOut(res, "WARNING: XML not well-formed (non-fatal): mods/A/gamedata/configs/ui/bad.xml: ")
        self.assertNotOut(res, "ok.xml")
        self.assertOut(res, "XML check: 2 file(s), 1 warning(s) [python parser]")

    def test_ci_013_xmllint_warning(self):
        """CI-013: with xmllint on PATH -> `xmllint --noout`, first line of its message, no suffix."""
        H.make_repo(self.repo, {"A": {"gamedata/configs/bad.XML": self.BAD, "s/a.script": b"local a = 1\n"}})
        res = self.validate(self.env_fake_luajit(xmllint=True))
        self.assertRc(res, 0)
        self.assertOut(res, "WARNING: XML not well-formed (non-fatal): mods/A/gamedata/configs/bad.XML: ")
        self.assertOut(res, "parser error : Start tag expected")
        self.assertNotOut(res, "#include \"x.xml\"")  # only the first line of the message
        self.assertOut(res, "XML check: 1 file(s), 1 warning(s)\n")

    def test_ci_013_gha_warning_has_file(self):
        """CI-013: GHA warning annotation names the xml file."""
        H.make_repo(self.repo, {"A": {"x/bad.xml": self.BAD}})
        res = self.validate(self.env_no_tools(gha=True))
        self.assertRc(res, 0)
        self.assertOut(res, "::warning file=mods/A/x/bad.xml::XML not well-formed (non-fatal): mods/A/x/bad.xml:")

    def test_ci_013_xml_does_not_change_failing_exit(self):
        """CI-013: exit code is decided by pack.json/Lua only (Lua failure + XML warning -> 1)."""
        H.make_repo(self.repo, {"A": {"x/bad.xml": self.BAD, "s/a.script": b"local a =\n"}})
        res = self.validate(self.env_fake_luajit())
        self.assertRc(res, 1)
        self.assertOut(res, "XML not well-formed (non-fatal)")

    def test_ci_013_unlisted_folder_xml_checked(self):
        """CI-013: xml in unlisted folders is also checked (mods/**)."""
        H.make_repo(self.repo, {"A": {"a.txt": b"x"}, "Old": {"bad.xml": self.BAD}}, pack_mods=["A"])
        res = self.validate(self.env_no_tools())
        self.assertRc(res, 0)
        self.assertOut(res, "mods/Old/bad.xml")


if __name__ == "__main__":
    unittest.main()
