-- Cell membership follows machines replaced in place (upgrade, rebuild, re-placement).
-- Runs in mock2's world and drives the real editor handlers.
local Cells = TREQ("scripts.cells")
local Selection = TREQ("shared.cell_selection")

local player, nauvis, FORCE = game.players[1], game.surfaces[1], game.forces.player
local saved_storage, saved_cursor = storage.production_cells, player.cursor_stack
local saved_translate, saved_clear_cursor = player.request_translation, player.clear_cursor
storage.production_cells = nil
player.cursor_stack = { valid_for_read = true, name = Selection.tool, clear = function() end }
player.cursor_stack.set_stack = function(stack) player.cursor_stack.name = stack.name; return true end
player.clear_cursor = function() return true end
player.request_translation = function() return 1 end

local next_unit = 970000
local function machine(x, y, recipe, force, kind)
  next_unit = next_unit + 1
  local e = { valid = true, type = kind or "assembling-machine", name = "assembling-machine-1",
    unit_number = next_unit, surface = nauvis, force = force or FORCE, position = { x = x, y = y },
    crafting_speed = 1, products_finished = 0, crafting_progress = 0, bonus_progress = 0, _r = recipe }
  e.get_recipe = function() return { name = e._r } end
  return e
end

local function window() return player.gui.screen[Cells.NAME] end
local function click(tag, id)
  assert(Cells.on_click(player, { valid = true, tags = { ssk_cell = tag, cell_id = id } }))
end
local function select_area(entities)
  player.cursor_stack.name = Selection.tool
  Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = entities }
end
local function save(name)
  window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = name
  click("save")
end
local function record(id) return storage.production_cells.records[id] end
local function members(id) local m = Cells.members(record(id)); local n = 0; for _ in pairs(m) do n = n + 1 end; return m, n end

-- Create a two-machine cell; positions are recorded at save.
local a = machine(0.5, 0.5, "copper-cable")
local b = machine(4.5, 0.5, "electronic-circuit")
local stop = machine(2, 2, nil, FORCE, "train-stop")
stop.backer_name = "[item=copper-plate]"
local wagon = machine(3, 3, nil, FORCE, "cargo-wagon")
wagon.bounding_box = {left_top = {x = 2, y = 2}, right_bottom = {x = 4, y = 4}}
local matched = machine(4, 3, nil, FORCE, "container")
matched.get_inventory = function() return { get_contents = function() return {{name = "copper-plate", count = 12}} end } end
local inserter = machine(3.5, 3, nil, FORCE, "inserter")
inserter.pickup_target, inserter.drop_target = wagon, matched
stop.get_stopped_train = function() return {valid = true, carriages = {wagon}} end
local old_find = nauvis.find_entities_filtered
nauvis.find_entities_filtered = function() return {inserter} end
local later_stop = machine(3, 2, nil, FORCE, "train-stop")
later_stop.backer_name = "Later"
later_stop.get_stopped_train = function() return nil end
select_area { a, b, stop, matched }
local draft = storage.production_cells.drafts[player.index]
assert(draft.stops[stop.unit_number] and not draft.members[stop.unit_number],
  "Initial selection links the stop without including it as a machine")
assert(draft.stops[stop.unit_number].role == "import" and draft.ports.inputs["item/copper-plate"]
  and draft.stops[stop.unit_number].buffers[matched.unit_number] == matched,
  "The same draft must suggest the named input, role and directly matched stock")
assert(not next(storage.production_cells.records), "Suggestions must remain in the unsaved draft")
nauvis.find_entities_filtered = old_find
draft.stops[stop.unit_number].role = "export"
Cells.pick_port(player, "outputs", "item/iron-gear-wheel")
local buffer = machine(2, 3, nil, FORCE, "container")
draft.stops[stop.unit_number].buffers[buffer.unit_number] = buffer
select_area { a, b, later_stop }
assert(draft.stops[stop.unit_number].role == "export" and draft.stops[stop.unit_number].buffers[buffer.unit_number] == buffer
  and not draft.stops[later_stop.unit_number] and draft.ports.outputs["item/iron-gear-wheel"]
  and not draft.ports.inputs["item/iron-gear-wheel"], "Later machine selection preserves role, ports and buffers")
save("Circuits")
local id = next(storage.production_cells.records)
assert(record(id).positions[a.unit_number].x == 0.5 and record(id).positions[b.unit_number].x == 4.5,
  "Saving a cell must record member positions")
assert(Cells.missing(record(id)) == 0)
assert(record(id).stops[stop.unit_number].role == "export" and record(id).stops[stop.unit_number].buffers[buffer.unit_number] == buffer
  and record(id).stops[stop.unit_number].buffers[matched.unit_number] == matched,
  "Saving retains explicitly configured stop roles and buffers")
-- Linking a new named station during Edit adds an otherwise absent balanced
-- material to the station's unambiguous side without saving until confirmation.
click("edit", id)
draft = storage.production_cells.drafts[player.index]
local named_stop = machine(7, 2, nil, FORCE, "train-stop")
named_stop.backer_name = "[item=copper-plate] [item=transport-belt]"
named_stop.get_stopped_train = function() return nil end
assert(not draft.ports.inputs["item/transport-belt"] and not draft.ports.outputs["item/transport-belt"])
click("pick_stops")
Cells.on_selected { item = Selection.stop_tool, player_index = player.index, surface = nauvis, entities = {named_stop} }
assert(draft.ports.inputs["item/transport-belt"] and draft.stops[named_stop.unit_number].role == "import",
  "A newly linked stop in Edit adds its other named material to the inferred side")
assert(not record(id).ports.inputs["item/transport-belt"], "An edited draft must not persist before Save")
assert(Cells.on_click(player, {valid = true, tags = {ssk_cell = "port", side = "inputs", key = "item/transport-belt"}}))
save("Circuits")
click("edit", id)
draft = storage.production_cells.drafts[player.index]
local function find_port(element, key)
  if element.tags and element.tags.ssk_cell == "port" and element.tags.key == key then return element end
  for _, child in ipairs(element.children) do
    local hit = find_port(child, key)
    if hit then return hit end
  end
end
local excluded = assert(find_port(window().ssk_cell_panel.ssk_cell_ports.inputs, "item/transport-belt"))
assert(not excluded.toggled and excluded.style.draw_grayscale_picture and not draft.ports.inputs["item/transport-belt"],
  "An excluded station-only material remains gray after Save and Edit")
Cells.cancel(player)
click("edit", id)
draft = storage.production_cells.drafts[player.index]
Cells.pick_port(player, "outputs", "item/transport-belt")
click("pick_stops")
Cells.on_selected { item = Selection.stop_tool, player_index = player.index, surface = nauvis, entities = {named_stop} }
assert(draft.ports.outputs["item/transport-belt"] and not draft.ports.inputs["item/transport-belt"],
  "A manually chosen opposite side takes precedence over the suggestion")
Cells.cancel(player)
select_area { a, stop, later_stop }
draft = storage.production_cells.drafts[player.index]
assert(not draft.stops[stop.unit_number] and draft.stops[later_stop.unit_number],
  "A new initial selection skips an owned stop and links an unowned stop")
Cells.cancel(player)

-- An upgrade destroys the old machine and builds a new one in the same place.
a.valid = false
assert(Cells.missing(record(id)) == 1 and select(2, members(id)) == 1, "Removed member must count as missing")
local a2 = machine(0.5, 0.5, "copper-cable")
a2.name = "assembling-machine-2"
Cells.on_built(a2)
local m, count = members(id)
assert(count == 2 and m[a2.unit_number] == a2 and not record(id).members[a.unit_number],
  "A machine built at a missing member's position must take over its slot")
assert(record(id).positions[a2.unit_number] and not record(id).positions[a.unit_number])
assert(Cells.missing(record(id)) == 0)

-- Unrelated positions, valid members, other forces and unsupported types never join.
Cells.on_built(machine(20.5, 20.5, "copper-cable"))
Cells.on_built(machine(4.5, 0.5, "copper-cable")) -- b is still valid
assert(select(2, members(id)) == 2 and record(id).members[b.unit_number] == b, "A valid member must never be replaced")
b.valid = false
Cells.on_built(machine(4.5, 0.5, "electronic-circuit", { name = "enemy" }))
Cells.on_built(machine(4.5, 0.5, nil, FORCE, "container"))
assert(Cells.missing(record(id)) == 1, "Enemy machines and non-production entities must not fill a slot")

-- Editing keeps the vacant slot by default, so a later rebuild still rejoins.
click("edit", id)
assert(window().ssk_cell_panel.children[1].ssk_cell_missing, "Editor must show missing machines")
save("Circuits")
assert(Cells.missing(record(id)) == 1, "Saving an edit must keep vacant slots")
local b2 = machine(4.5, 0.5, "electronic-circuit")
Cells.on_built(b2)
assert(record(id).members[b2.unit_number] == b2 and Cells.missing(record(id)) == 0,
  "A slot kept through an edit must still re-attach")

-- A slot can become vacant after the editor takes its initial snapshot.
click("edit", id)
assert(not window().ssk_cell_panel.children[1].ssk_cell_missing)
b2.valid = false
save("Circuits")
assert(Cells.missing(record(id)) == 1 and record(id).positions[b2.unit_number],
  "Saving an open editor must retain a machine slot that became vacant")
local b3 = machine(4.5, 0.5, "electronic-circuit")
Cells.on_built(b3)
assert(record(id).members[b3.unit_number] == b3, "A replacement must rejoin after the edit")

-- Forgetting drops vacant slots; a rebuild there no longer joins.
a2.valid = false
click("edit", id)
click("forget")
assert(not window().ssk_cell_panel.children[1].ssk_cell_missing, "Forget must clear the missing count")
save("Circuits")
assert(Cells.missing(record(id)) == 0 and not record(id).positions[a2.unit_number])
Cells.on_built(machine(0.5, 0.5, "copper-cable"))
assert(select(2, members(id)) == 1, "A forgotten slot must not re-attach")

-- Replacing the selection discards vacant slots from the previous membership.
local c = machine(8.5, 0.5, "copper-cable")
select_area { c }
save("Second")
local second
for key, r in pairs(storage.production_cells.records) do if r.name == "Second" then second = key end end
c.valid = false
click("edit", second)
local d = machine(12.5, 0.5, "copper-cable")
select_area { d }
save("Second")
assert(Cells.missing(record(second)) == 0, "Replacing a selection must not keep old vacant slots")

-- Two cells sharing a machine both follow its replacement.
select_area { d }
save("Shared")
local shared
for key, r in pairs(storage.production_cells.records) do if r.name == "Shared" then shared = key end end
d.valid = false
local d2 = machine(12.5, 0.5, "copper-cable")
Cells.on_built(d2)
assert(record(second).members[d2.unit_number] == d2 and record(shared).members[d2.unit_number] == d2,
  "Every cell holding the slot must re-attach")

-- Deleting a cell removes its slots from the index.
storage.production_cells.deletions = { [player.index] = { id = shared, record = record(shared) } }
Cells.finish_delete(player, true)
for _, by_key in pairs(storage.production_cells.slots) do
  for _, slot in pairs(by_key) do assert(slot[shared] == nil, "Deleted cell left a slot in the index") end
end

-- Records saved before positions existed are backfilled from valid members.
local legacy = machine(16.5, 0.5, "copper-cable")
storage.production_cells.records[99] = { id = 99, name = "Old", surface_index = 1,
  members = { [legacy.unit_number] = legacy }, display_item = false }
storage.production_cells.slots = nil
legacy.valid = false
local legacy2 = machine(16.5, 0.5, "copper-cable")
Cells.on_built(legacy2) -- reindex ran after the machine was gone: no position to recover
assert(not record(99).members[legacy2.unit_number], "A slot without a recorded position cannot be guessed")
legacy2.valid = true
storage.production_cells.records[99].members = { [legacy2.unit_number] = legacy2 }
storage.production_cells.records[99].positions = nil
Cells.reindex()
assert(record(99).positions[legacy2.unit_number], "Reindex must backfill positions from valid members")

-- A composite edit must preserve the parent id/history and commit no partial tree.
local original = record(second)
local before_id, before_since = storage.production_cells.next_id, original.since
local staged = { name = "Division", surface_index = 1, members = { [d2.unit_number] = d2 }, parent_draft = 0 }
local missing = machine(19.5, 0.5, "iron-gear-wheel")
original.members[missing.unit_number] = missing
original.positions[missing.unit_number] = { x = 19.5, y = 0.5 }
local edit = { id = second, original = original, name = original.name, surface_index = 1,
  members = original.members, ports = original.ports, stops = original.stops, staged = { staged } }
missing.valid = false
assert(Cells.apply_composite(player, edit), "Valid composite edit should succeed")
assert(record(second).since == before_since and record(before_id).parent_id == second,
  "Composite edit must preserve parent history and link its new child")
assert(Cells.missing(record(second)) == 1, "Composite save must also retain newly vacant slots")
assert(storage.production_cells.children[second][1] == before_id)
local snapshot, next_id = record(second), storage.production_cells.next_id
edit.original = snapshot
staged.members = { [legacy2.unit_number] = legacy2 }
assert(not Cells.apply_composite(player, edit), "Out-of-parent staged selection must fail")
assert(record(second) == snapshot and storage.production_cells.next_id == next_id and not record(next_id),
  "Invalid composite apply must not alter records or allocate ids")
local valid = Cells.valid_hierarchy(storage.production_cells.records,
  { id = second, surface_index = 1, members = {} })
assert(not valid, "Removing a child's member from its parent must be blocked")
storage.production_cells.deletions = { [player.index] = { id = second, record = snapshot } }
Cells.finish_delete(player, true)
assert(record(second) == snapshot, "Deleting a parent with children must be blocked")

Cells.cancel(player)
storage.production_cells, player.cursor_stack, player.request_translation, player.clear_cursor = saved_storage, saved_cursor, saved_translate, saved_clear_cursor
print("CELL MEMBERSHIP PASS: positions, upgrade/rebuild re-attach, guards, edit keep/forget, replace, shared, delete, backfill")
