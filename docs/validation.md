# Beta 0.1.0 validation

- Full Lua syntax and offline regression suite passed, including sampling,
  history, responsive widths, selection retention and all three chart views.
- Native Factorio 2.1.23 on an isolated Space Age save: 600 seconds of newly
  recorded Production Flow history survived save/reload.
- 18 Full Sankey/Focus/Balance cases and seven Balance scroll/group cases passed.
  Native checks retain the same selector controls across live refresh and keep
  hovered node elements valid. They invoke GUI handlers; they do not simulate
  physically opening every dropdown with a mouse.
- Seven review screenshots are native engine captures. Incidental tooltip
  popups are suppressed by the test harness after tooltip assertions, so they
  do not cover the charts. Game data and drawings are otherwise unchanged.
- Original save and live mod/configuration files retained their input hashes.
- The installable ZIP includes the MIT license and excludes injected test hooks.

Live updates retain the visible Balance rows and their order. Refresh/filter
changes reapply membership and sorting. Rows leaving the measurement window show
Inactive with zero rates until refresh, rather than retaining stale numbers.

Broader modpack, multiplayer and large-factory performance testing remains open.
