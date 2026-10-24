# Changelog

## Unreleased

### Performance

- Make the chest-stock scan cooldown configurable in Mod settings / Map: minimum
  1 game minute, default 5. The wait starts after each completed scan, so large
  maps cannot scan back to back. The 32-chest-per-tick budget stays in place.
- Apply interval changes live, rescheduling idle scans from their last completion
  and allowing active scans to finish without restarting them.
- Check the cooldown over three 40,000-update repetitions with 50,000 full chests,
  both with Balance open and closed. Completed scans were about 5 minutes
  26 seconds apart. Measured average stock-script overhead was about 0.08 ms per
  update on the test laptop; results are hardware-specific.

### Clarity

- Show the stock sample age separately from the five-second production-rate
  refresh. Explain that the seven-sample stock trend depends on the scan interval (about 30 minutes at the
  default, about 6 at the minimum, longer for large scans).
- Replace the history/window wording in the short description with an introduction
  focused on production imbalances and interactive item/fluid charts.

These changes are committed for development. There is no new version or release.

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
