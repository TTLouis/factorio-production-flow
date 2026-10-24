"""Run Lua 5.2 checks without a system Lua installation (optional Lupa runtime)."""
import os
from pathlib import Path
import sys

TESTS = Path(__file__).resolve().parent
MOD = TESTS.parent / "mod" / "production-flow"
(TESTS / "out").mkdir(exist_ok=True)
sys.path.insert(0, str(TESTS / ".runtime"))
try:
    from lupa.lua52 import LuaRuntime
except ImportError:
    raise SystemExit("Install Lua support: python -m pip install --target tests/.runtime lupa")

lua = LuaRuntime()
check = lua.eval("function(s,n) local f,e=load(s,n); if not f then error(e) end end")
paths = sorted(MOD.rglob("*.lua")) + sorted(TESTS.glob("*.lua")) + sorted((TESTS / "development").glob("*.lua"))
for path in paths:
    check(path.read_text(encoding="utf-8"), str(path))
print(f"Syntax OK: {len(paths)} Lua files", flush=True)
script = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else TESTS / "mock2.lua"
args = {0: os.path.relpath(script, MOD).replace("\\", "/")}
args.update(enumerate(sys.argv[2:], 1))
lua.globals().arg = lua.table_from(args)
os.chdir(MOD)
lua.execute(script.read_text(encoding="utf-8"), name=str(script))
