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
local function grid(side)
  return window().ssk_cell_panel.ssk_cell_ports[side].slots.scroll.materials
end
local function ports_of(side, excluded)
  local out = {}
  for _, element in ipairs(grid(side).children) do
    if element.tags.ssk_cell == "port" and element.toggled == (not excluded) then out[element.tags.key] = element end
  end
  return out
end
local function add_button(side) return grid(side).add_material end
local function press(button) assert(Cells.on_click(player, button)) end

local cable, circuit = machine(0.5, "copper-cable"), machine(4.5, "electronic-circuit")

-- Suggestions follow the machines currently selected, including fluid flows and unique recipe icons/names.
local refinery = machine(8.5, "advanced-oil-processing")
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = { refinery } }
assert(ports_of("inputs")["fluid/water"] and ports_of("outputs")["fluid/petroleum-gas"])
assert(window().ssk_cell_panel.ssk_cell_form.ssk_cell_item_column.ssk_cell_display_item.sprite == "recipe/advanced-oil-processing",
  "Unique top-ranked recipe becomes the automatic display icon")
assert(name_field().text == "Advanced oil processing", "Unique top-ranked recipe becomes the automatic cell name")
Cells.cancel(player)

-- A balanced intermediate is available on both sides as a gray choice.
cable.crafting_speed = 1.5
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = { cable, circuit } }
assert(ports_of("inputs", true)["item/copper-cable"] and ports_of("outputs", true)["item/copper-cable"],
  "Internally balanced ingredients and products remain available as excluded choices")
Cells.cancel(player)
cable.crafting_speed = 1

-- New cells start with the proposed boundary selected in two grids.
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = { cable, circuit } }
assert(window().location.x < 50, "The editor opens at the left of the screen")
assert(ports_of("outputs")["item/electronic-circuit"] and ports_of("inputs")["item/iron-plate"])
assert(ports_of("inputs", true)["item/copper-cable"] and ports_of("outputs", true)["item/copper-cable"],
  "Internal intermediates stay excluded by default even when ratios are imperfect")
local inputs = grid("inputs").children
assert(inputs[1].sprite == "item/copper-plate" and inputs[2].sprite == "item/iron-plate"
  and inputs[3].sprite == "item/copper-cable", "Upstream inputs precede intermediates on the input side")
for _, side in ipairs({ "inputs", "outputs" }) do
  local slots = grid(side).children
  assert(slots[#slots] == add_button(side), "The + button uses the first free slot")
end
name_field().text = "Circuits"
window().location = { x = 300, y = 200 }
press(assert(ports_of("inputs")["item/iron-plate"]))
press(assert(ports_of("inputs", true)["item/iron-plate"]))
press(assert(ports_of("outputs")["item/electronic-circuit"]))
press(assert(ports_of("outputs", true)["item/electronic-circuit"]))
assert(ports_of("inputs")["item/iron-plate"] and ports_of("outputs")["item/electronic-circuit"])
assert(not ports_of("inputs", true)["item/iron-plate"] and not ports_of("outputs", true)["item/electronic-circuit"])
press(add_button("outputs"))
local popup = assert(player.gui.screen.ssk_material_picker, "+ opens the material picker")
assert(popup.tags.target == "cell-outputs" and not popup.tags.allowed, "Any item or fluid can be added")
TREQ("scripts.material_picker").close(player)
Cells.pick_port(player, "outputs", "item/iron-gear-wheel")
for _, key in ipairs({ "item/copper-plate", "item/copper-cable" }) do Cells.pick_port(player, "inputs", key) end
assert(ports_of("outputs")["item/electronic-circuit"] and ports_of("inputs")["item/copper-cable"], "Picked items are listed")
assert(name_field().text == "Circuits", "Adding items keeps the typed name")
assert(window().location.x == 300 and window().location.y == 200, "Editing items keeps the window where it was")
press(ports_of("inputs")["item/copper-cable"])
assert(not ports_of("inputs")["item/copper-cable"], "Clicking an item removes it")
assert(ports_of("inputs", true)["item/copper-cable"], "Removing a choice makes the material available again")
assert(grid("outputs").children[1].sprite == "item/electronic-circuit"
  and grid("outputs").children[2].sprite == "item/copper-cable",
  "End products precede a faster intermediate in the output grid")
Cells.pick_port(player, "outputs", "item/copper-cable")
assert(not ports_of("inputs", true)["item/copper-cable"], "Suggestions respect materials chosen on the other side")
press(ports_of("outputs")["item/copper-cable"])
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
local saved_oil_group = prototypes.recipe["advanced-oil-processing"].group
local saved_ec_group = prototypes.recipe["electronic-circuit"].group
local saved_ec_item = rawget(prototypes.item, "electronic-circuit")
prototypes.recipe["advanced-oil-processing"].group = { name = "intermediate-products", order = "c" }
prototypes.recipe["electronic-circuit"].group = { name = "intermediate-products", order = "c" }
prototypes.item["electronic-circuit"] = { name = "electronic-circuit", group = { name = "intermediate-products", order = "c" }, subgroup = { name = "intermediate-product", order = "a" } }
Cells.open_display_picker(player)
local display_picker = assert(player.gui.screen.ssk_material_picker)
assert(not display_picker.tags.allowed, "The display picker offers every item, fluid and unique recipe")
local picker_keys = {}
display_picker.ssk_title.ssk_query.text = "oil"
TREQ("scripts.material_picker").on_text_changed { player_index = player.index, element = display_picker.ssk_title.ssk_query }
for _, key in ipairs(display_picker.ssk_material_inner.ssk_slot_frame.ssk_slot_scroll.ssk_results.tags.keys) do
  picker_keys[key] = true
end
assert(picker_keys["recipe/advanced-oil-processing"], "Unique recipe icons appear in the display picker")
display_picker.ssk_title.ssk_query.text = "electronic"
TREQ("scripts.material_picker").on_text_changed { player_index = player.index, element = display_picker.ssk_title.ssk_query }
picker_keys = {}
for _, key in ipairs(display_picker.ssk_material_inner.ssk_slot_frame.ssk_slot_scroll.ssk_results.tags.keys) do
  picker_keys[key] = true
end
assert(picker_keys["item/electronic-circuit"] and not picker_keys["recipe/electronic-circuit"],
  "Recipes that share a name with an item are deduplicated")
TREQ("scripts.material_picker").close(player)
prototypes.recipe["advanced-oil-processing"].group = saved_oil_group
prototypes.recipe["electronic-circuit"].group = saved_ec_group
prototypes.item["electronic-circuit"] = saved_ec_item
Cells.pick_display_item(player, "recipe/advanced-oil-processing")
assert(display.sprite == "recipe/advanced-oil-processing", "A recipe icon can represent the cell")
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
local detail = Flow.build(id, { mode = "capacity" })
assert(detail.nodes["item/iron-plate"] and detail.nodes["item/electronic-circuit"].cell_output)
assert(detail.nodes["item/copper-cable"] and not detail.nodes["item/copper-cable#cell-input"],
  "Internal cable remains visible and its unselected external share is omitted")
record.ports.inputs["item/copper-cable"] = true
record.ports.inputs["item/copper-plate"] = nil
local selected = Flow.build(id, { mode = "capacity" })
assert(selected.links["item/copper-cable#cell-input>item/copper-cable"].rate == 1)
assert(not selected.nodes["item/copper-plate"], "Deselecting an input hides the external source")
record.ports.inputs["item/copper-cable"] = nil
record.ports.inputs["item/copper-plate"] = true

-- Edit: starts from the saved boundary; nothing changes until Save.
click { ssk_cell = "edit", cell_id = id }
assert(ports_of("outputs")["item/iron-gear-wheel"] and ports_of("inputs")["item/copper-plate"],
  "Editing must start from the saved boundary")
press(ports_of("outputs")["item/electronic-circuit"])
press(ports_of("inputs")["item/copper-plate"])
assert(not ports_of("outputs")["item/electronic-circuit"])
assert(ports_of("outputs", true)["item/electronic-circuit"] and ports_of("inputs", true)["item/copper-plate"],
  "Edits can accept suggestions for remaining materials")
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
-- Train stops are owned metadata, never Flow nodes or material links.
do
  local record = storage.production_cells.records[made.Cable]
  local old = record.stops
  record.stops = { [99123] = { unit = 99123, role = "import" } }
  local with_stop = Flow.build(nil, { mode = "capacity", surface = nauvis.index })
  for key, value in pairs(staged.nodes) do
    assert(with_stop.nodes[key] and with_stop.nodes[key].prod == value.prod and with_stop.nodes[key].cons == value.cons,
      "Linked stops must not change Flow nodes or rates")
  end
  for key in pairs(with_stop.nodes) do assert(staged.nodes[key], "Linked stops must not add Flow nodes") end
  for key, value in pairs(staged.links) do
    assert(with_stop.links[key] and with_stop.links[key].rate == value.rate, "Linked stops must not change Flow links")
  end
  for key in pairs(with_stop.links) do assert(staged.links[key], "Linked stops must not add Flow links") end
  record.stops = old
end
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
-- Ancestor membership is inclusive, while only peers compete for overview
-- ownership. A grandchild must not turn its parent into a shared root.
do
  local records = storage.production_cells.records
  local cable, circuits = records[made.Cable], records[made.Circuits]
  local parent_id, grandchild_id = 9001, 9002
  local members = {}
  for unit, entity in pairs(cable.members) do members[unit] = entity end
  for unit, entity in pairs(circuits.members) do members[unit] = entity end
  records[parent_id] = { id = parent_id, name = "Parent", surface_index = nauvis.index, members = members, since = 0 }
  records[grandchild_id] = { id = grandchild_id, name = "Grandchild", surface_index = nauvis.index,
    members = cable.members, parent_id = made.Cable, since = 0 }
  cable.parent_id, circuits.parent_id = parent_id, parent_id
  local roots = Flow.build(nil, { mode = "capacity", surface = nauvis.index })
  assert(roots.nodes["recipe/cell-" .. parent_id] and not roots.nodes["recipe/cell-" .. made.Cable],
    "Root overview must not count descendants as peers")
  local children = Flow.build(nil, { mode = "capacity", surface = nauvis.index, scope = parent_id })
  assert(not children.overlap and children.links["recipe/cell-" .. made.Cable .. ">" .. cable_key]
    and children.links[cable_key .. ">recipe/cell-" .. made.Circuits],
    "Disjoint children must link despite their inclusive parent and grandchild")
  local parent = Flow.build(parent_id, { mode = "capacity", surface = nauvis.index })
  assert(parent.nodes["recipe/cell-" .. made.Cable] and parent.nodes["recipe/cell-" .. made.Circuits]
    and parent.links["recipe/cell-" .. made.Cable .. ">" .. cable_key]
    and parent.links[cable_key .. ">recipe/cell-" .. made.Circuits],
    "Parent Flow must group children and retain their internal transfer")
  records[parent_id].ports = { inputs = {}, outputs = {} }
  local hidden = Flow.build(parent_id, { mode = "capacity", surface = nauvis.index })
  assert(hidden.links["recipe/cell-" .. made.Cable .. ">" .. cable_key]
    and hidden.links[cable_key .. ">recipe/cell-" .. made.Circuits],
    "A hidden parent output must not remove an internal transfer")
  records[parent_id].ports = nil
  local unit, entity = next(cable.members)
  circuits.members[unit] = entity
  local overlap = Flow.build(nil, { mode = "capacity", surface = nauvis.index, scope = parent_id })
  assert(overlap.overlap and not overlap.links["recipe/cell-" .. made.Cable .. ">" .. cable_key],
    "A machine shared by siblings must be excluded from both peer rates")
  local shared_parent = Flow.build(parent_id, { mode = "capacity", surface = nauvis.index })
  local remainder = shared_parent.nodes["recipe/cell-" .. parent_id]
  assert(remainder and shared_parent.links["recipe/cell-" .. parent_id .. ">" .. cable_key]
    and not shared_parent.links["recipe/cell-" .. made.Cable .. ">" .. cable_key],
    "Shared sibling production must appear exactly once in the parent remainder")
  circuits.members[unit] = nil
  cable.parent_id, circuits.parent_id = nil, nil
  records[parent_id], records[grandchild_id] = nil, nil
end
-- A loop is broken at the oldest cell; its backward use gets its own input node.
local loop = Flow.stages({ 1, 2 }, {
  [1] = { surface_index = 1, ports = { inputs = { a = true }, outputs = { b = true } } },
  [2] = { surface_index = 1, ports = { inputs = { b = true }, outputs = { a = true } } },
})
assert(loop[1] == 1 and loop[2] == 2, "Loops are ordered by creation")

-- Output ranking is local to the cell. Fuel-making recipes add no level
-- and fuel is ranked after ordinary products.
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
prototypes.item = setmetatable({ nutrients = { name = "nutrients", fuel_value = 2e6, fuel_categories = { "nutrients" } } },
  { __index = saved_items })
local function biochamber(x, name, burner)
  local e = machine(x, name)
  e.crafting_speed = 2
  if burner then
    e.name = "biochamber"
    e.prototype = { get_max_energy_usage = function() return 500000 / 60 end }
  end
  return e
end
local burners_before = storage.cell_burner_prototypes
storage.cell_burner_prototypes = {
  biochamber = { effectivity = 1, fuel_categories = { nutrients = true } },
}
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
  == "item/yumako-mash", "A fuel-making recipe does not lower its ingredient")

local bioflux, nutrients = "item/bioflux", "item/nutrients"
local bioflux_cell = { id = 100, surface_index = nauvis.index, name = "Bioflux",
  members = {}, ports = { inputs = { ["item/jelly"] = true, ["item/yumako-mash"] = true },
    outputs = { [bioflux] = true } } }
local nutrient_chamber
for i, name in ipairs({ "bioflux", "bioflux", "bioflux", "nutrients-from-bioflux" }) do
  local e = biochamber(40.5 + i * 4, name, true)
  e.productivity_bonus = 0.5
  bioflux_cell.members[e.unit_number] = e
  if name == "nutrients-from-bioflux" then nutrient_chamber = e end
end
storage.production_cells.records[bioflux_cell.id] = bioflux_cell
local capacity = Flow.build(bioflux_cell.id, { mode = "capacity" })
assert(capacity.nodes[bioflux .. "#cell-output"].cell_output)
assert(math.abs(capacity.links[bioflux .. ">" .. bioflux .. "#cell-output"].rate - 1) < 1e-6,
  "The selected Bioflux endpoint shows the surplus after the nutrient recipe")
assert(capacity.nodes[nutrients] and not capacity.nodes[nutrients].cell_output)
assert(not capacity.nodes[nutrients .. "#cell-fuel-input"], "Internal fuel covers the steady-state demand")
local loop = assert(capacity.fuel_returns[1])
assert(loop.key == nutrients and #loop.consumers == 2)
assert(loop.consumers[1].key == "recipe/bioflux" and math.abs(loop.consumers[1].rate - 0.75) < 1e-6)
assert(loop.consumers[2].key == "recipe/nutrients-from-bioflux" and math.abs(loop.consumers[2].rate - 0.25) < 1e-6,
  "The nutrient producer also burns fuel")
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = bioflux_cell.members }
local output_buttons = grid("outputs").children
assert(output_buttons[1].sprite == bioflux and output_buttons[1].toggled
  and output_buttons[#output_buttons - 1].sprite == nutrients and not output_buttons[#output_buttons - 1].toggled,
  "New cells put internal fuel last and leave it excluded as an export")
Cells.cancel(player)
nutrient_chamber.crafting_speed = 0.01
bioflux_cell.ports.inputs[nutrients] = true
local short = Flow.build(bioflux_cell.id, { mode = "capacity" })
assert(math.abs(short.nodes[nutrients .. "#cell-fuel-input"].cons - 0.7) < 1e-6,
  "A running fuel shortfall remains visible as an external input")
Cells.on_selected { item = Selection.tool, player_index = player.index, surface = nauvis, entities = bioflux_cell.members }
assert(grid("inputs").children[1].sprite == nutrients and grid("inputs").children[1].toggled,
  "Fuel ranks ahead of higher-demand ingredients in the input grid")
Cells.cancel(player)
nutrient_chamber.crafting_speed = 2
bioflux_cell.ports.inputs[nutrients] = nil
storage.cell_burner_prototypes = {}
local recipe_only = Flow.build(bioflux_cell.id, { mode = "capacity" })
assert(not recipe_only.nodes[nutrients] and not recipe_only.nodes["recipe/nutrients-from-bioflux"],
  "A downstream product without a selected or internal use is omitted")
storage.production_cells.records[bioflux_cell.id] = nil
storage.cell_burner_prototypes = burners_before
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

-- Cell-to-cell cycles break by widest downstream fanout and route backward
-- feedback through thin return lines instead of duplicating the material node.
do
  local loop_records = {
    [1] = { id = 1, surface_index = 1, ports = { inputs = { ["fluid/sulfuric-acid"] = true }, outputs = { ["item/iron-plate"] = true } } },
    [2] = { id = 2, surface_index = 1, ports = { inputs = { ["item/iron-plate"] = true }, outputs = { ["fluid/sulfuric-acid"] = true } } },
    [3] = { id = 3, surface_index = 1, ports = { inputs = { ["fluid/sulfuric-acid"] = true }, outputs = { ["item/copper-plate"] = true } } },
    [4] = { id = 4, surface_index = 1, ports = { inputs = { ["fluid/sulfuric-acid"] = true, ["item/iron-plate"] = true, ["item/copper-plate"] = true }, outputs = { ["item/battery"] = true } } },
  }
  local stages = Flow.stages({ 1, 2, 3, 4 }, loop_records)
  assert(stages[2] == 1 and stages[1] == 2 and stages[3] == 2 and stages[4] == 3,
    "Wider-fanout utility cell (acid) precedes iron even when created later")
  local g = { nodes = {}, links = {} }
  for id = 1, 4 do g.nodes["recipe/cell-" .. id] = { key = "recipe/cell-" .. id, is_cell = true, tier = 2 * stages[id], prod = 0, cons = 0, contrib = {} } end
  Flow.link_stages(g, {
    { id = 1, cell = "recipe/cell-1", surface = nauvis, stage = stages[1],
      flows = { { key = "fluid/sulfuric-acid", amount = -400 }, { key = "item/iron-plate", amount = 120 } } },
    { id = 2, cell = "recipe/cell-2", surface = nauvis, stage = stages[2],
      flows = { { key = "item/iron-plate", amount = -32 }, { key = "fluid/sulfuric-acid", amount = 1600 } } },
    { id = 3, cell = "recipe/cell-3", surface = nauvis, stage = stages[3],
      flows = { { key = "fluid/sulfuric-acid", amount = -400 }, { key = "item/copper-plate", amount = 120 } } },
    { id = 4, cell = "recipe/cell-4", surface = nauvis, stage = stages[4],
      flows = { { key = "fluid/sulfuric-acid", amount = -200 }, { key = "item/iron-plate", amount = -88 }, { key = "item/copper-plate", amount = -88 }, { key = "item/battery", amount = 60 } } },
  })
  assert(g.nodes["item/iron-plate#surface-1-output"] and not g.nodes["item/iron-plate#surface-1-input"],
    "Looped iron plate stays one output node without a duplicate left-side input node")
  assert(g.cell_returns and #g.cell_returns == 1
    and g.cell_returns[1].key == "item/iron-plate#surface-1-output"
    and g.cell_returns[1].consumers[1].key == "recipe/cell-2"
    and g.cell_returns[1].consumers[1].rate == 32,
    "Backward iron-plate feedback routes as a thin return line to the acid cell")
end

Cells.cancel(player)
storage.production_cells, player.cursor_stack, player.request_translation = saved_storage, saved_cursor, saved_translate
print("CELL PORTS PASS: manual boundary add/remove/move, kept window place, surface list, saved boundary, edit section, older cells, display-item ranking, mined raw depth, All view filter, surface scope, show button, list docks left and closes on outside click, production-order stages")
