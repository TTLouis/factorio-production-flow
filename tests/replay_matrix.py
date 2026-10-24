"""Compare both real export fixtures across layouts, line styles and renderers."""
import os
from pathlib import Path
import re
import subprocess
import sys

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent
CASES = [
    ("detail", "clean", "metro"), ("detail", "clean", "curves"),
    ("detail", "lanes", "metro"), ("detail", "lanes", "curves"),
    ("focus", "clean", "metro"), ("overview", "clean", "metro"),
    ("inspector", "clean", "curves"), ("inspector-narrow", "clean", "curves"),
]
for surface in ("nauvis", "vulcanus"):
    for view, layout, lines in CASES:
        traces = []
        for renderer in ("sprites", "poly"):
            name = f"{surface}-{view}-{layout}-{lines}-{renderer}"
            out = TESTS / "out" / f"{name}.txt"
            env = os.environ.copy()
            env.update(DATA=f"../../tests/data/rd_{surface}.lua", VIEW=view, LAYOUT=layout,
                       LINES=lines, RENDER=renderer, JOG="1", HEIGHT="sqrt",
                       FOCUS="item/processing-unit" if surface == "nauvis" else "item/tungsten-plate")
            env.update(NEIGHBORHOOD="0", W="3296", H="1060")
            if view.startswith("inspector"):
                env.update(VIEW="focus", NEIGHBORHOOD="1", W="520" if view.endswith("narrow") else "960", H="600")
            result = subprocess.run([sys.executable, str(TESTS / "run_lua.py"),
                                     str(TESTS / "replay.lua"), str(out)],
                                    cwd=ROOT, env=env, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace")
            if result.returncode:
                raise RuntimeError(name + "\n" + result.stdout + result.stderr)
            match = re.search(r"MISALIGNED ports\s+(\d+)", result.stdout)
            assert match and int(match[1]) == 0, name + ": misaligned ports"
            match = re.search(r"HEADER overlaps\s+(\d+)", result.stdout)
            assert match and int(match[1]) == 0, name + ": icons or names overlap node bars"
            if layout == "clean" and not view.startswith("inspector"):
                match = re.search(r"ROUTE HEADER overlaps\s+(\d+)", result.stdout)
                assert match and int(match[1]) == 0, name + ": routed shape enters a reserved header"
            trace = Path(str(out) + ".geometry").read_text(encoding="utf-8")
            assert "PATH|" in trace, name + ": empty drawing"
            traces.append(trace)
        assert traces[0] == traces[1], f"Renderer routes differ: {surface}/{view}/{layout}/{lines}"
        print(f"PASS {surface}/{view}/{layout}/{lines}: matching routes, aligned ports, clear headers", flush=True)
print("REPLAY MATRIX OK: 32 renders / 16 renderer comparisons")
