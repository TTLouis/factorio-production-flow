# Production Flow

This file supplies the next Mod Portal description. The screenshots are native Factorio 2.1.24 captures at 100% UI scale.

## Short description

Spot production shortages with interactive Sankey charts, item and fluid history, and chest stock tracking. Transfers follows Space Age cargo deliveries and Space Exploration cargo rockets and delivery cannons.

## Mod page description

**Where did all your green circuits go?** Follow the recipes using them, see whether production is keeping up, and check how long your chest stock will last. In Space Age, follow cargo from the surface that loaded it to the one where it landed.

**Supported game setups** include base Factorio, Space Age, and Space Exploration. Balance, Focus, and Full Sankey are available in all three. The optional Space Age and Space Exploration integrations add their own **Transfers** views.

Available in English, Simplified Chinese (简体中文), and Traditional Chinese (繁體中文). All views, mod settings, help, tooltips, and alerts follow your Factorio language setting.

**支持简体中文和繁體中文。** 界面会跟随 Factorio 的语言设置，无需另装汉化模组。

**Feedback needed:** Try Production Flow in your factory and share what works, what is confusing, or what you would like improved. Feedback on Balance, chart readability, mod compatibility and performance is especially helpful. Leave a message in the [Mod Portal discussion](https://mods.factorio.com/mod/production-flow/discussion) or [GitHub Issues](https://github.com/TTLouis/factorio-production-flow/issues). For bugs, include your Factorio/mod versions, what you expected, what happened and a screenshot if possible.

### Balance production and stock

Sort items and fluids by deficit or time to empty, then select one to inspect what makes and uses it. Star materials or groups to keep them handy, and set watches for a minimum production rate or time to empty.

The Underproducing, OK and Overproducing summaries help you scan the factory at a glance. Turn on **Details** to see utilisation and stock trends. The headings and filters stay visible as you scroll. Use **Refresh table** to reapply your filters and sort order.

![Balance Flow shows what makes and uses electronic circuits](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/30-balance-flow.png)

Click the material slot to search for an item or fluid. Browse familiar item categories or jump straight to the Fluids section.

Switch to **History** to compare Made, Used, Net, estimated use by product and chest stock for the same material. Hover to line up the charts at one point in time. Choose a production period from one minute to 1,000 hours.

![Balance History aligns production rates, net rate and chest stock](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/31-balance-history.png)

### Follow platform cargo in Space Age

Pick a space platform in **Transfers → Flow** to see where it loads and unloads cargo. Follow the ribbons to inspect what moved on each route. The platform card shows how much was loaded, made aboard, unloaded, and kept aboard. Star your regular platforms to keep them at the top.

![Transfers Flow shows a platform loading at four planets, unloading at five and processing ore aboard](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/32-transfers-export.png)

![Transfers Flow shows a science-pack route from Vulcanus to Nauvis](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/33-transfers-science.png)

Open **History** to see when cargo moved. Switch to **Time** to see the gaps between deliveries, or **Events** to put recorded cargo exchanges side by side. Expand a delivery in the log to see what was in the pod.

![Transfers History shows the delivery timeline and an expanded cargo manifest](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/34-transfers-history.png)

### Track shipments in Space Exploration

- **Flow** maps cargo rocket and delivery cannon routes into and out of the selected surface. Group routes by **Transport** or **Items**, then click a ribbon to open its shipment history.
- **Items** compares quantities sent and received with local production, usage, and chest stock. Select a material to see how its supply and stock changed over time.
- **History** shows shipments by elapsed **Time** or as a compact sequence of **Events**. Expand a shipment to see its contents and any measured losses. Jump to the sender or receiver when its location is available.

![Space Exploration Transfers Flow shows cargo rocket and delivery cannon routes into and out of Nauvis, with zone details](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/38-se-transfers-flow.png)

![Space Exploration Transfers Items shows shipment materials alongside production and stock history](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/39-se-transfers-items.png)

Received quantities are measured when a rocket lands on a pad with enough room or a delivery chest catches a cannon package. Receipts stay unknown for full-pad landings, off-pad landings, and spilled packages. Delivery cannon tracking requires Space Exploration 0.7.64.

### Explore recipes and inspect machines

Use **Focus** to trace the inputs and consumers of one item or fluid. Open **Machine status** from Balance or Focus to check for missing inputs, blocked outputs or power issues, and preview a machine before jumping to it.

Use **Back**, **Forward** or **Last visits** to revisit materials in Focus. Zoom, Fit and Show labels are on the chart toolbar. Hover a ribbon to see its total flow and rates by recipe, or use the gear for more chart settings.

![Focus traces the recipes connected to electronic circuits](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/35-focus-circuit.png)

![Machine status lists sampled machines that make or use electronic circuits](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/36-machine-status.png)

**Full Sankey** gives you a broader view of recipe flows on one surface. Dense charts and optional grouping are still being refined.

![Full Sankey shows recipe flows across Nauvis](https://raw.githubusercontent.com/TTLouis/factorio-production-flow/main/docs/screenshots/37-full-sankey.png)

### How the calculations work

- **Made, Used and Net.** Made and Used are changes in Factorio's production counters for the selected surface, divided by the recorded duration. Net is Made minus Used. The default period is ten minutes. While a period fills, rates use the history recorded so far. That history survives saving and loading.
- **Recipe connections.** Production Flow samples completed crafts on tracked machines. It uses ingredient amounts and expected product yields to estimate rates for each recipe link, accounting for productivity and the expected yield of probabilistic outputs. Recipe estimates can differ from the measured totals.
- **Selected-material usage.** The **Uses** side shows how much of the selected material each recipe consumes. A recipe running at ten normal crafts per second and using two iron plates per craft consumes twenty iron plates per second.
- **Utilisation and status.** The mod compares observed normal craft rates with the capacity of the current machines, based on crafting speed and recipe time. A net difference within 5% of the larger Made or Used rate counts as roughly balanced. Machine, recipe or module changes can affect comparisons with historical activity. Treat utilisation warnings as clues about where to look.
- **Stock and Empty in.** Stock counts physical items in ordinary and logistic chests on the selected surface, including requester and buffer chests, across all qualities. Chests outside a logistic network count too. Items stored without recent activity appear as **Stock only**. Production rates refresh every five seconds. Chest reads are spread across ticks, with a configurable wait after each completed scan of one game minute minimum and five by default. A dash means stock is unavailable, and zero means measured empty. **Empty in** uses the recent drain from up to seven completed scans, or the net production deficit when no drain is measured. Seven scans span about 30 game minutes at the default interval or six at the minimum, with longer spans on large maps. Empty time assumes the current drain continues. Items moving between chests during a scan can affect the sample.
- **Ribbon widths.** Proportional mode scales widths by rate, while compressed mode uses the square root of the rate. Thin flows have a minimum visible width and fluids use a separate scale. Compare widths within the same material because different materials can use different units.

Open the **?** button in-game for help with controls, measurements and chart limits. See [how the calculations work](https://github.com/TTLouis/factorio-production-flow/blob/main/docs/calculations.md) for more detail.

### Compatibility and scope

Requires **Factorio 2.1**. Space Age and Space Exploration are optional integrations that enable Transfers. Production history and cargo tracking fill as the mod observes activity. Production charts show recipe relationships on a single surface, and Transfers records observed cargo shipments between surfaces, with the measurement limits described above. Broader modpack compatibility, multiplayer and large-factory performance are still being tested.

**Remove night vision tint** is enabled by default under **Settings → Mod settings → Startup**. It uses neutral colours throughout the game while night vision equipment is active. Night vision still brightens the scene, and the neutral palette can look brighter than the equipment's original palette. Turn it off and restart Factorio to restore the original look. Production Flow charts use their own palette in either mode.

Created by **TTLouis** under the **MIT license**. [Source code](https://github.com/TTLouis/factorio-production-flow)
