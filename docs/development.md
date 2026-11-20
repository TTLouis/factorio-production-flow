# Development and native validation

Manufacturing rates, capacity, stock and charts currently support Factorio's
default `player` force. Other-force players cannot open the window. Foreign
machines remain only as candidates in the bounded round-robin registry, so an
observed ownership change can reset the craft-counter baseline before sampling
resumes. The engine exposes no generic entity-force-change event; a round trip
between sampled visits cannot be distinguished from uninterrupted ownership.
Existing historical craft bins have no force identity, so earlier mixed-force
samples cannot be separated retroactively. They are preserved until they age
out; this change does not reset production history.

Install `requirements-dev.txt`, then run `python tests/run_lua.py`.
The offline suite uses synthetic data and does not need a Factorio installation.
The focused suites run separately with `python tests/run_lua.py` followed by
`tests/history_data_test.lua`, `tests/transfers_test.lua` or
`tests/machine_status_test.lua`.

Optional native checks (Windows, a local licensed Factorio installation required):

Keep test and review sessions muted. Automated clients use `--disable-audio`;
interactive isolated profiles set `[sound]` `master-volume=0` and `master-muted=true`.

```powershell
python tests/engine_smoke.py "C:/path/to/Factorio/bin/x64/Factorio.exe"
python tests/save_test.py --exe "C:/path/to/Factorio/bin/x64/Factorio.exe" --save "C:/path/to/your-space-age-save.zip"
```

The save runner copies a Space Age save using only bundled mods, records at least
600 seconds of history, and takes native screenshots. Original save/profile hashes
are checked. The isolated stage is under `tests/out/`. Reuse the returned stage
with `--stage tests/out/<stage> --phase full` or `--phase scroll`. Additional
phases are `ux` (controls and help), `audit` (network reservations versus physical
stored items), `focus` (active and empty Focus flows, both renderers and Back),
`selection` (scrolled Balance row selection before/after captures), `picker` (combined material search, Back/Forward, trail and Clear
history, compact/expanded Balance and Focus controls, framed list headers and
grouped activity counts), `warmup` (fresh-install defaults and incomplete history),
`diagnostics` (Balance sort controls, watches, sampled machine status, preview
zoom and remote view), `history-view` (Balance's Flow and History selector,
material and metric changes, shared time axes, and measured and estimated stock),
`transfer-view` (native cargo arrivals and route and material filters), and
`ribbon-view` (itemised hover details in Balance History, Focus, Full Sankey and Transfers at 100% scale),
and `portal` (Mod Portal gallery images 30–37 from real save data: it records another 20 game
minutes, then picks the busiest real platforms and writes the choice to `portal-platforms.json`).
Phase-specific evidence records native image hashes and the clean archive hash.
Release packages contain Balance with Flow and History, Focus, Full Sankey and
Transfers (when Space Age and its cargo events are available). Local diagnostic and render fixtures live under `tests/development/`.
The native harness
injects its diagnostic helper into an isolated test copy after creating the clean
candidate archive. These helpers and test hooks are excluded from release ZIPs.

GUI changes follow the vanilla button, frame and label rules in
[ui-style.md](ui-style.md).

`python tests/gui_interaction.py` runs a vanilla chart regression using launch
arguments and isolated mod/config copies at 100%, 125% and 150% scale. It checks
native wrapper geometry, ribbon event flags and top/middle/bottom node hit regions
in Balance, Focus and Full Sankey with both renderers, then records screenshots.
Its hit model and separately reported handler dispatches do not constitute engine
mouse input. `--source-ref TAG --expect-obstruction` checks the historical row
obstruction without changing the working checkout. The fixture uses synthetic
vanilla recipe rates; it is not a working-factory or modded-save validation.

`python tests/gui_simulation.py` complements those captures with actual engine
mouse events. A private main-menu simulation captions existing fixed-size chart
icons for lookup, moves Factorio's simulation cursor and clicks through the
normal mod event handler. It checks top/middle/bottom selection in all three
charts with both renderers at configured 100%, 125% and 150% scale. Virtual
simulation players report scale 1, so the test uses a fixed chart panel rather
than asserting full-window sizing; `gui_interaction.py` covers normal windows.
Both runners keep clean candidate archives, source hashes and logs in fresh
ignored stages, and leave the live profile and source saves untouched. The Lua
suite additionally checks Transfer hover geometry, target reuse and hidden
targets at fractional scales, and normal-window native checks cover indexed GUI insertion.

Run `python tests/cells_native.py` to validate manual production cell selection
on a disposable vanilla map. The fixture dispatches registered handlers with
native entities and GUI elements, checks that saving and replacing membership
require confirmation, and captures the draft, saved list, and both Cells
Sankey views at 100% UI scale. It also replaces members in the engine: a
fast-replace upgrade (raised as `script_raised_built`) and a ghost revival
(`script_raised_revive`) must rejoin the cell, and the editor must report the
missing machine in between. The offline `cells_membership_test.lua` covers the
slot index, edit keep/forget, replacement drags, shared slots and deletion.

The Cells tab shows measured throughput by default: the sampler attributes each
member's crafts to its cells from the moment a cell is created, and the chart
uses the selected period, clipped to the cell's age. The Capacity switch shows
every member at full crafting speed. The All view groups cells by surface and
leaves out machines shared by several cells in both modes. The native fixture
powers and feeds its machines, compares the measured cable crafts with the
engine's `products_finished`, and captures the Capacity view. The offline
`cells_measured_test.lua` covers attribution, ring roll-up, creation clipping,
shared exclusion, membership changes, utilisation and purge on delete.

The create and edit forms list the cell's boundary items, suggested from the
members' recipes (net consumption as inputs, net production as outputs). The
player removes items that do not really cross the boundary; saving locks the
rest, and the All view shows only locked items. Cells saved before the lock show
every net flow until they are edited. The All view orders cells into stages from their
boundaries (`Flow.stages`): a cell whose input another cell makes comes one
stage later, the shared item becomes one node between them, and the tab's list
follows the same order. Loops are ordered by creation. Like the other tabs, the Cells tab lists
and charts only the cells on the surface chosen in the window header. Surface
labels use the header picker's localised name and icon, and cell nodes do not
repeat the surface. The saved-cells list's Production Flow button opens the
Cells tab on that cell and switches the header to the cell's surface when it
differs. The Cells tab's list header has New, Edit and Delete buttons, and cells
with missing members carry a warning icon. Flow and Map sub-tabs share the
area beside the list. Map shows the selected cell, or every listed cell for All,
fitted to the members' current positions (never zoomed past 1x); its subheader
has a zoom slider, move buttons, Fit, a remote-view jump and Edit. A player's
zoom and moves are kept per cell until Fit or a surface change. The Flow frame
has a fixed width, so a cell with many tiers scrolls horizontally instead of
running past the window. Guidance lives in the in-game help's Cells topic, not
in chat: picking a selection tool prints nothing, and chat messages are kept
for errors such as a wrong surface or an empty selection.
`cells_ports_test.lua` covers suggestions, removal and restore, locking, the
edit form, the All view filter and the surface scope; `cells_native.lua` checks
the Show button, the tab buttons, the Map tab (centring, zoom, moves, Fit and
the jump), horizontal scrolling of
a wide chart, the empty-surface message and the help topic.

A cell follows machines that are cloned to another surface (Space Exploration
spaceship launches and landings) only when every live member has an eligible
copy on the same new surface and the originals are gone. Copies that leave the
originals in place, partial moves and splits across surfaces keep the cell where
it was. The native fixture clones a cell's machines to a new surface;
`cells_clone_test.lua` covers the wait, copy grace period, partial and split
moves and a source surface deleted in the same tick.

For the sampler cost, run `python tests/cells_benchmark.py --save PATH` on an
authorized save. It snapshots the source, benchmarks a private copy without
cells and with every sampled machine in two overlapping cells, alternating the
order, and reports steady-state update times. `--no-overlap` drops the
per-surface cell and `--limit N` caps the number of small cells for a more
typical layout.

For an authorized modded save, use Factorio's `--sync-mods` with an isolated
`--config` and `--mod-directory` first. Then run
`python tests/modded_gui.py --save PATH --mods SYNCED_MOD_DIRECTORY`.
The default capture is 2560×1440 at 125%. This runner copies the save and selected
mods, adds the current Production Flow source, collects at least 600 seconds of
real production history, and captures the three charts with both renderers.
It accelerates and unpauses only the private copy during warmup, then returns to
normal speed and suppresses other mods' screen dialogs for the captures. Its
evidence identifies actual mod versions and distinguishes native geometry checks
from engine mouse-input tests. Save, profile and source hashes are checked after
the run. Mod synchronization can select newer compatible releases; record those
differences instead of claiming the reporter's original mod set is identical.

Player-facing text follows [localization.md](localization.md). The normal Lua
runner also validates locale keys, parameters and catalog coverage, runs the
validator's Python regression tests, and exercises native LocalisedString shapes
in the Lua UI tests. Native graphical save phases additionally translate every
key and plural test case through Factorio itself. Use `--language zh-CN` with a
fresh stage to validate Simplified Chinese, or `--language zh-TW` for Traditional
Chinese; the default is English. The runner
records the actual client locale and preserves phase-specific screenshots.

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

Before drafting update notes or a mod description, follow the
[release writing guide](release-writing-guide.md). Keep public copy concise and
player-facing; reserve fuller technical explanations for GitHub.

Release history has one editable source: `mod/production-flow/changelog.txt`.
After editing it, run `python tools/changelog.py --write` to regenerate the root
`CHANGELOG.md`, then `python tools/changelog.py --check`. Generate GitHub release
notes with `python tools/changelog.py --release VERSION`; do not maintain separate
release bullets manually. The check verifies the root rendering and the latest
version against `info.json`. Historical engineering detail lives in
[validation.md](validation.md).

Repository hygiene CI runs the check plus the changelog and publisher Python
suites on pushes and pull requests. The publisher checks new release sources,
puts the generated version-specific notes into the verified bundle, and uses them
as the GitHub release body during publication. Older immutable release tags
without this tooling retain their original publication behavior.

Local tooling checks:

```powershell
python tools/changelog.py --check
python -m unittest discover -s tests -p changelog_test.py -v
python -m unittest discover -s tests -p publish_test.py -v
```

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
uploads the description's screenshots to Factorio and replaces their inline
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


For the five-minute cooldown, use at least `--ticks 40000` when checking scan
cadence so a run includes more than one complete cycle. The native hook asserts
that consecutive completed scans are never less than five game minutes apart.
Keep older high-cadence results separately: the per-active-tick budget remains 32,
but long-run average work is reduced by the cooldown after each complete scan.


`python tests/stock_stress.py --stage PATH_TO_EXISTING_STRESS_STAGE --settings-check`
checks the runtime-global setting in the native engine using its existing
1,000-chest fixture. It verifies the default, edits between 1 and 5 minutes,
rescheduling through the real setting-change event, and retention of an active
scan. This is a functional check, not a performance benchmark. Offline tests also
verify the setting declaration (1-minute minimum, 5-minute default), increasing
and decreasing the cooldown, and applying a new interval after a scan finishes.

`python tests/transport_benchmark.py --open-tab balance --baseline-fixes combined`
builds a disposable native save with 32,768 transfer boundaries and ten real
empty surfaces, then compares closed and open Balance cases for three 40,000-update
runs each. Its private baseline restores full-retention transfer queries and the
previous statistics allocation functions; the report names the exact baseline
commit and records source, settings, save and raw timing hashes. This measures
the combined changes, rather than attributing the timing difference to either
change individually. Use `--baseline-fixes f2` or `f6` for isolated comparisons.
`--offline-check` validates fixtures and hooks without launching Factorio.
