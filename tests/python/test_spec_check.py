"""tools/spec_check.py: consistency of specs, tests, COVERAGE.md and README.

Spec: specs/system/spec-check.md (CHK-001 .. CHK-008).
"""
import contextlib
import io
import json
import os
import sys
import unittest

import bp_helpers as H

sys.path.insert(0, os.path.join(H.REPO_ROOT, "tools"))
import spec_check as SC  # noqa: E402

PACK = '{\n  "section": "xrRazom Sync",\n  "mods": [\n    "zz A"\n  ]\n}\n'
SPEC_A = ("# FX-A: a\n"
          "Статус: действует        Проверка в игре: подтверждено        Мод: `zz A`        Скрипт: `a.script`\n"
          "\n## Требования\n"
          "### FX-A-001 one  [auto]\n"
          "### FX-A-002 two  [auto]\n"
          "### FX-A-003 three  [manual]\n"
          "### ~~FX-A-004 gone~~ (удалено)  [auto]\n")
README = ("## Состав пакета\n\n| Мод | Что делает | Где нужен | В игре | Спека |\n|---|---|---|---|---|\n"
          "| zz A | a | хост | подтверждено | x |\n\n## Для разработки\n")
SREADME = "## Реестр фиксов\n\n| ID | Мод | Кратко |\n|---|---|---|\n| FX-A | zz A | a |\n"
COVERAGE = "| Requirement | Test |\n|---|---|\n| FX-A-001 | t |\n| FX-A-002 | t |\n| FX-A-003 | manual |\n"
LUA = 'local H = ...\nH.case("FX-A-001 first", function() end)\nH.xfail("FX-A-002 second", "r", function() end)\n'


class SpecCheckTests(H.TempTestCase):
    def make(self, **over):
        files = {
            "pack/pack.json": PACK,
            "README.md": README,
            "specs/README.md": SREADME,
            "specs/fixes/fx-a.md": SPEC_A,
            "tests/lua/COVERAGE.md": COVERAGE,
            "tests/lua/test_a.lua": LUA,
        }
        files.update(over)
        for rel, text in files.items():
            path = os.path.join(self.repo, *rel.split("/"))
            if text is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                H.write_bytes(path, text.encode("utf-8"))
        return self.repo

    def findings(self, **over):
        return SC.check(self.make(**over))

    def codes(self, found, level=None):
        return [(x["level"], x["check"]) for x in found if level is None or x["level"] == level]

    def test_chk_001_clean_repo_has_no_findings(self):
        """CHK-001 CHK-003 CHK-004 CHK-005: consistent fake repo -> no findings."""
        self.assertEqual([], self.findings())

    def test_chk_001_auto_without_test_is_error(self):
        """CHK-001: [auto] requirement without a test -> error; [manual] and deleted ones are not checked."""
        found = self.findings(**{"tests/lua/test_a.lua": 'H.case("FX-A-001 x", function() end)\n'})
        self.assertEqual([("error", "CHK-001")], self.codes(found))
        self.assertIn("FX-A-002", found[0]["message"])

    def test_chk_001_via_and_gap(self):
        """CHK-001: 'via' an ID with tests -> fine; 'via' an untested ID -> error; 'GAP' -> warning."""
        lua = {"tests/lua/test_a.lua": 'H.case("FX-A-001 x", function() end)\n'}
        cov = COVERAGE.replace("| FX-A-002 | t |", "| FX-A-002 | via FX-A-001 (same path) |")
        self.assertEqual([], self.findings(**dict(lua, **{"tests/lua/COVERAGE.md": cov})))
        cov = COVERAGE.replace("| FX-A-002 | t |", "| FX-A-002 | via FX-A-003 |")
        self.assertEqual([("error", "CHK-001")], self.codes(self.findings(**dict(lua, **{"tests/lua/COVERAGE.md": cov}))))
        cov = COVERAGE.replace("| FX-A-002 | t |", "| FX-A-002 | GAP: not testable yet |")
        found = self.findings(**dict(lua, **{"tests/lua/COVERAGE.md": cov}))
        self.assertEqual([("warning", "CHK-001")], self.codes(found))
        self.assertIn("not testable yet", found[0]["message"])

    def test_chk_001_test_name_forms(self):
        """CHK-001: PowerShell Test-Case / TC and python function names / first docstring line count as tests."""
        ps = "Test-Case 'FX-A-001 ps' {\n}\nTC 'FX-A-002 agent' {\n}\n"
        self.assertEqual([], self.findings(**{"tests/lua/test_a.lua": "", "tests/publish/cases.ps1": ps}))
        py = 'class T:\n    def test_x(self):\n        """FX-A-001 FX-A-002: doc."""\n'
        self.assertEqual([], self.findings(**{"tests/lua/test_a.lua": "", "tests/python/test_x.py": py}))
        py = "class T:\n    def test_repo_017_ci_005_x(self):\n        pass\n"
        self.make(**{"tests/python/test_x.py": py})
        self.assertIn("REPO-017", SC.test_ids(self.repo))
        self.assertIn("CI-005", SC.test_ids(self.repo))

    def test_chk_002_unknown_and_deleted_ids(self):
        """CHK-002: test naming an unknown ID -> error; naming a deleted requirement -> warning."""
        lua = LUA + 'H.case("FX-A-009 ghost", function() end)\nH.case("FX-A-004 old", function() end)\n'
        found = self.codes(self.findings(**{"tests/lua/test_a.lua": lua}))
        self.assertIn(("error", "CHK-002"), found)
        self.assertIn(("warning", "CHK-002"), found)

    def test_chk_003_coverage_missing_and_unknown(self):
        """CHK-003: requirement absent from COVERAGE.md and unknown ID in COVERAGE.md -> warnings; ranges expand."""
        cov = "| FX-A-001, -002 | t |\n| FX-A-077 | t |\n"
        found = self.findings(**{"tests/lua/COVERAGE.md": cov})
        msgs = [x["message"] for x in found if x["check"] == "CHK-003"]
        self.assertTrue(any("FX-A-003" in m and "missing" in m for m in msgs), msgs)
        self.assertTrue(any("FX-A-077" in m for m in msgs), msgs)
        self.assertFalse(any("FX-A-002" in m for m in msgs), msgs)
        self.assertEqual(set(), {lv for lv, c in self.codes(found) if c == "CHK-003"} - {"warning"})

    def test_chk_004_verdict(self):
        """CHK-004: no verdict in the header -> error; README column differs -> warning; mod without spec -> warning."""
        spec = SPEC_A.replace("Проверка в игре: подтверждено        ", "")
        self.assertIn(("error", "CHK-004"), self.codes(self.findings(**{"specs/fixes/fx-a.md": spec})))
        readme = README.replace("| подтверждено |", "| частично |")
        found = self.findings(**{"README.md": readme})
        self.assertEqual([("warning", "CHK-004")], self.codes(found))
        self.assertIn("частично", found[0]["message"])
        found = self.findings(**{"specs/fixes/fx-a.md": None, "tests/lua/COVERAGE.md": "", "tests/lua/test_a.lua": ""})
        self.assertIn(("warning", "CHK-004"), self.codes(found))

    def test_chk_005_docs_vs_pack(self):
        """CHK-005: renamed mod in pack.json -> missing/stale warnings, never errors."""
        found = self.findings(**{"pack/pack.json": PACK.replace('"zz A"', '"zz A v2"')})
        msgs = [x["message"] for x in found if x["check"] == "CHK-005"]
        self.assertIn("README.md: missing zz A v2", msgs)
        self.assertIn("specs/README.md: stale zz A", msgs)
        self.assertNotIn(("error", "CHK-005"), self.codes(found))

    def test_chk_006_unverified_markers_are_notes(self):
        """CHK-006: [НЕ ПРОВЕРЕНО] markers are counted as a note per spec."""
        found = self.findings(**{"specs/fixes/fx-a.md": SPEC_A + "\n- x [НЕ ПРОВЕРЕНО]\n- y [НЕ ПРОВЕРЕНО]\n"})
        self.assertEqual([("note", "CHK-006")], self.codes(found))
        self.assertIn("2 x", found[0]["message"])

    def test_chk_007_read_only_exit_codes_json(self):
        """CHK-007: no files written; exit 0 clean, 1 on error, 2 without specs/; --json prints the findings."""
        root = self.make()
        before = sorted(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(0, SC.main(["--root", root, "--json"]))
        self.assertEqual([], json.loads(out.getvalue()))
        self.assertEqual(before, sorted(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs))
        self.make(**{"tests/lua/test_a.lua": ""})
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(1, SC.main(["--root", root]))
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(2, SC.main(["--root", self.bin]))

    def test_chk_008_real_repository(self):
        """CHK-008: the real repository has no spec_check errors; warnings become GitHub ::warning lines."""
        found = SC.check(H.REPO_ROOT)
        if os.environ.get("GITHUB_ACTIONS") == "true":
            for x in found:
                if x["level"] == "warning":
                    print("::warning title=%s::%s" % (x["check"], x["message"]))
        self.assertEqual([], [x["message"] for x in found if x["level"] == "error"])


if __name__ == "__main__":
    unittest.main()
