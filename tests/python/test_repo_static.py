"""Static checks of the real repository checkout.

Spec: specs/system/repo-layout.md (REPO-002, REPO-003, REPO-005, REPO-006, REPO-008, REPO-014, REPO-015, REPO-017).
"""
import json
import os
import re
import sys
import unittest

import bp_helpers as H

R = H.REPO_ROOT
needs_git = unittest.skipUnless(H.is_git_checkout(), "not a git checkout (or git missing)")


def pack_json_bytes(section, mods):
    """REPO-005 serialisation: 2/4-space indent, LF, escape only '"', '\\' and < U+0020 as \\uXXXX."""
    def esc(s):
        out = []
        for ch in s:
            if ch in '"\\':
                out.append("\\" + ch)
            elif ord(ch) < 0x20:
                out.append("\\u%04x" % ord(ch))
            else:
                out.append(ch)
        return '"' + "".join(out) + '"'
    lines = ["{", '  "section": %s,' % esc(section), '  "mods": [']
    lines += ["    %s%s" % (esc(m), "," if i < len(mods) - 1 else "") for i, m in enumerate(mods)]
    lines += ["  ]", "}"]
    return ("\n".join(lines) + "\n").encode("utf-8")


class RealPackJsonTests(H.TempTestCase):
    def load(self):
        raw = H.read_bytes(os.path.join(R, "pack", "pack.json"))
        if raw.startswith(H.BOM):
            raw = raw[3:]
        return json.loads(raw.decode("utf-8"))

    def test_repo_003_real_pack_json_schema(self):
        """REPO-003: real pack.json is an object, non-empty section, unique valid names, non-empty mods/<name>/."""
        data = self.load()
        self.assertIsInstance(data, dict)
        self.assertIsInstance(data.get("section"), str)
        self.assertTrue(data["section"].strip())
        mods = data.get("mods")
        self.assertIsInstance(mods, list)
        self.assertTrue(mods)
        self.assertEqual(len(mods), len(set(mods)), "duplicate names")
        for m in mods:
            self.assertIsInstance(m, str)
            self.assertTrue(m.strip(), repr(m))
            self.assertFalse("/" in m or "\\" in m or m in (".", ".."), m)
            d = os.path.join(R, "mods", m)
            self.assertTrue(os.path.isdir(d), d)
            self.assertTrue(any(files for _, _, files in os.walk(d)), "empty " + d)

    def test_repo_003_real_repo_validate_passes(self):
        """REPO-003 / REPO-007: `build_pack.py validate` on the real checkout accepts pack.json (Lua tool removed)."""
        res = H.run_build_pack(["validate", "--repo", R], self.env_no_tools())
        self.assertRc(res, 0)
        self.assertOut(res, "pack.json OK")
        self.assertNotOut(res, "is not listed in pack/pack.json")

    def test_repo_005_real_pack_json_format(self):
        """REPO-005: committed pack.json bytes = publish serialisation (UTF-8 no BOM, LF, indent 2/4, final LF)."""
        raw = H.read_bytes(os.path.join(R, "pack", "pack.json"))
        self.assertFalse(raw.startswith(H.BOM))
        self.assertNotIn(b"\r", raw)
        data = json.loads(raw.decode("utf-8"))
        self.assertEqual(raw, pack_json_bytes(data["section"], data["mods"]))

    def test_repo_005_serialiser_example(self):
        """REPO-005: reference serialiser reproduces the spec example bytes (sanity of the check above)."""
        self.assertEqual(pack_json_bytes("xrRazom Sync", ["A", "B"]),
                         b'{\n  "section": "xrRazom Sync",\n  "mods": [\n    "A",\n    "B"\n  ]\n}\n')

    def test_repo_006_build_accepts_bom_copy_of_real_pack(self):
        """REPO-006: a BOM-prefixed copy of the real pack.json is read by build_pack.py validate."""
        data = self.load()
        mods = dict((m, {"a.txt": b"x"}) for m in data["mods"])
        raw = H.BOM + H.read_bytes(os.path.join(R, "pack", "pack.json")).lstrip(H.BOM)
        H.make_repo(self.repo, mods, pack_raw=raw)
        res = self.validate(self.env_no_tools())
        self.assertRc(res, 0)
        self.assertOut(res, "pack.json OK")


class GitAttributesTests(unittest.TestCase):
    def test_repo_008_gitattributes_star_minus_text(self):
        """REPO-008: .gitattributes contains the rule `* -text`."""
        text = H.read_bytes(os.path.join(R, ".gitattributes")).decode("utf-8")
        rules = [l.split() for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#")]
        self.assertIn(["*", "-text"], rules)
        # nothing re-enables text/eol for any pattern
        for r in rules:
            for attr in r[1:]:
                self.assertFalse(attr in ("text", "text=auto") or attr.startswith("eol="), r)

    @needs_git
    def test_repo_008_text_attribute_unset_for_mod_files(self):
        """REPO-008: git check-attr reports text: unset for every tracked mods/ file."""
        files = [f for f in H.tracked_files() if f.startswith("mods/")]
        self.assertTrue(files)
        p = H.git(R, "check-attr", "-z", "text", "--", *files)
        parts = p.stdout.decode("utf-8").split("\0")
        vals = dict((parts[i], parts[i + 2]) for i in range(0, len(parts) - 2, 3))
        for f in files:
            self.assertEqual(vals.get(f), "unset", f)

    @needs_git
    def test_repo_008_worktree_bytes_equal_blobs(self):
        """REPO-008: every tracked mods/, pack/, installer/, agent/, host/ file in the work tree hashes
        (--no-filters) to its index blob, i.e. checkout did no CRLF/LF conversion."""
        p = H.git(R, "ls-files", "-s", "-z")
        entries = {}
        for rec in p.stdout.decode("utf-8").split("\0"):
            if not rec:
                continue
            meta, path = rec.split("\t", 1)
            if path.split("/")[0] in ("mods", "pack", "installer", "agent", "host"):
                entries[path] = meta.split()[1]
        self.assertTrue(entries)
        paths = sorted(entries)
        h = H.git(R, "hash-object", "--no-filters", "--stdin-paths",
                  input="\n".join(paths).encode("utf-8") + b"\n")
        hashes = h.stdout.decode().split()
        self.assertEqual(len(hashes), len(paths), h.stderr)
        modified = H.git(R, "diff", "--name-only", "-z").stdout.decode("utf-8").split("\0")
        for path, got in zip(paths, hashes):
            if path in modified:
                continue  # locally edited file: not a checkout conversion
            self.assertEqual(got, entries[path], path)

    def test_repo_008_publish_git_calls_disable_autocrlf(self):
        """REPO-008: every git invocation in host/publish.ps1 passes -c core.autocrlf=false -c core.quotepath=false."""
        text = H.read_bytes(os.path.join(R, "host", "publish.ps1")).decode("utf-8-sig")
        calls = [l for l in text.splitlines() if re.search(r"&\s*git(\.exe)?\b", l) and not l.lstrip().startswith("#")]
        self.assertTrue(calls, "no git invocations found")
        for l in calls:
            self.assertIn("core.autocrlf=false", l)
            self.assertIn("core.quotepath=false", l)
        # GitRead builds a ProcessStartInfo for git: its Arguments must carry both flags
        lines = text.splitlines()
        psi = [i for i, l in enumerate(lines) if re.search(r"FileName\s*=\s*\$script:gitExe", l)]
        self.assertTrue(psi, "ProcessStartInfo for git not found")
        for i in psi:
            window = "\n".join(lines[i:i + 3])
            self.assertIn("'core.autocrlf=false'", window)
            self.assertIn("'core.quotepath=false'", window)


@needs_git
class TrackedFilesTests(unittest.TestCase):
    def setUp(self):
        # tests/ may legitimately contain fixtures (modlist.txt, markers) - REPO-014 targets the product tree
        self.files = [f for f in H.tracked_files() if not f.startswith("tests/")]

    def test_repo_002_repo_014_no_top_level_meta_or_marker(self):
        """REPO-002 / REPO-014: no mods/*/meta.ini and no xrrfix_pack.txt anywhere is tracked."""
        bad = [f for f in self.files
               if re.match(r"^mods/[^/]+/meta\.ini$", f, re.I) or f.lower().split("/")[-1] == "xrrfix_pack.txt"]
        self.assertEqual(bad, [])

    def test_repo_014_no_build_artifacts_profiles_agent_state(self):
        """REPO-014: no dist/, xrRazom_fixes.zip, notes.md, modlist.txt, *.xrrfix.bak, agent state files tracked."""
        state = {"gamma_root.txt", "installed_version.txt", "repo_root.txt"}
        bad = []
        for f in self.files:
            base = f.split("/")[-1].lower()
            if (f.startswith("dist/") or "/dist/" in f or base in ("xrrazom_fixes.zip", "notes.md", "modlist.txt")
                    or base.endswith(".xrrfix.bak") or base in state or base.endswith(".log")):
                bad.append(f)
        self.assertEqual(bad, [])

    def test_repo_014_no_secrets(self):
        """REPO-014 / SYS-014: no Discord webhook URLs or GitHub tokens in tracked text files."""
        hook = re.compile(r"discord(app)?\.com/api/webhooks/\d+/[\w-]{20,}")
        token = re.compile(r"\b(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b")
        hits = []
        for f in self.files:
            p = os.path.join(R, *f.split("/"))
            if not os.path.isfile(p) or os.path.getsize(p) > 5 * 1024 * 1024:
                continue
            text = H.read_bytes(p).decode("utf-8", "replace")
            if hook.search(text) or token.search(text):
                hits.append(f)
        self.assertEqual(hits, [])


class EncodingTests(unittest.TestCase):
    """REPO-015: service file encodings."""

    def service_files(self, pattern):
        out = []
        for d in ("host", "installer", "agent"):
            full = os.path.join(R, d)
            if os.path.isdir(full):
                out += [os.path.join(full, f) for f in sorted(os.listdir(full)) if re.search(pattern, f, re.I)]
        return out

    def test_repo_015_ps1_and_publish_ini_have_bom(self):
        """REPO-015: host/*.ps1, installer/*.ps1, agent/*.ps1, host/publish.ini start with EF BB BF."""
        files = self.service_files(r"\.ps1$") + [os.path.join(R, "host", "publish.ini")]
        self.assertGreaterEqual(len(files), 5)
        for f in files:
            self.assertEqual(H.read_bytes(f)[:3], H.BOM, f)

    def test_repo_015_cyrillic_txt_has_bom(self):
        """REPO-015: service .txt files containing non-ASCII (Cyrillic) start with a BOM."""
        for f in self.service_files(r"\.txt$"):
            data = H.read_bytes(f)
            if any(b >= 0x80 for b in data):
                self.assertEqual(data[:3], H.BOM, f)

    def test_repo_015_bat_ascii(self):
        """REPO-015: every .bat (host, installer, agent) is pure ASCII."""
        files = self.service_files(r"\.bat$")
        self.assertGreaterEqual(len(files), 3)
        for f in files:
            data = H.read_bytes(f)
            self.assertTrue(all(b < 0x80 for b in data), f)

    @unittest.skip("KNOWN-REPO-2: .bat CRLF is not required by REPO-015 (open question)")
    def test_known_repo_2_bat_crlf(self):
        """KNOWN-REPO-2 placeholder: .bat line endings (CRLF) not asserted."""



# REPO-017 shares the comparison with tools/spec_check.py (CHK-005).
sys.path.insert(0, os.path.join(H.REPO_ROOT, "tools"))
from spec_check import doc_mismatches  # noqa: E402


class DocsListPackTests(unittest.TestCase):
    README = "\n".join([
        "## Состав пакета", "",
        "| Мод | Что делает | Где нужен | Спека |", "|---|---|---|---|",
        "| zz A | a | хост | x |", "",
        "## Для разработки", "| zz Z | not a mod row |", "",
    ])
    SPECS = "\n".join([
        "## Реестр фиксов", "",
        "| ID | Мод | Кратко |", "|---|---|---|",
        "| FX-A | zz A | a |", "",
        "## Другие моды в пакете", "",
        "| ID | Мод | Кратко | Спека |", "|---|---|---|---|",
        "| MOD-B | B v.1 | b | x |", "",
    ])

    def test_repo_017_in_sync(self):
        """REPO-017: every pack mod listed once in both docs -> no findings; tables of other sections ignored."""
        readme = self.README.replace("| zz A | a | хост | x |", "| zz A | a | хост | x |\n| B v.1 | b | хост | x |")
        self.assertEqual([], doc_mismatches(["zz A", "B v.1"], readme, self.SPECS))

    def test_repo_017_missing_and_stale(self):
        """REPO-017: a renamed mod is reported as missing (new name) and stale (old name) in each doc."""
        found = doc_mismatches(["zz A", "B v.2", "zz New"], self.README, self.SPECS)
        self.assertIn("README.md: missing zz New", found)
        self.assertIn("README.md: missing B v.2", found)
        self.assertIn("specs/README.md: missing zz New", found)
        self.assertIn("specs/README.md: missing B v.2", found)
        self.assertIn("specs/README.md: stale B v.1", found)
        self.assertNotIn("README.md: stale zz Z", found)

    def test_repo_017_real_docs_list_pack(self):
        """REPO-017: real README.md / specs/README.md vs pack/pack.json; mismatch = warning + skip, never a failure."""
        raw = H.read_bytes(os.path.join(R, "pack", "pack.json"))
        if raw.startswith(H.BOM):
            raw = raw[3:]
        mods = json.loads(raw.decode("utf-8"))["mods"]
        read = lambda *p: H.read_bytes(os.path.join(R, *p)).decode("utf-8")
        found = doc_mismatches(mods, read("README.md"), read("specs", "README.md"))
        if found:
            msg = "docs out of sync with pack/pack.json: " + "; ".join(found)
            if os.environ.get("GITHUB_ACTIONS") == "true":
                print("::warning title=REPO-017::" + msg)
            self.skipTest(msg)


class KnownLimitations(unittest.TestCase):
    @unittest.skip("KNOWN-CI-7: Windows-invalid / case-colliding mod names are not rejected (open question)")
    def test_known_ci_7_windows_invalid_names(self):
        """KNOWN-CI-7 placeholder."""

    @unittest.skip("KNOWN-CI-8: section with a newline breaks pack.txt (open question)")
    def test_known_ci_8_section_newline(self):
        """KNOWN-CI-8 placeholder."""

    @unittest.skip("KNOWN-CI-9: committed mods/N/xrrfix_pack.txt would be shipped (open question)")
    def test_known_ci_9_marker_shipped(self):
        """KNOWN-CI-9 placeholder."""


if __name__ == "__main__":
    unittest.main()
