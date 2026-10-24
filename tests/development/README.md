# Local development fixtures

These helpers are outside `mod/production-flow` and never enter release ZIPs.

- `diag.lua`: the offline suite loads this directly; `save_test.py` injects a copy
  into its isolated mod only after producing the clean candidate archive. It
  records local evidence and offline replay inputs.
- `render_test.lua`: the offline suite exercises the original fake-graph fixture
  directly. The release has no command, tab or event wiring for it.

Release behavior is tested without either helper wired into `control.lua`.
