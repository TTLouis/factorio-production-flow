# How Production Flow calculates rates

Balance totals and recipe links use different measurements.

## Production and consumption

On the selected surface, the sampler records changes in Factorio's production
statistic counters. Made and Used divide those changes by the recorded duration.
Net = Made - Used. Net percentage = Net / max(Made, Used) * 100.
A 5% tolerance is used when classifying roughly balanced rates.

The default window is 600 seconds. Completed one-second samples are used for
that window; longer periods use coarser history. During warm-up, the denominator
is the history actually recorded, not an assumed full ten minutes.

## Recipe links and productivity

Recipe links come from observed completed-craft counters on assembling machines,
furnaces and rocket silos. Intervals whose recipe changed are discarded.
The sampler interprets completed-craft counters as including productivity bonus
crafts and divides by one plus the sampled productivity bonus to estimate normal
crafts. Ingredients are normal crafts/s multiplied by ingredient amount. Products
use base expected yield plus the productivity-eligible yield times the bonus.
Probabilistic products use expected average amounts, so links are estimates and
can differ from the game's measured item/fluid totals.

Single-output recipes are represented as material-to-material connections.
Multi-output recipes can remain separate recipe nodes. Returned catalysts are
netted out of drawn links. A Balance consumer label reports consumption of the
selected material, not its output production rate.

## Utilisation and warnings

Current crafting capacity sums crafting_speed / recipe_time over tracked machines.
Utilisation compares estimated normal crafts/s with that capacity. Current
machines and settings are compared with historical activity; changes in modules,
recipes or machine count can produce estimates over 100%.

Rates within the 5% tolerance can receive utilisation warnings: below 85% is
considered waiting; at least 95% is considered busy. These are diagnostic hints,
not direct observations of missing inputs, power, transport or demand. Source/sink
cases have separate handling when machine or stock data is unavailable.

## Stock, trend and time to empty

Stock combines all qualities in logistic provider and storage inventories on the
surface. Factorio's available network count subtracts pending robot pickups and
can be negative. The sampler adds those pickup reservations back once per owner
to report physically stored stock, including reserved items. Requester
inventories, other chests, items in transit and fluid tanks are excluded. A dash
means no stock data; zero means measured empty stock. On upgrade, the old stock
trend baseline is cleared so the definition change does not create a false drain.
Stock is sampled every ten seconds; the recent trend uses about one minute of samples, independently of
the selected production window.

Time to empty divides stock by the drain rate. A negative recent stock trend is
preferred; otherwise a production deficit supplies the drain estimate. This
assumes the current drain continues. The UI prefixes estimated times with ≈.

## Widths, names and grouping

Proportional ribbons use rate-based widths. Compressed ribbons use the square
root of the rate after visual fluid scaling. Minimum visible widths keep small
flows legible. Ribbons with different source materials have different units;
their widths are not a conserved mass balance.

Charts default to individual item/fluid names. A molten-copper material is named
Molten copper; copper-plate output is Copper plate. The single-output casting
recipe is represented by that material connection. The inspector's Making line
lists recorded producing recipes, ordered by estimated output contribution.
Optional grouping is
unfinished and can aggregate those materials under broad categories such as
Vulcanus; those are category names, not recipe names or production locations.
