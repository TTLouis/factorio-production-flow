# Development and native validation

Install `requirements-dev.txt`, then run `python tests/run_lua.py`.
The offline suite uses synthetic data and does not need a Factorio installation.

Optional native checks (Windows, a local licensed Factorio installation required):

```powershell
python tests/engine_smoke.py "C:/path/to/Factorio/bin/x64/Factorio.exe"
python tests/save_test.py --exe "C:/path/to/Factorio/bin/x64/Factorio.exe" --save "C:/path/to/your-space-age-save.zip"
```

The save runner copies a Space Age save using only bundled mods, records at least
600 seconds of history, and takes native screenshots. Original save/profile hashes
are checked. The isolated stage is under `tests/out/`. Reuse the returned stage
with `--stage tests/out/<stage> --phase full` or `--phase scroll`.

The prototype rename to production-flow makes it a separate mod from the old
unpublished signal-sankey experiments. Do not enable both in the same test.
History from the experimental mod is not migrated; the beta collects new history.

Replay tools require your own diagnostic exports. Private development fixtures
under tests/data are deliberately not included in the repository.

Build with `python tools/build.py`. It reads the name/version from info.json,
packages a single matching root directory, includes LICENSE and changelog.txt,
and excludes development tools. Public publishing is a separate manual step.
