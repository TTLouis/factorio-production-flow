"""Paired native transfer-ledger benchmark in a new, disposable Factorio profile.

No engine is launched with --offline-check. Normal runs build one saved map with
32,768 boundaries, then compare the former full-retention retrieval with the
candidate on that same map, with the GUI closed and open. Times are simulation
and script update costs, not rendering FPS or normal game speed.
"""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mod/production-flow"
FIXTURE = ROOT / "tests/development/transport_query_fixture.lua"
DEFAULT_ENGINE = Path("D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe")
SAVE_NAME = "_autosave-transport-ledger.zip"
WARMUP = 300
F6_BASELINE_COMMIT = "b872e3efdf4ea4efd943ead6f616a3faeb16029e"
HOOK = r'''
local Fixture=require("scripts.transport_query_fixture")
local cfg=require("scripts.transport_benchmark_config")
local SK=require("scripts.sankey_ui")
local Sampler=require("scripts.sampler")
local Canvas=require("scripts.canvas")
local Transport=require("scripts.transport_flows")
local B={}
local started,initialized,saved,query_count,refreshes
local function settings_values(source)
  local values={};for name,setting in pairs(source) do values[name]=setting.value end;return values
end
function B.build_ready()
  if cfg.mode~="build" then return end
  game.tick_paused=false;game.speed=64
  for _,player in pairs(game.players) do
    if player.controller_type==defines.controllers.cutscene then player.exit_cutscene() end
    player.opened=nil
    for _,root in pairs({player.gui.screen,player.gui.center}) do
      for _,child in pairs(root.children) do child.visible=false end
    end
  end
  log("TRANSPORT BUILD READY tick="..game.tick)
end
function B.init()
  if cfg.mode~="build" then return end
  local freeplay=remote.interfaces.freeplay
  if freeplay and freeplay.set_skip_intro then remote.call("freeplay","set_skip_intro",true) end
  if freeplay and freeplay.set_disable_crashsite then remote.call("freeplay","set_disable_crashsite",true) end
  B.build_ready()
end
function B.tick(UI)
  started=started or game.tick
  local elapsed=game.tick-started
  if cfg.mode=="build" then
    game.tick_paused=false
    if elapsed==0 then B.build_ready();log("TRANSPORT BUILD START tick="..game.tick) end
    if elapsed%1000==0 then log("TRANSPORT BUILD PROGRESS tick="..game.tick.." elapsed="..elapsed) end
    if not saved and game.tick>=10000 then
      -- The graphical --load-game phase creates the saved benchmark player.
      -- --create alone has no player; LuaGameScript cannot create one.
      local player=assert(game.players[1],"Build via graphical --load-game so a native player exists")
      local surface=game.surfaces.nauvis or game.surfaces[1]
      local remote=game.create_surface("transport-benchmark-remote",{width=32,height=32,
        autoplace_controls={},default_enable_all_autoplace_controls=false})
      local stats_surfaces={surface.index,remote.index}
      for i=1,8 do
        local s=game.create_surface("transport-benchmark-empty-"..i,{width=32,height=32,
          autoplace_controls={},default_enable_all_autoplace_controls=false})
        stats_surfaces[#stats_surfaces+1]=s.index
      end
      Canvas.surface()
      local counts=Fixture.seed(player.force,surface,remote,game.tick)
      counts.real_empty_surfaces=#stats_surfaces;counts.internal_canvas_surfaces=1
      storage.transport_benchmark={surface=surface.index,remote=remote.index,counts=counts,
        seed_tick=game.tick,stats_surfaces=stats_surfaces}
      for _,p in pairs(game.players) do UI.close(p) end
      saved=true;game.auto_save("transport-ledger")
      log("TRANSPORT FIXTURE PASS "..helpers.table_to_json(counts))
    end
    return
  end
  if not initialized then
    local meta=assert(storage.transport_benchmark,"Load the seeded private save")
    local player=assert(game.players[1],"Saved map has no benchmark player")
    local surface=assert(game.surfaces[meta.surface])
    Fixture.attach();Fixture.refresh(game.tick)
    local check=Transport.query(player.force,surface,game.tick,cfg.period)
    assert(#check.events==24,"Native selected-window stock-event count changed")
    assert(#Transport.history(player.force,surface,game.tick,cfg.period).records==4,
      "Native selected-window shipment count changed")
    if cfg.baseline and cfg.baseline_f2 then Fixture.full_retention_baseline() end
    query_count=0;refreshes=0
    local original=Transport.query
    Transport.query=function(...) query_count=query_count+1;return original(...) end
    for _,p in pairs(game.players) do UI.close(p) end
    if cfg.open then
      storage.ui=storage.ui or {}
      local us=storage.ui[player.index] or {};storage.ui[player.index]=us
      us.tab_id=cfg.tab;us.surface=surface.name;us.period=cfg.period
      us.period_default_10m=true;us.live=true;us.renderer=cfg.renderer
      us.bal_filter="all";us.bal_mode="flow";us.view="detail"
      local fx=SK.balance_state(us);fx.focus="item/iron-plate";fx.live=true;fx.renderer=cfg.renderer
      UI.open(player)
      assert(UI.is_open(player) and query_count>0,"Open UI did not execute the product transport query")
    end
    local us=storage.ui and storage.ui[player.index] or {}
    log("TRANSPORT BENCH SETTINGS "..helpers.table_to_json({mods=script.active_mods,
      global=settings_values(settings.global),startup=settings_values(settings.startup),
      player=settings_values(settings.get_player_settings(player)),period=cfg.period,
      tab=cfg.tab,renderer=cfg.renderer,open=cfg.open,baseline=cfg.baseline,
      baseline_fixes=cfg.baseline_fixes,fixture=meta.counts,seed_tick=meta.seed_tick,
      display_resolution=player.display_resolution,display_scale=player.display_scale,
      canvas_w=us.canvas_w,canvas_h=us.canvas_h}))
    initialized=true
  end
  if elapsed==cfg.ticks-1 then
    assert(storage.transfers.boundary_observations.count==32768,"Ledger no longer near its cap")
    local meta=storage.transport_benchmark
    for _,index in ipairs(meta.stats_surfaces) do
      assert(storage.stat_last[index],"Real empty surface statistics were not measured")
      assert(Sampler.coverage(index,cfg.period)>0,"Real empty surface lost measured coverage")
    end
    if cfg.open then
      assert(refreshes>=math.max(0,math.floor((cfg.ticks-1)/300)-1),"Missing native UI refreshes")
      assert(query_count>=refreshes+1,"UI refresh skipped the product query")
    else assert(query_count==0,"Closed-window fixture unexpectedly ran a chart query") end
    log("TRANSPORT BENCH PASS "..helpers.table_to_json({ticks=cfg.ticks,queries=query_count,
      refreshes=refreshes,open=cfg.open,baseline=cfg.baseline,real_stats_surfaces=#meta.stats_surfaces,
      canvas_sampled=storage.stat_last[game.surfaces["ssk-canvas"].index]~=nil}))
  end
end
function B.before_auto()
  if initialized then Fixture.refresh(game.tick);refreshes=refreshes+1 end
end
function B.after_auto(UI)
  if initialized and cfg.open then
    -- --benchmark players are disconnected, so the normal connected-player
    -- loop omits them. Exercise the same only_auto product refresh explicitly.
    for _,p in pairs(game.players) do
      if not p.connected then assert(UI.is_open(p));UI.refresh(p,true) end
    end
  end
end
return B
'''


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_hashes(directory):
    return {p.relative_to(directory).as_posix(): sha256(p)
            for p in sorted(directory.rglob("*")) if p.is_file() and "tools" not in p.relative_to(directory).parts}


def profile_guard():
    """Hash settings and saves/mod archives; never read credentials into output."""
    profile = Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming"))) / "Factorio"
    paths = {profile / "config/config.ini", profile / "mods/mod-list.json", profile / "mods/mod-settings.dat"}
    for name in ("saves", "mods"):
        directory = profile / name
        if directory.exists():
            paths.update(directory.rglob("*.zip"))
    return {"root": str(profile), "sha256": {p.relative_to(profile).as_posix(): sha256(p)
            for p in sorted(paths) if p.is_file()}}


def hardware():
    result = {"platform": platform.platform(), "machine": platform.machine(),
              "processor": os.environ.get("PROCESSOR_IDENTIFIER") or platform.processor(),
              "logical_cpus": os.cpu_count()}
    if os.name == "nt":
        import ctypes
        class Memory(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [
                (name, ctypes.c_ulonglong) for name in
                ("physical", "available", "page", "available_page", "virtual", "available_virtual", "extended")]
        memory = Memory(); memory.length = ctypes.sizeof(memory)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
            result["physical_memory_bytes"] = memory.physical
    return result


def require_idle_engine(engine):
    if os.name == "nt":
        listing = subprocess.check_output(["tasklist", "/FI", "IMAGENAME eq " + engine.name,
            "/FO", "CSV", "/NH"], text=True, errors="replace")
        if any(row and row[0].casefold() == engine.name.casefold() for row in csv.reader(listing.splitlines())):
            raise RuntimeError("Factorio is already running. Finish the other engine run before this benchmark; no process was stopped.")


def inject(control):
    tick = "  Sampler.on_tick(e.tick)"
    auto = "script.on_nth_tick(UI_REFRESH_EVERY, function() UI.auto_refresh() end)"
    if control.count(tick) != 1 or control.count(auto) != 1:
        raise RuntimeError("Control hooks changed; inspect and update the private benchmark injection")
    init = "script.on_init(function() setup(true) end)"
    if control.count(init) != 1:
        raise RuntimeError("Control initialization hook changed")
    control = control.replace(init, "script.on_init(function() TransportBench.init(); setup(true) end)")
    for event in ("on_player_created", "on_player_joined_game"):
        needle = "script.on_event(defines.events." + event + ", function(e)"
        if control.count(needle) != 1:
            raise RuntimeError("Control player hook changed: " + event)
        control = control.replace(needle, needle + "\n  TransportBench.build_ready()")
    return 'local TransportBench=require("scripts.transport_benchmark")\n' + control.replace(
        tick, "  TransportBench.tick(UI)\n" + tick).replace(
        auto, "script.on_nth_tick(UI_REFRESH_EVERY, function() TransportBench.before_auto(); "
        "UI.auto_refresh(); TransportBench.after_auto(UI) end)")


def function_block(source, header):
    matches = list(re.finditer(r"(?ms)^" + re.escape(header) + r"\r?\n.*?^end(?:\r?\n|$)", source))
    if len(matches) != 1:
        raise RuntimeError("Expected one top-level function: " + header)
    return matches[0].group()


def f6_baseline_source(source, original):
    for header in ("local function add_into(dst, src)", "function Sm.on_stats(tick)"):
        source = source.replace(function_block(source, header), function_block(original, header), 1)
    return source


def original_sampler():
    return subprocess.check_output(["git", "-c", "safe.directory=" + ROOT.as_posix(), "show",
        F6_BASELINE_COMMIT + ":mod/production-flow/scripts/sampler.lua"], cwd=ROOT, text=True, encoding="utf-8")


def install(stage, args, mode, baseline=False, opened=False):
    target = stage / "mods/production-flow"
    shutil.copytree(stage / "source-snapshot", target, dirs_exist_ok=True)
    shutil.copyfile(stage / "harness/transport_query_fixture.lua", target / "scripts/transport_query_fixture.lua")
    (target / "scripts/transport_benchmark.lua").write_text(HOOK, encoding="utf-8")
    # JSON strings/numbers/booleans are also valid Lua literals for these fields.
    config = dict(mode=mode, baseline=baseline, baseline_f2=args.baseline_fixes in ("combined", "f2"),
                  baseline_fixes=args.baseline_fixes, open=opened, ticks=args.ticks,
                  period=args.period_seconds, tab=args.open_tab, renderer=args.renderer)
    (target / "scripts/transport_benchmark_config.lua").write_text(
        "return {" + ",".join(k + "=" + json.dumps(v) for k, v in config.items()) + "}\n", encoding="utf-8")
    (target / "control.lua").write_text(inject((stage / "source-snapshot/control.lua").read_text(encoding="utf-8")), encoding="utf-8")
    if baseline and args.baseline_fixes in ("combined", "f6"):
        sampler = target / "scripts/sampler.lua"
        sampler.write_text(f6_baseline_source(sampler.read_text(encoding="utf-8"),
            (stage / "harness/sampler-f6-baseline-original.lua").read_text(encoding="utf-8")), encoding="utf-8")
    return source_hashes(target)


def execute(stage, engine, arguments, label, timeout, marker=None, save=None):
    logfile = stage / (label + ".log")
    if logfile.exists():
        raise FileExistsError("Preserve earlier evidence: " + str(logfile))
    command = [str(engine), "--config", str(stage / "config.ini"), "--mod-directory", str(stage / "mods"),
               *map(str, arguments)]
    if arguments == ['--version']:
        command = [str(engine), '--version']
    (stage / (label + ".command.json")).write_text(json.dumps(command, indent=2), encoding="utf-8")
    startup = None
    if os.name == "nt":
        startup = subprocess.STARTUPINFO(); startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow = 0
    with logfile.open("w", encoding="utf-8") as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, startupinfo=startup,
                                   env=dict(os.environ, SteamAppId="427520", SteamGameId="427520"))
        process_record = {"pid": process.pid, "command": command, "label": label,
                          "started_utc": datetime.now(timezone.utc).isoformat()}
        (stage / (label + ".process.json")).write_text(json.dumps(process_record, indent=2), encoding="utf-8")
        stop_reason = "process-exit"
        def read_output():
            contents = logfile.read_text(encoding="utf-8", errors="replace")
            # Native log() may be buffered on stdout while the graphical client
            # runs. Its stage-local engine log has immediate build progress.
            current = stage / "factorio-current.log"
            if marker and current.is_file():
                contents += "\n" + current.read_text(encoding="utf-8", errors="replace")
            return contents
        try:
            deadline = time.monotonic() + timeout
            while process.poll() is None:
                if (stage / "STOP").exists():
                    stop_reason = "STOP-requested"
                    raise RuntimeError("STOP requested for owned benchmark process: " + str(stage))
                contents = read_output()
                if "Error while" in contents or "Error ModManager" in contents:
                    raise RuntimeError(contents[-6000:])
                if marker and marker in contents and "Saving finished" in contents and save and save.is_file():
                    stop_reason = "fixture-save-complete"
                    return contents
                if time.monotonic() >= deadline:
                    stop_reason = "timeout"
                    raise TimeoutError(str(logfile))
                time.sleep(0.5)
            contents = read_output()
            if process.returncode or marker and marker not in contents:
                raise RuntimeError(contents[-6000:])
            return contents
        except BaseException:
            if stop_reason == "process-exit": stop_reason = "exception-or-cancellation"
            raise
        finally:
            # Terminate only the process this call owns, including build mode
            # after its completed autosave and on cancellation/timeouts.
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait(timeout=15)
            process_record.update(stopped_utc=datetime.now(timezone.utc).isoformat(),
                                  stop_reason=stop_reason, returncode=process.returncode)
            (stage / (label + ".stopped.json")).write_text(json.dumps(process_record, indent=2), encoding="utf-8")


def metrics(samples):
    result = {}
    for column in ("wholeUpdate", "scriptUpdate"):
        values = sorted(row[column] for row in samples)
        if not values:
            raise RuntimeError("No steady-state timing samples")
        result[column] = {"mean_ms": statistics.mean(values), "p95_ms": values[int((len(values)-1)*.95)],
                          "p99_ms": values[int((len(values)-1)*.99)], "max_ms": max(values), "samples": len(values),
                          "above_16_67_ms": sum(value > 16.67 for value in values)}
    return result


def parse_timings(contents, expected_ticks, expected_runs):
    """Verbose update values are nanoseconds; discard 300 rows of each run."""
    columns = None
    runs = []
    current = []
    previous_tick = None
    for line in contents.splitlines():
        if line.startswith("tick,"):
            if current:
                runs.append(current); current = []
            columns = next(csv.reader([line])); previous_tick = None
            continue
        if columns and re.match(r"^t\d+,", line):
            row = next(csv.reader([line])); tick = int(row[0][1:])
            if previous_tick is not None and tick <= previous_tick:
                runs.append(current); current = []
            current.append({name: float(row[columns.index(name)]) / 1e6 for name in ("wholeUpdate", "scriptUpdate")})
            previous_tick = tick
    if current:
        runs.append(current)
    if len(runs) != expected_runs or any(len(run) != expected_ticks for run in runs):
        raise RuntimeError("Incomplete verbose samples: " + str([len(run) for run in runs]))
    steady = [run[WARMUP:] for run in runs]
    return {"steady_state": metrics([row for run in steady for row in run]),
            "per_run": [metrics(run) for run in steady], "excluded_initial_updates_per_run": WARMUP}


def prepare(stage, args):
    (stage / "mods").mkdir(parents=True)
    (stage / "harness").mkdir()
    shutil.copyfile(FIXTURE, stage / "harness/transport_query_fixture.lua")
    shutil.copyfile(__file__, stage / "harness/transport_benchmark.py")
    (stage / "harness/sampler-f6-baseline-original.lua").write_text(original_sampler(), encoding="utf-8")
    shutil.copytree(SOURCE, stage / "source-snapshot", ignore=shutil.ignore_patterns("tools"))
    (stage / "mods/mod-list.json").write_text(json.dumps({"mods": [{"name": name, "enabled": True}
        for name in ("base", "elevated-rails", "quality", "space-age", "recycler", "production-flow")]}), encoding="utf-8")
    (stage / "config.ini").write_text("[path]\nread-data=" + (args.engine.parents[2] / "data").as_posix()
        + "\nwrite-data=" + stage.as_posix() + "\n[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\n"
        "hide-achievement-popups=true\n", encoding="utf-8")
    (stage / "map-gen.json").write_text(json.dumps({"seed": 20261116, "width": 32, "height": 32,
        "autoplace_controls": {}, "default_enable_all_autoplace_controls": False}), encoding="utf-8")
    install(stage, args, "build")
    execute(stage, args.engine, ["--create", stage / "seed.zip", "--map-gen-settings", stage / "map-gen.json"],
            "create", args.timeout)
    save = stage / "saves" / SAVE_NAME
    execute(stage, args.engine, ["--load-game", stage / "seed.zip", "--disable-audio", "--disable-migration-window",
            "--window-size", "1920x1080", "--force-graphics-preset", "low"], "build", args.timeout,
            marker="TRANSPORT FIXTURE PASS", save=save)
    return save


def offline_check():
    inject((SOURCE / "control.lua").read_text(encoding="utf-8"))
    rows = ["tick,wholeUpdate,scriptUpdate"]
    for run in range(2):
        rows.extend(f"t{i},1000000,250000" for i in range(302))
    parsed = parse_timings("\n".join(rows), 302, 2)
    assert parsed["steady_state"]["wholeUpdate"]["samples"] == 4
    assert parsed["steady_state"]["scriptUpdate"]["mean_ms"] == 0.25
    try:
        parse_timings("\n".join(rows[:-1]), 302, 2)
    except RuntimeError:
        pass
    else:
        raise AssertionError("Incomplete timing samples accepted")
    sys.path.insert(0, str(ROOT / "tests/.runtime"))
    from lupa.lua52 import LuaRuntime
    lua = LuaRuntime()
    baseline_sampler=f6_baseline_source((SOURCE / "scripts/sampler.lua").read_text(encoding="utf-8"), original_sampler())
    for name, code in (("private hook", HOOK), ("fixture", FIXTURE.read_text(encoding="utf-8")),
                       ("F6 baseline sampler", baseline_sampler)):
        lua.eval("function(s,n) assert(load(s,n)) end")(code, name)
    for opened in (False, True):
        for baseline in (False, True):
            mocked = LuaRuntime()
            mocked.globals().opened = opened; mocked.globals().baseline = baseline
            mocked.execute(r'''
              local config={mode="benchmark",ticks=1000,period=60,tab="balance",renderer="poly",
                open=opened,baseline=baseline,baseline_f2=true,baseline_fixes="combined"}
              local fixture={attach=function()end,refresh=function()end,full_retention_baseline=function()end}
              local events={};for i=1,24 do events[i]={} end
              local transport={query=function()return{events=events}end,
                history=function()return{records={{},{},{},{}}}end}
              package.loaded["scripts.transport_query_fixture"]=fixture
              package.loaded["scripts.transport_benchmark_config"]=config
              package.loaded["scripts.transport_flows"]=transport
              package.loaded["scripts.sankey_ui"]={balance_state=function(us)us.bal_fx={};return us.bal_fx end}
              package.loaded["scripts.sampler"]={coverage=function()return 60 end}
              package.loaded["scripts.canvas"]={}
              script={active_mods={}};settings={global={},startup={},get_player_settings=function()return{}end}
              helpers={table_to_json=function()return "{}" end}
              messages={};log=function(message)messages[#messages+1]=message end
              storage={transport_benchmark={surface=1,counts={},stats_surfaces={}},ui={},stat_last={},
                transfers={boundary_observations={count=32768}}}
              for i=1,10 do storage.stat_last[i]={};storage.transport_benchmark.stats_surfaces[i]=i end
              local player={index=1,force={},connected=false}
              game={tick=10000,players={player},surfaces={[1]={name="A"},["ssk-canvas"]={index=11}}}
              UI={close=function(p)p.open=false end,is_open=function(p)return p.open end,
                open=function(p)p.open=true;transport.query()end,
                refresh=function(p,only_auto)assert(p.open and only_auto);transport.query()end}
            ''')
            mocked.globals().Benchmark = mocked.execute(HOOK)
            mocked.execute('for i=1,1000 do game.tick=10000+i;Benchmark.tick(UI); '
                'if game.tick%300==0 then Benchmark.before_auto();Benchmark.after_auto(UI) end end; '
                'assert(#messages==2 and string.find(messages[2],"TRANSPORT BENCH PASS",1,true))')
    previous = Path.cwd()
    try:
        os.chdir(SOURCE)
        lua.execute('script={active_mods={["space-age"]="2.1.24"}}; '
            'defines={events={on_cargo_pod_finished_ascending=1,on_cargo_pod_finished_descending=2,'
            'on_cargo_pod_delivered_cargo=3}};storage={}; force={valid=true,index=1}; '
            'a={valid=true,index=1,name="A"};b={valid=true,index=2,name="B"}')
        fixture = lua.execute(FIXTURE.read_text(encoding="utf-8"))
        reloaded_fixture = lua.execute(FIXTURE.read_text(encoding="utf-8"))
        # Factorio permits require only while parsing control/modules. Load
        # every module first, then enforce that contract for runtime methods.
        lua.execute('F=require("scripts.transport_flows"); '
            'require=function(name) error("Runtime require is prohibited: "..name) end; '
            'local ok,err=pcall(require,"scripts.transfers"); '
            'assert(not ok and string.find(err,"Runtime require is prohibited",1,true))')
        fixture.seed(lua.globals().force, lua.globals().a, lua.globals().b, 10000)
        # A freshly loaded fixture must attach without regenerating canonical data.
        fixture = reloaded_fixture; fixture.attach(); fixture.refresh(50000)
        lua.execute('q=F.query(force,a,50000,60); '
                    'assert(#q.events==24); h=F.history(force,a,50000,60);assert(#h.records==4)')
        fixture.full_retention_baseline()
        lua.execute('local q2=F.query(force,a,50000,60);assert(#q2.events==#q.events); '
            'for i,event in ipairs(q.events) do assert(event.key==q2.events[i].key and '
            'event.delta==q2.events[i].delta and event.tick==q2.events[i].tick) end')
    finally:
        os.chdir(previous)
    print("PASS offline closed/open baseline/candidate hooks, complete/per-run timing parser, saved-fixture attach/refresh and baseline event equivalence")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    parser.add_argument("--ticks", type=int, default=40000)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=1800, help="Seconds per owned engine process")
    parser.add_argument("--open-tab", choices=("balance", "sankey"), default="balance")
    parser.add_argument("--renderer", choices=("poly", "sprite"), default="poly")
    parser.add_argument("--period-seconds", type=int, choices=(60,), default=60)
    parser.add_argument("--baseline-fixes", choices=("combined", "f2", "f6"), default="combined",
                        help="Combined F2 transfer query + F6 empty statistics baseline, or isolate one fix")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--offline-check", action="store_true")
    args = parser.parse_args()
    if args.offline_check:
        offline_check(); return
    if args.ticks <= WARMUP or args.runs < 1 or args.timeout < 1:
        parser.error("Require ticks > 300, runs >= 1 and timeout >= 1")
    if args.period_seconds != 60:
        parser.error("The current four-shipment selected-window fixture requires --period-seconds 60")
    args.engine = args.engine.resolve()
    if not args.engine.is_file():
        parser.error("Factorio executable does not exist")
    require_idle_engine(args.engine)
    stage = ROOT / "tests/out" / datetime.now().strftime("transport-benchmark-%Y%m%d-%H%M%S-%f")
    stage.mkdir(parents=True)
    print("Stage: " + str(stage), flush=True)
    guard = profile_guard()
    report = {"created_utc": datetime.now(timezone.utc).isoformat(), "hardware": hardware(),
              "engine": str(args.engine), "engine_sha256": sha256(args.engine),
              "parameters": {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
              "live_profile_before": guard, "benchmarks": [], "limitations": [
                  "Synthetic near-cap transfer ledger, ten real empty surfaces and internal ssk-canvas; not working-factory performance.",
                  "Baseline selection " + args.baseline_fixes + ": combined restores F2 full-retention queries plus F6 on_stats/add_into from immutable " + F6_BASELINE_COMMIT + "; combined effects are not separately attributed.",
                  "Closed/open runs use the same saved map and frozen source snapshot; GUI construction runs for a disconnected saved player.",
                  "Verbose wholeUpdate/scriptUpdate measure simulation/script costs, not rendering FPS or ordinary game speed.",
                  "First 300 updates excluded per repetition; rare scheduler/OS outliers remain visible in maximums."]}
    try:
        version = execute(stage, args.engine, ["--version"], "engine-version", 60)
        report["engine_version"] = version.strip()
        report["f6_baseline_commit"] = F6_BASELINE_COMMIT
        save = prepare(stage, args)
        report["save"] = str(save); report["save_sha256"] = sha256(save)
        report["source_sha256"] = source_hashes(stage / "source-snapshot")
        report["harness_sha256"] = source_hashes(stage / "harness")
        report["config_sha256"] = sha256(stage / "config.ini")
        report["mod_list_sha256"] = sha256(stage / "mods/mod-list.json")
        report["seed_sha256"] = sha256(stage / "seed.zip")
        if args.build_only:
            report["status"] = "fixture-built"
            return
        for opened in (False, True):
            # Reverse pair order in the open case to reduce order/warm-cache bias.
            for baseline in ((True, False) if not opened else (False, True)):
                label = ("open-" + args.open_tab if opened else "closed") + ("-baseline" if baseline else "-candidate")
                installed = install(stage, args, "benchmark", baseline=baseline, opened=opened)
                print("Benchmark " + label, flush=True)
                contents = execute(stage, args.engine, ["--benchmark", save, "--benchmark-ticks", args.ticks,
                    "--benchmark-runs", args.runs, "--benchmark-verbose", "all"], label, args.timeout)
                markers = re.findall(r"TRANSPORT BENCH PASS (\{.*\})", contents)
                settings = re.findall(r"TRANSPORT BENCH SETTINGS (\{.*\})", contents)
                if len(markers) != args.runs or len(settings) != args.runs:
                    raise RuntimeError("Missing explicit native PASS/settings markers in " + label)
                entry = dict(label=label, baseline=baseline, open=opened, log=str(stage / (label + ".log")),
                             installed_source_sha256=installed, native_pass=[json.loads(x) for x in markers],
                             settings=[json.loads(x) for x in settings], **parse_timings(contents, args.ticks, args.runs))
                report["benchmarks"].append(entry)
                if sha256(save) != report["save_sha256"]:
                    raise RuntimeError("Source fixture save changed during benchmarking")
                (stage / "results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        report["comparisons"] = {}
        for opened in (False, True):
            baseline, candidate = [next(row for row in report["benchmarks"] if row["open"] == opened and row["baseline"] == flag)
                                   for flag in (True, False)]
            report["comparisons"]["open" if opened else "closed"] = {name: {
                "candidate_minus_baseline_mean_ms": candidate["steady_state"][name]["mean_ms"]-baseline["steady_state"][name]["mean_ms"],
                "baseline_mean_ms": baseline["steady_state"][name]["mean_ms"],
                "candidate_mean_ms": candidate["steady_state"][name]["mean_ms"]} for name in ("wholeUpdate", "scriptUpdate")}
        report["status"] = "PASS"
    except BaseException as error:
        report["status"] = "FAILED"; report["error"] = str(error)
        raise
    finally:
        after = profile_guard(); report["live_profile_after"] = after
        report["live_profile_unchanged"] = guard == after
        if report.get("save"):
            report["source_save_unchanged"] = sha256(Path(report["save"])) == report["save_sha256"]
        if guard != after:
            report["status"] = "FAILED"; report["profile_guard_error"] = "Live profile settings/save/mod archive hashes changed"
        (stage / "results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print("Results: " + str(stage / "results.json"), flush=True)
        if guard != after and sys.exc_info()[0] is None:
            raise RuntimeError(report["profile_guard_error"])


if __name__ == "__main__":
    main()
