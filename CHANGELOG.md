# Changelog

## 0.2.7 — 2026-11-12

- Keep Sankey labels and icons aligned with their flow bars at fractional GUI
  scales, including 125%. [Issue #2](https://github.com/TTLouis/factorio-production-flow/issues/2),
  reported by [HorizonBeta](https://github.com/HorizonBeta).
- Add Simplified Chinese support for all views, mod settings, help, tooltips and
  alerts, using Factorio terminology and Chinese time and rate units.
- Display interface text in each player's game language. English remains available.

## 0.2.6 — 2026-11-11

- Correct recipe input, output and utilisation estimates with productivity modules,
  research bonuses and delayed bonus crafts, including recipe-use estimates in History.
- Hide Transfers when Space Age or its required cargo events are unavailable.
  Return to Balance if a saved Transfers selection is no longer available.
- Jump to the selected space platform in remote view from Transfers Flow or History.
- List Space Age as a recommended dependency while retaining base-game support.

## 0.2.5

- Switch between Flow and History for the selected material in Balance. Compare
  Made, Used, Net, estimated use by product and chest stock on a shared timeline.
  Hover to highlight the same time across charts, and start the Made and Used
  axis at zero or fit it to the data.
- Choose production periods from one minute to 1,000 hours. Rate history uses
  trailing averages for periods of one hour or longer.
- In Space Age, use Transfers to see where each platform loads and unloads cargo.
  Inspect route manifests, browse the delivery timeline and log, and star favourite
  platforms. Onboard production shows materials the platform also unloaded during
  the selected period by default.
- Hover Sankey ribbons in Balance Flow, Focus and Full Sankey for total flow
  and rates by recipe. Transfers ribbons show cargo quantities and average
  rates per material.
- Sort Balance by measures such as biggest deficit or soonest empty, and set
  watches for starred materials or materials in starred groups.
- Check machine status in Balance and Focus, then preview a machine before jumping
  to it.
- Science-pack use left after recorded recipe consumption appears as **Labs
  (estimated)**. This can include spoilage and other untracked consumption.

## 0.1.4 — 2026-11-08

- Fix a crash when opening the shared item and fluid picker before selecting a
  material. [Issue #1](https://github.com/TTLouis/factorio-production-flow/issues/1)
- Refactor the picker, Balance calculations, and production graph internals and
  document the sampler's data structures.

Verified first-use Focus search with recorded item and fluid flows on Factorio
2.1.24 with Space Age.

## 0.1.3 — 2026-10-24

### UI improvements

- Use a searchable item/fluid icon selector with familiar categories and a Fluids
  section. Exclude signal-only, parameter and hidden entries.
- Add Balance item/group favourites and Underproducing, OK and Overproducing
  summary columns. Use one fixed, framed column-heading row aligned with the
  data, including with Details enabled. Remove the upper category headings and
  leave an 8 px gap between Empty in and the scrollbar.
- Keep zoom and labels visible, with less-used settings in a gear fly-out.
- Add Focus Back/Forward, six-material Last visits, a clickable trail and Clear
  history. Keep the navigation controls compact.
- Move Refresh table to the header and remove the Balance footer counters.
- Remove development tabs, renderer comparison controls, test commands and
  diagnostic exports from the release.
- Restore selector side margins, let the scrollbar use the right margin, and
  preserve the bottom inset on chart settings.

### Fixes

- Clear unrelated factory flows when Focus selects wood or another material
  without recorded recipe flow. Back restores the previous selection.
- Keep the Balance list and scroll position when selecting a row after live
  rates or statuses change, including with the inspector paused.
- Correct the oversized navigation arrow and clipped selector scrollbar.

### Performance

- Make the chest-stock scan cooldown configurable in Mod settings / Map: minimum
  1 game minute, default 5. The wait starts after each completed scan, so large
  maps cannot scan back to back. The 32-chest-per-tick budget stays in place.
- Apply interval changes live, rescheduling idle scans from their last completion
  and allowing active scans to finish without restarting them.
- Earlier cooldown checks used three 40,000-update repetitions with 50,000 full chests,
  both with Balance open and closed. Completed scans were about 5 minutes
  26 seconds apart. Measured average stock-script overhead was about 0.08 ms per
  update on the test laptop; results are hardware-specific and predate the final UI.

### Clarity

- Distinguish chest-stock sampling from the five-second production-rate refresh.
  Explain that the seven-sample stock trend depends on the scan interval (about 30 minutes at the
  default, about 6 at the minimum, longer for large scans).
- Replace the history/window wording in the short description with an introduction
  focused on production imbalances and interactive item/fluid charts.

Published on GitHub and the Factorio Mod Portal.

## 0.1.2 performance work

- Cache the GUI child list once per Balance table refresh, avoiding repeated
  full-array copies for every cell.
- Spread physical chest inventory reads across ticks and publish only complete
  scans, including ordinary and all logistic chest types across qualities.
- Verify exact stock totals on fixed-seed maps with 1,000, 10,000 and 50,000 chests,
  up to 2.4 million randomized stacks from 210 item types and five qualities.
- Compare stock sampling enabled/disabled, Balance open/closed, and a working
  Space Age save; record average, p95, p99 and maximum update timings.

See [validation and measurements](docs/validation.md) and the
[Factorio changelog](mod/production-flow/changelog.txt).
