#!/usr/bin/env python3
"""Run tests/lua/run.lua through lupa's embedded LuaJIT (no system luajit needed).

    python -m pip install lupa
    python tests/lua/run_local.py [filter]

Exit code is the same as `luajit tests/lua/run.lua [filter]`: 0 = no failures, 1 = failures,
2 = no LuaJIT runtime available in lupa.
"""
import importlib
import os
import sys


def luajit_runtime():
    for name in ("luajit21", "luajit20"):
        try:
            mod = importlib.import_module("lupa." + name)
        except ImportError:
            continue
        return name, mod.LuaRuntime(unpack_returned_tuples=True)
    return None, None


def main(argv):
    name, rt = luajit_runtime()
    if rt is None:
        sys.stderr.write(
            "run_local.py: lupa with an embedded LuaJIT is required "
            "(python -m pip install lupa; needs lupa >= 2.0 for lupa.luajit21/luajit20)\n")
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    run = os.path.join(here, "run.lua").replace("\\", "/")
    lua_arg = {0: run}
    for i, a in enumerate(argv, 1):
        lua_arg[i] = a
    g = rt.globals()
    g.arg = rt.table_from(lua_arg)
    g.XRR_TEST_NO_EXIT = True
    print("run_local.py: lupa.%s (%s)" % (name, rt.eval("jit and jit.version or _VERSION")))
    sys.stdout.flush()
    code = g.dofile(run)
    rt.execute("io.stdout:flush()")
    return int(code) if code is not None else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
