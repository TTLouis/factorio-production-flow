"""Run Lua 5.2 checks without a system Lua installation (optional Lupa runtime)."""
import os
from pathlib import Path
import sys

TESTS = Path(__file__).resolve().parent
MOD = TESTS.parent / "mod" / "production-flow"
from localization_check import validate
catalog, language_count = validate()
print(f"LOCALIZATION OK: {len(catalog)} English keys; {language_count} language(s)", flush=True)
if len(sys.argv) == 1:
    import unittest
    suite = unittest.defaultTestLoader.discover(str(TESTS), pattern="localization_test.py")
    if not unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful():
        raise SystemExit(1)
(TESTS / "out").mkdir(exist_ok=True)
sys.path.insert(0, str(TESTS / ".runtime"))
try:
    from lupa.lua52 import LuaRuntime
except ImportError:
    raise SystemExit("Install Lua support: python -m pip install --target tests/.runtime lupa")

lua = LuaRuntime()
lua.globals().TEST_LOCALE = lua.table_from(catalog)
lua.globals().LOC = lua.execute((TESTS / "locale_test_support.lua").read_text(encoding="utf-8"))(lua.globals().TEST_LOCALE)
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
if len(sys.argv) == 1:
    # Provider accounting runs in a fresh Lua world so its force/surface fixtures
    # cannot mutate the UI regression world's globals or saved state.
    for name in ["se_rockets_test.lua", "se_rocket_receipts_test.lua", "se_cannons_test.lua", "se_cannon_pairing_test.lua", "se_transfer_data_test.lua", "se_dense_presentation_test.lua", "transfer_endpoints_test.lua", "cannon_prototype_test.lua", "transport_flows_test.lua", "empty_pods_test.lua", "history_data_test.lua", "transfer_exchanges_test.lua", "canvas_visibility_test.lua", "surface_lifecycle_test.lua", "catalyst_stats_test.lua", "swimlane_columns_test.lua", "product_probability_test.lua", "sampler_empty_stats_test.lua", "cell_port_suggestions_test.lua"]:
        focused = LuaRuntime()
        provider_test = TESTS / name
        focused.execute(provider_test.read_text(encoding="utf-8"), name=str(provider_test))
    focused = LuaRuntime()
    rail_test = TESTS / "cell_rail_test.lua"
    focused.execute(rail_test.read_text(encoding="utf-8"), name=str(rail_test))
