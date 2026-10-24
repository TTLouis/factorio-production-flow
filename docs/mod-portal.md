# Production Flow (Beta)

## Short description
Production balances and recipe flow charts for items and fluids, with saved history and a 10-minute default window.

## Mod page description
Production Flow helps you see where your factory's resources are going and whether production is keeping up.

Compare recorded item and fluid rates, then explore the recipes connecting their inputs and consumers.

**Balance is the main focus of this beta.** Compare made, used and net rates, inspect an item's inputs and consumers, and review utilisation and logistic stock in an organized list. In-game help explains the controls, numbers and chart limits.

![Balance: item groups](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/02-balance-groups.png)

![Balance: steam condensation and water consumption](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/01-balance-water.png)

![Balance: copper casting with plain material names](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/12-balance-copper-casting.png)

**Focus and Full Sankey — need more polish.** Both views are available for exploring recipe chains and broader production overviews. Charts default to individual item and fluid names. Graph grouping is optional and unfinished; its broad category labels can obscure material details. Their layout, navigation and readability still need work, especially with dense factories.

![Full Sankey: highlighted petroleum chain — needs more polish](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/06-petroleum-pinned.png)

**How the calculations work**

- **Made, Used and Net:** Made and Used are changes in Factorio's production-statistic counters on the selected surface, divided by the recorded duration. Net is Made minus Used. Rates use a 10-minute window by default; during warm-up they use the available recorded history. History survives saving and loading.
- **Recipe connections:** The mod samples completed crafts on tracked crafting machines. Ingredient amounts and estimated product yields turn that activity into rates for each recipe link, with adjustments for productivity and expected yields for probabilistic outputs. These estimates can differ from the measured production totals.
- **Selected-item usage:** The Uses side reports how much of the selected material each consumer takes. For example, 10 normal crafts/s of a recipe using 2 iron plates per craft represents 20 iron plates/s consumed.
- **Utilisation and status:** Observed normal craft rates are compared with the current machines' capacity, calculated from crafting speed and recipe time. Net differences within 5% of the larger made/used rate count as roughly balanced. Utilisation warnings are diagnostic hints; they do not prove why a machine is waiting. Machine or module changes can affect comparisons with historical activity.
- **Stock and Empty in:** Stock combines all qualities in logistic provider and storage inventories, including items reserved for robot pickup. Pending pickups are added back to Factorio's availability count so stored items are not shown as negative. Other chests, requester inventories, items in transit and fluid tanks are excluded. A dash means no stock data; zero means measured empty. Its recent change is measured over roughly one minute. Time to empty uses that measured drain when available, otherwise the net production deficit. It is an estimate based on the current drain continuing.
- **Ribbon widths:** Proportional mode uses rate-based widths; compressed mode uses a square-root scale. Fluids have a separate visual scale and thin flows have a minimum thickness. Widths across different materials are not a conserved mass balance.

![Balance: steam inputs and uses](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/09-balance-steam-usage.png)

![Balance: stored logistic stock and estimated empty time](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/13-balance-stored-stock.png)

**Compatibility and scope**

Requires **Factorio 2.1**. Tested with **Factorio 2.1.23 and Space Age**, including planetary and local space-platform production. Broader modpack, multiplayer and large-factory performance testing is still needed.

Recording starts when the mod is installed; earlier recipe activity cannot be recovered. Charts describe recipe relationships. Belt/pipe routing, interplanetary shipment tracking, non-logistic chests and fluid-tank stock are outside the current beta.

Diagnostic files remain local. Automatic exports are optional and off by default for new installations. Nothing is uploaded automatically.

Created by **TTLouis** · **MIT license** · [Source code](https://github.com/TTLouis/factorio-production-flow) · [Feedback and issues](https://github.com/TTLouis/factorio-production-flow/issues)
