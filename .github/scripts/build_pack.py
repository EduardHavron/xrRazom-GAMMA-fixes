#!/usr/bin/env python3
"""Validate the repo and build the xrRazom fixes release zip.

Usage:
  build_pack.py validate [--repo DIR]
  build_pack.py build --version VER [--repo DIR] [--out DIR]

validate: pack/pack.json sanity, LuaJIT compile-only check of mods/**/*.script,
          XML well-formedness (warnings only).
build:    writes <out>/xrRazom_fixes.zip and <out>/notes.md (see CONTRACT.md "Release zip").

In CI (env CI=true) luajit is mandatory; locally a missing luajit only warns.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ZIP_NAME = "xrRazom_fixes.zip"
INSTALLER_FILES = ["install.ps1", "install.bat", "README.txt"]
BOM = b"\xef\xbb\xbf"
IN_CI = os.environ.get("CI", "").lower() == "true"
GHA = os.environ.get("GITHUB_ACTIONS", "").lower() == "true"


def _gha(kind, msg, path=None):
    """Print an annotation (GitHub Actions) or a plain message."""
    if GHA:
        loc = " file=%s" % path if path else ""
        # Annotations are single-line; escape newlines per GHA spec.
        text = msg.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
        print("::%s%s::%s" % (kind, loc, text))
    else:
        print("%s: %s" % (kind.upper(), msg))
    sys.stdout.flush()


def error(msg, path=None):
    _gha("error", msg, path)


def warn(msg, path=None):
    _gha("warning", msg, path)


def rel(path, base):
    return os.path.relpath(path, base).replace(os.sep, "/")


def walk_files(root):
    """All files under root (recursive), as paths relative to root with '/'."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in filenames:
            out.append(rel(os.path.join(dirpath, fn), root))
    return out


# ---------------------------------------------------------------- pack.json
def load_pack(repo):
    """Returns (section, mods) or raises SystemExit on invalid pack.json."""
    pj = os.path.join(repo, "pack", "pack.json")
    errors = 0
    try:
        with open(pj, "rb") as f:
            raw = f.read()
        if raw.startswith(BOM):
            raw = raw[len(BOM):]
        data = json.loads(raw.decode("utf-8"))
    except FileNotFoundError:
        error("pack/pack.json not found", "pack/pack.json")
        sys.exit(1)
    except (ValueError, UnicodeDecodeError) as e:
        error("pack/pack.json does not parse: %s" % e, "pack/pack.json")
        sys.exit(1)

    if not isinstance(data, dict):
        error("pack/pack.json: top level must be an object", "pack/pack.json")
        sys.exit(1)

    section = data.get("section")
    if not isinstance(section, str) or not section.strip():
        error("pack/pack.json: 'section' must be a non-empty string", "pack/pack.json")
        errors += 1

    mods = data.get("mods")
    if not isinstance(mods, list) or not mods:
        error("pack/pack.json: 'mods' must be a non-empty array", "pack/pack.json")
        sys.exit(1)

    mods_dir = os.path.join(repo, "mods")
    seen = set()
    for m in mods:
        if not isinstance(m, str) or not m.strip():
            error("pack/pack.json: mod name must be a non-empty string, got %r" % (m,), "pack/pack.json")
            errors += 1
            continue
        if m in seen:
            error("pack/pack.json: duplicate mod name '%s'" % m, "pack/pack.json")
            errors += 1
        seen.add(m)
        if "/" in m or "\\" in m or m in (".", ".."):
            error("pack/pack.json: invalid mod name '%s'" % m, "pack/pack.json")
            errors += 1
            continue
        if not os.path.isdir(os.path.join(mods_dir, m)):
            error("pack/pack.json lists '%s' but mods/%s/ does not exist" % (m, m), "pack/pack.json")
            errors += 1
        elif not walk_files(os.path.join(mods_dir, m)):
            error("mods/%s/ is empty" % m, "pack/pack.json")
            errors += 1

    if os.path.isdir(mods_dir):
        for d in sorted(os.listdir(mods_dir)):
            if os.path.isdir(os.path.join(mods_dir, d)) and d not in seen:
                warn("mods/%s/ is not listed in pack/pack.json and will NOT be released" % d)

    if errors:
        sys.exit(1)
    return section, mods


# ---------------------------------------------------------------- lua
def check_lua(repo):
    luajit = shutil.which("luajit")
    mods_dir = os.path.join(repo, "mods")
    scripts = [f for f in walk_files(mods_dir) if f.lower().endswith(".script")]
    if luajit is None:
        if IN_CI:
            error("luajit not found (required in CI)")
            return 1
        warn("luajit not found - skipping Lua syntax check of %d .script file(s)" % len(scripts))
        return 0

    failed = 0
    tmp = tempfile.mkdtemp(prefix="luachk_")
    try:
        src_tmp = os.path.join(tmp, "chunk.lua")
        out_tmp = os.path.join(tmp, "chunk.bc")
        for f in scripts:
            path = os.path.join(mods_dir, f)
            with open(path, "rb") as fh:
                data = fh.read()
            if data.startswith(BOM):
                data = data[len(BOM):]
            with open(src_tmp, "wb") as fh:
                fh.write(data)
            # -b = save bytecode: parses/compiles only, never executes the chunk.
            p = subprocess.run([luajit, "-b", src_tmp, out_tmp],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if p.returncode != 0:
                msg = p.stdout.decode("utf-8", "replace").strip()
                msg = msg.replace(src_tmp, "mods/" + f)
                error("Lua syntax error in mods/%s:\n%s" % (f, msg), "mods/" + f)
                failed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("Lua check: %d .script file(s), %d failed" % (len(scripts), failed))
    return 1 if failed else 0


# ---------------------------------------------------------------- xml (warnings only)
def check_xml(repo):
    mods_dir = os.path.join(repo, "mods")
    files = [f for f in walk_files(mods_dir) if f.lower().endswith(".xml")]
    xmllint = shutil.which("xmllint")
    bad = 0
    for f in files:
        path = os.path.join(mods_dir, f)
        if xmllint:
            p = subprocess.run([xmllint, "--noout", path],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            ok, msg = p.returncode == 0, p.stdout.decode("utf-8", "replace").strip()
        else:
            import xml.etree.ElementTree as ET
            try:
                ET.parse(path)
                ok, msg = True, ""
            except Exception as e:  # noqa: BLE001
                ok, msg = False, str(e)
        if not ok:
            bad += 1
            # Keep annotation short; GAMMA xml often uses #include / no root.
            first = msg.splitlines()[0] if msg else "not well-formed"
            warn("XML not well-formed (non-fatal): mods/%s: %s" % (f, first), "mods/" + f)
    print("XML check: %d file(s), %d warning(s)%s" % (len(files), bad, "" if xmllint else " [python parser]"))
    return 0


# ---------------------------------------------------------------- build
def sha16(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:16]


def build(repo, version, out_dir):
    section, mods = load_pack(repo)
    os.makedirs(out_dir, exist_ok=True)

    for f in INSTALLER_FILES:
        if not os.path.isfile(os.path.join(repo, "installer", f)):
            error("installer/%s is missing" % f, "installer/" + f)
            sys.exit(1)

    lines = ["version=" + version, "profile=github", "section=" + section, ""]
    entries = []  # (arcname, source path)
    for m in mods:
        mdir = os.path.join(repo, "mods", m)
        files = sorted(walk_files(mdir), key=lambda p: p.replace("/", "\\"))
        lines.append("[mod] " + m)
        for f in files:
            src = os.path.join(mdir, f)
            lines.append("  %s  %s" % (sha16(src), f.replace("/", "\\")))
            entries.append(("mods/%s/%s" % (m, f), src))
    pack_txt = "\n".join(lines) + "\n"

    zpath = os.path.join(out_dir, ZIP_NAME)
    if os.path.exists(zpath):
        os.remove(zpath)
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.writestr("pack.txt", pack_txt.encode("utf-8"))
        for f in INSTALLER_FILES:
            z.write(os.path.join(repo, "installer", f), f)
        for arc, src in entries:
            z.write(src, arc)
        # peer agent files: the agent updates itself from the release
        agent_dir = os.path.join(repo, "agent")
        if os.path.isdir(agent_dir):
            for f in sorted(os.listdir(agent_dir)):
                fp = os.path.join(agent_dir, f)
                if os.path.isfile(fp):
                    z.write(fp, "agent/" + f)

    # Release notes
    msg = ""
    try:
        p = subprocess.run(["git", "-C", repo, "log", "-1", "--format=%B"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if p.returncode == 0:
            msg = p.stdout.decode("utf-8", "replace").strip()
    except OSError:
        pass
    notes = []
    if msg:
        notes += [msg, ""]
    notes += ["**Состав пакета** (секция «%s», порядок = приоритет):" % section, ""]
    notes += ["- %s" % m for m in mods]
    notes += ["", "Установка: распакуйте `%s` и запустите `install.bat`." % ZIP_NAME]
    with open(os.path.join(out_dir, "notes.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(notes) + "\n")

    with open(os.path.join(out_dir, "pack.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(pack_txt)
    print("Built %s: %d mod(s), %d file(s), %d bytes"
          % (zpath, len(mods), len(entries), os.path.getsize(zpath)))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["validate", "build"])
    ap.add_argument("--repo", default=".")
    ap.add_argument("--version")
    ap.add_argument("--out", default="dist")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    if a.cmd == "validate":
        load_pack(repo)
        print("pack.json OK")
        rc = check_lua(repo)
        check_xml(repo)
        return rc
    if not a.version:
        ap.error("--version is required for build")
    return build(repo, a.version, os.path.abspath(a.out))


if __name__ == "__main__":
    sys.exit(main())
