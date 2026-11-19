-- Cell membership follows machines replaced in place (upgrade, rebuild, re-placement).
-- Runs in mock2's world and drives the real editor handlers.
local Cells = TREQ("scripts.cells")
local Selection = TREQ("shared.cell_selection")

local player, nauvis, FORCE = game.players[1], game.surfaces[1], game.forces.player
local saved_storage, saved_cursor = storage.production_cells, player.cursor_stack
local saved_translate = player.request_translation
storage.production_cells = nil
player.cursor_stack = { valid_for_read = true, name = Selection.tool, clear = function() end }
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
select_area { a, b }
save("Circuits")
local id = next(storage.production_cells.records)
assert(record(id).positions[a.unit_number].x == 0.5 and record(id).positions[b.unit_number].x == 4.5,
  "Saving a cell must record member positions")
assert(Cells.missing(record(id)) == 0)

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

Cells.cancel(player)
storage.production_cells, player.cursor_stack, player.request_translation = saved_storage, saved_cursor, saved_translate
print("CELL MEMBERSHIP PASS: positions, upgrade/rebuild re-attach, guards, edit keep/forget, replace, shared, delete, backfill")
