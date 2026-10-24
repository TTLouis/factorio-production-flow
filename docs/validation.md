# Unreleased: configurable stock cooldown

The development branch has not been published or version-bumped.

Chest sampling waits for a configurable interval after a completed scan before
starting another: a runtime-global map setting, minimum 1 minute and default 5.
The longer benchmark below uses the five-minute default. The 32-entry-per-tick budget is retained.
This prevents back-to-back scans even when a full scan takes longer than the old
10-second interval. Balance shows the stock sample age separately from its
five-second production-rate refresh. The stock trend uses up to seven completed
samples, normally about 30 minutes and longer for large scans.

A deterministic test asserts that no scan can begin during the five-minute rest
period, and that scan state survives initialization. The same mixed-quality
native Space Age stock audit and updated Balance/help/scroll views are rechecked.
A native settings check additionally verifies the five-minute default, changes
between 1 and 5 minutes through the real setting-change event, and retention of
an in-flight scan. Unit tests cover the 1-minute minimum declaration and live
rescheduling in both directions.
The changelog explicitly records these performance changes and the stress testing.
The short description is revised independently of the runtime measurements.

## Longer benchmark

Same i7-13700H / Windows 11 / Factorio 2.1.23 setup as the earlier report below.
The 50,000-chest fixture (2.4 million randomized stacks) is reused, plus its
seed world's starting container. Four variants compare stock enabled/disabled
with the window closed or Balance/Everything open. Each variant runs 3 x 40,000
updates, excluding the first 300 of each repetition: 119,100 measured updates.
The longer window includes multiple stock-scan cycles. The native hook asserts
that consecutive completed scans are never less than five game minutes apart.
Completions occurred at ticks 3,126 and 22,688 in each repetition: 19,562 ticks
apart, about 5 minutes 26 seconds, including scan time.

All values below are milliseconds per update. Baselines retain the rest of the
mod and only disable the new stock tick. Measurements are hardware-specific and
include normal scheduling, caching and garbage-collection variation.

| 50,000-chest case | Baseline mean | Stock mean | Stock p99 | Stock maximum | Script mean delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| Closed window | 0.154 | 0.241 | 1.415 | 7.475 | 0.083 |
| Open Balance / Everything | 0.187 | 0.280 | 2.164 | 19.243 | 0.085 |

The 60 UPS budget is 16.67 ms per update. Means and p99 stayed well below that
budget; the largest open-window outlier was 19.243 ms (baseline maximum 14.703 ms).
This is not a rendering-FPS measurement or a guarantee of hitch-free play. The
measured closed-window stock-script overhead is about 0.083 ms/update, compared
with about 0.923 ms in the earlier high-cadence 0.1.2 test below. Individual active
scan ticks still perform the same bounded work; the cooldown reduces average load.

Local evidence: `tests/out/stock-cooldown-20261024/results.json` and raw native
logs with completion timestamps. Stock and Balance source hashes match the
benchmarked code. A subsequent help-text punctuation correction does not affect
those paths; final native captures use the packaged help text.

# Beta 0.1.2 validation

Ordinary and logistic chest stock, in-game wording, and the Balance refresh fix
passed the full Lua regression suite and 19 offline publishing checks. Native
Factorio 2.1.23 tests used an isolated Space Age copy; the original save and live
profile hashes remained unchanged. The 600-second production history survived
reload. Updated Balance, grouping/scrolling, help and warm-up captures are in the
[screenshot gallery](screenshots/index.html). Full Sankey/Focus examples retained
from 0.1.1 cover unchanged views.

The native stock audit found 3,144 existing containers. A separate no-network
fixture verified all eight wooden/iron/steel/logistic chest prototypes with mixed
qualities: 108 steel plates counted exactly. The offline suite additionally covers
force/surface scopes, deduplication, invalid/removal/build handling during a scan,
32-entry budgets, completed scans only, saving mid-scan, baseline migration,
known zero/unavailable stock and stock-only Balance rows.

## UPS measurements

Windows 11, Intel Core i7-13700H, Factorio 2.1.23 with bundled Space Age mods.
Dedicated seed 20261024 maps contain 1,000 / 10,000 / 50,000 chests, each with 48
distinct randomized item stacks, randomized quantities and five qualities selected
from 210 visible, non-spoiling item types. Six chest types are mixed, without
roboports or inserters. All per-item totals were verified before saving. The
largest map contains 2.4 million stacks; scans take 1,563 ticks (26.05 game seconds)
at the fixed 32-entry budget. Smaller maps still start scans about every 10 seconds.

Each paired benchmark reloads the identical save, enabling/disabling only the new
stock tick while retaining the rest of the mod. Three repetitions of 3,600 ticks
per variant; the first 300 updates of each repetition are excluded from these
steady-state figures (9,900 measured updates per variant). Values are milliseconds
per simulation update. The script delta includes stock work and its Lua allocation
cost; total update differences also include scheduling/cache/thermal noise.

| Closed-window case | Baseline mean | Stock enabled mean | Enabled p99 | Script mean delta |
| --- | ---: | ---: | ---: | ---: |
| chests-1000 | 0.198 | 0.247 | 2.348 | 0.054 |
| chests-10000 | 0.186 | 0.807 | 3.594 | 0.524 |
| chests-50000 | 0.180 | 1.279 | 5.090 | 0.923 |
| space-age | 3.535 | 3.960 | 7.183 | 0.054 |

At 50,000 full chests, open Balance/Everything averaged 1.449 ms per update
(p99 5.849 ms). The 60 UPS budget is 16.67 ms; this is simulation/GUI script
headroom, not a promise about rendering FPS or other hardware. Isolated maxima
crossed that budget: 18.888 ms on the largest open stress run versus 17.096 ms in
its baseline. The working Space Age factory also had long outliers in both
variants (open: 188.810 ms enabled / 159.807 ms baseline), so averages alone must
not be read as a guarantee of hitch-free play. Its enabled open-window p99 was
7.034 ms. These runs cover one machine and save; broader performance testing
remains useful.

The test exposed an independent Balance refresh issue: retrieving `table.children`
inside every cell loop copied roughly 2.5 million GUI element references for 200
rows. Caching the children once per table reduced the 1,000-chest open-window
mean from 3.803 to 0.252 ms, and the observed maximum from 1,245.219 to 10.907 ms
in these runs. Timings are observed measurements, not deterministic upper bounds.

Run the [documented stress harness](development.md#chest-stock-and-ups-stress-tests)
to repeat the checks. Local evidence is under `tests/out/stock-stress-20261024-013150`
(`results.json`, raw native verbose logs, fixture totals and generated saves) and
`tests/out/save-test-20261023-233322-790435` (phase-specific source/image manifests).
Test hooks are excluded from the release archive.

Candidate `production-flow_0.1.2.zip` SHA256:
`3e664bdc07a5a56fa6f75cafbb928c28af1fa9c8af39ed53b42d347a0e84afe5`.

## Earlier 0.1.1 evidence

- Full Lua syntax and offline regression suite passed, including sampling,
  history, responsive widths, selection retention and all three chart views.
- Native Factorio 2.1.23 on an isolated Space Age save: 600 seconds of newly
  recorded Production Flow history survived save/reload.
- 20 Full Sankey/Focus/Balance cases, seven Balance scroll/group cases, and two
  focused copper naming/preset checks passed.
  Native checks retain the same selector controls across live refresh and keep
  hovered node elements valid. They invoke GUI handlers; they do not simulate
  physically opening every dropdown with a mouse.
- Review screenshots are native engine captures. Incidental tooltip
  popups are suppressed by the test harness after tooltip assertions, so they
  do not cover the charts. Game data and drawings are otherwise unchanged.
- Original save and live mod/configuration files retained their input hashes.
- The installable ZIP includes the MIT license and excludes injected test hooks.

Live updates retain the visible Balance rows and their order. Refresh/filter
changes reapply membership and sorting. Rows leaving the measurement window show
Inactive with zero rates until refresh, rather than retaining stale numbers.

Broader modpack, multiplayer and large-factory performance testing remains open.

Individual item/fluid names are now the default. A one-time migration replaces
the unpublished grouped default; later deliberate grouped-view selections persist.
The view picker explicitly marks grouping as unfinished. Regression checks cover
defaults, migration, persistence, and absence of aggregate nodes in the plain view.
Native copper-chain checks cover Vulcanus and a space platform.

### Usability and stored stock

The 0.1.1 offline suite also covers reservation and quality correction, old stock
baseline reset, warm-up indication, the built-in question-mark action, hidden
developer controls, stable help across refresh/Escape and explicit Update list.

Native Space Age cases cover fresh installation/warm-up, stored stock audit,
all three chart views, vertical-only Balance scrolling/groups, producing recipe
names and all three help tabs. The harness records phase-specific image hashes
against the clean candidate archive; injected save-test hooks are excluded from
that archive. Tests call GUI event handlers and render through the native engine;
physical mouse interaction with every dropdown is not simulated.

For 11 negative item/quality entries in the save, corrected network stock equalled
physical provider/storage inventory across all qualities. For example, Nauvis
steel showed -3 available, with 104 reserved for pickup and 101 physically stored.
The correction adds back reservations; it does not simply hide the negative value.
Duplicate owners in provider/storage lists are counted once. The old stock
baseline is cleared on upgrade to avoid a false stock trend. A defensive zero
fallback logs any remaining negative corrected count; none occurred in this audit.

Fresh-install defaults are tested in a separate private mod directory so older
saved export settings cannot override the new default. Existing preferences are
preserved. Original saves and the live Factorio profile retain their input hashes.

### Public release and publishing automation

Production Flow 0.1.1 is published at https://mods.factorio.com/mod/production-flow.
The installable ZIP on GitHub and the Mod Portal has SHA256
`934cc0a60a9dd1e264a148adcff6e18aa749207187058c7a735a035468c75c16`.
Its only addition to the native-tested archive is the 512px thumbnail rendered
from the existing toolbar icon's curves. The previous runtime files are unchanged.

Eighteen offline publishing checks cover source/version and archive validation,
checksum mismatches, credential separation, first publication, existing-version
reruns, partial page-update recovery and eventual public-metadata consistency.
Text validation permits only CRLF/LF differences from Git checkout normalization;
binary assets must match exactly. The original release archive is uploaded intact.

[GitHub Actions run 40065531645](https://github.com/TTLouis/factorio-production-flow/actions/runs/40065531645)
passed tagged-source Lua tests, publishing tests, archive validation and the live
publication/synchronization job. The public page was also checked in a browser:
Utilities category, no gameplay-feature tags, MIT license, 0.1.1 download, six
loaded screenshots and the correct icon. GitHub topics were not changed.
