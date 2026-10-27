# Production Flow (Beta)

Published for 0.1.3, including the UI improvements, updated photos and
configurable stock cooldown. The description below matches the live Mod Portal page.

## Short description
See where your factory's resources go. Spot imbalances and explore item and fluid production with interactive Sankey charts.

## Mod page description
Production Flow uses interactive Sankey charts to show where your factory's resources go and whether production is keeping up.

Compare recorded item and fluid rates, then explore the recipes connecting their inputs and consumers.

**Feedback needed:** Try the beta in your factory and share what works, what is confusing, or what you would like improved. Feedback on Balance, chart readability, mod compatibility and performance is especially helpful. Leave a message in the [Mod Portal discussion](https://mods.factorio.com/mod/production-flow/discussion) or [GitHub Issues](https://github.com/TTLouis/factorio-production-flow/issues). For bugs, include your Factorio/mod versions, what you expected, what happened and a screenshot if possible.

**Balance is the main focus of this beta.** Compare made, used and net rates, inspect an item's inputs and consumers, and review utilisation and chest stock in an organized list. Item/fluid selection and production measurements are independent of chest storage. In-game help explains the controls, numbers and chart limits.

Underproducing, OK and Overproducing summaries organize the activity counts. A single fixed heading row stays aligned with the columns, including with Details enabled. A framed list and extra space before its scrollbar keep the scrolling area clear. Star an item or group to keep it at the top, and use the Refresh table icon above the list to reapply filters and sorting.

![Balance: aligned single-row headings, scrollbar spacing and header Refresh](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/24-balance-controls.png)

![Balance: grouped materials and favourites](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/25-balance-groups.png)

Click the material slot to search the item/fluid icon selector. Familiar item categories remain, with a separate Fluids section. Zoom, Fit and Show labels stay visible; the gear opens less-used chart settings.

![Material selector: Fluids section with restored side margins](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/26-material-picker.png)

![Material search: scrollbar replaces the right-hand margin on longer lists](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/29-material-scroll.png)

**Focus and Full Sankey — need more polish.** Both views are available for exploring recipe chains and broader production overviews. Charts default to individual item and fluid names. Graph grouping is optional and unfinished; its broad category labels can obscure material details. Their layout, navigation and readability still need work, especially with dense factories.

Focus includes Back/Forward, a Last visits list and clickable icons for the last six materials. Clear history keeps the current selection and collected production data.

![Focus: Back/Forward, Last visits, clickable materials and Clear history](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/27-focus-navigation.png)

![Full Sankey: compact controls and chart settings with a bottom inset — needs more polish](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/28-chart-settings.png)

**How the calculations work**

- **Made, Used and Net:** Made and Used are changes in Factorio's production-statistic counters on the selected surface, divided by the recorded duration. Net is Made minus Used. Rates use a 10-minute window by default; during warm-up they use the available recorded history. History survives saving and loading.
- **Recipe connections:** The mod samples completed crafts on tracked crafting machines. Ingredient amounts and estimated product yields turn that activity into rates for each recipe link, with adjustments for productivity and expected yields for probabilistic outputs. These estimates can differ from the measured production totals.
- **Selected-item usage:** The Uses side reports how much of the selected material each consumer takes. For example, 10 normal crafts/s of a recipe using 2 iron plates per craft represents 20 iron plates/s consumed.
- **Utilisation and status:** Observed normal craft rates are compared with the current machines' capacity, calculated from crafting speed and recipe time. Net differences within 5% of the larger made/used rate count as roughly balanced. Utilisation warnings are diagnostic hints; they do not prove why a machine is waiting. Machine or module changes can affect comparisons with historical activity.
- **Stock and Empty in:** Physical contents of ordinary and logistic chests on the selected surface, including requester and buffer chests, with all qualities combined. No logistic network is required. Items stored without recent activity appear as **Stock only**. Reads are spread across ticks; each completed scan is followed by a configurable wait (minimum 1 game minute, default 5) before another starts. Production rates refresh every 5 seconds. A dash means unavailable; zero means measured empty. Empty time uses the recent stock drain (up to seven completed samples: about 30 minutes at the default interval or 6 at the minimum, longer for large scans), otherwise the net production deficit, and assumes that drain continues. Items moving during a scan can affect a sample.
- **Ribbon widths:** Proportional mode uses rate-based widths; compressed mode uses a square-root scale. Fluids have a separate visual scale and thin flows have a minimum thickness. Widths across different materials are not a conserved mass balance.

**Compatibility and scope**

Requires **Factorio 2.1**. Tested with **Factorio 2.1.23 and Space Age**, including planetary and local space-platform production. Broader modpack compatibility, multiplayer and large-factory performance are still under testing and polish.

Recording starts when the mod is installed; earlier recipe activity cannot be recovered. Charts describe recipe relationships. Belt/pipe routing, interplanetary shipment tracking, player/vehicle inventories, machine buffers, belts, ground items, linked/infinity chests and fluid-tank stock are outside the current beta.

Created by **TTLouis** · **MIT license** · [Source code](https://github.com/TTLouis/factorio-production-flow) · [Feedback and issues](https://github.com/TTLouis/factorio-production-flow/issues)
