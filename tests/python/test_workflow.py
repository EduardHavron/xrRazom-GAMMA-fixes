"""Static checks of .github/workflows/release.yml (+ executing the Discord step with fakes on POSIX).

Spec: specs/system/ci-release.md (CI-001..CI-006, CI-015, CI-019..CI-028 are [manual] in the spec; these
tests only check the workflow text), specs/system/repo-layout.md (REPO-006, REPO-012, REPO-016 [auto]).
YAML-structure tests need PyYAML and are skipped without it.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import unittest

import bp_helpers as H

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None

needs_yaml = unittest.skipUnless(yaml is not None, "PyYAML not installed")

TEXT = H.read_bytes(H.WORKFLOW).decode("utf-8")
TRIGGER_PATHS = ["mods/**", "pack/**", "installer/**", "agent/**",
                 ".github/workflows/release.yml", ".github/scripts/**"]
STEP_NAMES = ["Checkout", "Install LuaJIT / xmllint", "Validate", "Build zip", "Create release", "Notify Discord"]


def load():
    return yaml.safe_load(TEXT)


def on_block(doc):
    # YAML 1.1: the bare key `on` is parsed as boolean True by PyYAML
    return doc.get("on", doc.get(True))


def steps(doc):
    return doc["jobs"]["release"]["steps"]


def step(doc, prefix):
    for s in steps(doc):
        if s.get("name", "").startswith(prefix):
            return s
    raise AssertionError("step %r not found" % prefix)


def path_matches(path, pattern):
    """GitHub paths filter subset used by release.yml: 'dir/**' or an exact file."""
    if pattern.endswith("/**"):
        return path.startswith(pattern[:-2])
    return path == pattern


def triggers(path, patterns):
    return any(path_matches(path, p) for p in patterns)


class WorkflowTextTests(unittest.TestCase):
    """Checks that only need the raw text (always run)."""

    def test_ci_001_repo_016_paths_listed(self):
        """CI-001 / REPO-016: every trigger path is listed in release.yml."""
        for p in TRIGGER_PATHS:
            self.assertRegex(TEXT, r"\n\s*-\s*'%s'\s*\n" % re.escape(p))
        self.assertNotIn("paths-ignore", TEXT)

    def test_ci_015_repo_012_version_expression(self):
        """CI-015 / REPO-012: VERSION = $(date -u +%Y.%m.%d)-<run_number>, exported as step output `version`."""
        self.assertIn('VERSION="$(date -u +%Y.%m.%d)-${{ github.run_number }}"', TEXT)
        self.assertIn('echo "version=$VERSION" >> "$GITHUB_OUTPUT"', TEXT)

    def test_ci_023_secret_name_and_skip_message(self):
        """CI-023: secret DISCORD_WEBHOOK; empty -> prints skip message and exits 0."""
        self.assertIn("DISCORD_WEBHOOK: ${{ secrets.DISCORD_WEBHOOK }}", TEXT)
        self.assertIn('if [ -z "$DISCORD_WEBHOOK" ]; then echo "DISCORD_WEBHOOK secret not set, skipping"; exit 0; fi', TEXT)


@needs_yaml
class WorkflowYamlTests(unittest.TestCase):
    def setUp(self):
        self.doc = load()

    def test_repo_016_ci_001_push_paths_filter(self):
        """REPO-016 / CI-001: push on main only, paths filter == expected list; specs/tests/README/host do not trigger."""
        on = on_block(self.doc)
        push = on["push"]
        self.assertEqual(push["branches"], ["main"])
        self.assertEqual(sorted(push["paths"]), sorted(TRIGGER_PATHS))
        self.assertNotIn("paths-ignore", push)
        for p in ("specs/system/publish.md", "tests/python/test_build.py", "README.md", "host/publish.ps1",
                  "LICENSE", ".gitattributes", ".github/workflows/tests.yml"):
            self.assertFalse(triggers(p, push["paths"]), p)
        for p in ("mods/X/gamedata/scripts/a.script", "pack/pack.json", "installer/install.ps1",
                  "agent/xrrfix_agent.ps1", ".github/workflows/release.yml", ".github/scripts/build_pack.py"):
            self.assertTrue(triggers(p, push["paths"]), p)

    def test_ci_002_workflow_dispatch_without_inputs(self):
        """CI-002: workflow_dispatch trigger without inputs."""
        on = on_block(self.doc)
        self.assertIn("workflow_dispatch", on)
        self.assertFalse((on["workflow_dispatch"] or {}).get("inputs"))
        self.assertEqual(sorted(on), ["push", "workflow_dispatch"])

    def test_ci_003_permissions_contents_write_only(self):
        """CI-003: permissions == {contents: write}, no job-level overrides."""
        self.assertEqual(self.doc["permissions"], {"contents": "write"})
        for job in self.doc["jobs"].values():
            self.assertNotIn("permissions", job)

    def test_ci_004_concurrency(self):
        """CI-004: concurrency group xrrfix-release, cancel-in-progress false."""
        self.assertEqual(self.doc["concurrency"], {"group": "xrrfix-release", "cancel-in-progress": False})

    def test_ci_005_step_order_and_runner(self):
        """CI-005: job `release` on ubuntu-latest; spec steps appear in this order; only Notify has `if: always()`
        among them; no step uses continue-on-error (a failing step aborts the following ones)."""
        job = self.doc["jobs"]["release"]
        self.assertEqual(job["runs-on"], "ubuntu-latest")
        names = [s.get("name", "") for s in job["steps"]]
        idx = []
        for prefix in STEP_NAMES:
            hits = [i for i, n in enumerate(names) if n.startswith(prefix)]
            self.assertEqual(len(hits), 1, (prefix, names))
            idx.append(hits[0])
        self.assertEqual(idx, sorted(idx), names)
        self.assertEqual(idx[-1], len(names) - 1, "Notify Discord must be the last step")
        for s in job["steps"]:
            self.assertNotIn("continue-on-error", s)
            if not s["name"].startswith("Notify"):
                self.assertNotIn("if", s, s["name"])

    def test_ci_006_tools_install(self):
        """CI-006: apt-get installs luajit and libxml2-utils and prints `luajit -v`."""
        run = step(self.doc, "Install LuaJIT").get("run", "")
        self.assertRegex(run, r"apt-get install .*\bluajit\b")
        self.assertIn("libxml2-utils", run)
        self.assertIn("luajit -v", run)

    def test_ci_007_validate_step_invocation(self):
        """CI-007..CI-013: Validate step runs `build_pack.py validate --repo .`."""
        run = step(self.doc, "Validate").get("run", "")
        self.assertIn("python3 .github/scripts/build_pack.py validate --repo .", run)

    def test_ci_015_ci_019_build_step(self):
        """CI-015 / CI-019: build step id `build`, runs build into dist and prints pack.txt / notes.md after markers."""
        s = step(self.doc, "Build zip")
        self.assertEqual(s.get("id"), "build")
        run = s["run"]
        self.assertIn('python3 .github/scripts/build_pack.py build --repo . --version "$VERSION" --out dist', run)
        self.assertIn("echo '--- pack.txt ---'; cat dist/pack.txt", run)
        self.assertIn("echo '--- notes.md ---'; cat dist/notes.md", run)

    def test_ci_020_repo_012_create_release(self):
        """CI-020 / REPO-012: gh release create v$VERSION with the zip, target sha, title, notes file, --latest; not draft/prerelease."""
        s = step(self.doc, "Create release")
        self.assertEqual(s["env"]["GH_TOKEN"], "${{ github.token }}")
        self.assertEqual(s["env"]["VERSION"], "${{ steps.build.outputs.version }}")
        run = " ".join(s["run"].replace("\\\n", " ").split())
        self.assertIn('gh release create "v$VERSION" dist/xrRazom_fixes.zip', run)
        self.assertIn('--target "$GITHUB_SHA"', run)
        self.assertIn('--title "xrRazom fixes $VERSION"', run)
        self.assertIn("--notes-file dist/notes.md", run)
        self.assertIn("--latest", run)
        for bad in ("--draft", "--prerelease", "--clobber"):
            self.assertNotIn(bad, run)
        self.assertEqual(len(re.findall(r"\.zip\b", run)), 1)

    def test_ci_022_notify_always(self):
        """CI-022: Notify Discord runs with if: always()."""
        self.assertEqual(step(self.doc, "Notify Discord").get("if"), "always()")

    def test_ci_024_ci_025_payload_shape(self):
        """CI-024 / CI-025: success color 5763719 + footer, failure color 15548997 with title 'Сборка фиксов упала'."""
        run = step(self.doc, "Notify Discord")["run"]
        self.assertIn('if [ "$JOB_STATUS" = "success" ]', run)
        self.assertIn("color:5763719", run)
        self.assertIn("color:15548997", run)
        self.assertIn('title:"Сборка фиксов упала"', run)
        self.assertIn('Фиксы xrRazom $VERSION', run)
        self.assertIn('$REPO_URL/releases/tag/v$VERSION', run)
        self.assertIn('footer:{text:("опубликовал "+$a)}', run)

    def test_ci_026_manual_build_text(self):
        """CI-026: empty commit message -> 'Ручная сборка'."""
        run = step(self.doc, "Notify Discord")["run"]
        self.assertIn('[ -n "$COMMIT_MSG" ] || COMMIT_MSG="Ручная сборка"', run)

    def test_ci_027_curl_failure_is_warning(self):
        """CI-027: curl -fsS ... && echo 'Discord notified' || echo '::warning::Discord notification failed'."""
        run = step(self.doc, "Notify Discord")["run"]
        self.assertIn('curl -fsS -H "Content-Type: application/json" -d "$PAYLOAD" "$DISCORD_WEBHOOK" && echo "Discord notified" || echo "::warning::Discord notification failed"', run)

    def test_ci_028_no_expressions_in_scripts(self):
        """CI-028: commit message, actor, version, URLs reach the notify/release scripts only via env."""
        notify = step(self.doc, "Notify Discord")
        self.assertNotIn("${{", notify["run"])
        self.assertNotIn("${{", step(self.doc, "Create release")["run"])
        env = notify["env"]
        self.assertEqual(env["COMMIT_MSG"], "${{ github.event.head_commit.message }}")
        self.assertEqual(env["ACTOR"], "${{ github.actor }}")
        self.assertEqual(env["VERSION"], "${{ steps.build.outputs.version }}")
        self.assertEqual(env["JOB_STATUS"], "${{ job.status }}")
        self.assertIn("jq -n", notify["run"])
        # no step script interpolates commit/actor expressions directly
        for s in steps(self.doc):
            run = s.get("run", "")
            self.assertNotIn("github.event.head_commit", run)
            self.assertNotIn("github.actor", run)


def notify_script():
    m = re.search(r"- name: Notify Discord\n(?:.*\n)*?\s+run: \|\n((?:\s{10}.*\n?)+)", TEXT)
    if not m:
        raise AssertionError("notify run block not found")
    return "\n".join(l[10:] for l in m.group(1).splitlines()) + "\n"


class MODSSnippetTests(H.TempTestCase):
    """REPO-006: the Discord step's python3 one-liner reads pack.json with and without BOM."""

    def snippet(self):
        m = re.search(r'python3 -c "([^"]+)"', TEXT)
        self.assertIsNotNone(m)
        # inside bash double quotes the code has no $/`/\\" escapes: pass it through verbatim
        return m.group(1)

    def test_repo_006_discord_mods_list_reads_bom(self):
        """REPO-006 / CI-024: the MODS one-liner lists '• <mod>' lines for pack.json with and without BOM."""
        code = self.snippet()
        for bom in (b"", H.BOM):
            with self.subTest(bom=bool(bom)):
                H.write_bytes(os.path.join(self.repo, "pack", "pack.json"),
                              bom + json.dumps({"section": "S", "mods": ["Мод A", "B"]}).encode("utf-8"))
                env = H.base_env(self.tmp, path=os.environ.get("PATH", ""))
                p = subprocess.run([sys.executable, "-c", code], cwd=self.repo, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(p.returncode, 0, p.stderr.decode("utf-8", "replace"))
                self.assertEqual(p.stdout.decode("utf-8").replace("\r\n", "\n"), "• Мод A\n• B\n")


@unittest.skipIf(H.IS_WIN, "runs the bash notify step; POSIX only")
@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "bash/jq not available")
class NotifyStepExecutionTests(H.TempTestCase):
    """CI-023..CI-027: run the real Notify Discord script with a fake curl/python3."""

    def run_notify(self, status="success", webhook="https://hook.invalid/x", msg="Fix A\n\nподробности",
                   curl_rc=0):
        H.write_bytes(os.path.join(self.repo, "pack", "pack.json"),
                      H.BOM + json.dumps({"section": "S", "mods": ["A", "Мод B"]}).encode("utf-8"))
        payload = os.path.join(self.tmp, "payload.json")
        calls = os.path.join(self.tmp, "curl_calls")
        H.install_sh_tool(self.bin, "curl",
                          'echo call >> "$FAKE_CURL_CALLS"\n'
                          'while [ $# -gt 0 ]; do case "$1" in -d) shift; printf "%s" "$1" > "$FAKE_CURL_OUT";; esac; shift; done\n'
                          'exit ${FAKE_CURL_RC:-0}\n')
        H.install_sh_tool(self.bin, "python3", 'exec "%s" "$@"\n' % sys.executable)
        script = os.path.join(self.tmp, "notify.sh")
        H.write_bytes(script, notify_script())
        env = H.base_env(self.tmp, path=self.bin + os.pathsep + os.environ.get("PATH", ""), extra={
            "DISCORD_WEBHOOK": webhook, "JOB_STATUS": status, "VERSION": "2026.10.13-7", "COMMIT_MSG": msg,
            "ACTOR": "dev", "RUN_URL": "https://github.com/o/r/actions/runs/1", "REPO_URL": "https://github.com/o/r",
            "FAKE_CURL_OUT": payload, "FAKE_CURL_CALLS": calls, "FAKE_CURL_RC": str(curl_rc)})
        p = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", script], cwd=self.repo, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = p.stdout.decode("utf-8", "replace")
        data = json.loads(H.read_bytes(payload).decode("utf-8")) if os.path.exists(payload) else None
        ncalls = len(H.read_bytes(calls).splitlines()) if os.path.exists(calls) else 0
        return p.returncode, out, data, ncalls

    def test_ci_023_no_secret_skips(self):
        """CI-023: empty DISCORD_WEBHOOK -> skip message, exit 0, no POST."""
        rc, out, data, n = self.run_notify(webhook="")
        self.assertEqual(rc, 0, out)
        self.assertIn("DISCORD_WEBHOOK secret not set, skipping", out)
        self.assertEqual(n, 0)

    def test_ci_024_success_payload(self):
        """CI-024 / CI-022: success -> exactly one POST with green embed, first commit line, mods list, footer."""
        rc, out, data, n = self.run_notify()
        self.assertEqual(rc, 0, out)
        self.assertEqual(n, 1)
        self.assertIn("Discord notified", out)
        self.assertEqual(data["username"], "xrRazom fixes")
        e = data["embeds"][0]
        self.assertEqual(e["title"], "Фиксы xrRazom 2026.10.13-7")
        self.assertEqual(e["url"], "https://github.com/o/r/releases/tag/v2026.10.13-7")
        self.assertEqual(e["color"], 5763719)
        self.assertEqual(e["footer"], {"text": "опубликовал dev"})
        self.assertEqual(e["description"],
                         "Fix A\n\n**Состав:**\n• A\n• Мод B\n\n"
                         "Агент у пира поставит обновление в течение 10 минут (при закрытом MO2).")

    def test_ci_025_failure_payload(self):
        """CI-025: non-success status -> red embed linking the run."""
        for status in ("failure", "cancelled"):
            with self.subTest(status=status):
                rc, out, data, n = self.run_notify(status=status)
                self.assertEqual(rc, 0, out)
                e = data["embeds"][0]
                self.assertEqual(e["title"], "Сборка фиксов упала")
                self.assertEqual(e["url"], "https://github.com/o/r/actions/runs/1")
                self.assertEqual(e["color"], 15548997)
                self.assertEqual(e["description"],
                                 "Коммит: Fix A\nРелиз не создан, пир остаётся на прошлой версии.")

    def test_ci_026_manual_build(self):
        """CI-026: empty commit message -> 'Ручная сборка'."""
        rc, out, data, n = self.run_notify(msg="")
        self.assertEqual(rc, 0, out)
        self.assertTrue(data["embeds"][0]["description"].startswith("Ручная сборка\n\n**Состав:**"))

    def test_ci_027_curl_failure_warns(self):
        """CI-027: curl failure -> '::warning::Discord notification failed', step still exits 0."""
        rc, out, data, n = self.run_notify(curl_rc=22)
        self.assertEqual(rc, 0, out)
        self.assertIn("::warning::Discord notification failed", out)

    def test_ci_028_commit_message_not_executed(self):
        """CI-028: shell metacharacters in the commit message are data, not code."""
        evil = '$(touch pwned) `touch pwned2` "; touch pwned3 #'
        rc, out, data, n = self.run_notify(msg=evil)
        self.assertEqual(rc, 0, out)
        for f in ("pwned", "pwned2", "pwned3"):
            self.assertFalse(os.path.exists(os.path.join(self.repo, f)), f)
        self.assertTrue(data["embeds"][0]["description"].startswith(evil))


if __name__ == "__main__":
    unittest.main()
