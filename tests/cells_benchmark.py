"""Paired native UPS benchmark: the same save without cells and with every machine in two cells.

Uses an isolated profile and a private copy of the save; the source save and the
live Factorio profile are never written. Runs are sequential and alternate order
(baseline, cells, cells, baseline, ...) to reduce warm-cache bias. Steady-state
metrics drop the first 300 updates of each run, as in stock_stress.py.
"""
import argparse
import csv
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mod/production-flow"
MODS = ["base", "elevated-rails", "quality", "space-age", "recycler", "production-flow"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def install(stage, cells, size, overlap, limit):
    # Every run installs from the snapshot taken at start, so edits made to the
    # checkout during a long benchmark cannot mix sources between runs.
    target = stage / "mods/production-flow"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(stage / "source/production-flow", target)
    shutil.copyfile(stage / "source/cells_benchmark.lua", target / "scripts/cells_benchmark.lua")
    (target / "scripts/cells_benchmark_config.lua").write_text(
        f"return {{cells={str(cells).lower()},size={size},overlap={str(overlap).lower()},limit={limit}}}\n",
        encoding="utf-8")
    control = target / "control.lua"
    text = control.read_text(encoding="utf-8")
    needle = "  Sampler.on_tick(e.tick)"
    assert text.count(needle) == 1
    control.write_text('local CellBench = require("scripts.cells_benchmark")\n' +
                       text.replace(needle, "  CellBench.tick()\n" + needle), encoding="utf-8")


def run(exe, stage, save, label, ticks, runs, marker):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    log = stage / f"{label}.log"
    command = [str(exe), "--config", str(stage / "config.ini"), "--mod-directory", str(stage / "mods"),
               "--benchmark", str(save), "--benchmark-ticks", str(ticks), "--benchmark-runs", str(runs),
               "--benchmark-verbose", "all", "--disable-audio"]
    with log.open("w", encoding="utf-8") as output:
        p = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, startupinfo=startup,
                             env=dict(os.environ, SteamAppId="427520", SteamGameId="427520"))
        try:
            p.wait(timeout=1800)
        finally:
            if p.poll() is None:
                p.terminate()
                p.wait(timeout=30)
    text = log.read_text(encoding="utf-8", errors="replace")
    if p.returncode or "Error while" in text or text.count(marker) < runs:
        raise RuntimeError(f"{label} failed (exit {p.returncode}); see {log}\n" + text[-3000:])
    samples, columns = [], None
    for line in text.splitlines():
        if line.startswith("tick,"):
            columns = next(csv.reader([line]))
        elif columns and re.match(r"^t\d+,", line):
            row = next(csv.reader([line]))
            if int(row[0][1:]) >= 300:
                samples.append({name: float(row[columns.index(name)]) / 1e6 for name in ("wholeUpdate", "scriptUpdate")})
    metrics = {}
    for name in ("wholeUpdate", "scriptUpdate"):
        values = sorted(s[name] for s in samples)
        metrics[name] = {"mean_ms": statistics.mean(values), "p95_ms": values[int((len(values) - 1) * .95)],
                         "p99_ms": values[int((len(values) - 1) * .99)], "max_ms": max(values), "samples": len(values)}
    setup = re.findall(r"CELL BENCH [A-Z]+: [^\r\n]*", text)
    return {"label": label, "steady_state": metrics, "setup": setup[:1], "log": str(log),
            "engine_results": [dict(zip(["avg_ms", "min_ms", "max_ms"], map(float, row)))
                               for row in re.findall(r"avg: ([\d.]+) ms, min: ([\d.]+) ms, max: ([\d.]+) ms", text)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--save", type=Path, required=True)
    parser.add_argument("--exe", type=Path, default=Path("D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe"))
    parser.add_argument("--ticks", type=int, default=7200)
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--pairs", type=int, default=2)
    parser.add_argument("--size", type=int, default=20, help="Machines per small cell")
    parser.add_argument("--no-overlap", action="store_true", help="Omit the per-surface cell, so no machine is shared")
    parser.add_argument("--limit", type=int, default=0, help="Maximum number of small cells (0 = all)")
    args = parser.parse_args()
    stage = ROOT / "tests/out" / datetime.now().strftime("cells-bench-%Y%m%d-%H%M%S")
    (stage / "mods").mkdir(parents=True)
    print(stage, flush=True)
    (stage / "mods/mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in MODS]}))
    (stage / "config.ini").write_text(
        f"[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n"
        "[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n"
        "[sound]\nmaster-muted=true\nmaster-volume=0\n")
    shutil.copytree(SOURCE, stage / "source/production-flow", ignore=shutil.ignore_patterns("tools"))
    shutil.copyfile(ROOT / "tests/cells_benchmark.lua", stage / "source/cells_benchmark.lua")
    save_hash = digest(args.save)
    copy = stage / "bench.zip"
    shutil.copyfile(args.save, copy)
    report = {"save": str(args.save), "save_sha256": save_hash, "ticks": args.ticks, "runs": args.runs,
              "size": args.size, "overlap": not args.no_overlap, "limit": args.limit,
              "engine": subprocess.check_output([str(args.exe), "--version"], text=True),
              "source_sha256": {f.relative_to(stage / "source/production-flow").as_posix(): digest(f)
                                for f in (stage / "source/production-flow").rglob("*") if f.is_file()},
              "fixture_sha256": digest(stage / "source/cells_benchmark.lua"), "benchmarks": []}
    order = []
    for pair in range(args.pairs):
        order += [False, True] if pair % 2 == 0 else [True, False]
    for index, cells in enumerate(order):
        label = f"{index + 1}-{'cells' if cells else 'baseline'}"
        install(stage, cells, args.size, not args.no_overlap, args.limit)
        print(f"Benchmark {label}", flush=True)
        report["benchmarks"].append(run(args.exe, stage, copy, label, args.ticks, args.runs,
                                        "CELL BENCH CELLS" if cells else "CELL BENCH BASELINE"))
        (stage / "results.json").write_text(json.dumps(report, indent=2))
    report["save_unchanged"] = digest(args.save) == save_hash
    (stage / "results.json").write_text(json.dumps(report, indent=2))
    assert report["save_unchanged"]
    for kind in ("baseline", "cells"):
        rows = [b["steady_state"] for b in report["benchmarks"] if b["label"].endswith(kind)]
        for name in ("wholeUpdate", "scriptUpdate"):
            keys = ("mean_ms", "p95_ms", "p99_ms", "max_ms")
            print(kind, name, {k: round(statistics.mean(r[name][k] for r in rows), 4) for k in keys}, flush=True)
    print(f"Results: {stage / 'results.json'}", flush=True)


if __name__ == "__main__":
    main()
