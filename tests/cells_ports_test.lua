-- Locked cell boundary: suggested from recipes, removable in the create and edit
-- forms, locked on save, applied by the All view; the Cells tab follows the surface.
local Cells = TREQ("scripts.cells")
local Flow = TREQ("scripts.cell_flow")
local Selection = TREQ("shared.cell_selection")

local player, nauvis, FORCE = game.players[1], game.surfaces[1], game.forces.player
local saved_storage, saved_cursor = storage.production_cells, player.cursor_stack
local saved_translate = player.request_translation
storage.production_cells = nil
player.cursor_stack = { valid_for_read = true, name = Selection.tool, clear = function() end }
player.request_translation = function() return 1 end

local next_unit = 960000
local function machine(x, recipe)
  next_unit = next_unit + 1
  local e = { valid = true, type = "assembling-machine", name = "assembling-machine-1", unit_number = next_unit,
    surface = nauvis, force = FORCE, position = { x = x, y = 80.5 }, crafting_speed = 1, products_finished = 0,
    crafting_progress = 0, bonus_progress = 0 }
  e.get_recipe = function() return { name = recipe } end
  return e
end
local function window() return player.gui.screen[Cells.NAME] end
local function click(tags)
  assert(Cells.on_click(player, { valid = true, tags = tags }))
end
local function name_field() return window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name end
local function shown(side)
  local out, row = {}, window().ssk_cell_panel.ssk_cell_ports["ssk_cell_" .. side]
  local function walk(element)
    if element.tags and element.tags.ssk_cell == "port" then out[element.tags.key] = element end
    for _, child in ipairs(element.children) do walk(child) end
  end
  walk(row)
  return out, row
end
local function has_reset(side)
  for _, child in ipairs(select(2, shown(side)).children) do
    if child.tags and child.tags.ssk_cell == "ports_reset" then return true end
  end
  return false
end

local cable, circuit = machine(0.5, "copper-cable"), machine(4.5, "electronic-circuit")
local suggested = Cells.suggest_ports({ [cable.unit_number] = cable, [circuit.unit_number] = circuit })
local function contains(list, key) for _, v in ipairs(list) do if v == key then return true end end return false end
assert(contains(suggested.inputs, "item/copper-plate") and contains(suggested.inputs, "item/iron-plate"),
  "Raw materials must be suggested as inputs")
assert(contains(suggested.outputs, "item/electronic-circuit") and not contains(suggested.inputs, "item/electronic-circuit"),
  "The final product must be suggested as an output")

-- Create: the form lists the suggestions; removing one keeps the typed name.
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = { cable, circuit } }
local inputs = shown("inputs")
assert(inputs["item/copper-plate"] and inputs["item/iron-plate"], "The create form must list suggested inputs")
assert(shown("outputs")["item/electronic-circuit"], "The create form must list suggested outputs")
assert(not has_reset("inputs"), "Nothing to restore before a removal")
name_field().text = "Circuits"
click { ssk_cell = "port", side = "inputs", key = "item/copper-plate" }
assert(not shown("inputs")["item/copper-plate"] and shown("inputs")["item/iron-plate"], "A removed input must leave the form")
assert(has_reset("inputs") and name_field().text == "Circuits", "Removal must offer restore and keep the name")
click { ssk_cell = "port", side = "bogus", key = "item/iron-plate" }
assert(shown("inputs")["item/iron-plate"], "Unknown sides are ignored")
click { ssk_cell = "save" }
local id, record = next(storage.production_cells.records)
assert(record.ports.inputs["item/iron-plate"] and not record.ports.inputs["item/copper-plate"],
  "Saving must lock the kept inputs only")
assert(record.ports.outputs["item/electronic-circuit"] and record.excluded.inputs["item/copper-plate"])

-- The All view shows only the locked boundary.
local function all_keys(opts)
  local keys = {}
  for key in pairs(Flow.build(nil, opts or { mode = "capacity" }).nodes) do keys[key:match("^[^#]+")] = true end
  return keys
end
local keys = all_keys()
assert(keys["item/iron-plate"] and keys["item/electronic-circuit"] and not keys["item/copper-plate"],
  "The All view must leave out removed boundary items")

-- Edit: the same section, starting from the saved choice; cancelling keeps the record.
click { ssk_cell = "edit", cell_id = id }
assert(not shown("inputs")["item/copper-plate"] and has_reset("inputs"), "Editing must start from the saved boundary")
click { ssk_cell = "port", side = "outputs", key = "item/electronic-circuit" }
assert(not shown("outputs")["item/electronic-circuit"])
assert(not record.excluded.outputs["item/electronic-circuit"], "Editing must not change the saved cell before saving")
click { ssk_cell = "ports_reset", side = "inputs" }
assert(shown("inputs")["item/copper-plate"] and not has_reset("inputs"), "Restore must bring back removed inputs")
click { ssk_cell = "save" }
record = storage.production_cells.records[id]
assert(record.ports.inputs["item/copper-plate"] and not record.ports.outputs["item/electronic-circuit"],
  "Edits to the boundary must be saved")
keys = all_keys()
assert(keys["item/copper-plate"] and not keys["item/electronic-circuit"])

-- Cells saved before the lock show every net flow.
record.ports, record.excluded = nil, nil
assert(all_keys()["item/electronic-circuit"], "Unlocked cells keep every net flow")

-- Surface scope: cells on other surfaces stay out of the list and the All view.
storage.production_cells.records[99] = { id = 99, name = "Elsewhere", surface_index = 72, members = {},
  positions = {}, display_item = false }
local ids = Flow.ids(nauvis.index)
assert(#ids == 1 and ids[1] == id and #Flow.ids() == 2, "The list must follow the selected surface")
local nodes = Flow.build(nil, { mode = "capacity", surface = nauvis.index }).nodes
assert(nodes["recipe/cell-" .. id] and not nodes["recipe/cell-99"], "The All view must follow the selected surface")
local measured = Flow.build(nil, { mode = "measured", period = 600, surface = nauvis.index })
local line = measured.nodes["recipe/cell-" .. id].rate_line
assert(not line or (line[1] == "production-flow.cells-node-utilisation" and #line == 2),
  "Cell nodes must not repeat the surface the tab already shows")

-- After saving, the saved-cells list docks at the left and closes on a click outside it.
storage.production_cells.records[99] = nil
click { ssk_cell = "edit", cell_id = id }
Cells.on_click_anywhere { player_index = player.index }
assert(window(), "A click outside must not close the editor")
click { ssk_cell = "save" }
local list = window()
assert(list and not storage.production_cells.drafts[player.index], "Saving must show the saved-cells list")
assert(list.location and list.location.x < 50 and not list.auto_center, "The saved-cells list must dock at the left")
local show
local function find_show(element)
  if element.tags and element.tags.ssk_cell == "show" and element.tags.cell_id == id then show = element end
  for _, child in ipairs(element.children) do find_show(child) end
end
find_show(list)
assert(show and show.sprite == "ssk-icon", "Each saved cell needs a Show in Production Flow button")
Cells.on_click_anywhere { player_index = player.index, element = list.ssk_cell_panel }
assert(window() == list, "A click inside the list must keep it open")
Cells.on_click_anywhere { player_index = player.index, element = { parent = nil } }
assert(not window(), "A click outside the list must close it")
Cells.on_click_anywhere { player_index = player.index }

-- Sequencing: cells are staged by what they make for each other, not by creation order.
Cells.cancel(player)
Cells.close(player)
storage.production_cells = nil
local made = {}
local function save_cell(name, entities)
  Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = entities }
  name_field().text = name
  click { ssk_cell = "save" }
  Cells.close(player)
  for cell_id, saved in pairs(storage.production_cells.records) do if saved.name == name then made[name] = cell_id end end
end
save_cell("Inserters", { machine(20.5, "inserter") })
save_cell("Circuits", { machine(24.5, "electronic-circuit") })
save_cell("Cable", { machine(28.5, "copper-cable") })
local ordered, stage = Flow.ids(nauvis.index)
assert(ordered[1] == made.Cable and ordered[2] == made.Circuits and ordered[3] == made.Inserters,
  "Cells must be listed in production order")
assert(stage[made.Cable] == 1 and stage[made.Circuits] == 2 and stage[made.Inserters] == 3)
local staged = Flow.build(nil, { mode = "capacity", surface = nauvis.index })
local function cell_node(name) return staged.nodes["recipe/cell-" .. made[name]] end
assert(cell_node("Cable").tier == 2 and cell_node("Circuits").tier == 4 and cell_node("Inserters").tier == 6)
assert(#staged.columns == 7 and staged.columns[4][1] == "production-flow.cells-stage", "Each stage gets its own column")
local function linked(from, to) return staged.links[from .. ">" .. to] end
local cable_key = "item/copper-cable#surface-" .. nauvis.index .. "-output"
assert(linked(cell_node("Cable").key, cable_key) and linked(cable_key, cell_node("Circuits").key),
  "A material made by one cell and used by a later one must join them")
assert(not staged.nodes["item/copper-cable#surface-" .. nauvis.index .. "-input"], "Joined materials are not imported again")
local iron_key = "item/iron-plate#surface-" .. nauvis.index .. "-input"
assert(staged.nodes[iron_key].tier == 3 and linked(iron_key, cell_node("Circuits").key) and linked(iron_key, cell_node("Inserters").key),
  "An import enters just before its first user")
-- A loop is broken at the oldest cell; its backward use gets its own input node.
local loop = Flow.stages({ 1, 2 }, {
  [1] = { surface_index = 1, ports = { inputs = { a = true }, outputs = { b = true } } },
  [2] = { surface_index = 1, ports = { inputs = { b = true }, outputs = { a = true } } },
})
assert(loop[1] == 1 and loop[2] == 2, "Loops are ordered by creation")

Cells.cancel(player)
storage.production_cells, player.cursor_stack, player.request_translation = saved_storage, saved_cursor, saved_translate
print("CELL PORTS PASS: suggestions, remove/restore, lock on save, edit section, All view filter, surface scope, show button, list docks left and closes on outside click, production-order stages")
