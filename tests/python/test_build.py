"""build_pack.py build: zip layout, pack.txt, notes.md, installer/agent files.

Spec: specs/system/ci-release.md (CI-014, CI-016..CI-019), specs/system/repo-layout.md (REPO-007, REPO-009).
"""
import hashlib
import os
import re
import unittest
import zipfile

import bp_helpers as H

INSTALLER_ORDER = ["install.ps1", "install.bat", "README.txt"]


def sha16(data):
    return hashlib.sha256(data).hexdigest()[:16]


class BuildTestCase(H.TempTestCase):
    def zip_path(self):
        return os.path.join(self.out, "xrRazom_fixes.zip")

    def zip_names(self):
        with zipfile.ZipFile(self.zip_path()) as z:
            return z.namelist()

    def zip_read(self, name):
        with zipfile.ZipFile(self.zip_path()) as z:
            return z.read(name)

    def build_ok(self, version="1", **kw):
        res = self.build(self.env_inherit(), version=version, **kw)
        self.assertRc(res, 0)
        return res


class ZipLayoutTests(BuildTestCase):
    """CI-016 / REPO-007: archive entries and order."""

    def test_ci_016_repo_007_entries_and_order(self):
        """CI-016 / REPO-007: pack.txt, installer x3, listed mods in pack order, top-level agent files only."""
        H.make_repo(self.repo, {
            "A": {"a.txt": b"A1"},
            "B": {"gamedata/scripts/b.script": b"B1"},
            "C": {"c.txt": b"C1"},
        }, pack_mods=["B", "A"], agent={"x.ps1": b"X", "a.bat": b"Y", "sub/y": b"Z"})
        self.build_ok()
        self.assertEqual(self.zip_names(), [
            "pack.txt", "install.ps1", "install.bat", "README.txt",
            "mods/B/gamedata/scripts/b.script", "mods/A/a.txt",
            "agent/a.bat", "agent/x.ps1",
        ])

    def test_ci_016_no_agent_dir(self):
        """CI-016: without agent/ there are no agent/ entries."""
        H.make_repo(self.repo, {"A": {"a.txt": b"A1"}})
        self.build_ok()
        self.assertFalse([n for n in self.zip_names() if n.startswith("agent/")])

    def test_ci_016_deflate_and_bytes_exact(self):
        """CI-016: entries are DEFLATE; mod, installer and agent files are byte-exact (CRLF, BOM preserved)."""
        crlf = b"\xef\xbb\xbflocal a = 1\r\nlocal b = 2\r\n"
        binary = bytes(range(256)) * 4
        H.make_repo(self.repo, {"A": {"gamedata/scripts/a.script": crlf, "gamedata/textures/t.dds": binary}},
                    agent={"xrrfix_agent.ps1": b"\xef\xbb\xbf# agent\r\n"})
        self.build_ok()
        with zipfile.ZipFile(self.zip_path()) as z:
            for info in z.infolist():
                self.assertEqual(info.compress_type, zipfile.ZIP_DEFLATED, info.filename)
            self.assertEqual(z.read("mods/A/gamedata/scripts/a.script"), crlf)
            self.assertEqual(z.read("mods/A/gamedata/textures/t.dds"), binary)
            self.assertEqual(z.read("agent/xrrfix_agent.ps1"), b"\xef\xbb\xbf# agent\r\n")
            for n in INSTALLER_ORDER:
                self.assertEqual(z.read(n), H.DEFAULT_INSTALLER[n], n)

    def test_ci_016_existing_zip_overwritten(self):
        """CI-016: an existing <out>/xrRazom_fixes.zip is replaced."""
        H.make_repo(self.repo, {"A": {"a.txt": b"A1"}})
        out = os.path.join(self.tmp, "dist")
        H.write_bytes(os.path.join(out, "xrRazom_fixes.zip"), b"garbage, not a zip")
        self.build_ok(out=out)
        self.assertEqual(self.zip_names()[0], "pack.txt")

    def test_ci_016_out_dir_created(self):
        """CI-016: a missing --out directory (nested) is created."""
        H.make_repo(self.repo, {"A": {"a.txt": b"A1"}})
        self.build_ok(out=os.path.join(self.tmp, "x", "y", "dist"))
        self.assertTrue(os.path.isfile(self.zip_path()))

    def test_ci_016_empty_dirs_not_included(self):
        """CI-016: empty sub-folders of a mod produce no zip entries."""
        H.make_repo(self.repo, {"A": {"a.txt": b"A1", "empty/deeper/": None}})
        self.build_ok()
        self.assertEqual([n for n in self.zip_names() if n.startswith("mods/")], ["mods/A/a.txt"])

    def test_ci_016_special_names(self):
        """CI-016: mod/file names with spaces, apostrophes, brackets, Cyrillic survive in zip and pack.txt."""
        m1 = "zz xrRazom Fix - Laser State"
        m2 = "zz Мод's [Тест] fix"
        H.make_repo(self.repo, {
            m1: {"gamedata/scripts/zz laser.script": b"1"},
            m2: {"gamedata/configs/текст.ltx": b"2", "readme it's.txt": b"3"},
        }, pack_mods=[m2, m1])
        self.build_ok()
        names = self.zip_names()
        self.assertIn("mods/%s/gamedata/configs/текст.ltx" % m2, names)
        self.assertIn("mods/%s/readme it's.txt" % m2, names)
        self.assertIn("mods/%s/gamedata/scripts/zz laser.script" % m1, names)
        self.assertLess(names.index("mods/%s/readme it's.txt" % m2),
                        names.index("mods/%s/gamedata/scripts/zz laser.script" % m1))
        pack = self.zip_read("pack.txt").decode("utf-8")
        self.assertIn("[mod] %s\n" % m2, pack)
        self.assertIn("  %s  gamedata\\configs\\текст.ltx\n" % sha16(b"2"), pack)

    def test_ci_016_mod_files_same_order_as_pack_txt(self):
        """CI-016: (deterministic case) mod files appear in the zip in the same order as listed in pack.txt."""
        H.make_repo(self.repo, {"A": {"gamedata/b.txt": b"1", "meta2.ini": b"2", "gamedata/a/c.txt": b"3"}})
        self.build_ok()
        zipped = [n[len("mods/A/"):] for n in self.zip_names() if n.startswith("mods/A/")]
        pack_files = [l.split("  ", 2)[2].replace("\\", "/")
                      for l in self.zip_read("pack.txt").decode("utf-8").splitlines() if l.startswith("  ")]
        self.assertEqual(sorted(zipped), sorted(pack_files))

    def test_ci_016_mod_files_sorted_like_pack_txt(self):
        """CI-016 item 3: mod files go into the zip sorted by '\'-path (same order as pack.txt)."""
        H.make_repo(self.repo, {"A": {"z.txt": b"1", "a/b.txt": b"2"}})
        self.build_ok()
        zipped = [n[len("mods/A/"):] for n in self.zip_names() if n.startswith("mods/A/")]
        self.assertEqual(zipped, ["a/b.txt", "z.txt"])


class PackTxtTests(BuildTestCase):
    """CI-017 / REPO-009: pack.txt format."""

    def test_ci_017_exact_example(self):
        """CI-017: spec example -> exact pack.txt bytes."""
        H.make_repo(self.repo, {"A": {"gamedata/b.txt": b"hello", "meta.ini": b"[General]\r\n"}})
        self.build_ok(version="1")
        expected = ("version=1\nprofile=github\nsection=S\n\n[mod] A\n  %s  gamedata\\b.txt\n  %s  meta.ini\n"
                    % (sha16(b"hello"), sha16(b"[General]\r\n"))).encode("utf-8")
        self.assertEqual(self.zip_read("pack.txt"), expected)

    def test_ci_017_repo_009_header_and_mod_order(self):
        """REPO-009 / CI-017: ["B","A"], version 2026.10.13-5 -> header, [mod] B, hashes of B, then [mod] A."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}, "B": {"x/1.txt": b"1", "x/2.txt": b"2"}},
                    pack_mods=["B", "A"], section="xrRazom Sync")
        self.build_ok(version="2026.10.13-5")
        pack = self.zip_read("pack.txt").decode("utf-8")
        self.assertTrue(pack.startswith("version=2026.10.13-5\nprofile=github\nsection=xrRazom Sync\n\n[mod] B\n"), pack)
        lines = pack.splitlines()
        self.assertEqual(lines[4:], ["[mod] B", "  %s  x\\1.txt" % sha16(b"1"), "  %s  x\\2.txt" % sha16(b"2"),
                                     "[mod] A", "  %s  a.txt" % sha16(b"a")])

    def test_ci_017_encoding_lf_trailing_newline(self):
        """CI-017: UTF-8 without BOM, LF only, ends with LF, no blank lines between mods."""
        H.make_repo(self.repo, {"Мод": {"a.txt": b"a\r\n"}, "B": {"b.txt": b"b"}}, section="Секция Sync")
        self.build_ok()
        raw = self.zip_read("pack.txt")
        self.assertFalse(raw.startswith(H.BOM))
        self.assertNotIn(b"\r", raw)
        self.assertTrue(raw.endswith(b"\n") and not raw.endswith(b"\n\n"))
        text = raw.decode("utf-8")
        self.assertIn("section=Секция Sync\n", text)
        self.assertEqual(text.split("\n\n", 1)[1].count("\n\n"), 0)

    def test_ci_017_section_verbatim(self):
        """CI-017: section is written unchanged (spaces, punctuation)."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}}, section="  my 'Sync' [x]  ")
        self.build_ok()
        self.assertIn("\nsection=  my 'Sync' [x]  \n", self.zip_read("pack.txt").decode("utf-8"))

    def test_ci_017_sha16_matches_files(self):
        """CI-017: every hash line = first 16 lowercase hex of SHA-256 of the repo file; two-space format."""
        files = {"gamedata/scripts/a.script": b"local a = 1\r\n", "gamedata/configs/b.ltx": b"\x00\xff" * 100,
                 "readme.txt": b""}
        H.make_repo(self.repo, {"A": files})
        self.build_ok()
        rows = [l for l in self.zip_read("pack.txt").decode("utf-8").splitlines() if l.startswith(" ")]
        self.assertEqual(len(rows), 3)
        for row in rows:
            m = re.match(r"^  ([0-9a-f]{16})  (\S.*)$", row)
            self.assertIsNotNone(m, row)
            rel = m.group(2).replace("\\", "/")
            self.assertEqual(m.group(1), sha16(files[rel]), row)

    def test_ci_017_sorted_by_backslash_path_ordinal(self):
        """CI-017: files sorted by '\\'-path, ordinal and case-sensitive ('a0.txt' < 'a\\b.txt'; 'B' < 'a')."""
        files = {"a/b.txt": b"1", "a0.txt": b"2", "a.txt": b"3", "B.txt": b"4", "c.txt": b"5"}
        H.make_repo(self.repo, {"A": files})
        self.build_ok()
        paths = [l.split("  ", 2)[2] for l in self.zip_read("pack.txt").decode("utf-8").splitlines()
                 if l.startswith("  ")]
        self.assertEqual(paths, ["B.txt", "a.txt", "a0.txt", "a\\b.txt", "c.txt"])

    def test_ci_017_out_pack_txt_identical(self):
        """CI-017: <out>/pack.txt has exactly the same bytes as the zip's pack.txt."""
        H.make_repo(self.repo, {"Мод A": {"x/y.txt": b"1"}})
        self.build_ok()
        self.assertEqual(H.read_bytes(os.path.join(self.out, "pack.txt")), self.zip_read("pack.txt"))

    def test_ci_017_only_listed_mods(self):
        """CI-017 / REPO-007: unlisted folders do not appear in pack.txt or zip."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}, "C": {"c.txt": b"c"}}, pack_mods=["A"])
        self.build_ok()
        self.assertNotIn("[mod] C", self.zip_read("pack.txt").decode("utf-8"))
        self.assertFalse([n for n in self.zip_names() if n.startswith("mods/C/")])


class NotesTests(BuildTestCase):
    """CI-018: notes.md."""

    def tail(self, section, mods):
        lines = ["**Состав пакета** (секция «%s», порядок = приоритет):" % section, ""]
        lines += ["- %s" % m for m in mods]
        lines += ["", "Установка: распакуйте `xrRazom_fixes.zip` и запустите `install.bat`."]
        return "\n".join(lines) + "\n"

    def test_ci_018_without_git(self):
        """CI-018: no git repo -> notes start with '**Состав пакета**', exit 0, UTF-8 no BOM, LF."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}, "Мод B": {"b.txt": b"b"}}, pack_mods=["Мод B", "A"],
                    section="xrRazom Sync")
        self.build_ok()
        raw = H.read_bytes(os.path.join(self.out, "notes.md"))
        self.assertFalse(raw.startswith(H.BOM))
        self.assertNotIn(b"\r", raw)
        self.assertEqual(raw.decode("utf-8"), self.tail("xrRazom Sync", ["Мод B", "A"]))

    @unittest.skipUnless(H.git_available(), "git not available")
    def test_ci_018_with_commit_message(self):
        """CI-018: git log -1 message (full, trimmed) + blank line, then the package list."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}})
        r = self.repo
        for args in (["init", "-q"], ["config", "user.name", "T"], ["config", "user.email", "t@example.invalid"],
                     ["config", "commit.gpgsign", "false"], ["add", "-A"]):
            p = H.git(r, *args)
            self.assertEqual(p.returncode, 0, p.stderr)
        msgf = os.path.join(self.tmp, "msg.txt")
        H.write_bytes(msgf, "Fix A: лазер\n\nподробности\nвторая строка\n\n".encode("utf-8"))
        p = H.git(r, "commit", "-q", "--cleanup=verbatim", "-F", msgf)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.build_ok()
        notes = H.read_bytes(os.path.join(self.out, "notes.md")).decode("utf-8")
        self.assertEqual(notes, "Fix A: лазер\n\nподробности\nвторая строка\n\n" + self.tail("S", ["A"]))

    @unittest.skipUnless(H.git_available(), "git not available")
    def test_ci_018_git_without_commits(self):
        """CI-018: git repo without commits (git log fails) -> build still succeeds, notes without message."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}})
        H.git(self.repo, "init", "-q")
        self.build_ok()
        notes = H.read_bytes(os.path.join(self.out, "notes.md")).decode("utf-8")
        self.assertTrue(notes.startswith("**Состав пакета**"), notes)


class BuildErrorTests(BuildTestCase):
    """CI-014 and argument handling."""

    def test_ci_014_missing_installer_file(self):
        """CI-014: each missing installer file -> 'installer/<f> is missing', exit 1, no zip."""
        for missing in INSTALLER_ORDER:
            with self.subTest(missing=missing):
                if os.path.isdir(self.repo):
                    H.rmtree(self.repo)
                inst = dict((k, v) for k, v in H.DEFAULT_INSTALLER.items() if k != missing)
                H.make_repo(self.repo, {"A": {"a.txt": b"a"}}, installer=inst)
                out = os.path.join(self.tmp, "dist_" + missing.replace(".", "_"))
                res = self.build(self.env_inherit(), out=out)
                self.assertRc(res, 1)
                self.assertOut(res, "ERROR: installer/%s is missing" % missing)
                self.assertFalse(os.path.exists(os.path.join(out, "xrRazom_fixes.zip")))

    def test_ci_014_gha_annotation(self):
        """CI-014: GHA annotation file=installer/<f>."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}},
                    installer={k: v for k, v in H.DEFAULT_INSTALLER.items() if k != "README.txt"})
        res = self.build(self.env_inherit(gha=True))
        self.assertRc(res, 1)
        self.assertOut(res, "::error file=installer/README.txt::installer/README.txt is missing")

    def test_ci_014_build_revalidates_pack_json(self):
        """CI-014: build re-runs the pack.json checks (CI-007..CI-009) -> exit 1, no zip."""
        cases = [(["A", "A"], "duplicate mod name 'A'"), (["A", "Missing"], "mods/Missing/ does not exist"),
                 ([], "'mods' must be a non-empty array")]
        for pack_mods, msg in cases:
            with self.subTest(pack_mods=pack_mods):
                if os.path.isdir(self.repo):
                    H.rmtree(self.repo)
                H.make_repo(self.repo, {"A": {"a.txt": b"a"}}, pack_mods=pack_mods)
                out = os.path.join(self.tmp, "dist_%d" % len(pack_mods))
                res = self.build(self.env_inherit(), out=out)
                self.assertRc(res, 1)
                self.assertOut(res, msg)
                self.assertFalse(os.path.exists(os.path.join(out, "xrRazom_fixes.zip")))

    def test_ci_014_build_without_version_is_argparse_error(self):
        """CI-014 / inputs table: `build` without --version -> argparse error, exit 2."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a"}})
        res = H.run_build_pack(["build", "--repo", self.repo, "--out", os.path.join(self.tmp, "d")],
                               self.env_inherit())
        self.assertRc(res, 2)
        self.assertOut(res, "--version is required for build")

    def test_ci_014_build_does_not_check_lua(self):
        """CI-014: build validates pack.json only (a broken script does not stop build)."""
        H.make_repo(self.repo, {"A": {"s/a.script": b"local a =\n"}})
        res = self.build(self.env_fake_luajit(ci="true"))
        self.assertRc(res, 0)
        self.assertEqual(self.luajit_calls(), [])

    def test_ci_019_built_line_counts_mod_files(self):
        """CI-019: 'Built <zip>: <n> mod(s), <m> file(s), <b> bytes' where m counts only mod files."""
        H.make_repo(self.repo, {"A": {"a.txt": b"a", "x/b.txt": b"b"}, "B": {"c.txt": b"c"}},
                    agent={"x.ps1": b"x"})
        res = self.build_ok()
        size = os.path.getsize(self.zip_path())
        self.assertOut(res, "Built %s: 2 mod(s), 3 file(s), %d bytes" % (self.zip_path(), size))


if __name__ == "__main__":
    unittest.main()
