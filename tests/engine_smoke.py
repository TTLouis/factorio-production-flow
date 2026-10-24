"""Validate polygons in a local Factorio engine using an isolated disposable map.

Does not read saves or change the installed mod, mod list or Factorio configuration.
"""
from datetime import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
exe = Path(sys.argv[1] if len(sys.argv) > 1 else
           r"D:\SteamLibrary\steamapps\common\Factorio\bin\x64\Factorio.exe")
if not exe.is_file():
    raise SystemExit("Pass the installed Factorio executable path as the first argument")
stage = TESTS / "out" / ("engine-smoke-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
mod = stage / "mods" / "production-flow"
shutil.copytree(ROOT / "mod" / "production-flow", mod, ignore=shutil.ignore_patterns("tools"))
shutil.copyfile(TESTS / "engine_smoke.lua", mod / "scripts" / "engine_smoke.lua")
control = mod / "control.lua"
source = control.read_text(encoding="utf-8")
hook = "script.on_init(function() setup(true) end)"
assert source.count(hook) == 1
source = 'local Smoke = require("scripts.engine_smoke")\n' + source.replace(
    hook, "script.on_init(function() setup(true); Smoke.run(UI, Canvas) end)")
control.write_text(source, encoding="utf-8")
(stage / "mods" / "mod-list.json").write_text(json.dumps({"mods": [
    {"name": "base", "enabled": True}, {"name": "production-flow", "enabled": True}
]}), encoding="utf-8")
data = exe.parents[2] / "data"
config = stage / "config.ini"
config.write_text(f"[path]\nread-data={data.as_posix()}\nwrite-data={stage.as_posix()}\n", encoding="utf-8")
gen = stage / "map-gen.json"
gen.write_text(json.dumps({"width": 64, "height": 64, "seed": 1}), encoding="utf-8")
result = subprocess.run([str(exe), "--config", str(config), "--mod-directory", str(stage / "mods"),
                         "--create", str(stage / "smoke.zip"), "--map-gen-settings", str(gen)],
                        capture_output=True, text=True, encoding="utf-8", errors="replace")
log = result.stdout + result.stderr
(stage / "output.txt").write_text(log, encoding="utf-8")
if result.returncode or "PRODUCTION FLOW ENGINE SMOKE OK" not in log:
    print(log[-10000:])
    raise SystemExit(f"Engine smoke failed; see {stage / 'output.txt'}")
print(next(line for line in log.splitlines() if "PRODUCTION FLOW ENGINE SMOKE OK" in line))
print(f"Engine log: {stage / 'output.txt'}")
