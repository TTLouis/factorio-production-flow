# Historical validation and engineering notes

Current release history is maintained in the
[Factorio changelog](../mod/production-flow/changelog.txt) and rendered into the
[root changelog](../CHANGELOG.md). This document preserves historical engineering
detail and measurements; its version-specific results are not current benchmarks.

The former manually maintained root changelog also recorded these details:

- 0.1.4 refactored the shared material picker, Balance calculations and production
  graph internals, and documented the sampler's data structures. First-use Focus
  search was verified with recorded item/fluid flows on Factorio 2.1.24 with Space Age.
- Earlier 0.1.3 cooldown checks used three 40,000-update repetitions with 50,000
  full chests, with Balance open and closed. Completed scans were about 5 minutes
  26 seconds apart. Average stock-script overhead was about 0.08 ms per update on
  the test laptop. These hardware-specific results predate the final 0.1.3 UI.
- 0.1.2 stress fixtures covered 1,000, 10,000 and 50,000 chests, up to 2.4 million
  randomized stacks from 210 item types and five qualities. Exact totals and
  stock-enabled/disabled comparisons were recorded with the original evidence.

# Published 0.1.3

Version 0.1.3 was published on 24 October 2026. The current UI
preview covers selector margins with and without a scrollbar, settings fly-out
bottom spacing, fixed Balance headings and Focus navigation at **100% only**.
See the [UI screenshots](ui-preview-0.1.3.md).

The Lua regression suite and 19 offline publisher tests pass. Native Factorio
2.1.23 checks pass with 25 captures (scroll and picker) at 100%, no skipped cases, and the configuration
event recording **0.1.0 → 0.1.3**. The saved ten-minute history survives the upgrade.
A direct 0.1.2 → 0.1.3 upgrade was not separately exercised.

Published `production-flow_0.1.3.zip` SHA256:
`ca2d586588c681c50a33afa51c8792df1f5531884d5d5fb370d3523a9573e312`

All 31 archive members match the final source. Runtime code and assets match the
native-tested source exactly; only changelog.txt was updated afterward to record
the approved heading and scrollbar refinements. The manifest, LICENSE, changelog
and 512 px thumbnail validate. Test hooks and development tools
are excluded. The six published gallery images match the native captures. Original
save/profile hashes and the published 0.1.2 archive remain unchanged. Following
the approved UI work, development tabs, test commands, export settings, logging
and renderer comparisons were removed from the runtime and validated again.
Standalone helpers remain under `tests/development/` and are injected only into
private test copies. Balance now has one aligned column-heading row and an 8 px
gutter before the scrollbar, checked in normal, Details and grouped views.
The native run asserts that the shipped command/settings
surface contains no development entries and that only three tabs remain.
The final ZIP differs from the native test archive only in changelog.txt and ZIP
entry order; no runtime code changed after native validation. Native harness checks invoke GUI handlers rather than
physically clicking every control.

Release tag `v0.1.3` points to `e190922a61a3d8f855647d02f05105d48df4a2e9`.
The [publishing workflow](https://github.com/TTLouis/factorio-production-flow/actions/runs/40142003898)
passed both validation and publication. The live GitHub ZIP and Mod Portal release
match the approved archive; the live description and six screenshot identifiers
match the approved files. Repository documentation was then updated to identify
0.1.3 as the current public beta. No runtime files or published archive changed.
No fresh UPS benchmark was run for these UI changes; stock measurements below
are historical.

# Configurable stock cooldown — historical measurements

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
logs with completion timestamps. The recorded source hashes identify the code
used for those measurements. Balance UI code has since changed for 0.1.3;
these historical results are not performance measurements of its final UI.

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

## SE surface logistics — 2026-11-13 development candidate

Implemented the cargo-rocket-only SE Logistics view, with importing origins to the left, the selected surface in the center and export destinations to the right. The new bounded ledger retains sent manifests by quality, launch/pad identities and public padless observations separately from Space Age's existing arrival ledger. Received quantities remain unknown; no private SE instrumentation is shipped or treated as a receipt API. Balance, production statistics, cannon/ship accounting and resupply forecasts are outside this first implementation slice.

Validation used Factorio 2.1.24 and installed SE 0.7.64 in a newly generated private map. Three real cargo rocket launches were saved/reloaded in the journey state. The shipping collector retained exact sent amounts, correct directional scope and one padless status; private ground truth did not fill its received fields. For example, the fixture's 1,000 dispatched iron plates became 992 at the landing pad while the public collector correctly continued to report sent 1,000 / received unknown.

The default Lua runner passes provider accounting and UI regressions, including mixed-quality normalization, duplicate/reload handling, force and surface isolation, deleted forces, retention overflow, filtering, scope/reopen state, provider removal and the existing Space Age tab/Transfers cases. The isolated native engine smoke test passed. Native SE GUI checks passed at 1920x1080 window resolution and 100% UI scale, including English translation probes; all five Factorio screenshots were visually inspected. These are functional/UI checks, with no new UPS performance claim. Mixed qualities were tested offline; the native fixture uses normal quality. No new Space Age graphical save run was performed.

Historical rocket-only evidence is [the dated SE Logistics report](../tests/out/se-fixture-20261113-222452-779507/README.md), including native screenshots, fixture saves, logs, source/archive hashes and profile preservation checks. The reusable procedure is [the SE fixture guide](../tests/development/se_transport_fixture.md). Original saves were not loaded or changed, and live mod-list, mod-settings and config SHA256 comparisons passed.

The canonical builder was run in a scratch workspace under this stage to protect existing `dist` artifacts. Its development ZIP has SHA256 `a154753d9910a92a8a0701157ed4ef0ad12254fefb17b1993abcf76e7c3c7ee0`. All 43 member bytes and member metadata match the clean fixture candidate; only ZIP member ordering differs, so it is not byte-identical to that archive. Test hooks are excluded. Source version and release history remain unchanged; nothing was committed, installed, pushed or published.

## SE Transfers cannon backend — 2026-11-14 development checkpoint

The intermediate backend checkpoint is [the cannon/backend validation report](../tests/out/se-fixture-20261114-000051-863980/README.md), superseding the rocket-only package above. The SE tab is now named Transfers. The delivery-cannon provider observes bounded, force/surface-scoped source firing effects for inspected SE 0.7.64 and discovers live cannon/receiver endpoints on demand. Ready packages and receiver stock remain current inventory snapshots; exact cannon sent/received manifests and destination remain unknown. Unsupported SE versions disable this provider. An additive prototype marker preserves existing creation effects; shipping code reads no private SE state.

Recorded rocket sender and intended-receiver snapshots now support validated navigation through SE's public remote-view API, retaining SE unlock rules. Offline tests cover stale, deleted, foreign, moved and cutscene endpoints and rejected jumps. Native sender/receiver jumps passed after the private fixture exited Factorio's opening cutscene. Cannon endpoints resolved independently after reload; the native jump pair used rocket pads. UI cannon rows and jump buttons are pending the user's requested design review. [Draft A](../tests/out/transfers-design-20261113-review/draft-a-flow.png) proposes the SA-style Flow shell; [Draft B](../tests/out/transfers-design-20261113-review/draft-b-items.png) previews a later Items view. These are illustrative mockups, not native screenshots or implemented layouts.

The complete Lua suite, prototype preservation/version checks, real SE rocket/cannon fixture with save/reload, English native translations, five native GUI captures and base-only engine smoke passed on Factorio 2.1.24 / SE 0.7.64. All five native images were visually reviewed at 1920×1080 window resolution and 100% UI scale. The report retains source/archive/screenshot hashes, unchanged live-profile hashes, and clean canonical-builder comparison. No original user save was loaded, and nothing was committed, installed, version-bumped or published. No fresh SA graphical save run or UPS benchmark was performed; quality cases remain offline coverage.

Balance, Focus, Full Sankey and material History still do not consume shared transport accounting. SA confirmed arrivals and SE rocket sends remain separate trackers; graph import/export vertices and Transfers Items are not ready. SE cannon packaging changes production statistics, so those statistics must be measured and reconciled before transport edges are added, to prevent double counting. This backend checkpoint does not claim those integrations.

## SE Transfers UI — 2026-11-14 initial implementation (historical)

The initial implementation checkpoint is [the native SE Transfers UI report](../tests/out/se-fixture-20261114-085548-387252/README.md), with [nine native screenshots](../tests/out/se-fixture-20261114-085548-387252/index.html). It is superseded by the spacing and stock chart checkpoint below. Flow uses proportional sent-item ribbons grouped by remote surface and transport method, method dividers, material/quality controls and native hover targets. Clicking a ribbon, inspect action or Items transfer readout opens the dedicated History tab with matching filters. The permanent Flow manifest inspector is removed. Period changes preserve History filters while resetting transient bucket/page/expansion; scope changes invalidate route state. Safe endpoint buttons retain force/surface/entity validation.

Items shows completed measured stock scans as adjoining bars with 1px outlines, a zero baseline, latest measured quantity and compact period transfer readouts. Stock remains the existing player-force/all-quality chest scope; unsupported selected-quality or force scopes show unavailable rather than misattributed stock. History uses a common signed axis: measured received imports above zero at arrival, known sent exports below zero at departure. Expandable manifests keep sent and received independent; unknowns remain unknown. Cannon firing observations are unpaired evidence with unknown payload/target/receipt, not guessed routes. The known-sent Flow scale is explicitly labeled because public SE receipt quantities are unavailable.

The full Lua suite passed: 84 Lua files, 635 English keys across three locale catalogs, localization validator regressions, existing SA/view tests, and new SE presentation/UI cases. Offline cases exercise separate qualities, dispatch/arrival windows, unknowns, filtering, period/scope preservation, return actions, stale jumps, stock scope, adjoining cells and a clearly isolated positive-receipt/negative-export renderer input. Final base-only engine smoke passed. Native Factorio 2.1.24 / SE 0.7.64 passed real rocket/cannon save/reload, 647 English native translation probes, all nine GUI cases and both actual History endpoint jump buttons. All screenshots were visually reviewed at 1920×1080 window resolution and 100% UI scale, including corrected right-edge time labels. Tests invoke GUI handlers; they do not claim physical mouse coverage of every control.

The measured-stock native screenshot uses explicitly labeled private synthetic scan values for layout verification; the missing-scan case likewise clears stock history privately. Both restore original stock state before final save. No received manifests are injected into the shipping ledger. Native mixed qualities and actual measured receipt events are not claimed. No new UPS benchmark or fresh SA graphical save run was performed. Balance/Focus/Full Sankey shared transport accounting and local-production reconciliation remain separate work; this checkpoint implements Transfers using supported evidence.

That checkpoint's clean canonical-builder development ZIP has SHA256 `7d4496b983c47f2a04e82ea1955deab335c4f46e094d766784caee3121a2b2b7`. All 48 member names and bytes matched its clean native-tested candidate; archive ordering may differ. The report retains the historical source, package, screenshot and unchanged live-profile hashes. Builds used an isolated scratch root to protect existing dist artifacts. Original user saves were not loaded; nothing was committed, installed, version-bumped, pushed or published.

## SE Transfers spacing and stock chart — 2026-11-14 (historical)

The earlier spacing checkpoint is [the spacing and stock chart report](../tests/out/se-fixture-20261114-095204-639974/README.md), with [nine native screenshots](../tests/out/se-fixture-20261114-095204-639974/index.html). It is superseded by the richer fixture and live-estimate checkpoint below. SE Transfers removes stacked main-content padding and nested-tab margins. Content panels sit flush; one vanilla subheader uses the guide's 12px horizontal/8px vertical inset, 40px first row, and a 28px History context row separated by 8px. Chart bodies use naked scroll panes with inner flows for spacing. Raised History headers and rows share column widths, actions align right, and an exact height budget replaces unused deductions. Flow ports fit inside the center card and share its vertical center; single-page controls are disabled, and newly appearing off-page routes invalidate cached paging.

Items now follows Balance History's stock behavior with a thinner chart at 34% of logical screen height. Light bars are completed physical scans; dark bars are estimates from the existing recorded Made-minus-Used calculation, adjusted to meet the next measured scan. Covered samples adjoin; isolated scans use 6px markers and missing rate coverage stays a gap. Every bar retains its 1px outline. The headline remains the latest measured count. Stock estimates do not create shipment receipts; sent and received quantities and hover-to-filtered-History navigation stay independent.

The full Lua suite passed, including new layout contracts, cached pagination, thin measured markers, joined estimates, gaps, distinct fills and outlines. Native Factorio 2.1.24 / SE 0.7.64 passed layout preflight, real rocket/cannon save/reload, 647 English translation probes, nine GUI cases and both actual endpoint jump actions. All screenshots were visually reviewed at 1920×1080 window resolution and 100% UI scale. The base-only engine smoke passed. Native harnesses invoke handlers rather than physically clicking every control. No new UPS benchmark or fresh SA graphical save run was performed; existing SA offline regressions passed.

The stock layout is a clearly labeled private renderer fixture with six synthetic scans and synthetic production/consumption bins, restored before final save. It rendered six measured and 40 estimated bars. The latest fractional-second interval lacks a completed rate bin and deliberately stays unjoined until coverage catches up. Public SE receipts and cannon manifests remain unknown. Original saves were not loaded and protected live-profile hashes are unchanged.

That checkpoint's clean canonical-builder development ZIP has SHA256 `9b0beedb3c12536daea6bf937781961f069fa7d931e67d8d7e7899cd64d3ba77`. All 48 member names and bytes matched its clean native-tested candidate. The report retains historical hashes and logs, including earlier failed style-family iterations. Existing dist artifacts remain intact. Nothing was committed, installed, version-bumped, pushed or published. Shared transport accounting for Balance, Focus and Full Sankey remains separate work.

## Rich SE fixture and live stock estimates — 2026-11-14 historical checkpoint

The earlier [native report](../tests/out/se-fixture-20261114-110938-755472/README.md) displays all fifteen screenshots inline. The physical fixture now runs twelve cargo rockets and ten cannon shots from four senders across Nauvis, Nauvis Orbit, Jakiro and Jakiro Orbit. Six imports and six exports connect Nauvis to three remote surfaces; ten manifests contain iron plates, with 6,200 sent outward and 5,150 sent inward. Eleven item types and launches spread through 450 seconds produce fuller Flow and History views. The original in-flight save/reload, padless rocket, missed cannon shot and spaceship clone/unload assertions remain.

![Real iron cargo rocket imports and exports across three remote surfaces](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-110938-755472/script-output/se-logistics/se-transfers-flow-iron.png)

The reported stale estimate bug is fixed in shared History code, benefiting both SE Items and Balance History. When contiguous valid scoped production history reaches the latest completed second, stock estimates forecast only its remaining fractional second to the current tick. The accumulating bin stays excluded from measured production totals. Newest scans inside that second retain joined interpolation adjusted to their measured count. Genuine gaps, stale history and missing surface coverage remain gaps; measured scans are unchanged and estimates stay nonnegative.

The fuller stock renderer fixture has thirteen measured scan inputs and 56 calculated bars, with native verification that the live estimate tick equals the capture tick (34,160). These scan counts and rate bins are synthetic, explicitly labeled here and in the detailed report, and restored before final save.

![Synthetic stock fixture with measured scans and estimates through the current capture time](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-110938-755472/script-output/se-logistics/se-transfers-items-measured-layout.png)

Four further native captures use isolated synthetic presentation inputs: 48 shipments across three remote surfaces, cargo/cannon dividers, independent sent/received manifests, signed History and a second History page. An 80-record/five-surface extension exercises Flow pagination. These screenshots carry a native SYNTHETIC TEST DATA title; they do not claim that the installed SE provider supplies paired cannon payloads or measured rocket receipts. The original query function and stock/rate histories are restored, and the real ledger is rechecked before saving.

Full Lua regressions passed: 86 syntax checks, 635 English keys across three catalogs, localization regressions, shared History edge cases, existing SA/UI tests and the new dense fixture isolation/filter/overflow tests. Native Factorio 2.1.24 / SE 0.7.64 passed the larger real transport scenarios and all fifteen GUI cases, 647 English translation probes, and both actual endpoint jump actions. All final screenshots were visually reviewed at 1920×1080 window resolution and 100% UI scale. A second reviewer confirmed the final paginated Flow controls and dividers. The base engine smoke passed. GUI handlers are invoked; physical mouse operation of every control is not claimed. No new UPS benchmark or fresh SA graphical save run was performed.

The current GUI stage reuses a hash-verified completed physical fixture from `se-fixture-20261114-110048-750645`, preserving its original logs and manifest. Reuse requires matching production source, engine, mod archives and construction sources; captures run in a fresh isolated stage. Native capture controls settle before readback, with tooltips suppressed before the warm-up frame rather than mutating the GUI at capture. Applied GUI hook hashes and unchanged live-profile hashes are recorded. Original user saves were not loaded.

The canonical-builder development ZIP has SHA256 `ba3ec1af35fdbd86b29e6fd8241c5f5e0186d07276ac000b5562e1a331f67e21`. All 48 member names and bytes match the clean native-tested candidate, and current production source hashes match it. Private hooks, fixtures and saves are excluded. Existing artifacts are preserved; no version bump, commit, push, installation or publication occurred.


## Surface transport boundaries and sampled SE factory — 2026-11-14 pre-audit checkpoint

The current [native report](../tests/out/se-fixture-20261114-133132-757281/README.md) embeds all seven current screenshots and includes measured-data tables, raw JSON/TSV exports, native logs, package identity and the isolated testing-world launcher. All twenty GUI handler cases were exercised. The earlier full twenty-image stage is preserved under `se-fixture-20261114-131746-842023`; its Balance image exposed the width issue fixed in this checkpoint.

Balance Flow, Focus and Full Sankey now use shared, read-only transport observations. Imports appear on the left and exports on the right; measured received imports and witnessed sent exports alone determine physical ribbon widths. Sent and received manifests remain separate. Unknown quantities have metadata targets rather than invented filled ribbons. Existing recipe rates, production, consumption and local stubs are unchanged. Clicking a transport bar/icon/ribbon opens Transfers History filtered by material, surface, direction and method; Return restores the original chart state. The normal Balance inspector now fits both boundaries while keeping the selected material centred; narrow inspectors and genuinely deeper upstream chains retain readable scrolling.

Stock estimates now follow **last physical scan + recorded production − recorded consumption + independently observed receipts − dispatches**. Transport is applied once at its own observed time only where it is not already represented in production statistics. A new scan resets the baseline; future scan differences are no longer spread backwards through estimates. Covered estimates reach the current tick; real gaps stay gaps. Native SA tests verify dispatch when hub ascent starts and when a rocket launch is ordered, instead of waiting for the ascent animation, with independent receipts on unloading. Repeated ascent events do not duplicate dispatches, including when pending tracking is full.

Physical scans include ordinary/logistic chests, landed temporary cargo containers, main pad/hub cargo, loaded rocket cargo and cargo awaiting platform launch. SE padless cargo containers are discovered despite their missing built event. Inventory IDs are selected by entity type so aliases cannot count one inventory repeatedly. Expanding scope invalidates old chest-only baselines. The scanner retains its 32-entity-per-tick budget and normal five-minute cooldown.

The actual test factory has eight crafting machines, eleven belt segments and nineteen inserters. It records 56 samples over 550 game seconds, with 1,372 iron plates made and 542 consumed. Twenty actual completed scan objects are retained in the final graphical evidence; the private fixture uses a 30-second cooldown and extended retention, without fabricated samples or injected production bins. Its twelve rockets and ten real cannon shots produce 44 atomic boundary probes across four SE surfaces. Twenty genuine padless containers, including 481 iron plates, are confirmed in the physical stock registry. Cannon packages and initial rocket cargo are seeded inputs; packaging manufacture is not exercised.

![Native Balance Flow with both transport boundaries visible](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-133132-757281/script-output/se-logistics/se-balance-flow-transports.png)

![Actual factory stock scans and production-minus-consumption estimates](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-133132-757281/script-output/se-logistics/se-transfers-items-factory-history.png)

![Native Full Sankey with separate transport boundaries](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-133132-757281/script-output/se-logistics/se-full-sankey-transports.png)

Full Lua regressions passed: 91 Lua syntax checks, 648 English keys across three catalogs, localization regressions, graph preservation/bounds, SA/SE filtered-History navigation, stock event timing/scopes and independent transfer ledgers. The extended SA transfer suite also passed its quality, launch-order, duplicate, pending-capacity and retention cases. Base engine smoke passed. Native Factorio 2.1.24 / SE 0.7.64 passed actual construction, in-flight reload, all twenty GUI cases, seven final screenshots, 660 English translation/plural probes and both endpoint jumps. Every current image was visually reviewed at 1920×1080 window resolution and 100% UI scale. Handlers were invoked; physical mouse coverage of every control is not claimed. Dedicated native SA pod and rocket probes pass on the identical source, with unchanged payload production statistics and correct physical stock baselines.

The separate clean-mod testing-world copy also passes a native localhost check after all capture/observer/SE adapter hooks are removed: every machine keeps its recipe and advances its craft counter over 692 game ticks. All five factory-output production counters increase. The verification runs against another disposable copy, does not save console changes, and preserves the playable input, source saves, original dependency archives and live profile hashes. Double-click `tests/out/se-fixture-20261114-133132-757281/launch-testing-world.cmd` to open the isolated playable profile.

The [paired benchmark report](../tests/out/transport-stock-perf-20261114-133836-145545/results.json) passes all eight cases. Each uses 40,000 updates: three repetitions for the 50,000-chest/2.4-million-stack fixture and one for the authorized working SA copy, each with Balance closed/open and sampling disabled/enabled. Multiple completed scan cycles and their minimum spacing are verified. Raw logs, exact fixture totals and source/input hashes are retained. First 300 updates of each repetition are excluded.

| Map / Balance window | Disabled mean ms | Enabled mean ms | Script overhead ms |
| --- | ---: | ---: | ---: |
| chests-50000 / closed | 0.1528 | 0.2307 | +0.0696 |
| chests-50000 / open | 0.1910 | 0.2642 | +0.0703 |
| working-space-age / closed | 4.4589 | 4.4576 | +0.0064 |
| working-space-age / open | 4.4919 | 4.5689 | +0.0466 |

The detailed native report records average, p95, p99 and maximum simulation/script update times and the hardware (i7-13700H, 64 GB RAM, Windows 11). Means and p99 values remain below the 16.67 ms budget for 60 UPS in these runs; occasional single-update outliers exceed it, including disabled baselines. Their cause is not isolated. These are simulation timings, not rendering FPS or a guarantee for every factory. The single working-factory repetition limits variance conclusions.

Public SE rocket receipt quantities and cannon payload/destination manifests remain unknown; private fixture truth and current receiver inventories never become public shipment receipts. Spaceship dispatch/arrival tracking is not claimed. Rockets/cannons are tracked as item cargo; barrels remain items.

The scratch canonical build SHA256 is `daa4bb1bd0b9ff31ca0dfaf28f54b841912176673a4e02155745509cbab20119`; the clean native-tested candidate is `bc305c49e5161a9197fd36fe97334b2d80f02228697bb9faff886b8c996051fb`. All 50 member names and bytes matched at this pre-audit checkpoint, although ZIP ordering differed. The pre-audit source hashes matched that tested candidate. Private hooks, test saves and exports are excluded. Existing dist artifacts are preserved. No version bump, commit, push, live-profile installation or publication occurred.


## Independent transport audit and corrections — 2026-11-14 before UI replacement

The [independent audit](../tests/out/transport-audit-20261114-142131-611509/AUDIT.md) records seven fixed findings with priorities, source paths, reproductions and limitations: aggregate stock bridging coarse surface-coverage gaps; quadratic History event accumulation; false complete SA receipt coverage after unmeasurable deliveries; false complete rocket-filtered SE Items totals; missing active partial-accounting disclosure; export timestamp tooltip identity; and staged-runtime evidence revalidation. No P1 finding was identified. These fixes preserve the approved design, separate sent/received observations and actual scan resets. No UI redesign was performed.

The audit first independently checked the pre-audit package, source/data/image hashes, helper isolation and all seven native screenshots. Its historical clean-play manifest hash predates later metadata extensions; original save/archive guards still match. The new staged-source validator rejects changed/missing/extra runtime files and unrecognized helper/control transformations. Ten focused Python tests cover those contracts.

The full Lua suite passes (91 syntax files, 648 English keys across three catalogs, 13 localization tests and registered GUI/provider/accounting suites); the extended SA transfer suite and changelog synchronization check pass too. Fresh base-engine smoke and native SA platform/rocket proofs pass on the same source. The [fresh SE report](../tests/out/se-fixture-20261114-142242-507821/README.md) embeds seven reviewed images and records all twenty GUI handler cases, twelve rocket launches, ten cannon firing observations, save/reload, endpoint jumps and 660 native translation/plural probes. The real factory again retains 56 samples, 44 private atomic boundary probes and twenty completed physical scans. Private fixture receipts remain distinct from public unknown receipts.

![Audited stock estimates with actual physical scan resets](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-142242-507821/script-output/se-logistics/se-transfers-items-factory-history.png)

The History event sweep reduces the identical 4,096-boundary offline probe from 68,571,000 to 1,147,000 Lua VM instructions while preserving totals. A 32,768-boundary case passes with 10,837,000 instructions. These are focused algorithm checks, not native UPS or rendering measurements. Physical scanner code/cadence/budget are unchanged in this audit. No broad benchmark was repeated; the eight paired-map/window measurements above remain historical pre-audit-source evidence, not a measurement of the new candidate.

The clean native candidate SHA256 is `f7f0e60d9c46069d081d3cb3b8e79fec0b6aa7fc72b34c30b0eb52c664d04c53`; the scratch canonical build is `a0b8eedfe13e0e0d0dc4b9f79806de7403beb6b9aad7ad35a618338139ec5571`. All 50 archive member names and bytes match and current production hashes match native testing. Source/data/screenshot/protected-profile identities pass. A fresh clean playable copy was not prepared; the previously verified playable world remains intact. Original saves, live profile and earlier artifacts stay untouched. No version bump, commit, push, installation or publication occurred.

Exact public SE rocket receipts/cannon pairing and a spaceship tracker remain incomplete. User decisions are pending for behavior after an observed unmeasurable receipt (gap versus labeled partial continuation) and the next feature priority. Current known-only stock behavior is retained with active disclosure; no unknown quantity is invented. The shared History shell is unchanged. Fresh full SA graphical coverage, native mixed-quality cargo display and native SE worst-case-ledger performance are not claimed.


## Connected transport nodes rebuilt from Git — 2026-11-14 historical checkpoint

At the user's request, the rejected side-column design was reverted before replacement. Production Flow has Git history on main at `2b1e28e`; recent feature work was uncommitted. All 50 dirty/untracked paths were preserved in a verified ZIP before view.lua, neighborhood.lua and sankey_ui.lua were restored byte-for-byte from that committed baseline. The [rollback and rebuild report](../tests/out/transport-node-rebuild-20261114-174602-004199/README.md) links the preserved source, original diff and new graph diff from HEAD. Unrelated collectors, accounting fixes, History state/navigation and documentation changes are retained.

External supply now belongs to the existing material node's hover. Methods and remote surfaces appear only in hover details; observed dispatch and receipt quantities stay separate. Exports are ordinary connected downstream nodes in the existing material groups and layout. Balance keeps its original centered three-column layout, with exports beside other Uses. There are no standalone import nodes, dedicated boundary columns or transport side lists in Balance Flow, Focus or Full Sankey. Neighborhood's layout function still matches Git exactly. Ordinary material clicks retain their behavior; exports open filtered History and Return restores the caller.

![Native Balance after restoring and rebuilding the original graph layout](D:/SideProjects/FactorioMods/signal-sankey-project/tests/out/se-fixture-20261114-175930-419318/script-output/se-logistics/se-balance-flow-transports.png)

The full Lua suite passes (91 syntax files, 650 English keys/three catalogs, thirteen localization tests and registered UI/accounting/provider suites); ten fixture-source validation tests and changelog synchronization pass. Fresh base-engine smoke and SA platform/rocket probes pass on the same source. The [native report](../tests/out/se-fixture-20261114-175930-419318/README.md) embeds all seven reviewed images at 1920×1080 window resolution and 100% UI scale, and records all twenty GUI handler cases, 662 native translation/plural probes, save/reload and endpoint jumps. Native GUI evidence retains merged material hover strings and confirms zero standalone import targets in all three related charts. Mouse hovering is not physically exercised. Full Sankey retains ordinary vertical scrolling.

The first SE rerun passed native rendering but failed an outdated host assertion that demanded import nodes; its failed stage remains preserved. The corrected contract passes in the fresh stage above. No existing result was changed to hide that failure.

Clean native candidate SHA256: `47117c42d4521bac4d214f4198359719162f0a439bb32d80148cdbb22143787f`. Scratch canonical build SHA256: `61f6c910a2db17a07b580b56bb20d294e9dd899111c5fbdd77cc6333e2765aa5`. All 50 archive member names/bytes match, current source matches native testing, and strict staged runtime/dependency validation passes. No new broad UPS benchmark or full SA graphical phase is claimed. Old performance stages remain historical source-specific evidence. Original saves/profile/archives stay untouched; no commit, push, version bump, installation or publication occurred.

## Compact exchange History and import receipts — 2026-11-14 historical checkpoint

The [current report](../tests/out/transport-exchanges-20261114-181853-078143/README.md) embeds eleven reviewed native images and links the before-change snapshot, exact source/package identities and raw evidence. Items now marks independently measured import receipts in green, with actual receipt time and quantity in hover. Stock measurements and estimates retain their existing colours and quantities. Unknown SE receipts receive no invented arrival marker.

History offers Time / Events on its x-axis. Events uses compact 24 px positions with paging, preserving actual times in hover. New Space Age cargo records group each platform visit and surface pair into one exchange, keeping both directions separate and skipping empty visits. A real native visit loaded 100 iron plates and unloaded 20: one exchange and two log records, retained after save/reload. Legacy records without visit identity and supported SE rockets remain individual shipments. No SE spaceship visit tracker is claimed. Existing saved SA GUIs rebuild to expose the new controls.

Full Lua regressions pass: 93 syntax files, 663 English keys across three catalogs, thirteen localization tests and registered exchange/UI/provider/accounting suites. Extended SA transfer tests, ten fixture-source validation tests, changelog synchronization and whitespace checks pass. Fresh Factorio 2.1.24 engine smoke and native SA boundary/two-way cargo tests pass on exact current source. SE 0.7.64 passes all 22 GUI handler cases, nine focused images, physical transport/reload checks, endpoint jumps and translation probes. Strict staged runtime/hook/dependency validation passes. Screenshots were inspected at 1920×1080 window resolution and 100% UI scale; handlers were invoked, with no claim of physical mouse coverage for every control.

Eight SE images use actual test-world observations; the ninth explicitly labels synthetic receipt presentation inputs and verifies restoration. Two additional SA images use actual cargo records, including a real 20-item receipt in a test window around the shared Items renderer. The report distinguishes this test window from a shipped SA Items tab. Earlier failed test-helper stages remain intact. Original cargo saves and live profile hash guards pass.

Clean native candidate SHA256: `0ad4b020a25105685eeeef556d35447a2abf1a1268cef7de719db499b3573b92`. Scratch canonical build SHA256: `cbf4a48582430e6d9caed3904b574c9cd6c1df76cdd63b37a94e989894e89e87`. All 51 archive member names and bytes match; current production source matches all final native manifests. Canonical dist and earlier archives remain intact. No new UPS benchmark or native worst-case ledger performance claim is made. No version bump, commit, push, installation or publication occurred.

## Uniform stock markers, right-aligned events and Items drafts — 2026-11-15 historical checkpoint

The [current report and two native layout drafts](../tests/out/transfer-items-drafts-20261115-050407-985551/README.md) keep the proposed Items redesign separate from the implemented chart corrections. Draft A reuses Balance's diagnostic table, filtered to shipment-manifest membership; Draft B uses a narrower shipping list with sent/received/stock columns and a wider History inspector. Both use the existing full Balance History renderer, actual test-world production and eleven real manifest item names. The controls are layout previews in isolated test copies; the full redesign is not installed in runtime source. Unknown SE receipt quantities remain dashes.

The reported wide measurement came from variable midpoint intervals around joined stock samples. Transfers Items and Balance History now keep measured markers six pixels wide, clipped at plot edges, with estimates meeting their edges only where rate coverage exists. The native factory view contains nineteen physical scans: eighteen six-pixel markers and one three-pixel clipped marker. Quantities, sample timestamps, accounting and scanner cadence are unchanged. Shipment Events now anchors the newest event at the right edge and fills older events toward the left, retaining chronological order, compact 24 px spacing, paging and timestamps. Shared/SE and SA platform History both follow this rule; Time mode retains its elapsed-time axis.

The full Lua suite passes (93 syntax files, 663 English keys across three catalogs, thirteen localization tests and registered suites), including new scan-width and right-edge regressions. Ten fixture-source validator tests, changelog synchronization and whitespace checks pass. Fresh Factorio 2.1.24 engine smoke and SE 0.7.64 validation pass all 22 native handler cases. Strict staged runtime/hook/dependency revalidation passes. A fresh GUI stage reuses an independently verified physical checkpoint after a test-helper-only failure reading LuaStyle.width; failed evidence is preserved. Actual saved SA cargo also passes the right-edge UI assertion after reload, keeping the 100-loaded/20-unloaded exchange and measured receipt marker. This is a graphical UI rerun, not a repeated backend cargo probe.

All nine final SE images, two final SA images and both drafts were inspected at 1920×1080 window resolution and 100% UI scale. GUI handlers were invoked; physical mouse coverage of every control is not claimed. The SE synthetic receipt image remains labelled and separate from real provider evidence. Source-save/live-profile guards pass. Clean native candidate SHA256: `33735908a7a5498a221bcafbdf08f533c663f41b7e3e9cd5656c60d2d1fa7014`; scratch canonical build SHA256: `ce786d6ce5c60e16f816ef427951628d7f31a38a64fe9be911832243c0a8383d`. All 51 member names and bytes match exact native-tested production sources, excluding private helpers. Canonical dist and prior evidence are retained. No new UPS benchmark, version bump, commit, push, installation or publication occurred.


## Transfers Items B with Balance table styling — 2026-11-15 historical checkpoint

The user selected B and requested corrected left-list formatting, favourites, consumption rate and time to empty using Balance’s theme. The [current implementation report](../tests/out/transfer-items-b-1794739361231/README.md) embeds all nine reviewed native screenshots. The runtime Items view now uses the existing Balance header/grid styles, star sprites/tool buttons, cell padding, dividers and right-aligned numeric columns. Columns are favourite, item, sent, received, Used /s, stock and Empty in. Header and row widths come from one definition; the item list has independent scrolling. Favourites share Balance’s saved state and sort eligible manifest items first; out-of-scope favourites and unrelated stock do not enter the list.

The right side reuses full Balance History with working usage/zero controls, selected-material changes from the manifest list, translated-name search and filtered shipment History links. Consumption, stock and depletion estimates come from Balance rows; future deliveries are not forecast. Quality/foreign-force scopes retain unknown aggregate measurements. Green independently observed receipt markers remain; unavailable SE receipts stay dashes. No new collector, scanner cadence or stock accounting is introduced.

Full Lua regressions pass: 94 syntax files, 667 English keys/three catalogs, thirteen localization tests and registered UI/provider/accounting suites. Eleven staged-source tests pass, including an LF clean-control staging regression. The first native attempt stopped at the strict physical-source guard because test-hook appending mixed line endings; its stage is preserved. The harness now normalizes only its injected private control copy, retaining exact clean candidate bytes and the strict validator. Fresh Factorio 2.1.24 smoke and SE 0.7.64 construction, in-flight reload, physical checkpoint and all 22 GUI handler cases pass. Native assertions verify eleven real manifest items, seven aligned columns, shared favourite state/order, search, selection and inspector controls.

All nine native images were inspected at 1920×1080 window resolution and 100% UI scale. The synthetic receipt presentation image remains clearly labelled and is restored before real provider validation. Handlers were invoked; physical mouse coverage of every control is not claimed. Clean native candidate SHA256: `150f39cbe8e6f6d0263a33214fdd6251ebbbd95ad30f66cb3a8d0bb84b31a421`; scratch canonical build SHA256: `1586e49e7ba53e373b835b72945ad0182ac65b050ffd3021af31a852a5f8e2e7`. All 52 member names/bytes and current production source hashes match native testing, excluding private helpers. Snapshot guards preserve unrelated preexisting source, original saves, live profile and prior artifacts. No new UPS benchmark, Space Age Items tab, version bump, commit, push, installation or publication is claimed.


## Revised navigation previews and refreshed Space Age checks — 2026-11-15

The [design and Space Age evidence report](../tests/out/transport-list-previews-1794754428113/README.md) supersedes the initial all-subtab sidebar proposals: surface Flow has no navigation list, ship/platform Flow keeps a vehicle selector, Items keeps material entries (with configured cannon recipes eligible), and History defaults to Total with an entity list. Two native History previews compare grouped and flat entities. This design task does not change production source.

The extended Space Age transfers Lua suite was rerun and passed. Fresh native current-source SA tests launch a real 100-item rocket and return 20 items by pod, retaining one exchange/two log rows and independent stock/statistics checks. Fresh graphical checks pass exchange identity after reload, right alignment, the real receipt marker and Flow/History navigation. SA Flow, History and receipt-renderer screenshots were inspected alongside the three corrected SE previews at 1920×1080 window resolution and 100% UI scale. All 52 production hashes match these stages; source-save and live-profile guards pass. The full Items table is still SE-only, the receipt image is a test window, and Total/entity History plus SE spaceship tracking remain proposed. Earlier boards are retained but superseded. No version, install, commit, push, publication or broad UPS run occurred.


## Grouped surface History with Total default — 2026-11-15 historical checkpoint

The [implementation and SA Items proposal report](../tests/out/grouped-history-1794757086338/README.md) is the current evidence index. Surface History now pins Total above a grouped entity list with Balance table styling, independent entity favourites, translated-name/unit search, record counts and last observed times. Selecting an entity filters its historical sender/receiver records; Total restores the current surface/material/method/direction scope. Missing or expired entities fall back to Total. Historical identities remain visible after their entities are destroyed. Shared SA/SE surface History uses this list; the existing SA platform History remains vehicle scoped. Surface Flow remains a full graph without an entity sidebar.

New SA dispatch/receipt records retain immutable physical endpoint snapshots. Older records without these identities remain in Total rather than being assigned to guessed entities. Receiver identity is hidden when querying a time before that receiver was observed. Configured SE cannon recipes now also populate eligible Items entries without requiring manifests; unmeasured cargo quantities remain dashes. Recipe configuration is item membership, not measured delivery evidence.

Full Lua regressions pass (96 syntax files, 688 English keys across three catalogs), including new entity grouping/default/filter/search/favourite/expiry/force-scope cases and endpoint snapshot/time isolation. The extended SA suite and eleven strict staged-source tests pass. Factorio 2.1.24 smoke and fresh SE construction, reload and all 24 native handler cases pass; all eleven SE screenshots were reviewed. Fresh SA native cargo tests pass real 100-up/20-down accounting, exchange grouping and save/reload. Six SA GUI screenshots were reviewed at 1920×1080 window resolution and 100% UI scale, including native endpoint grouping, one-record entity focus, restored two-record Total, right-aligned exchange and receipt marker checks. GUI handlers were invoked; exhaustive physical mouse coverage is not claimed.

SA Items is a proposal only: two private native drafts reuse the Balance-style Items renderer, one with actual test cargo and one explicitly labelled synthetic eight-item layout data. Draft platform/direction/quality controls are illustrative and not wired into the shipping SA UI. Existing SA platform Flow/History remains implemented; no SA Items tab or new SE spaceship tracker is claimed. Native clean candidate and scratch canonical build match all member names and bytes, with exact current production hashes. Logs, hashes, protected-profile/source-save guards and the before-change snapshot are linked from the report. No new UPS benchmark, version bump, install, commit, push or publication occurred.


## Balance History imports and saved-map camera fix — 2026-11-15 current checkpoint

The [current evidence report](../tests/out/balance-imports-1794765292369/README.md) records the implementation and reviewed native images. Balance History’s stock chart shows green independently observed import receipts, with actual arrival time and selected-item quantity on hover. Markers use the transport observations already queried for estimates; no extra provider query or stock scan is added. Qualities received at the same tick share a summed marker. Scope follows the material, surface and visible period. Receipts can appear before a stock scan; unavailable SE receipt quantities never create a marker. Made/Used/Net and measured stock quantities are unchanged. SA retains Flow/History; its Items proposal was cancelled.

User review caught blank plots in the first finished-SA-save screenshots. Those images and their earlier visual approval are superseded. The data and drawing objects existed, but the saved-map camera did not show the player-filtered renderings. Charting the complete generated backing chunks fixes the cold-load view without changing the per-player visibility masks. New regressions cover full chart bounds, cached chunks and player isolation. A diagnostic that temporarily removed visibility masks is retained as diagnostic evidence only; final screenshots use the shipping renderer and normal masks.

Full Lua checks pass: 97 syntax files, 688 English keys, three catalogs and registered UI/provider/accounting/visibility suites. Receipt tests cover time/material/surface isolation, quality summing, statistics inclusion, unchanged stock/rate totals, no-scan rendering, hover alignment, right-edge tooltips and stale-marker clearing. A focused native cargo check observed 100 sent up and 20 returned, with correct ordinary Balance receipt markers and controls. The finished SA playthrough (courpted.zip, confirmed finished_but_continuing=true) was also tested: the initial run collected 600 fresh simulated seconds; the corrected cold-load capture reuses its previously warmed ten-minute history and collects another minute. All three plots render, with real superconductor imports on Vulcanus and active iron production/use on Nauvis.

The older testing/SE 0.7.zip save is a satellite-production test in editor mode. It is checked using active rocket fuel/rocket parts, not inactive iron plate. Its private copy migrates SE 0.7.9 to installed 0.7.64 and omits four unavailable older optional mods; this is screenshot evidence, not an identical replay of the original mod set or proof of measured cargo receipts. Correct transport setup is validated separately with a fresh matched SE 0.7.64 fixture, actual cargo rocket/cannon operations, in-flight reload and native GUI cases. Unknown public SE receipt quantities remain unknown. Manifests distinguish these two purposes.

Final screenshots use 1920×1080 window resolution and 100% UI scale. Source hashes, clean candidate identity, native logs, image hashes and unchanged original-save/live-profile guards are linked from the report. GUI handlers were invoked; exhaustive physical mouse operation is not claimed. No new broad UPS benchmark, version bump, install, commit, push or publication occurred.


## Interaction/alignment fixes and deeper code review — 2026-11-16

The [current evidence report](../tests/out/issue-3-20261116/final-review/README.md) records the confirmed fixes, disposition of every supplied static-review finding, source/package identity and preserved failed/negative controls. Chart wrappers no longer intercept upper/middle item clicks, exact paired offsets prevent fractional-scale icon/label drift, and ribbon/stub targets receive native hover events. Additional verified fixes cover stale saved keys, reload-safe hover state, removed players/surfaces, catalyst statistics, probabilistic 2.1 products, partial-import Swimlanes, consistent default-force accounting, empty cargo receipts, selected-window transfer retrieval, empty-statistics allocation and camera recovery on finite/deleted backing surfaces.

Final Lua and publisher checks pass. Native validation includes 54 actual engine mouse clicks, 18 ordinary native captures at 1920×1080 and actual 100%/125%/150% UI scales, native probability/productivity/deletion/canvas checks, and natural cargo events. Issue #2's downloaded Bob/Angel save acquired 605 fresh simulated seconds of real production history; its private warmed copy passes all six views at 2560×1440 and 125%, with 228 aligned label/icon pairs and three visible camera witnesses. Every native capture was reviewed. The official mod sync selected 11 newer compatible versions and eight additional dependencies; this is not an exact replay of the original mod set. GUI handlers/model checks and actual engine mouse input are distinguished in the report.

The combined F2/F6 near-cap comparison uses three 40,000-update runs per closed/open baseline/candidate case, excluding the first 300 updates each. Open-window average script update time was 2.311 ms in the restored baseline and 0.015 ms in the candidate; the report includes simulation/script p95, p99, maxima and all raw repetitions.

Current graph-cutoff topology behavior (F13) remains unchanged; a hysteresis policy was not introduced. Real multiplayer checksum/join behavior and player-only cargo transport are not claimed. Old mixed-force history cannot be retroactively separated. Original saves, the live profile and tested source hashes remain unchanged; clean candidate members match the tested native archives. No version bump, install, commit, push, tag or publication occurred.

## Label defaults follow-up — 2026-11-16

Unset label preferences now default on only in Balance and Focus; Full Sankey defaults off. Explicit saved true/false choices are preserved. The full Lua suite passes ([log](../tests/out/labels-defaults-lua.log)). A private adaptation of the native harness verifies the actual checkbox defaults for all three tabs and both renderers at 1920×1080 and 100% UI scale, plus preservation of saved choices ([native evidence](../tests/out/gui-interaction-20261116-084722-063761/0-1/evidence.json)). Original profile and source guards pass. This default-only follow-up changes the Sankey UI source after the preceding comprehensive candidate; its new clean archive/source hashes are recorded in the native stage manifest. Sampling/query code and layout geometry are unchanged; the broad benchmark was not repeated.

## Actual-save review and Focus controls — 2026-11-16

The latest review uses the user's real `courpted.zip` Space Age factory through preserved private warmed copies, with actual production history and no substituted rates or entities. [Native evidence](../tests/out/modded-gui-20261116-091913-641895/evidence.json) confirms that the Focus picker starts a fresh root/history, including when choosing the same root; Clear removes that root, both navigation stacks and stale selections while preserving collected production data. The first root can be cleared even without prior visits. Full Sankey selection dims unrelated bars/stems/stubs and labels, grays unrelated icons and preserves their clickability. Both native renderers retain 18 related colored nodes and dim 40 unrelated nodes on the actual factory. [Full regression log](../tests/out/focus-root-controls-20261116-091106/combined-full.log) passes; module state/references and native grayscale style were independently reviewed. Source/save/profile guards pass. These UI follow-ups postdate the earlier performance candidate; sampling/query code is unchanged. Interactive review is user controlled and test/review audio stays at volume zero. No release/version bump or publication is part of this review.

## Unpublished SE/transport validation checkpoint — 2026-11-16

The [local validation report](../tests/out/local-se-review-20261116-153251/README.md) binds fresh evidence to the existing dirty checkout above release commit `3eff3d7`. Production source and existing edits are preserved; only this evidence index is appended. Full Lua regressions (114 syntax files, 689 English keys, three catalogs), the extended Space Age transfer suite, eleven fixture-source integrity tests, changelog synchronization and base-engine smoke pass. Fresh Factorio 2.1.24 / SE 0.7.64 construction, twelve rocket launches, ten cannon observations, in-flight reload, private physical checks and all 24 native GUI handler cases pass. All eleven fixture captures were reviewed at 1920×1080 window resolution and 100% UI scale; the synthetic receipt image is explicitly labelled and restored before final collector checks.

A private copy of the user's older `testing/SE 0.7.zip` satellite-production save also passes after 36,051 fresh updates, with two reviewed native Balance History captures and unchanged original-save/profile hashes. It migrates SE 0.7.9 to 0.7.64 and omits four unavailable optional saved mods, so it is saved-map production evidence rather than an identical mod-set replay or measured receipt proof. Public rocket receipts and cannon manifests/destinations remain unknown; spaceship lifecycle evidence remains exploratory, with no shipping spaceship collector. Current source/archive/hook/dependency revalidation passes. This checkpoint changes no runtime code and introduces no new bug fix, UPS measurement, version bump, commit, push, tag, installation or publication; the published 0.2.9 release is separate from this local development candidate.

## Chart colours and Transfers theme fixes — 2026-11-17

The [SE shipment history follow-up report](../tests/out/se-fixture-20261117-203938-487402/report.md) shows all main tabs and the three Transfers subtabs together. History drops the redundant scope strip and labels the Sender and Receiver action columns. Full Lua and all 24 native fixture cases pass with the source, candidate and screenshot hashes verified.

The [renewed release audit](../tests/out/ui-audit-refresh-20261117/README.md) records the paired midnight checks for Balance History and SE Transfers Items. The [main tab and platform list follow-up](../tests/out/ui-edge-roster-20261117/README.md) records the removal of the additional side inset and the final two-column Space Age list with its separate left favourite buttons. Native captures are embedded at 1920×1080 and 100% UI scale, including a 30-platform fixture. The full Lua suite, base engine smoke and all 24 SE GUI cases pass on the follow-up. All 55 packaged members match the source used for its native captures.

The [18 November centring check](../tests/out/ui-centering-20261118/README.md) compares the tab pane with both edges of the outer window. Both edges now measure 12 px from the window frame in 14 fresh native captures at 1920×1080 and 100% UI scale. The Lua suite and all 24 SE GUI cases pass on that source.

SE heading follow-up. Recording status and the surface jump use the free space beside the native subtabs. Flow gains 56 px of chart space and History gains 36 px while keeping one context row. The Lua suite and all 24 native SE fixture cases pass at 1920×1080 and 100% UI scale. All twelve screenshots decode and match their recorded hashes. The [fixture manifest](../tests/out/se-fixture-20261117-200503-174757/manifest.json) identifies the verified source and clean candidate.

SA spacing follow-up: the platform list and Flow/History panels use matching native inset frames. Their borders separate the columns and the standalone line has been removed. On the latest SA save's private copy, native Flow, History Time and History Events captures show 8 px of visible background on each outer edge and a clean 4 px gap between the borders at 1920×1080 and 100% UI scale. The Lua suite and original save/profile guards pass. See the [follow-up evidence and candidate manifest](../tests/out/modded-gui-20261117-195920-540433/review-evidence.json).

The [reproduction and validation report](../tests/out/transport-ui-fixes-20261117-183400/README.md) records the user's latest SA and K2SE saves through private warmed copies. Balance now keeps its material colours during idle, hover and pinning. Focus reuses Full Sankey's complete node/ribbon dimming: final native cases dim 22 unrelated SA nodes and three SE nodes. The powered SE night-vision equipment tinted world-camera drawings even with full daylight; affected Sankey and transport Flow/History plots now reuse GUI sprites and shared ribbon geometry when night vision is present. Equipment and factory lighting are unchanged.

SA's short platform list no longer reserves an unused scrollbar gutter. History uses a vanilla two-state Time/Events switch with page navigation on its left; explicit event pages remain selected as history grows. Ordinary SE Flow and History show all cargo, with Items selections and explicit route/item links kept in their own context. SE History reuses Balance's sibling `inside_deep_frame` panels with matching depth and 4 px padding instead of a standalone divider; SA retains its native line. The UI theme document is preserved; superseded text-button and divider drafts are retained only as intermediate evidence.

Full Lua regressions (117 syntax files, 689 English keys, three catalogs), eleven staged-source integrity tests, changelog/whitespace checks and base-engine smoke pass. Final actual-save validation covers eight native cases per map. A fresh Factorio 2.1.24 / SE 0.7.64 fixture passes all 24 GUI handler cases and twelve captures, including populated real rocket/cannon observations, reload and endpoint jumps; its private hook forces the GUI backend for populated route coverage. All 28 final native images decode completely and were reviewed at 1920×1080 and 100% UI scale. Physical mouse coverage is not claimed. The labelled synthetic receipt case stays separate from public SE evidence; unknown receipts and cannon payloads remain unknown. Final source, loaded hooks and all 55 clean candidate members match. Original save/profile guards pass. Earlier private-helper controller-restoration and PNG-readback failures are preserved and distinguished from final passes. No new UPS claim, version bump, commit, push, release or publication is part of this checkpoint.
