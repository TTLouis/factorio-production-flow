# Isolated Space Exploration transport fixture

Run from the Production Flow repository:

```powershell
python tests/se_transport_fixture.py
```

Add `--capture` to check the SE Transfers GUI in a local graphical client after the functional run. It exercises all twenty-four handler cases at 1920×1080 and 100% UI scale. Real-event cases cover rocket/cannon observations, multiple materials and remote surfaces, route and entity History, Items, graph handoffs and endpoint jumps. Stock and rate plots use genuine completed shipping scans and live factory production; the private 30-second scan cooldown and extended retention keep the measurements visible without changing shipping defaults. English native translation probes must pass. These are native GUI handler checks, not exhaustive physical mouse input.

Five presentation cases are explicitly labelled `SYNTHETIC TEST DATA` in the native window title. The dense query overrides use 48 sample shipments (and an 80-record overflow extension) to exercise independent manifests, signed History, receipt markers and pagination. Their cannon routes and receipts are invented renderer inputs, not public SE observations. Provider storage is untouched, the query is restored and real collector totals are rechecked before final save. `gui.json` distinguishes each synthetic screenshot.

The Production Flow cargo-rocket collector is checked independently against twelve real public launch callbacks: sent quantities must remain exact after reload, direction must reverse with the selected surface, the padless status must be preserved, and every pad landing must report a received manifest equal to the private fixture truth of what survived the flight, while padless landings keep received quantities unknown. Per-surface counts and expected manifests derive from the fixture scenario contract. A clean candidate ZIP and original source hashes are recorded before test-only hooks are added. Hooks, private SE copies and saves remain outside release source.

This exploratory harness is pinned to the inspected Factorio 2.1.24 and locally installed Space Exploration 0.7.64 packages. It resolves SE's required dependencies from the local mod directory. It downloads nothing, omits optional unrelated mods, disables Space Age, and copies the current Production Flow source without changing its metadata or runtime code.

Each invocation creates a fresh ignored `tests/out/se-fixture-*` stage. It builds a new map rather than reading or migrating a user's save. The live mod list, mod settings and config are hashed before and after the run. Mod archives, fixture sources, Production Flow source, logs and save files have SHA256 evidence in `manifest.json`.

For capture-hook changes alone, `--capture --capture-from tests/out/<verified-stage>` creates a fresh stage using that stage's completed physical fixture. It requires a passed source manifest, unchanged protected hashes, matching production source/engine/mod archives, matching physical construction sources and a verified save hash. The original stage remains untouched; copied physical logs and its manifest retain provenance. New production-source changes require a full fresh physical run. GUI hook hashes are recorded at injection. Captures render a warm-up frame before the final readback, with automatic UI refresh held during that short interval; stock is then redrawn at the capture tick using the explicitly synthetic rate input. Only the final images listed in `gui.json` belong to the report; warm-up frames remain diagnostic artifacts.

The runner builds `fixture-ready.zip`, starts an unadvertised server bound to `127.0.0.1`, saves `_autosave-se-fixture-inflight.zip` at 1,500 ticks while the first three rockets are travelling and nine later rockets are prepared, stops its own server, then reloads that checkpoint. Later launches and shots are staggered through 27,000 ticks (450 seconds); verification completes at 33,000 ticks (550 seconds), preserving a populated timeline within the selected window. The server processes are bounded and terminated by the runner. Run Factorio tests sequentially. This is functional testing, not performance qualification.

## Scenarios and assertions

- Twelve rockets connect Nauvis with Nauvis Orbit, its first actual moon and that moon's orbit. There are six Nauvis exports and six imports, with three remote groups on each side. Ten manifests contain iron plates: 6,200 sent outward and 5,150 sent inward, kept separate from measured receipts. Other cargo includes plates, ores, circuits, gears, fuel, bricks, batteries and water barrels. The original outbound/return/padless scenarios retain their manifests.
- The independent companion observer records real public cargo-rocket events. Their item/quality manifests must exactly match the pre-launch inventories. The save/reload must preserve those records without relaunching the rockets.
- Private SE instrumentation records post-loss surviving manifests and actual landing-pad inventory changes. Every surviving cargo quantity must match the pad's increase. Recovered rocket sections and the capsule remain separate from shipped cargo.
- Four Nauvis cannons fire ten real packages toward three remote surfaces. Nine packages must be caught in full. The primary cannon also fires once at an empty coordinate, spilling 25 plates, then returns its aim to its catcher. The completed save verifies the aim and inventory of all four catchers.
- The shipping cannon observer must independently retain ten source firing-effect observations across reload and pair each with its landing projectile. Every shot must report its package manifest, target surface/zone/position and a settled outcome: the nine caught packages must report received manifests and receivers equal to the private fixture truth, and the deliberate miss must report a spill with no receipt. On-demand endpoint discovery reports current ready packages or receiver inventory separately; stored plates never become attributable receipts.
- A real enclosed spaceship must pass SE's integrity check. It carries 100 circuits, 50 steel plates and a tank with 1,000 water. Booster fuel is recorded separately. Its normal launch and anchor cloning is exercised; its location near Nauvis is set by the fixture, so this does not validate navigation, travel duration, engines or obstacle survival.
- Ordinary public entity-clone callbacks must expose the ship chest's item manifest and tank's fluid snapshot at both boundaries. Private ship lifecycle traces corroborate those observations. After anchoring, a controlled transfer unloads only 40 circuits and 250 water, demonstrating that onboard arrival contents differ from unloading.

Rockets and cannons carry item stacks. Barrel items remain items. The fluid-tank case is specific to the spaceship and is not a claim that cargo rockets or delivery cannons have fluid inventories.

## Public observations versus private truth

`tests/se_transport_fixture.lua` runs as an independent companion mod and records the callbacks a shipping mod can subscribe to. `tests/development/se_transport_fixture_adapter.lua` is injected into the disposable SE copy to construct fixtures, control inputs and expose ground truth. It accesses private SE structs and wraps two internal functions. Those private calls and traces are not a supported companion-mod integration API and must never enter a release package.

The fixture establishes launch-manifest access and a promising spaceship-clone observation path for these cases. It does not establish a public successful rocket-arrival or cannon-shipment API; the shipping receipts below rely on version-gated SE 0.7.64 behaviour instead. A receiver stock delta in this controlled fixture is exact because it has no other transfers; the same delta cannot attribute receipts in a live factory with inserters, robots and concurrent deliveries. The public padless event precedes physical landing and lacks its own manifest in this version.

The shipping cannon observer adds a script marker to the existing source flash, preserving any prior creation effects. Its position-to-cannon contract is inspected and enabled only for SE 0.7.64. Two further additive markers, on the landing projectile and on the spill explosion, pair each beam with the projectile SE creates in the same tick and detect spills at the target. The package is read from the cannon's output slot (or its recipe when the last package left). At the landing tick a delivery chest at the exact target, found with SE's own lookup, means the whole package was inserted. Rocket receipts read SE's in-flight launch inventory through `game.get_script_inventories` and are confirmed only when the landing pad holds the landed cargo. Unsupported SE versions disable these providers. No private SE globals or fixture adapters are used. Beams without a projectile (for example intercepted shots) stay unpaired firing observations with unknown manifests and a safe sender jump. Current inventory snapshots never become receipts.

A shipping spaceship observer would still need coverage for concurrent ships, cloned/split/deleted entities, all cargo-bearing entity types, dynamic construction aboard a docked ship, quality, force boundaries and save/load at each transition. Onboard manifests, fuel consumption and unload quantities must remain separate concepts.

## Inspecting a completed save

Use the stage's private config and mods when loading its completed save. Do not copy the instrumented SE mod or fixture mod into the live profile. The completed save runs at normal speed and its fixture schedule has finished. For example, substitute the actual printed stage path:

```powershell
& 'D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe' --config "$fixtureStage/config.ini" --mod-directory "$fixtureStage/mods" --load-game "$fixtureStage/saves/_autosave-se-fixture-complete.zip"
```

The machine-generated result is `script-output/se-fixture-results.json`. Logs preserve launch, private truth, checkpoint, reload and final PASS evidence. The test save is an instrumented development artifact, not a normal user save or release candidate.


## Current sampled factory and focused UI check

Run `python tests/se_transport_fixture.py --capture --focused-capture --timeout 900` for all twenty-four GUI cases and twelve focused captures, including populated unfiltered Flow and the grouped History divider. Omit `--focused-capture` to capture every case. The private capture hook forces the shared GUI sprite backend to exercise populated routes; the user-save check separately verifies the real night-vision gate. No provider manifests, stock values or manufacturing rates are fabricated. JSON and TSV exports contain 10-second factory measurements and atomic boundary deltas; ready cannon packages and rocket cargo remain explicitly seeded test inputs.
