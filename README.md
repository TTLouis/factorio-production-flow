# Production Flow

**Production balances and interactive Sankey charts for Factorio.**

Production Flow shows what your factory makes, what it consumes, and how recipes
connect on the selected surface. Its optional Transfers integrations cover
Space Age cargo deliveries and Space Exploration shipment activity.

**Feedback needed:** Help shape the beta by sharing what works, what is confusing,
and what needs improving. Report bugs or suggest improvements on
[GitHub Issues](https://github.com/TTLouis/factorio-production-flow/issues) or the
[Mod Portal discussion](https://mods.factorio.com/mod/production-flow/discussion).

See [the changelog](CHANGELOG.md) for release history.

## Views

Charts default to individual item and fluid names. Optional grouping and
the layout of dense charts are still being refined.

- **Balance.** Find shortages and explore what makes and uses the selected item
  or fluid. Switch from Flow to History to compare production, use, net rate
  and chest stock on the same timeline.
- **Transfers.** Follow confirmed Space Age cargo deliveries by platform, or
  browse Space Exploration cargo rocket and delivery cannon routes, items and
  shipment history.
- **Focus.** Trace upstream and downstream recipe connections for one material.
- **Cells.** Group machines into production cells, compare measured throughput
  with capacity, and follow linked train stops and their cargo history.
- **Full Sankey.** Explore the recipe network on the selected surface. The Chart
  overview outlines the visible area as you pan and zoom. Click a material in
  the overview to jump to it. Selecting a material pins its rate card and dims
  unrelated nodes and flows. The card keeps recent history visible after the
  bar drops out of the current period.

In Full Sankey, use **Shift + mouse wheel**, **wheel tilt**, or **Page Up / Page Down**
to scroll horizontally. The overview box is on by default. Turn off **Live Full
Sankey overview box** in per-player mod settings to use Factorio’s native scrollbars.

The Full Sankey overview shows all plotted links and highlights the selected chain. Turn off **Show Full Sankey overview bands** in map mod settings to keep the overview's clickable materials and viewport box with fewer elements to draw. Hover over a material for its rate preview. Turn on **Detailed Full Sankey ribbons** in per-player mod settings to see recipe details on ribbon hover.

Click a machine icon in the Full Sankey side card to preview a matching machine or drill and jump to it in remote view. Alt-click a material in Full Sankey, Focus, Balance Flow, or the Flow chart of an individual cell without subcells to open its rate history. Use the pushpin to keep the flyout beside other materials and the chevron to fold it to its title bar. **Used by** lists every observed consuming recipe in the flyout's reported period.

Destination/source colors, hover highlighting, pinned selections, optional labels,
Fit and Center help you explore the charts. Automatic updates preserve selectors and
row positions; use the **Refresh table** icon to reapply list ordering and filters. The **?**
button opens in-game help for controls, calculations, alerts and stock.
Choose a **Period** from one minute to 1,000 hours. The default is ten minutes.
History survives saving and loading. A warm-up indicator shows how much time
has been recorded so far.

![Balance History shows production rates, net rate and chest stock](docs/screenshots/31-balance-history.png)
![Transfers shows cargo loaded and unloaded by a space platform](docs/screenshots/32-transfers-export.png)

## Install

Requires **Factorio 2.1**. Tested with Factorio **2.1.25** in base Factorio,
Space Age, and Space Exploration 0.7.64 with Krastorio 2. Space Age and Space
Exploration are optional integrations.

Install [Production Flow from the Mod Portal](https://mods.factorio.com/mod/production-flow),
or download the ZIP from the
[GitHub releases](https://github.com/TTLouis/factorio-production-flow/releases)
and place it in your Factorio mods directory.
Open Production Flow in-game, select a surface, and inspect a Balance row with
its magnifier button. Expand inputs to follow its recipe chain upstream.
In Focus, use the magnifier in the toolbar to search for an item or fluid.

## What the charts measure

Production charts show recipe relationships based on observed crafting and
production statistics. In Space Exploration, Transfers records dispatched cargo
and confirms receipts when a rocket unloads fully into a landing pad or a
delivery chest catches a cannon package. Unverified receipts stay unknown.
Balance History marks confirmed imports from either integration on the stock chart.

Stock counts items across all qualities in ordinary and logistic chests on the
selected surface, including chests outside a logistic network. It also counts
cargo stored in landing pads, platform hubs and loaded rocket silos, along with
eligible cargo pods. Production measurements work independently of storage.
Player/vehicle inventories, machine buffers, belts, ground items, linked/infinity
chests and fluid tanks are excluded. Empty-time values are estimates. Large maps
use staggered inventory scans, publishing only completed results. Each scan is
followed by the cooldown selected in Mod settings / Map (1-minute minimum,
5-minute default); Balance shows stock sample age and the selected interval.

See [how rates are calculated](docs/calculations.md) for the measurements,
productivity adjustments, utilisation estimates and stock calculations.

Compressed widths, minimum visible thickness and separate fluid scaling help
readability; they are not a conserved mass balance across different materials.
Dense charts can still cross or require scrolling. Modpack compatibility,
multiplayer and large-factory performance need broader testing.

## Development

The [validation notes](docs/validation.md) record past compatibility tests,
performance measurements, and engineering decisions.

Python 3.11+ is sufficient for the offline test and packaging commands:

```sh
python -m pip install -r requirements-dev.txt
python tests/run_lua.py
python tools/build.py
```

The test harness uses Lupa's Lua 5.2 runtime. It checks Lua syntax, sampling,
recipe APIs, layout, Balance, Focus and Full Sankey behavior with synthetic data.
The game is needed for native GUI validation; see [development notes](docs/development.md).
Publishing a GitHub release runs the validation and Mod Portal publishing workflow.
Ordinary development pushes do not publish.

`mod/production-flow/` is the installable source. `tests/` contains the offline
harness and optional native runners. Build output, private saves, diagnostic
exports and local preview galleries are excluded from Git.

## Feedback and contributions

Player feedback is especially useful for:

- Balance controls, labels and numbers that are unclear or look incorrect.
- Focus and Full Sankey layout, navigation and readability on real factories.
- Modpack compatibility, multiplayer behavior and large-factory performance.

Share feedback on [GitHub Issues](https://github.com/TTLouis/factorio-production-flow/issues)
or the [Mod Portal discussion](https://mods.factorio.com/mod/production-flow/discussion).
For bugs, include the Factorio/mod versions, relevant mods, surface, time window,
material or recipe, steps to reproduce, expected and actual behavior, and a
screenshot if possible. For slowdowns, include your factory size and whether the
Production Flow window was open. General impressions and suggestions are welcome
too; you do not need a full bug report to share them.

For code contributions, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE), copyright 2026 TTLouis. Factorio and the game artwork depicted in
screenshots belong to their respective owners.
