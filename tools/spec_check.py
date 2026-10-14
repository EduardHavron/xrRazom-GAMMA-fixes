#!/usr/bin/env python3
"""Read-only consistency check of specs/, tests/, COVERAGE.md, README.md and pack/pack.json.

    python tools/spec_check.py [--root DIR] [--json]

Spec: specs/system/spec-check.md (CHK-*). Never writes files. Exit code: 0 = no errors
(warnings and notes allowed), 1 = at least one error, 2 = cannot read the repository.
"""
import argparse
import glob
import json
import os
import re
import sys

ID = r"(?:SYS|REPO|PUB|CI|INS|AGT|CHK|FX-[A-Z]+|MOD-[A-Z]+)-\d{3}"
ID_RE = re.compile(r"\b" + ID + r"\b")
REQ_RE = re.compile(r"^### (~~)?(" + ID + r")\b.*?\[(auto|manual)\]\s*$")
PY_FN_RE = re.compile(r"(?:^|_)(sys|repo|pub|ci|ins|agt|chk)_(\d{3})(?=_|$)")
TEST_NAME_RES = {
    ".lua": [re.compile(r'\bH\.(?:case|xfail|skip)\(\s*"([^"]*)"')],
    ".ps1": [re.compile(r"^\s*(?:Test-Case|TC)\s+'([^']*)'", re.M)],
}
UNVERIFIED = "[НЕ ПРОВЕРЕНО]"
VERDICT_RE = re.compile(r"Проверка в игре:\s*(подтверждено|частично|не подтверждено|не проводилась|не записана)")
VERDICTS = ("подтверждено", "частично", "не подтверждено", "не проводилась", "не записана")


def read(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    return raw.decode("utf-8")


def rel(root, path):
    return os.path.relpath(path, root).replace(os.sep, "/")


# ---------------------------------------------------------------- collectors

def requirements(root):
    """{id: {"mode": auto|manual, "deleted": bool, "file": rel path}} from specs/**/*.md headings."""
    out = {}
    for path in sorted(glob.glob(os.path.join(root, "specs", "**", "*.md"), recursive=True)):
        for line in read(path).splitlines():
            m = REQ_RE.match(line)
            if m:
                out[m.group(2)] = {"mode": m.group(3), "deleted": bool(m.group(1)), "file": rel(root, path)}
    return out


def test_ids(root):
    """{id: [test names]} for every test case name under tests/ (lua, PowerShell, python)."""
    out = {}

    def add(name, ids):
        for i in ids:
            out.setdefault(i, []).append(name)

    for path in glob.glob(os.path.join(root, "tests", "**", "*"), recursive=True):
        ext = os.path.splitext(path)[1]
        if ext in TEST_NAME_RES:
            text = read(path)
            for rx in TEST_NAME_RES[ext]:
                for name in rx.findall(text):
                    add(name, ID_RE.findall(name))
        elif ext == ".py" and os.path.basename(path).startswith("test_"):
            text = read(path)
            for m in re.finditer(r"^\s*def (test_\w+)\(self[^)]*\):\s*\n(?:\s*\"\"\"(.*?)(?:\"\"\"|\n))?", text, re.M):
                fn, doc = m.group(1), m.group(2) or ""
                ids = ["%s-%s" % (p.upper(), n) for p, n in PY_FN_RE.findall(fn)] + ID_RE.findall(doc)
                add(fn, sorted(set(ids)))
    return out


def coverage(root):
    """(ids, rows) from tests/*/COVERAGE.md.

    ids: every requirement ID named anywhere ('FX-A-005, -006' expands to FX-A-005 and FX-A-006).
    rows: {id: text after the first cell} for table rows whose first cell names the ID; used for
    'via <ID>, <ID>' (covered by tests of other requirements) and 'GAP' (known missing test).
    """
    ids, rows = set(), {}
    for path in sorted(glob.glob(os.path.join(root, "tests", "*", "COVERAGE.md"))):
        for line in read(path).splitlines():
            for m in re.finditer(r"\b(" + ID + r")((?:\s*,\s*-\d{3})*)", line):
                base = m.group(1)
                ids.add(base)
                prefix = base[: base.rindex("-")]
                for n in re.findall(r"-(\d{3})", m.group(2)):
                    ids.add("%s-%s" % (prefix, n))
            if line.startswith("|"):
                cells = line.strip().strip("|").split("|", 1)
                if len(cells) == 2:
                    for i in ID_RE.findall(cells[0]):
                        rows.setdefault(i, cells[1])
    return ids, rows


def via_ids(row):
    """IDs listed after 'via' in a COVERAGE.md row, up to the first '(' or '.'."""
    m = re.search(r"\bvia\b([^(.]*)", row or "")
    return ID_RE.findall(m.group(1)) if m else []


def table_cells(text, headings, col):
    """Cell `col` of the data rows of markdown tables under the given `## ` headings."""
    rows, active = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            active = line[3:].strip() in headings
            continue
        if not (active and line.startswith("|")):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) <= col or set(cells[0]) <= set("-: ") or cells[col] in ("Мод", "ID"):
            continue
        rows.append(cells)
    return rows


def doc_mismatches(pack_mods, readme_text, specs_text):
    """REPO-017 / CHK-005: 'missing' and 'stale' mod names in README.md and specs/README.md."""
    docs = {
        "README.md": [r[0] for r in table_cells(readme_text, ("Состав пакета",), 0)],
        "specs/README.md": [r[1] for r in table_cells(specs_text, ("Реестр фиксов", "Другие моды в пакете"), 1)],
    }
    out = []
    for doc, names in docs.items():
        out += ["%s: missing %s" % (doc, m) for m in pack_mods if m not in names]
        out += ["%s: stale %s" % (doc, n) for n in names if n not in pack_mods]
    return out


def spec_headers(root):
    """{spec rel path: {"mod": folder name or None, "verdict": str or None, "unverified": count}} for specs/fixes."""
    out = {}
    for path in sorted(glob.glob(os.path.join(root, "specs", "fixes", "*.md"))):
        text = read(path)
        head = "\n".join(text.splitlines()[:4])
        mod = re.search(r"Мод: `([^`]+)`", head)
        verdict = VERDICT_RE.search(head)
        out[rel(root, path)] = {
            "mod": mod.group(1) if mod else None,
            "verdict": verdict.group(1) if verdict else None,
            "unverified": text.count(UNVERIFIED),
        }
    return out


# ---------------------------------------------------------------- checks

def check(root):
    findings = []

    def f(level, code, msg):
        findings.append({"level": level, "check": code, "message": msg})

    reqs = requirements(root)
    tests = test_ids(root)
    cov, rows = coverage(root)
    live = {i: r for i, r in reqs.items() if not r["deleted"]}

    # CHK-001 every [auto] requirement has a test (own name, or 'via' other tested IDs, or a declared GAP)
    for i, r in sorted(live.items()):
        if r["mode"] != "auto" or i in tests:
            continue
        row = rows.get(i, "")
        via = via_ids(row)
        if "GAP" in row:
            f("warning", "CHK-001", "%s [auto]: known gap in COVERAGE.md: %s" % (i, row.split("GAP", 1)[1].strip(" :|")))
        elif via and all(v in tests for v in via):
            continue
        elif via:
            f("error", "CHK-001", "%s [auto]: COVERAGE.md says via %s, but %s have no test"
              % (i, ", ".join(via), ", ".join(v for v in via if v not in tests)))
        else:
            f("error", "CHK-001", "%s [auto] (%s) has no test case" % (i, r["file"]))
    # CHK-002 every ID named by a test exists in the specs
    for i in sorted(tests):
        if i not in reqs:
            f("error", "CHK-002", "test %r names unknown requirement %s" % (tests[i][0], i))
        elif reqs[i]["deleted"]:
            f("warning", "CHK-002", "test %r names deleted requirement %s" % (tests[i][0], i))
    # CHK-003 COVERAGE.md lists every live requirement and nothing unknown
    for i in sorted(live):
        if i not in cov:
            f("warning", "CHK-003", "%s (%s) is missing from tests/*/COVERAGE.md" % (i, live[i]["file"]))
    for i in sorted(cov):
        if i not in reqs:
            f("warning", "CHK-003", "COVERAGE.md names unknown requirement %s" % i)

    # CHK-004 / CHK-005 docs vs pack.json, verdicts
    try:
        pack = json.loads(read(os.path.join(root, "pack", "pack.json")))["mods"]
        readme = read(os.path.join(root, "README.md"))
        sreadme = read(os.path.join(root, "specs", "README.md"))
    except (OSError, ValueError, KeyError) as e:
        raise SystemExit("spec_check: cannot read repository files: %s" % e)
    for m in doc_mismatches(pack, readme, sreadme):
        f("warning", "CHK-005", m)

    headers = spec_headers(root)
    by_mod = {h["mod"]: (p, h) for p, h in headers.items() if h["mod"]}
    readme_rows = {r[0]: r for r in table_cells(readme, ("Состав пакета",), 0)}
    head_cells = [c.strip() for c in next((l for l in readme.splitlines() if l.startswith("| Мод |")), "").strip("|").split("|")]
    vcol = head_cells.index("В игре") if "В игре" in head_cells else None
    for mod in pack:
        if mod not in by_mod:
            f("warning", "CHK-004", "%s has no spec in specs/fixes/" % mod)
            continue
        path, h = by_mod[mod]
        if h["verdict"] is None:
            f("error", "CHK-004", "%s: header has no 'Проверка в игре: <%s>'" % (path, " | ".join(VERDICTS)))
            continue
        if vcol is None:
            f("warning", "CHK-004", "README.md: table 'Состав пакета' has no column 'В игре'")
            vcol = -1
        row = readme_rows.get(mod)
        if row and vcol >= 0 and (len(row) <= vcol or row[vcol] != h["verdict"]):
            f("warning", "CHK-004", "README.md: %s 'В игре' = %r, spec %s says %r"
              % (mod, row[vcol] if len(row) > vcol else "", path, h["verdict"]))

    # CHK-006 unverified markers (information only)
    for path, h in headers.items():
        if h["unverified"]:
            f("note", "CHK-006", "%s: %d x %s" % (path, h["unverified"], UNVERIFIED))
    return findings


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
    ap.add_argument("--json", action="store_true", help="print findings as a JSON array")
    a = ap.parse_args(argv)
    if not os.path.isdir(os.path.join(a.root, "specs")):
        print("spec_check: %s is not a repository root (no specs/)" % a.root, file=sys.stderr)
        return 2
    try:
        findings = check(a.root)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    if a.json:
        print(json.dumps(findings, ensure_ascii=False, indent=1))
    else:
        for x in findings:
            print("%-7s %s  %s" % (x["level"].upper(), x["check"], x["message"]))
        n = {lv: sum(1 for x in findings if x["level"] == lv) for lv in ("error", "warning", "note")}
        print("spec_check: %d error(s), %d warning(s), %d note(s)" % (n["error"], n["warning"], n["note"]))
    return 1 if any(x["level"] == "error" for x in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
