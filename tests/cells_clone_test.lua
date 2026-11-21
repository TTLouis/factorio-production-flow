-- Cells follow machines moved to another surface by cloning (Space Exploration
-- spaceships), but not copies, partial moves or splits across surfaces.
local Cells = TREQ("scripts.cells")

local FORCE = game.forces.player
local nauvis = game.surfaces[1]
local ship, other = { index = 71, name = "ship" }, { index = 72, name = "other" }
local saved_cells, saved_units, saved_tick = storage.production_cells, storage.cell_units, game.tick

local next_unit = 980000
local function machine(surface, x)
  next_unit = next_unit + 1
  local e = { valid = true, type = "assembling-machine", name = "assembling-machine-1", unit_number = next_unit,
    surface = surface, force = FORCE, position = { x = x, y = 60.5 }, crafting_speed = 1 }
  e.get_recipe = function() return { name = "copper-cable" } end
  return e
end
local function clone(source, surface)
  local copy = machine(surface, source.position.x)
  Cells.on_cloned(source, copy)
  return copy
end

local records, made = {}, {}
local function cell(id, ...)
  local members = {}
  for _, e in ipairs({ ... }) do members[e.unit_number] = e end
  records[id] = { id = id, name = "Cell " .. id, surface_index = 1, members = members, display_item = false }
end
local m = {}
for i = 1, 8 do m[i] = machine(nauvis, i * 4 + 0.5) end
cell(1, m[1], m[2]) -- moves
cell(2, m[3])       -- copied: original kept
cell(3, m[4], m[5]) -- partial: only one member cloned
cell(4, m[6], m[7]) -- split across two surfaces
cell(6, m[1]); records[6].parent_id = 1
cell(7, m[4]); records[7].parent_id = 3
storage.production_cells = { next_id = 6, records = records, drafts = {}, deletions = {} }
Cells.reindex()
local cells = storage.production_cells

local start = game.tick
made[1], made[2] = clone(m[1], ship), clone(m[2], ship)
made[3] = clone(m[3], ship)
made[4] = clone(m[4], ship)
made[6], made[7] = clone(m[6], ship), clone(m[7], other)
for _, i in ipairs({ 1, 2, 4, 5, 6, 7 }) do m[i].valid = false end

Cells.resolve_clones()
assert(cells.records[1].surface_index == 1 and cells.clones[1], "Cloning must not be resolved in the tick it started")

game.tick = start + 1
Cells.resolve_clones()
local moved = cells.records[1]
assert(moved.surface_index == ship.index and moved.members[made[1].unit_number] == made[1]
  and moved.members[made[2].unit_number] == made[2] and not moved.members[m[1].unit_number],
  "A cell whose live members all moved to one surface must follow them")
assert(moved.positions[made[1].unit_number] and Cells.missing(moved) == 0, "Moved members need positions")
assert(cells.records[6].surface_index == ship.index and cells.records[6].members[made[1].unit_number],
  "A child must follow the qualifying root move")
assert(cells.records[7].surface_index == 1 and Cells.missing(cells.records[7]) == 1,
  "A child must not move independently when its parent moved only partially")
assert(storage.cell_units[made[1].unit_number][1] == 1 and not storage.cell_units[m[1].unit_number],
  "The sampler index must follow the moved members")
assert(cells.records[2].surface_index == 1 and cells.clones[2], "A copy keeps waiting while the original exists")
assert(cells.records[3].surface_index == 1 and Cells.missing(cells.records[3]) == 2,
  "A partial move leaves the cell in place with missing members")
assert(cells.records[4].surface_index == 1 and Cells.missing(cells.records[4]) == 2,
  "Members split across surfaces must not move the cell")

game.tick = start + 601
Cells.resolve_clones()
assert(not cells.clones and cells.records[2].members[m[3].unit_number] == m[3],
  "A copied cell keeps its original members after the grace period")

-- The source surface is deleted in the tick of the move: the cell follows first.
local m9 = machine(nauvis, 50.5)
cells.records[5] = { id = 5, name = "Cell 5", surface_index = 1, members = { [m9.unit_number] = m9 }, display_item = false }
Cells.reindex()
local m9copy = clone(m9, ship)
m9.valid = false
Cells.on_surface_deleted(1)
assert(cells.records[5] and cells.records[5].surface_index == ship.index and cells.records[1],
  "Cells moving off a deleted surface must survive")
assert(not cells.records[2] and not cells.records[3] and not cells.records[4],
  "Cells left on a deleted surface are removed")
assert(cells.records[5].members[m9copy.unit_number] == m9copy)

storage.production_cells, storage.cell_units, game.tick = saved_cells, saved_units, saved_tick
print("CELL CLONE PASS: move, wait a tick, copy grace, partial, split, deleted source surface")
