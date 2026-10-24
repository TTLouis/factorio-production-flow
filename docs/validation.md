# Beta 0.1.1 validation

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

## Usability and stored stock

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

## Public release and publishing automation

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
