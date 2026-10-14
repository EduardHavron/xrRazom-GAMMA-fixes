"""Shared helpers for the build_pack.py / repo tests (stdlib only).

Not a test module (unittest discovery only loads test*.py). The test directory is put on
sys.path by `python -m unittest discover -s tests/python`, so tests do `import bp_helpers`.
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
BUILD_PACK = os.path.join(REPO_ROOT, ".github", "scripts", "build_pack.py")
WORKFLOW = os.path.join(REPO_ROOT, ".github", "workflows", "release.yml")
BOM = b"\xef\xbb\xbf"
IS_WIN = os.name == "nt"

_TOOL_NAMES = ("luajit", "xmllint")


def _dir_has_tool(d, names):
    for n in names:
        for ext in ("", ".exe", ".cmd", ".bat", ".com"):
            if os.path.isfile(os.path.join(d, n + ext)):
                return True
    return False


def filtered_path(drop=_TOOL_NAMES):
    """Current PATH without any directory that contains one of `drop` (e.g. a real luajit)."""
    parts = [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
    return os.pathsep.join(p for p in parts if not _dir_has_tool(p, drop))


def make_temp_root(prefix="bp_test_"):
    base = os.environ.get("RUNNER_TEMP") or None
    return tempfile.mkdtemp(prefix=prefix, dir=base)


def rmtree(path):
    def onerr(func, p, _exc):
        try:
            os.chmod(p, stat.S_IWRITE)
            func(p)
        except OSError:
            pass
    shutil.rmtree(path, onerror=onerr) if sys.version_info < (3, 12) else shutil.rmtree(path, onexc=onerr)


def write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(data, str):
        data = data.encode("utf-8")
    with open(path, "wb") as f:
        f.write(data)


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


# ------------------------------------------------------------------ fake tools
FAKE_LUAJIT_PY = r'''
import json, os, sys
BOM = b"\xef\xbb\xbf"
args = sys.argv[1:]
if len(args) != 3 or args[0] != "-b":
    sys.stderr.write("fake luajit: unexpected args %r\n" % (args,))
    sys.exit(3)
src, out = args[1], args[2]
with open(src, "rb") as f:
    data = f.read()
log = os.environ.get("FAKE_LUAJIT_LOG")
if log:
    with open(log, "a", encoding="utf-8") as f:
        f.write(json.dumps({"args": args, "head": data[:3].hex(), "len": len(data)}) + "\n")
if data.startswith(BOM):
    sys.stderr.write("luajit: %s:1: unexpected symbol near '<\\239>'\n" % src)
    sys.exit(1)
text = data.decode("utf-8", "replace")
if text.rstrip().endswith("=") or "@@SYNTAX_ERROR@@" in text:
    n = text.rstrip().count("\n") + 1
    sys.stderr.write("luajit: %s:%d: unexpected symbol near '<eof>'\n" % (src, n))
    sys.exit(1)
with open(out, "wb") as f:
    f.write(b"\x1bLJ fake bytecode")
sys.exit(0)
'''

FAKE_XMLLINT_PY = r'''
import sys
import xml.etree.ElementTree as ET
args = sys.argv[1:]
if len(args) != 2 or args[0] != "--noout":
    sys.stderr.write("fake xmllint: unexpected args %r\n" % (args,))
    sys.exit(3)
path = args[1]
try:
    ET.parse(path)
except Exception:
    sys.stderr.write("%s:1: parser error : Start tag expected, '<' not found\n#include \"x.xml\"\n^\n" % path)
    sys.exit(1)
sys.exit(0)
'''


def install_fake_tool(bin_dir, name, py_source):
    """Create an executable `name` in bin_dir that runs py_source with the current interpreter.

    Windows: name.py + name.cmd (found by shutil.which through PATHEXT).
    POSIX:   name (python script with an absolute shebang, chmod 755).
    """
    os.makedirs(bin_dir, exist_ok=True)
    if IS_WIN:
        py = os.path.join(bin_dir, name + "_fake.py")
        write_bytes(py, py_source)
        cmd = '@echo off\r\n"%s" "%%~dp0%s_fake.py" %%*\r\nexit /b %%ERRORLEVEL%%\r\n' % (sys.executable, name)
        write_bytes(os.path.join(bin_dir, name + ".cmd"), cmd.encode("ascii"))
    else:
        p = os.path.join(bin_dir, name)
        write_bytes(p, "#!%s\n%s" % (sys.executable, py_source))
        os.chmod(p, 0o755)


def install_sh_tool(bin_dir, name, sh_source):
    """POSIX-only shell shim."""
    p = os.path.join(bin_dir, name)
    write_bytes(p, "#!/bin/sh\n" + sh_source)
    os.chmod(p, 0o755)


# ------------------------------------------------------------------ fixture repo
DEFAULT_INSTALLER = {
    "install.ps1": BOM + "# fake installer\r\nWrite-Host 'привет'\r\n".encode("utf-8"),
    "install.bat": b"@echo off\r\npowershell -File install.ps1 %*\r\n",
    "README.txt": BOM + "Установка\n".encode("utf-8"),
}


def make_repo(root, mods, pack_mods=None, section="S", pack_raw=None,
              installer=None, agent=None):
    """Create a minimal repo checkout under root.

    mods:      {mod name: {relative path with '/': bytes|str}}  (empty dict -> empty folder)
    pack_mods: list for pack.json "mods" (default: list(mods))
    pack_raw:  bytes/str written verbatim as pack/pack.json (overrides section/pack_mods);
               None + pack_mods == "absent" -> no pack.json at all.
    installer: {name: bytes} (default DEFAULT_INSTALLER; missing names are not written)
    agent:     {relative path: bytes} under agent/ (None -> no agent dir)
    """
    os.makedirs(root, exist_ok=True)
    for name, files in mods.items():
        mdir = os.path.join(root, "mods", name)
        os.makedirs(mdir, exist_ok=True)
        for relp, data in files.items():
            if relp.endswith("/"):
                os.makedirs(os.path.join(mdir, *relp.strip("/").split("/")), exist_ok=True)
            else:
                write_bytes(os.path.join(mdir, *relp.split("/")), data)
    pj = os.path.join(root, "pack", "pack.json")
    if pack_raw is not None:
        write_bytes(pj, pack_raw)
    elif pack_mods != "absent":
        doc = {"section": section, "mods": list(mods) if pack_mods is None else pack_mods}
        write_bytes(pj, json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    inst = DEFAULT_INSTALLER if installer is None else installer
    for n, data in inst.items():
        write_bytes(os.path.join(root, "installer", n), data)
    if agent is not None:
        os.makedirs(os.path.join(root, "agent"), exist_ok=True)
        for n, data in agent.items():
            write_bytes(os.path.join(root, "agent", *n.split("/")), data)
    return root


class Result(object):
    def __init__(self, rc, out):
        self.rc = rc
        self.out = out

    def __repr__(self):
        return "rc=%s\n--- output ---\n%s" % (self.rc, self.out)


def base_env(tmp_root, path=None, ci=None, gha=False, extra=None):
    env = dict(os.environ)
    for k in ("CI", "GITHUB_ACTIONS"):
        env.pop(k, None)
    if ci is not None:
        env["CI"] = ci
    if gha:
        env["GITHUB_ACTIONS"] = "true"
    env["PATH"] = filtered_path() if path is None else path
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    # git must never discover an enclosing repository above the fixture
    env["GIT_CEILING_DIRECTORIES"] = os.path.dirname(os.path.abspath(tmp_root))
    if extra:
        env.update(extra)
    return env


def run_build_pack(args, env, cwd=None, timeout=120):
    p = subprocess.run([sys.executable, BUILD_PACK] + list(args), cwd=cwd, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    return Result(p.returncode, p.stdout.decode("utf-8", "replace").replace("\r\n", "\n"))


class TempTestCase(unittest.TestCase):
    """TestCase with a fresh temp root per test (self.tmp) and a fake-tool bin dir (self.bin)."""

    def setUp(self):
        self.tmp = make_temp_root()
        self.repo = os.path.join(self.tmp, "repo")
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)

    def tearDown(self):
        if os.environ.get("BP_TESTS_KEEP_TEMP"):
            print("kept temp:", self.tmp)
            return
        rmtree(self.tmp)

    # env presets -------------------------------------------------------
    def env_no_tools(self, **kw):
        """PATH without luajit/xmllint (CI unset unless ci=...)."""
        return base_env(self.tmp, path=filtered_path(), **kw)

    def env_fake_luajit(self, xmllint=False, **kw):
        install_fake_tool(self.bin, "luajit", FAKE_LUAJIT_PY)
        if xmllint:
            install_fake_tool(self.bin, "xmllint", FAKE_XMLLINT_PY)
        self.luajit_log = os.path.join(self.tmp, "luajit_log.jsonl")
        extra = kw.pop("extra", {}) or {}
        extra["FAKE_LUAJIT_LOG"] = self.luajit_log
        return base_env(self.tmp, path=self.bin + os.pathsep + filtered_path(), extra=extra, **kw)

    def env_inherit(self, **kw):
        """Real PATH (git available) for build tests."""
        return base_env(self.tmp, path=os.environ.get("PATH", ""), **kw)

    def luajit_calls(self):
        if not os.path.isfile(self.luajit_log):
            return []
        with open(self.luajit_log, encoding="utf-8") as f:
            return [json.loads(l) for l in f if l.strip()]

    # runners -----------------------------------------------------------
    def validate(self, env):
        return run_build_pack(["validate", "--repo", self.repo], env)

    def build(self, env, version="1", out=None):
        out = out or os.path.join(self.tmp, "dist")
        self.out = out
        return run_build_pack(["build", "--repo", self.repo, "--version", version, "--out", out], env)

    def assertRc(self, res, rc):
        self.assertEqual(res.rc, rc, "unexpected exit code\n%r" % res)

    def assertOut(self, res, text):
        self.assertIn(text, res.out, "expected %r in output\n%r" % (text, res))

    def assertNotOut(self, res, text):
        self.assertNotIn(text, res.out, "did not expect %r in output\n%r" % (text, res))


def git_available():
    return shutil.which("git") is not None


def git(repo, *args, **kw):
    cmd = ["git", "-c", "core.autocrlf=false", "-c", "core.quotepath=false", "-C", repo] + list(args)
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kw)


def is_git_checkout(path=REPO_ROOT):
    if not git_available():
        return False
    p = git(path, "rev-parse", "--show-toplevel")
    if p.returncode != 0:
        return False
    top = os.path.normcase(os.path.normpath(p.stdout.decode("utf-8", "replace").strip()))
    return top == os.path.normcase(os.path.normpath(path))


def tracked_files(path=REPO_ROOT):
    p = git(path, "ls-files", "-z")
    return [x for x in p.stdout.decode("utf-8").split("\0") if x]
