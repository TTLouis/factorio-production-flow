-- Cell boundary: chosen by hand in the create and edit forms, saved with the cell,
-- applied by the All view; display-item ranking; the Cells tab follows the surface.
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
local function ports_of(side)
  local out = {}
  local function walk(element)
    if element.tags and element.tags.ssk_cell == "port" then out[element.tags.key] = element end
    for _, child in ipairs(element.children) do walk(child) end
  end
  walk(window().ssk_cell_panel.ssk_cell_ports.ssk_cell_port_table["ssk_cell_" .. side .. "_ports"])
  return out
end
local function add_button(side) return window().ssk_cell_panel.ssk_cell_ports.ssk_cell_port_table["ssk_cell_" .. side .. "_add"] end
local function press(button) assert(Cells.on_click(player, button)) end

local cable, circuit = machine(0.5, "copper-cable"), machine(4.5, "electronic-circuit")
assert(Cells.suggest_ports == nil, "Boundaries are chosen by hand, not suggested")

-- Create: the boundary starts empty; + adds items and fluids, a click removes them.
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = { cable, circuit } }
assert(window().location.x < 50, "The editor opens at the left of the screen")
assert(not next(ports_of("inputs")) and not next(ports_of("outputs")), "A new cell's boundary starts empty")
assert(add_button("inputs") and add_button("outputs"), "Both sides offer +")
name_field().text = "Circuits"
window().location = { x = 300, y = 200 }
press(add_button("outputs"))
local popup = assert(player.gui.screen.ssk_material_picker, "+ opens the material picker")
assert(popup.tags.target == "cell-outputs" and not popup.tags.allowed, "Any item or fluid can be added")
TREQ("scripts.material_picker").close(player)
for _, key in ipairs({ "item/electronic-circuit", "item/iron-gear-wheel" }) do Cells.pick_port(player, "outputs", key) end
for _, key in ipairs({ "item/iron-plate", "item/copper-plate", "item/copper-cable" }) do Cells.pick_port(player, "inputs", key) end
assert(ports_of("outputs")["item/electronic-circuit"] and ports_of("inputs")["item/copper-cable"], "Picked items are listed")
assert(name_field().text == "Circuits", "Adding items keeps the typed name")
assert(window().location.x == 300 and window().location.y == 200, "Editing items keeps the window where it was")
press(ports_of("inputs")["item/copper-cable"])
assert(not ports_of("inputs")["item/copper-cable"], "Clicking an item removes it")
Cells.pick_port(player, "inputs", "item/iron-gear-wheel")
assert(ports_of("inputs")["item/iron-gear-wheel"] and not ports_of("outputs")["item/iron-gear-wheel"],
  "An item added to the other side moves there")
Cells.pick_port(player, "outputs", "item/iron-gear-wheel")
assert(ports_of("outputs")["item/iron-gear-wheel"] and not ports_of("inputs")["item/iron-gear-wheel"])
click { ssk_cell = "port", side = "bogus", key = "item/iron-plate" }
Cells.pick_port(player, "bogus", "item/stone")
assert(ports_of("inputs")["item/iron-plate"] and not ports_of("inputs")["item/stone"], "Unknown sides are ignored")
local display = window().ssk_cell_panel.ssk_cell_form.ssk_cell_item_column.ssk_cell_display_item
assert(display.sprite == "item/electronic-circuit", "A new cell starts with its main product")
Cells.open_display_picker(player)
assert(player.gui.screen.ssk_material_picker and not player.gui.screen.ssk_material_picker.tags.allowed,
  "The display picker offers every item and fluid")
TREQ("scripts.material_picker").close(player)
Cells.pick_display_item(player, "fluid/water")
assert(display.sprite == "fluid/water", "A fluid can represent the cell")
click { ssk_cell = "save" }
local id, record = next(storage.production_cells.records)
assert(record.display_item == "fluid/water"
  and Flow.build(nil, { mode = "capacity" }).nodes["recipe/cell-" .. id].sprite == "fluid/water",
  "The chosen display fluid is saved and charted")
assert(record.ports.inputs["item/iron-plate"] and record.ports.inputs["item/copper-plate"]
  and not record.ports.inputs["item/copper-cable"], "Saving keeps exactly the chosen inputs")
assert(record.ports.outputs["item/electronic-circuit"] and record.ports.outputs["item/iron-gear-wheel"]
  and record.excluded == nil and record.added == nil)
assert(window().location.x == 300, "The saved-cells list opens where the editor was")

-- The All view shows only the chosen boundary.
local function all_keys(opts)
  local keys = {}
  for key in pairs(Flow.build(nil, opts or { mode = "capacity" }).nodes) do keys[key:match("^[^#]+")] = true end
  return keys
end
local keys = all_keys()
assert(keys["item/iron-plate"] and keys["item/electronic-circuit"] and not keys["item/copper-cable"],
  "The All view must chart only the chosen items")

-- Edit: starts from the saved boundary; nothing changes until Save.
click { ssk_cell = "edit", cell_id = id }
assert(ports_of("outputs")["item/iron-gear-wheel"] and ports_of("inputs")["item/copper-plate"],
  "Editing must start from the saved boundary")
press(ports_of("outputs")["item/electronic-circuit"])
press(ports_of("inputs")["item/copper-plate"])
assert(not ports_of("outputs")["item/electronic-circuit"])
assert(record.ports.outputs["item/electronic-circuit"], "Editing must not change the saved cell before saving")
click { ssk_cell = "save" }
record = storage.production_cells.records[id]
assert(record.ports.inputs["item/iron-plate"] and not record.ports.inputs["item/copper-plate"]
  and not record.ports.outputs["item/electronic-circuit"], "Edits to the boundary must be saved")
keys = all_keys()
assert(keys["item/iron-plate"] and not keys["item/electronic-circuit"] and not keys["item/copper-plate"])

-- Cells saved before boundaries were chosen by hand show every net flow, and
-- editing one starts from those flows.
local chosen = record.ports
record.ports = nil
assert(all_keys()["item/electronic-circuit"], "Older cells keep every net flow")
click { ssk_cell = "edit", cell_id = id }
assert(ports_of("outputs")["item/electronic-circuit"] and ports_of("inputs")["item/copper-plate"],
  "Editing an older cell starts from its net flows")
click { ssk_cell = "list" }
record.ports = chosen

-- Surface scope: cells on other surfaces stay out of the list and the All view.
storage.production_cells.records[99] = { id = 99, name = "Elsewhere", surface_index = 72, members = {},
  positions = {}, display_item = false }
local ids = Flow.ids(nauvis.index)
assert(#ids == 1 and ids[1] == id and #Flow.ids() == 2, "The list must follow the selected surface")
local elsewhere = { index = 72, name = "elsewhere", valid = true }
rawset(game.surfaces, 72, elsewhere)
Cells.open(player)
local function listed()
  local names = {}
  local function walk(element)
    if element.tags and element.tags.ssk_cell == "show" then names[element.tags.cell_id] = true end
    for _, child in ipairs(element.children) do walk(child) end
  end
  walk(window())
  return names
end
local picker = window().ssk_cell_panel.children[1].ssk_cell_list_surface
assert(picker and #picker.items == 3 and picker.selected_index == 1, "The list offers Where I am and each surface with cells")
assert(listed()[id] and not listed()[99], "The list starts on the player's surface")
picker.selected_index = 3
Cells.on_list_surface(player, picker)
assert(listed()[99] and not listed()[id], "Choosing a surface lists its cells")
assert(window().ssk_cell_panel.children[1].ssk_cell_list_surface.selected_index == 3, "The choice is kept")
picker = window().ssk_cell_panel.children[1].ssk_cell_list_surface
picker.selected_index = 1
Cells.on_list_surface(player, picker)
assert(listed()[id] and not listed()[99])
Cells.close(player)
rawset(game.surfaces, 72, nil)
local nodes = Flow.build(nil, { mode = "capacity", surface = nauvis.index }).nodes
assert(nodes["recipe/cell-" .. id] and not nodes["recipe/cell-99"], "The All view must follow the selected surface")
local measured = Flow.build(nil, { mode = "measured", period = 600, surface = nauvis.index })
local line = measured.nodes["recipe/cell-" .. id].rate_line
assert(not line or (line[1] == "production-flow.cells-node-utilisation" and #line == 2),
  "Cell nodes must not repeat the surface the tab already shows")

-- After saving, the saved-cells list docks at the left and closes on a click outside it.
storage.production_cells.records[99] = nil
storage.production_cells.places = nil
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
local function save_cell(name, entities, ports)
  Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = entities }
  for side, list in pairs(ports) do
    for _, key in ipairs(list) do Cells.pick_port(player, side, key) end
  end
  name_field().text = name
  click { ssk_cell = "save" }
  Cells.close(player)
  for cell_id, saved in pairs(storage.production_cells.records) do if saved.name == name then made[name] = cell_id end end
end
save_cell("Inserters", { machine(20.5, "inserter") }, { inputs = { "item/electronic-circuit", "item/iron-gear-wheel",
  "item/iron-plate" }, outputs = { "item/inserter" } })
save_cell("Circuits", { machine(24.5, "electronic-circuit") }, { inputs = { "item/iron-plate", "item/copper-cable" },
  outputs = { "item/electronic-circuit" } })
save_cell("Cable", { machine(28.5, "copper-cable") }, { inputs = { "item/copper-plate" }, outputs = { "item/copper-cable" } })
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

-- Display item: depth first. Bioflux and nutrients are both two steps from raw
-- fruit, even when nutrients are made from bioflux. Among equals, an item the cell
-- uses itself (as an ingredient or as fuel) ranks lower, then the item drawing on
-- more raw materials ranks higher; the much larger nutrient rate does not decide.
local saved_graph, saved_items = storage.graph, prototypes.item
local function node(key, depth, producers) return { key = key, depth = depth, era = 0, producers = producers or {} } end
local function recipe(ingredients, products, energy)
  local r = { era = 0, energy = energy, ingredients = {}, products = {} }
  for key, amount in pairs(ingredients) do r.ingredients[#r.ingredients + 1] = { key = key, amount = amount } end
  for key, amount in pairs(products) do r.products[#r.products + 1] = { key = key, amount = amount, prod = amount } end
  return r
end
storage.graph = {
  nodes = {
    ["item/yumako"] = node("item/yumako", 0), ["item/jellynut"] = node("item/jellynut", 0),
    ["item/yumako-mash"] = node("item/yumako-mash", 1, { "yumako-processing" }),
    ["item/jelly"] = node("item/jelly", 1, { "jellynut-processing" }),
    ["item/bioflux"] = node("item/bioflux", 2, { "bioflux" }),
    ["item/nutrients"] = node("item/nutrients", 2, { "nutrients-from-yumako-mash", "nutrients-from-bioflux" }),
  },
  recipes = {
    ["yumako-processing"] = recipe({ ["item/yumako"] = 1 }, { ["item/yumako-mash"] = 2 }, 1),
    ["jellynut-processing"] = recipe({ ["item/jellynut"] = 1 }, { ["item/jelly"] = 4 }, 1),
    ["bioflux"] = recipe({ ["item/yumako-mash"] = 15, ["item/jelly"] = 12 }, { ["item/bioflux"] = 4 }, 6),
    ["nutrients-from-yumako-mash"] = recipe({ ["item/yumako-mash"] = 4 }, { ["item/nutrients"] = 6 }, 2),
    ["nutrients-from-bioflux"] = recipe({ ["item/bioflux"] = 5 }, { ["item/nutrients"] = 40 }, 2),
  },
}
prototypes.item = setmetatable({ nutrients = { name = "nutrients", fuel_categories = { "nutrients" } } },
  { __index = saved_items })
local function biochamber(x, name, burner)
  local e = machine(x, name)
  e.crafting_speed = 2
  e.prototype = { burner_prototype = burner and { fuel_categories = { nutrients = true } } or nil }
  return e
end
local function main_item(...)
  local members = {}
  for _, e in ipairs({ ... }) do members[e.unit_number] = e end
  return Cells.display_item({}, members)
end
assert(main_item(biochamber(40.5, "bioflux", true), biochamber(44.5, "nutrients-from-bioflux", true)) == "item/bioflux",
  "Bioflux, not the nutrients feeding the biochambers, represents a bioflux cell")
assert(main_item(biochamber(48.5, "bioflux"), biochamber(52.5, "nutrients-from-bioflux")) == "item/nutrients",
  "An item the cell uses itself ranks below an equally deep item it does not use")
assert(main_item(biochamber(56.5, "yumako-processing", true), biochamber(60.5, "nutrients-from-yumako-mash", true))
  == "item/nutrients", "A deeper item outranks a shallower one")
storage.graph, prototypes.item = saved_graph, saved_items

-- Mined resources stay raw even when a later recipe also makes them, so the
-- chains built on them keep their depth.
local G = TREQ("scripts.graph")
local function ore_graph(mined)
  return { mined = mined, recipes = {
      crushing = { era = 5, ingredients = { { key = "item/chunk" } } },
      smelting = { era = 0, ingredients = { { key = "item/ore" } } },
    }, nodes = {
      ["item/chunk"] = { era = 5, producers = {} },
      ["item/ore"] = { era = 0, producers = { "crushing" } },
      ["item/plate"] = { era = 0, producers = { "smelting" } },
    } }
end
local fixed, old = ore_graph({ ["item/ore"] = true }), ore_graph(nil)
G.compute_depth(fixed); G.compute_depth(old)
assert(fixed.nodes["item/ore"].depth == 0 and fixed.nodes["item/plate"].depth == 1, "Mined ore is raw")
assert(old.nodes["item/plate"].depth == 0, "Without the mined list the chain collapses (the old behaviour)")

Cells.cancel(player)
storage.production_cells, player.cursor_stack, player.request_translation = saved_storage, saved_cursor, saved_translate
print("CELL PORTS PASS: manual boundary add/remove/move, kept window place, surface list, saved boundary, edit section, older cells, display-item ranking, mined raw depth, All view filter, surface scope, show button, list docks left and closes on outside click, production-order stages")
