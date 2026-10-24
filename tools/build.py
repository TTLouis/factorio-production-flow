"""Build a local Factorio ZIP. Does not publish or install it."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib
import json
ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "mod/production-flow"
info = json.loads((source / "info.json").read_text())
assert (source / "LICENSE").read_bytes() == (ROOT / "LICENSE").read_bytes()
name = info["name"] + "_" + info["version"]
out = ROOT / "dist" / (name + ".zip")
out.parent.mkdir(exist_ok=True)
with ZipFile(out, "w", ZIP_DEFLATED) as z:
    for p in sorted(source.rglob("*")):
        rel = p.relative_to(source)
        if p.is_file() and "tools" not in rel.parts and "__pycache__" not in rel.parts:
            z.write(p, name + "/" + rel.as_posix())
print(out)
print("SHA256:", hashlib.sha256(out.read_bytes()).hexdigest())
