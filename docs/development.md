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
with `--stage tests/out/<stage> --phase full` or `--phase scroll`. Additional
phases are `ux` (controls and help), `audit` (network reservations versus physical
stored items) and `warmup` (fresh-install defaults and incomplete history).
Phase-specific evidence records native image hashes and the clean archive hash.
Development tabs, exports and renderer comparisons are hidden unless the
per-player **Show development tools** setting is enabled.

The prototype rename to production-flow makes it a separate mod from the old
unpublished signal-sankey experiments. Do not enable both in the same test.
History from the experimental mod is not migrated; the beta collects new history.

Replay tools require your own diagnostic exports. Private development fixtures
under tests/data are deliberately not included in the repository.

Build with `python tools/build.py`. It reads the name/version from info.json,
packages a single matching root directory, includes LICENSE and changelog.txt,
and excludes development tools. Building locally does not publish; the GitHub
release workflow below handles publication.

## Publishing from GitHub

The **Publish Mod Portal** Actions workflow runs when a GitHub release is
published, including beta pre-releases. Ordinary pushes do not publish. The
release tag must be `v` followed by the exact version in `info.json`.

The workflow runs the tagged source's Lua suite and the publisher's offline
tests. If the release already has its installable ZIP, every archive member must
match the tagged mod source. Text permits CRLF/LF line-ending differences from
Windows/Git checkouts; images and other binary files must match byte for byte.
If no ZIP was attached, the workflow builds it and
attaches that same archive to GitHub before uploading it to Factorio. The
512px thumbnail, MIT license, description and screenshots are checked too.

The credential-free validation job passes an archive and checksum manifest to
the publishing job. The Factorio key is available only in the publishing step.
Add `FACTORIO_API_KEY` under repository Settings > Secrets and variables >
Actions, with **ModPortal: Publish Mods**, **ModPortal: Upload Mods** and
**ModPortal: Edit Mods** permissions. Do not commit the key or put it in an issue.

The first run creates the listing; later releases add versions. The page comes
from `docs/mod-portal.md`. Metadata in `tools/mod_portal.json` uses **Utilities**
for QoL/interface functionality, with no gameplay-feature tags. The workflow
uploads the description's six screenshots to Factorio and replaces their inline
links with the portal-hosted URLs. It preserves additional manual gallery images.
GitHub topics are not managed.

Use **Run workflow** on `main` to publish an existing release such as `v0.1.1`.
**Validate only** is checked by default; clear it to publish. A run validates
before publishing and never re-uploads an existing version with the same archive.
A differing archive for the same version stops the run. Interrupted page/gallery
updates can be resumed by running the same release again.

Local publishing checks: `python -m unittest discover -s tests -p publish_test.py -v`.
The tests use synthetic files and mocked APIs, never live credentials. API
contracts: [initial publication](https://wiki.factorio.com/Mod_publish_API),
[release upload](https://wiki.factorio.com/Mod_upload_API),
[page metadata](https://wiki.factorio.com/Mod_details_API), and
[images](https://wiki.factorio.com/Mod_images_API).


## Chest stock and UPS stress tests

`python tests/stock_stress.py --open --save PATH_TO_COPIED_SPACE_AGE_SAVE`
builds isolated 1,000-, 10,000- and 50,000-chest maps, each with 48 randomized
stacks per chest. Seed 20261024 fixes item, quality and quantity selection.
The fixture uses ordinary steel chests plus every logistic chest type, no
logistic networks or inserters, and non-spoiling visible items. It verifies exact
per-item totals before saving. This tests dense inventory reads; it is not a
substitute for a moving, working factory.

The runner compares the same save with the new stock tick enabled and disabled,
while keeping the rest of Production Flow enabled. Each pair runs 3 x 3,600
updates. It records native `--benchmark-verbose all` timings and excludes the
first 300 updates of each repetition from steady-state mean/p95/p99/max.
Closed-window and open Balance/Everything pairs distinguish background sampling
from UI refresh. Benchmark players are disconnected, so the injected test hook
calls the normal five-second UI refresh explicitly. These headless benchmarks
measure simulation/GUI script cost, not rendering FPS. Normal play caps at 60 UPS;
compare update times with the 16.67 ms budget rather than treating uncapped UPS as
a promised game speed. Laptop scheduling, thermals and garbage collection add
noise; isolated maxima are not deterministic upper bounds.

Use `--stage tests/out/stock-stress-TIMESTAMP --benchmark-only --open` to repeat
existing maps. `--capture` records the native Balance list and a chest inventory.
Stage saves, logs, screenshots, source hashes and results stay under `tests/out`.
Test hooks are injected into private mod copies and never included in release ZIPs.
The separate `tests/save_test.py --phase audit` also verifies wooden/iron chests,
all logistic chest types, mixed qualities and no-network stock on a Space Age copy.
