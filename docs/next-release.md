# Changes queued for the next release

Use this handoff to prepare the next version block in the [Factorio changelog](../mod/production-flow/changelog.txt). Add changes here as they land on `main`. Remove the entries carried into a version block when preparing that release.

## Production Flow cell tutorials (`cd921d1`)

### Features

- Open **Tips and tricks → Production Flow** for animated lessons on creating a production cell, adding subdivisions, and linking train stops and their buffer storage.
- Read guides to the production chart modes and to cargo tracking in the Space Age and Space Exploration **Transfers** tabs. The guides are available in English, Simplified Chinese, and Traditional Chinese.

### Bugfixes

- Keep subdivision outputs connected to the machines that use them in the parent cell's Flow chart.

### Mod information

The [Mod Portal description](mod-portal.md) explains cell setup, subdivisions, and train tracking, and points players to the lessons. The [README](../README.md) and [in-game mod description](../mod/production-flow/info.json) also describe production cells.

## Chart renderer startup setting

### Features

- Choose **Chart renderer** under **Settings → Mod settings → Startup** for Balance Flow, Balance History, Focus, and Full Sankey. **GUI sprites** is the default and keeps chart colours independent of night vision. The two camera choices remove or keep the equipment's original tint. Restart Factorio to apply a change.
- The neutral camera option also removes the tint from the game world while night vision still brightens the scene. The GUI default restores the equipment's original colours for players who had the previous standalone tint setting enabled.

### Mod information

The [Mod Portal description](mod-portal.md) explains the three startup choices.

The [local validation report](../tests/out/startup-chart-renderer-main-20261128/README.md) covers the port onto `main`, the three startup profiles, and the night-vision colour checks.
