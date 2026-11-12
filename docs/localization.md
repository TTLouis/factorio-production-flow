# Localization

English is the source catalog in `mod/production-flow/locale/en/locale.cfg`.
The mod ships English (`en`) and Simplified Chinese (`zh-CN`). Additional languages
can be selected and reviewed separately without changing the runtime interface code.

The original 528 keys are translated in Simplified Chinese. One shared rate
format key also localizes the History usage readout, bringing each catalog to 529
keys. Chinese rate units use `/秒` (and `/分钟` for per-minute values); explanations
use “每秒”. The narrow Balance time column uses “时/分/秒”, while longer durations
use “小时/分钟/秒”. SI prefixes and mass symbols such as `k`, `M`, `G`, `g`, `kg`
and `t` remain conventional symbols.

Simplified Chinese follows the installed Factorio 2.1.24 catalogs under
`data/core/locale/zh-CN/`, `data/base/locale/zh-CN/` and
`data/space-age/locale/zh-CN/`. Important terms include:

| Meaning | Simplified Chinese |
| --- | --- |
| Balance / Focus / Transfers views | 收支 / 焦点 / 货运 |
| Made / Used / Net | 生产 / 消耗 / 净值 |
| Stock / measured / estimated | 库存 / 实测 / 估算 |
| Utilisation / productivity bonus | 利用率 / 产能加成 |
| Space platform / cargo pod | 太空平台 / 货舱 |
| Lab / science pack | 研究中心 / 科技包 |
| Requester chest / buffer chest | 优先集货箱（蓝箱） / 主动存货箱（绿箱） |

The brand name Production Flow and player-entered names remain unchanged.
Warnings keep the distinction between measured shortages and estimated activity
hints; they do not turn a possible cause into a diagnosis.

## Runtime text

Use `local Loc = require("scripts.locale")` and pass `Loc("key", ...)` to a
Factorio caption, tooltip, dropdown item, command help or rendering text field.
This produces a native `LocalisedString` under `[production-flow]`; Factorio
resolves it for the player displaying it. Do not resolve English in runtime code
or cache one player's translated interface text for another player.

Keep each complete phrase in one locale entry, with `__1__`, `__2__`, etc. for
changing values. For example:

```ini
[production-flow]
ui-recorded=Recorded __1__ / __2__
```

```lua
caption = Loc("ui-recorded", Sampler.duration(seconds), Sampler.duration(period))
```

Translators can reorder parameters. Format numerical values in Lua before passing
them as parameters when precision matters. Time units, rate units, magnitude
suffixes and surrounding wording belong in the catalog. Use Factorio's native
plural expressions rather than English singular/plural suffixes:

```ini
material-count=__1__ __plural_for_parameter__1__{1=material|rest=materials}__
```

Prototype names stay as the prototype's `localised_name`. Planet names use the
planet's localization. Preserve player-entered platform, surface and group names.
Technical prototype names remain the fallback when a prototype or its locale
is unavailable.

Use `Loc.join(...)` or `Loc.join_list(parts, separator)` when assembling
independent messages, rich-text decorations or lists. They preserve nested
LocalisedStrings and split long lists into groups of at most 20 parameters.
Keep layout-only spaces outside locale entries. Avoid Lua concatenation,
`string.format("%s", ...)`, `tostring()` or `table.concat()` on localized values.

GUI names, tags, sort keys, cache signatures, saved selections and recipe/material
identities must use raw IDs or data, never translated names or LocalisedStrings.
The Transfers flow cache, for example, uses raw cargo weight and endpoint data.

## Adding a language

Copy the English catalog to `locale/<Factorio-language-code>/locale.cfg` and
translate its values. Keep section names, keys and parameter numbers unchanged.
Treat existing keys as stable identifiers when English wording changes.
Preserve functional rich-text tags and icons. Plural branches can follow the
target language's rules. Keep each entry on one source line; use `\n` for
intentional displayed line breaks. Review help text and estimated/measured
terminology along with short labels.

The validator requires complete catalogs for shipped languages. Missing keys,
extra keys, duplicate keys, mismatched parameter sets and changed functional
rich-text tags fail validation; this
keeps incomplete translations from silently mixing English into the interface.

Run:

```powershell
python tests/localization_check.py
python -m unittest discover -s tests -p localization_test.py -v
python tests/run_lua.py
```

The last command includes both checks above and the offline Lua suite. The
literal-text guard catches ordinary English prose and unit strings in shipped
Lua; it is a conservative check, so review dynamically assembled text as well.
Comments, developer-only fixtures, machine-readable IDs, numeric formats and
punctuation are not translation messages.

Then run the relevant native save phases from `development.md`. Inspect actual
Factorio screenshots for wrapping, clipping and overlap, including longer
translations at the supported display scales. The test harness invokes GUI
handlers; it does not physically click every control.

Graphical phases also request actual Factorio translations for every key and for
zero, singular and plural values, using the selected client language. They
require `LOCALIZATION NATIVE PASS` before completing and record the actual client
locale in their evidence. Existing behavioural assertions resolve English
independently, so they still test the same calculations and controls while the
client renders Chinese. All resolvers and probes are injected only into the
isolated test copy after its clean candidate archive is created, and are excluded
from installable packages.

The native runner defaults to English. Select Chinese with `--language zh-CN`
when creating a fresh stage and keep that argument on later phases:

```powershell
python tests/save_test.py --save "$spaceAgeSave" --language zh-CN --phase history
python tests/save_test.py --stage "$saveStage" --language zh-CN --phase ux
python tests/save_test.py --stage "$saveStage" --language zh-CN --phase picker
python tests/save_test.py --stage "$saveStage" --language zh-CN --phase history-view
```

Use the actual stage printed by the runner. Reusing a stage with a different
language is rejected to preserve its earlier evidence. Screenshots are retained
in phase-specific directories. Translations still benefit from fluent-speaker
wording review in addition to these technical and visual checks.
