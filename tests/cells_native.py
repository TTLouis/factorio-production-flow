"""Exercise manual cell selection on a new, muted native map and capture the GUI."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from gui_interaction import PROFILE, ROOT, TESTS, digest


def is_complete_png(path):
    if not path.is_file() or path.stat().st_size < 12:
        return False
    with path.open("rb") as stream:
        stream.seek(-12, 2)
        return stream.read() == bytes.fromhex("0000000049454e44ae426082")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", default="D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe")
    args = parser.parse_args()
    exe = Path(args.exe).resolve()
    stage = TESTS / "out" / datetime.now().strftime("cells-native-%Y%m%d-%H%M%S-%f")
    target = stage / "mods/production-flow"
    source = ROOT / "mod/production-flow"
    shutil.copytree(source, target, ignore=shutil.ignore_patterns("tools"))
    print(stage, flush=True)
    protected = [PROFILE / name for name in
                 ("config/config.ini", "mods/mod-list.json", "mods/mod-settings.dat", "player-data.json")]
    before = {str(path): digest(path) for path in protected if path.is_file()}
    manifest = {
        "engine": subprocess.check_output([str(exe), "--version"], text=True),
        "source_sha256": {path.relative_to(target).as_posix(): digest(path)
                          for path in target.rglob("*") if path.is_file()},
        "fixture_sha256": digest(TESTS / "cells_native.lua"),
        "profile_sha256": before,
    }
    shutil.copyfile(TESTS / "cells_native.lua", target / "scripts/cells_native.lua")
    # Read the engine's data-stage shortcut prototype. The runtime shortcut
    # API only reports availability for shortcuts with the "lua" action.
    with (target / "data-final-fixes.lua").open("a", encoding="utf-8") as data:
        data.write("""
local selection = require("shared.cell_selection")
local shortcut = assert(data.raw.shortcut[selection.tool])
assert(shortcut.action == "spawn-item" and shortcut.item_to_spawn == selection.tool)
assert(not shortcut.technology_to_unlock)
""")
    control = target / "control.lua"
    hook = "  Sampler.on_tick(e.tick)"
    text = control.read_text(encoding="utf-8")
    assert text.count(hook) == 1
    control.write_text('local CellTest = require("scripts.cells_native")\n' +
                       text.replace(hook, hook + "\n  CellTest.tick(UI)"), encoding="utf-8")
    (stage / "mods/mod-list.json").write_text(json.dumps({"mods": [
        {"name": name, "enabled": name in ("base", "production-flow")}
        for name in ("base", "production-flow", "space-age", "elevated-rails", "quality", "recycler")]}))
    (stage / "config.ini").write_text(
        f"[path]\nread-data={exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n"
        "[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\n[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale=1\n"
        "[sound]\nmaster-muted=true\nmaster-volume=0\n")
    (stage / "map-gen.json").write_text(json.dumps({"width": 64, "height": 64, "seed": 3, "peaceful_mode": True}))
    common = [str(exe), "--config", str(stage / "config.ini"), "--mod-directory", str(stage / "mods"), "--disable-audio"]
    save = stage / "fixture.zip"
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    env = dict(os.environ, SteamAppId="427520", SteamGameId="427520")
    try:
        with (stage / "create.log").open("w") as stream:
            subprocess.run(common + ["--create", str(save), "--map-gen-settings", str(stage / "map-gen.json")],
                           stdout=stream, stderr=subprocess.STDOUT, env=env, startupinfo=startup,
                           check=True, timeout=120)
        log = stage / "native.log"
        with log.open("w") as stream:
            game = subprocess.Popen(common + ["--load-game", str(save), "--window-size", "1600x900",
                                    "--disable-migration-window", "--force-graphics-preset", "low"],
                                    stdout=stream, stderr=subprocess.STDOUT, env=env, startupinfo=startup)
            try:
                deadline = time.monotonic() + 150
                while time.monotonic() < deadline:
                    output = log.read_text(encoding="utf-8", errors="replace")
                    screenshots = [stage / "script-output/cells" / name for name in ("draft.png", "saved.png", "missing.png", "overview.png", "inside.png", "inside-capacity.png", "delete.png")]
                    if "PRODUCTION CELLS NATIVE PASS" in output and "CELL REPLACEMENT PASS" in output and "CELL MEASURED PASS" in output and "CELL CLONE PASS" in output and all(is_complete_png(p) for p in screenshots):
                        manifest["screenshots_sha256"] = {path.name: digest(path) for path in screenshots}
                        break
                    if game.poll() is not None or "Error while running" in output:
                        raise RuntimeError(output[-5000:])
                    time.sleep(0.25)
                else:
                    raise TimeoutError(f"See {log}")
            finally:
                if game.poll() is None:
                    game.terminate()
                game.wait(timeout=30)
    finally:
        manifest["profile_unchanged"] = all(Path(path).is_file() and digest(Path(path)) == h for path, h in before.items())
        (stage / "evidence.json").write_text(json.dumps(manifest, indent=2))
        assert manifest["profile_unchanged"]
    print("PRODUCTION CELLS NATIVE PASS")


if __name__ == "__main__":
    main()
