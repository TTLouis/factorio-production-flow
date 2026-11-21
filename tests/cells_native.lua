-- Private native fixture. Dispatches registered handlers using real GUI and entities.
local T = {}
local RecipeDetails = require("scripts.recipe_details")
local Selection = require("shared.cell_selection")
local Sprites = require("shared.sprites")
local Palette = require("shared.palette")
local Flow = require("scripts.cell_flow")
local Cells = require("scripts.cells")
local Sampler = require("scripts.sampler")
local CellsUI = require("scripts.cells_ui")
local Model = require("scripts.model")
local View = require("scripts.view")
local Sankey = require("scripts.sankey_ui")
-- The construction checks assert full-speed rates; measured rates are checked
-- separately once the machines have run on real ingredients.
local CAPACITY = {mode = "capacity"}

local function find(parent, key, value, part)
  if parent.tags[key] == value and (not part or parent.tags.part == part) then return parent end
  for _, element in ipairs(parent.children) do
    local found = find(element, key, value, part)
    if found then return found end
  end
end

local function click(player, parent, key, value)
  local element = assert(find(parent, key, value), value)
  script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = element}
end

-- Adds a boundary item through the editor's + button and the material picker.
local function ports(player, side)
  return player.gui.screen.ssk_cells.ssk_cell_panel.ssk_cell_ports[side]
end

local function add_port(player, side, key)
  local grid = ports(player, side).slots.scroll.materials
  assert(grid.children[#grid.children] == grid.add_material, "The picker opens from the first free slot")
  click(player, grid.add_material, "side", side)
  local popup = assert(player.gui.screen.ssk_material_picker, "+ opens the material picker")
  local kind, name = key:match("^(%a+)/(.+)$")
  local group = prototypes[kind][name].group.name
  local function group_tab(element)
    if element.tags.ssk_picker == "group" and element.tags.group == group then return element end
    for _, child in ipairs(element.children) do
      local found = group_tab(child)
      if found then return found end
    end
  end
  local tab = group_tab(popup)
  if tab then script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = tab} end
  click(player, player.gui.screen.ssk_material_picker, "key", key)
  assert(not player.gui.screen.ssk_material_picker and find(ports(player, side), "key", key).toggled,
    "The picked item joins the boundary")
end

local function select_area(player, entities)
  script.get_event_handler(defines.events.on_player_selected_area){
    player_index = player.index, item = Selection.tool, surface = player.surface, entities = entities,
  }
end

local function screenshot(player, name)
  game.take_screenshot{player = player, path = "cells/" .. name .. ".png",
    resolution = {1920, 1080}, show_gui = true, force_render = true}
end

local function outlines(player, slot)
  local mine = storage.cell_outlines and storage.cell_outlines[player.index]
  return mine and mine[slot or "map"]
end

local function cells_tab(player)
  local tabs = player.gui.screen.ssk_main.ssk_inner.ssk_tabs
  for i, id in ipairs(tabs.tags.ssk_tab_ids) do
    if id == "cells" then
      if tabs.selected_tab_index ~= i then
        tabs.selected_tab_index = i
        script.get_event_handler(defines.events.on_gui_selected_tab_changed){player_index = player.index, element = tabs}
      end
      return player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split
    end
  end
  error("Cells tab missing")
end

-- The tab lists cells in production order, so look rows up by cell id.
local function row_of(player, id)
  for i, cell_id in ipairs(storage.ui[player.index].cells.ids) do
    if cell_id == id then return i + 1 end
  end
end

local function has_caption(element, key)
  local caption = element.caption
  if type(caption) == "table" and caption[1] == key then return true end
  for _, child in ipairs(element.children) do if has_caption(child, key) then return true end end
  return false
end

local REFINERY_OUTPUTS = { ["heavy-oil"] = 5, ["light-oil"] = 60, ["petroleum-gas"] = 55 }

local function edit_refinery(player, UI)
  local surface = game.create_surface("cells-refinery-test")
  surface.request_to_generate_chunks({0, 0}, 1)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -18, 18 do
    for y = -6, 6 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end
  end
  surface.set_tiles(tiles)
  local cells = storage.production_cells
  local record = { id = cells.next_id, name = "Oil refinery", display_item = "fluid/petroleum-gas",
    surface_index = surface.index, since = game.tick, members = {}, positions = {},
    ports = { inputs = { ["fluid/crude-oil"] = true, ["fluid/water"] = true }, outputs = {} } }
  for i = 1, 6 do
    local refinery = i <= 5
    local recipe = refinery and "advanced-oil-processing" or "heavy-oil-cracking"
    player.force.recipes[recipe].enabled = true
    local machine = assert(surface.create_entity { name = refinery and "oil-refinery" or "chemical-plant",
      position = { i * 5 - 18, 0 }, force = player.force, raise_built = true })
    assert(machine.set_recipe(recipe))
    record.members[machine.unit_number] = machine
    record.positions[machine.unit_number] = machine.position
  end
  cells.records[record.id], cells.next_id = record, record.id + 1
  storage.cell_test_refinery = record.id
  local us = storage.ui[player.index]
  us.tab_id, us.surface = "cells", surface.name
  us.cells.selected, us.cells.view, us.cells.mode, us.cells.chart = record.id, "flow", "capacity", {}
  UI.open(player)
  click(player, cells_tab(player), "ssk_ui", "cell_edit")
  for _, material in ipairs({"heavy-oil", "light-oil", "petroleum-gas"}) do
    local key = "fluid/" .. material
    local outputs = ports(player, "outputs")
    assert(not find(outputs, "key", key).toggled)
    click(player, outputs, "key", key)
    assert(find(ports(player, "outputs"), "key", key).toggled)
  end
  click(player, ports(player, "outputs"), "key", "fluid/heavy-oil")
  local outputs = ports(player, "outputs")
  assert(not find(outputs, "key", "fluid/heavy-oil").toggled
    and find(outputs, "key", "fluid/light-oil").toggled and find(outputs, "key", "fluid/petroleum-gas").toggled,
    "Each refinery output toggles independently")
  click(player, outputs, "key", "fluid/heavy-oil")
end

local function check_refinery_overview(player, record)
  local graph = Flow.build(nil, {mode = "capacity", surface = record.surface_index})
  local key = "recipe/cell-" .. record.id
  for material, rate in pairs(REFINERY_OUTPUTS) do
    assert(record.ports.outputs["fluid/" .. material])
    local link = graph.links[key .. ">fluid/" .. material .. "#surface-" .. record.surface_index .. "-output"]
    assert(math.abs(assert(link).rate - rate) < 1e-7, "Wrong net output for " .. material)
  end
  for material, rate in pairs({ ["crude-oil"] = 100, water = 65 }) do
    local link = graph.links["fluid/" .. material .. "#surface-" .. record.surface_index .. "-input>" .. key]
    assert(math.abs(assert(link).rate - rate) < 1e-7, "Wrong input for " .. material)
  end
  local chart = cells_tab(player).ssk_cell_views.ssk_cell_chart
  local state = {split_raw = false}
  Sankey.defaults(state)
  local layout = View.build(player, state, 1050, 715, graph)
  local bar = layout.nodes[key]
  assert(bar.width == 96 and #bar.fins == 2 and #bar.fouts == 3)
  local ribbons = storage.sk_render[player.index].ribbons
  local function close(a, b) return math.abs(a - b) < 1e-6 end
  local function check_stack(segments, input)
    local y, ratio = bar.y, nil
    for _, segment in ipairs(segments) do
      local edge = input and segment.y2 or segment.y1
      local height = segment.cell_band_h
      assert(height >= 28 and height + 1e-6 >= segment.t and close(edge + segment.t / 2, y + height / 2),
        "Ribbon center must follow its band and bands must touch")
      if height > 28.000001 then
        ratio = ratio or height / segment.rate
        assert(close(height / segment.rate, ratio), "Bands above the floor are proportional to their rates")
      end
      local endpoint = input and segment.link.a or segment.link.b
      local material = endpoint.group_key
      local hit = assert(find(chart, "cell_material", material, "bar"))
      assert(hit.tags.key == key and hit.tags.side == (input and "inputs" or "outputs"))
      local icon = assert(find(chart, "cell_material", material, "icon"))
      assert(icon.sprite == material and icon.style.minimal_width == 22 and icon.style.minimal_height == 22)
      assert(hit.sprite == Sprites.bar(endpoint.color), "Bands use the full material colour")
      local shaded = false
      for _, ribbon in ipairs(ribbons) do
        if ribbon.kind == "bar" and ribbon.from == segment.from and ribbon.to == segment.to then
          assert(ribbon.elem.sprite == Sprites.bar(Palette.muted(endpoint.color)), "Flow ribbons use the shaded material colour")
          shaded = true
        end
      end
      assert(shaded, "Expected a straight ribbon section for " .. material)
      y = y + height
      if material == "fluid/heavy-oil" then assert(close(height, 28), "Small heavy-oil output needs the icon floor") end
    end
    assert(close(y, bar.y + bar.h), "Both stacks fill the bar")
  end
  check_stack(bar.fins, true)
  check_stack(bar.fouts, false)
  assert(find(chart, "ssk_label", key).caption == record.name)
  log("CELL REFINERY BANDS PASS: two inputs and three independently selected net outputs")
end

local function show_bioflux_fuel(player, UI)
  local surface, cells = game.surfaces.nauvis, storage.production_cells
  assert(storage.cell_burner_prototypes.biochamber, "The startup index includes biochambers")
  local record = { id = cells.next_id, name = "Bioflux", display_item = "bioflux",
    surface_index = surface.index, since = game.tick, members = {}, positions = {},
    ports = { inputs = { ["item/jelly"] = true, ["item/yumako-mash"] = true },
      outputs = { ["item/bioflux"] = true } } }
  for i, name in ipairs({ "bioflux", "bioflux", "bioflux", "nutrients-from-bioflux" }) do
    player.force.recipes[name].enabled = true
    local machine = assert(surface.create_entity {
      name = "biochamber", position = { i * 4, -12 }, force = player.force, raise_built = true,
    })
    assert(machine.set_recipe(name))
    if i == 1 then machine.burner.currently_burning = { name = "nutrients" } end
    record.members[machine.unit_number] = machine
    record.positions[machine.unit_number] = machine.position
  end
  cells.records[record.id] = record
  local graph = Flow.build(record.id, CAPACITY)
  local port = assert(graph.links["item/bioflux>item/bioflux#cell-output"])
  assert(math.abs(port.rate - 1) < 1e-6, port.rate)
  local loop = assert(graph.fuel_returns[1])
  assert(loop.key == "item/nutrients" and #loop.consumers == 2)
  assert(math.abs(loop.consumers[1].rate - 0.75) < 1e-6, loop.consumers[1].rate)
  assert(math.abs(loop.consumers[2].rate - 0.25) < 1e-6, loop.consumers[2].rate)
  assert(not graph.nodes["item/nutrients#cell-fuel-input"], "A cold start is separate from running demand")
  local us = storage.ui[player.index]
  us.tab_id, us.surface = "cells", surface.name
  us.cells.selected, us.cells.view, us.cells.mode, us.cells.chart = record.id, "flow", "capacity", {}
  UI.open(player)
  local chart = cells_tab(player).ssk_cell_views.ssk_cell_chart
  assert(find(chart, "key", "item/bioflux#cell-output"))
  assert(find(chart, "ssk_cell_fuel", "item/nutrients"), "The capacity chart draws a nutrient return")
  assert(not find(chart, "key", "item/nutrients#cell-output"))
  assert(not find(chart, "ssk_return_direction", "left"), "Inline markers are off by default")
  log("CELL BIOFLUX FUEL PASS: 1 Bioflux/s exported and 1 nutrient/s returned to four biochambers")
end

local function show_recipe_returns(player, UI)
  -- Feed known rates from native recipes into the regular Full Sankey entry
  -- point so this test does not depend on waiting for matching machine cycles.
  local model = { seconds = 60, edges = {}, residuals = {}, rates = { recipes = {} } }
  for _, name in ipairs({ "water-barrel", "empty-water-barrel", "kovarex-enrichment-process" }) do
    local recipe = assert(storage.graph.recipes[name])
    local rate = name == "kovarex-enrichment-process" and 0.05 or 1
    model.rates.recipes[name] = { normal_cps = rate, cps = rate }
    for _, part in ipairs(recipe.ingredients) do
      local amount = part.amount * rate
      local residual = model.residuals[part.key] or { prod = 0, cons = 0 }
      residual.cons = residual.cons + amount
      model.residuals[part.key] = residual
      model.edges[#model.edges + 1] = { from = part.key, to = "recipe/" .. name, rate = amount, reversing = recipe.reversing }
    end
    for _, part in ipairs(recipe.products) do
      local amount = part.amount * rate
      local residual = model.residuals[part.key] or { prod = 0, cons = 0 }
      residual.prod = residual.prod + amount
      model.residuals[part.key] = residual
      model.edges[#model.edges + 1] = { from = "recipe/" .. name, to = part.key, rate = amount, reversing = recipe.reversing }
    end
  end
  local original = Model.build
  Model.build = function() return model end
  local us = storage.ui[player.index]
  us.tab_id, us.view, us.live = "sankey", "detail", false
  UI.open(player)
  Model.build = original
  local main = assert(player.gui.screen.ssk_main)
  assert(find(main, "ssk_loop_return", "recipe/empty-water-barrel"), "The empty-barrel recipe needs a thin return")
  assert(find(main, "ssk_loop_return", "item/uranium-235"), "The returned Kovarex catalyst needs a thin return")
  log("RECIPE RETURNS NATIVE PASS")
end

function T.tick(UI)
  local player = game.connected_players[1]
  if not player or game.tick < 30 then return end
  local stage = storage.cell_test_phase
  local function window() return assert(player.gui.screen.ssk_cells) end
  if stage == nil then
    local surface = player.surface
    local function spawn(name, x, force)
      return assert(surface.create_entity{name = name, position = {x, 8}, force = force, raise_built = true})
    end
    -- Power for measured crafts: one substation covers every test machine.
    assert(surface.create_entity{name = "substation", position = {3, 12}, force = "player"})
    local power = assert(surface.create_entity{name = "electric-energy-interface", position = {3, 15}, force = "player"})
    power.electric_buffer_size = 1e9
    power.power_production = 1e7
    if not player.character then
      player.set_controller{type = defines.controllers.god}
      assert(player.create_character())
    end
    player.teleport({0, 3})
    storage.cell_test_machines = {
      spawn("assembling-machine-1", -4, "player"),
      spawn("assembling-machine-1", 0, "player"),
      spawn("wooden-chest", 3, "player"),
      spawn("assembling-machine-1", 6, "enemy"),
      spawn("assembling-machine-1", 10, "player"),
    }
    local machines = storage.cell_test_machines
    player.force.recipes["copper-cable"].enabled = true
    player.force.recipes["electronic-circuit"].enabled = true
    machines[1].set_recipe("copper-cable")
    machines[2].set_recipe("electronic-circuit")
    machines[5].set_recipe("iron-gear-wheel")
    player.mod_settings["ssk-allow-small-window"] = {value = true}
    UI.open(player)
    click(player, assert(player.gui.screen.ssk_main, serpent.line(player.display_resolution) .. " scale=" .. player.display_scale .. " force=" .. player.force.name), "ssk_ui", "cells")
    click(player, window(), "ssk_cell", "select")
    assert(player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == Selection.tool
      and not player.gui.screen.ssk_cells, "tool not equipped or window still open")
    local e = storage.cell_test_machines
    select_area(player, {e[3], e[4]})
    assert(player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == Selection.tool
      and not player.gui.screen.ssk_cells, "tool not equipped or window still open")
    select_area(player, {e[1], e[2], e[3], e[4], e[1]})
    assert(not player.cursor_stack.valid_for_read)
    local drafted = assert(outlines(player, "draft"), "The draft's machines must be outlined")
    local game_boxes, chart_boxes = 0, 0
    for _, object in ipairs(drafted.objects) do
      if object.type == "rectangle" and not object.filled then
        if object.render_mode == "chart" then chart_boxes = chart_boxes + 1 else game_boxes = game_boxes + 1 end
      end
    end
    local expected = table_size(storage.production_cells.drafts[player.index].members)
    assert(game_boxes == expected and chart_boxes == expected,
      "Every selected machine gets one game outline and one chart outline")
    log("CELL DRAFT OUTLINES: " .. #drafted.objects .. " objects")
    assert(not next(storage.production_cells.records))
    assert(window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text == "Electronic circuit",
      "Faster copper cable output is consumed inside the cell")
    assert(find(ports(player, "inputs"), "key", "item/copper-plate").toggled)
    assert(find(ports(player, "outputs"), "key", "item/electronic-circuit").toggled)
    local inputs = ports(player, "inputs").slots.scroll.materials.children
    assert(inputs[1].sprite == "item/copper-plate" and inputs[2].sprite == "item/iron-plate"
      and inputs[3].sprite == "item/copper-cable")
    storage.cell_test_phase = "capture-suggestions"
  elseif stage == "capture-suggestions" then
    screenshot(player, "suggestions")
    storage.cell_test_phase = "accept-suggestions"
  elseif stage == "accept-suggestions" then
    assert(not find(ports(player, "inputs"), "key", "item/copper-cable").toggled,
      "Internal copper-cable intermediate starts excluded by default")
    click(player, ports(player, "inputs"), "key", "item/copper-cable")
    assert(find(ports(player, "inputs"), "key", "item/copper-cable").toggled)
    click(player, ports(player, "inputs"), "key", "item/copper-cable")
    assert(not find(ports(player, "inputs"), "key", "item/copper-cable").toggled)
    add_port(player, "outputs", "fluid/water")
    click(player, ports(player, "outputs"), "key", "fluid/water")
    assert(not find(ports(player, "outputs"), "key", "fluid/water").toggled)
    storage.cell_test_phase = "capture-draft"
  elseif stage == "capture-draft" then
    screenshot(player, "draft")
    storage.cell_test_phase = "save"
  elseif stage == "save" then
    window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = "Circuit assembly"
    click(player, window(), "ssk_cell", "save")
    local record = assert(storage.production_cells.records[1])
    local e = storage.cell_test_machines
    assert(record.name == "Circuit assembly" and record.surface_index == player.surface.index)
    assert(record.display_item == "electronic-circuit")
    assert(record.members[e[1].unit_number] == e[1] and record.members[e[2].unit_number] == e[2])
    assert(table_size(record.members) == 2)
    assert(record.ports.inputs["item/copper-plate"] and record.ports.outputs["item/electronic-circuit"]
      and not record.ports.inputs["item/copper-cable"] and not record.ports.outputs["fluid/water"],
      "Saving keeps only the selected slots")
    assert(not outlines(player, "draft"), "Saving clears the draft's outlines")
    storage.cell_test_phase = "capture-list"
  elseif stage == "capture-list" then
    screenshot(player, "saved")
    storage.cell_test_phase = "show"
  elseif stage == "show" then
    click(player, window(), "ssk_cell", "show")
    assert(not player.gui.screen.ssk_cells, "Show must close the saved-cells list")
    local split = cells_tab(player)
    assert(storage.ui[player.index].tab_id == "cells" and storage.ui[player.index].cells.selected == 1
      and split.ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == row_of(player, 1),
      "Show must open the Cells tab on the chosen cell")
    assert(player.gui.screen.ssk_main.ssk_window_bar.ssk_surface_picker.selected_index == 1,
      "A cell on the player's surface keeps Where I am")
    click(player, player.gui.screen.ssk_main, "ssk_ui", "cells")
    storage.cell_test_phase = "edit"
  elseif stage == "edit" then
    click(player, window(), "ssk_cell", "edit")
    window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = "Canceled edit"
    click(player, window(), "ssk_cell", "add")
    local machines = storage.cell_test_machines
    select_area(player, {machines[5], machines[1], machines[5]})
    local cells = storage.production_cells
    assert(table_size(cells.drafts[player.index].members) == 3, "Addition must preserve and deduplicate existing machines")
    assert(table_size(cells.records[1].members) == 2, "Changes must remain in the draft until Save")
    click(player, window(), "ssk_cell", "select")
    select_area(player, {machines[5]})
    assert(table_size(cells.drafts[player.index].members) == 1, "Replace must still reset the whole draft")
    assert(outlines(player, "draft"), "Editing outlines the cell's machines")
    click(player, window(), "ssk_cell", "list")
    assert(not outlines(player, "draft"), "Cancelling an edit clears its outlines")
    assert(storage.production_cells.records[1].name == "Circuit assembly")
    click(player, window(), "ssk_cell", "edit")
    window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = "Circuit assembler"
    click(player, window(), "ssk_cell", "remove")
    select_area(player, {machines[5]})
    assert(not player.gui.screen.ssk_cells and player.cursor_stack.name == Selection.tool,
      "Dragging only over a nonmember must keep the removal tool active")
    select_area(player, {machines[1], machines[1], machines[5]})
    assert(table_size(cells.drafts[player.index].members) == 1)
    assert(table_size(cells.records[1].members) == 2 and machines[1].valid and machines[5].valid,
      "Removal must only update draft membership and leave factory entities intact")
    assert(window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text == "Circuit assembler")
    add_port(player, "inputs", "item/copper-cable")
    click(player, window(), "ssk_cell", "save")
    assert(cells.records[1].ports.inputs["item/copper-cable"] and cells.records[1].ports.outputs["item/electronic-circuit"])
    assert(table_size(cells.records) == 1 and cells.records[1].name == "Circuit assembler")
    assert(table_size(cells.records[1].members) == 1 and cells.records[1].members[storage.cell_test_machines[2].unit_number])
    assert(not next(cells.drafts))
    click(player, window(), "ssk_cell", "select")
    select_area(player, {machines[1]})
    click(player, window(), "ssk_cell", "add")
    select_area(player, {machines[5], machines[1], machines[3]})
    local picker = window().ssk_cell_panel.ssk_cell_form.ssk_cell_item_column.ssk_cell_display_item
    assert(picker.type == "sprite-button" and picker.sprite == "item/copper-cable")
    click(player, window(), "target", "cell")
    local popup = assert(player.gui.screen.ssk_material_picker)
    assert(not popup.tags.allowed and find(popup, "key", "item/electronic-circuit"),
      "Any item or fluid can represent a cell")
    local item = assert(find(popup, "key", "item/iron-gear-wheel"))
    script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = item}
    assert(picker.sprite == "item/iron-gear-wheel")
    assert(not player.gui.screen.ssk_material_picker)
    add_port(player, "outputs", "item/copper-cable")
    add_port(player, "outputs", "item/iron-gear-wheel")
    add_port(player, "inputs", "item/copper-plate")
    click(player, window(), "ssk_cell", "save")
    click(player, window(), "ssk_cell", "close")

    local all = Flow.build(nil, CAPACITY)
    local copper = "item/copper-cable#surface-" .. player.surface.index
    assert(all.links["recipe/cell-2>" .. copper .. "-output"].rate == 2)
    -- The cable cell feeds the circuit cell, so the circuits come one stage later.
    assert(all.links[copper .. "-output>recipe/cell-1"].rate == 3, "Cable made by cell 2 must feed cell 1")
    assert(all.nodes["recipe/cell-2"].tier == 2 and all.nodes["recipe/cell-1"].tier == 4)
    assert(Flow.ids()[1] == 2, "The supplying cell is listed first")
    assert(cells.records[2].display_item == "iron-gear-wheel")
    assert(all.nodes["recipe/cell-2"].sprite == "item/iron-gear-wheel")
    assert(all.nodes["recipe/cell-1"].caption[1] == "production-flow.cells-node-name")
    local inside = Flow.build(1, CAPACITY)
    assert(inside.links["item/copper-cable>recipe/electronic-circuit"].rate == 3)
    -- Recipe bar details read real entities: the cell's members, and the sampler's
    -- registry for the surface view (whose name and quality are then kept).
    local cell_detail = serpent.line(RecipeDetails.recipe({ rates = inside.recipe_rates, members = inside.members,
      capacity = true, sidx = player.surface.index }, "electronic-circuit", tostring))
    assert(cell_detail:find("recipe-details-capacity", 1, true) and cell_detail:find("recipe-details-machine\"", 1, true)
      and cell_detail:find("[entity=assembling-machine-1]", 1, true), cell_detail)
    local surface_detail = serpent.line(RecipeDetails.recipe({ rates = {}, sidx = player.surface.index }, "copper-cable", tostring))
    assert(surface_detail:find("[entity=assembling-machine-1]", 1, true) and not surface_detail:find("recipe-details-measured", 1, true),
      surface_detail)
    log("CELL RECIPE DETAILS: " .. cell_detail .. " | " .. surface_detail)
    assert(inside.links["recipe/electronic-circuit>item/electronic-circuit"].rate == 1)
    local cable = storage.cell_test_machines[1]
    cells.records[1].members[cable.unit_number] = cable
    assert(Flow.build(nil, CAPACITY).overlap and not Flow.build(nil, CAPACITY).links["recipe/cell-2>" .. copper .. "-output"])
    cells.records[1].members[cable.unit_number] = nil
    storage.cell_test_phase = "replace"
  elseif stage == "replace" then
    -- Real engine replacements of cell 2's members: an upgrade (fast-replace, raised as
    -- script_raised_built) and a destroyed machine that is later rebuilt from its ghost.
    local cells, machines, surface = storage.production_cells, storage.cell_test_machines, player.surface
    local gear, cable = machines[5], machines[1]
    local gear_unit, cable_unit, cable_position = gear.unit_number, cable.unit_number, cable.position
    local upgraded = assert(surface.create_entity{name = "assembling-machine-2", position = gear.position,
      force = "player", fast_replace = true, spill = false, raise_built = true})
    assert(not gear.valid and upgraded.valid, "Fast-replace must replace the old machine")
    if not upgraded.get_recipe() then upgraded.set_recipe("iron-gear-wheel") end
    local record = cells.records[2]
    assert(record.members[upgraded.unit_number] == upgraded and not record.members[gear_unit],
      "An upgraded member must stay in its cell")
    assert(Cells.missing(record) == 0)
    machines[5] = upgraded

    UI.open(player)
    click(player, assert(player.gui.screen.ssk_main), "ssk_ui", "cells")
    local function edit_cell()
      local edit
      local function find_edit(element)
        if element.tags.ssk_cell == "edit" and element.tags.cell_id == 2 then edit = element end
        for _, child in ipairs(element.children) do find_edit(child) end
      end
      find_edit(window())
      script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = assert(edit)}
    end
    edit_cell()
    assert(not window().ssk_cell_panel.children[1].ssk_cell_missing)
    assert(cable.die())
    local ghost = surface.find_entity("entity-ghost", cable_position)
    storage.cell_test_death_ghost = ghost ~= nil
    ghost = ghost or assert(surface.create_entity{name = "entity-ghost", inner_name = "assembling-machine-1",
      position = cable_position, force = "player"})
    storage.cell_test_ghost = ghost
    click(player, window(), "ssk_cell", "save")
    record = cells.records[2]
    assert(Cells.missing(record) == 1 and record.members[cable_unit], "Save must keep a slot that became vacant in the editor")
    assert(Flow.build(2, CAPACITY).links["recipe/copper-cable>item/copper-cable"] == nil, "A missing member must not be charted")

    edit_cell()
    assert(window().ssk_cell_panel.children[1].ssk_cell_missing, "The editor must report the missing machine")
    assert(find(window(), "ssk_cell", "forget"), "The editor must offer to forget missing machines")
    storage.cell_test_phase = "capture-missing"
  elseif stage == "capture-missing" then
    screenshot(player, "missing")
    storage.cell_test_phase = "rebuild"
  elseif stage == "rebuild" then
    local cells, machines = storage.production_cells, storage.cell_test_machines
    click(player, window(), "ssk_cell", "list")
    assert(cells.records[2] and Cells.missing(cells.records[2]) == 1, "Leaving the editor must not change the cell")
    click(player, window(), "ssk_cell", "close")
    UI.open(player)
    local listed = cells_tab(player).ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.items
    assert(serpent.line(listed[row_of(player, 2)]):find("warning_icon", 1, true)
      and not serpent.line(listed[row_of(player, 1)]):find("warning_icon", 1, true),
      "A cell with missing machines must carry a warning in the Cells tab: " .. serpent.line(listed))
    UI.close(player)
    local _, revived = storage.cell_test_ghost.revive{raise_revive = true}
    assert(revived and revived.valid, "Ghost revival failed")
    if not revived.get_recipe() then revived.set_recipe("copper-cable") end
    local record = cells.records[2]
    assert(record.members[revived.unit_number] == revived and Cells.missing(record) == 0,
      "A member rebuilt from its ghost must rejoin the cell")
    machines[1] = revived
    log("CELL REPLACEMENT PASS: fast-replace upgrade and ghost revival re-attached; death ghost created by engine: "
      .. tostring(storage.cell_test_death_ghost))
    local copper = "item/copper-cable#surface-" .. player.surface.index
    assert(Flow.build(nil, CAPACITY).links["recipe/cell-2>" .. copper .. "-output"].rate == 2, "Rebuilt member must be charted again")

    -- Feed every member so the sampler measures real engine crafts.
    assert(machines[1].insert{name = "copper-plate", count = 100} > 0)
    assert(machines[2].insert{name = "iron-plate", count = 100} > 0)
    assert(machines[2].insert{name = "copper-cable", count = 200} > 0)
    assert(machines[5].insert{name = "iron-plate", count = 100} > 0)
    storage.cell_test_feed_tick = game.tick
    storage.cell_test_phase = "measure"
  elseif stage == "measure" then
    if game.tick < storage.cell_test_feed_tick + 20 * 60 then return end
    local cells, machines, sidx = storage.production_cells, storage.cell_test_machines, player.surface.index
    local cable = machines[1]
    assert(cable.products_finished > 5 and machines[2].products_finished > 5 and machines[5].products_finished > 5,
      "Fed machines must have crafted: " .. cable.products_finished .. "/" .. machines[2].products_finished
      .. "/" .. machines[5].products_finished)
    -- The revived cable machine joined after the cell was created, so every craft it
    -- finished belongs to cell 2. The sampler may lag by the bin still filling.
    local rates, seconds = Sampler.cell_rates(2, sidx, 600, cells.records[2].since)
    local measured = rates["copper-cable"] and rates["copper-cable"].cps * seconds or 0
    assert(math.abs(measured - cable.products_finished) <= 3,
      "Measured cable crafts " .. measured .. " must match the engine's " .. cable.products_finished)
    assert(rates["iron-gear-wheel"] and not rates["electronic-circuit"], "Cell 2 measured another cell's recipe")
    local circuits = Sampler.cell_rates(1, sidx, 600, cells.records[1].since)
    assert(circuits["electronic-circuit"] and not circuits["copper-cable"], "Cell 1 must measure only its circuit machine")
    local inside = Flow.build(2, {mode = "measured", period = 600})
    assert(inside.partial and inside.utilisation and inside.utilisation > 0.2 and inside.utilisation <= 1.05,
      "Measured utilisation out of range: " .. tostring(inside.utilisation))
    assert(inside.nodes["recipe/copper-cable"].rate_line, "Measured recipe nodes need a utilisation line")
    local overview = Flow.build(nil, {mode = "measured", period = 600})
    assert(overview.nodes["recipe/cell-1"].rate_line and overview.nodes["recipe/cell-2"].note,
      "Measured cell nodes need utilisation and a partial-window note")
    assert(overview.newest and overview.newest < 600, "The All view must report how much data the newest cell has")
    log(string.format("CELL MEASURED PASS: cable crafts engine=%d measured=%.1f over %.0f s; cell 2 utilisation %.2f",
      cable.products_finished, measured, seconds, inside.utilisation))

    UI.open(player)
    local main = player.gui.screen.ssk_main
    main.auto_center = false
    main.location = {20, 32}
    local tabs = main.ssk_inner.ssk_tabs
    for i, id in ipairs(tabs.tags.ssk_tab_ids) do
      if id == "cells" then tabs.selected_tab_index = i; break end
    end
    script.get_event_handler(defines.events.on_gui_selected_tab_changed){player_index = player.index, element = tabs}
    local split = tabs.content_cells.ssk_cell_split
    local all_rows = split.ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list
    if all_rows.selected_index ~= 1 then
      all_rows.selected_index = 1
      script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = all_rows}
      split = player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split
    end
    assert(split.ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == 1)
    local titlebar = split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar
    assert(not titlebar.ssk_cell_scope and titlebar.ssk_cell_title.ssk_zoom, "Flow header has zoom and no explanatory subtitle")
    assert(find(split.ssk_cell_views.ssk_cell_chart, "key", "recipe/cell-2"), "Overview must render a single cell node")
    assert(split.ssk_cell_views.ssk_cell_map_tab.enabled, "All shows every cell on the map")
    assert(find(split.ssk_cell_views.ssk_cell_chart, "side", "inputs") and find(split.ssk_cell_views.ssk_cell_chart, "side", "outputs"),
      "The cell renderer must draw both bar halves")
    storage.cell_test_phase = "capture-overview"
  elseif stage == "capture-overview" then
    screenshot(player, "overview")
    storage.cell_test_phase = "open-inside"
  elseif stage == "open-inside" then
    local tabs = player.gui.screen.ssk_main.ssk_inner.ssk_tabs
    local rows = tabs.content_cells.ssk_cell_split.ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list
    rows.selected_index = row_of(player, 1)
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = rows}
    local split = tabs.content_cells.ssk_cell_split
    assert(find(split.ssk_cell_views.ssk_cell_chart, "key", "recipe/electronic-circuit"), "Individual cell must render its recipe")
    assert(not find(split.ssk_cell_views.ssk_cell_chart, "key", "recipe/copper-cable"), "Another cell's recipe leaked into the view")
    storage.cell_test_phase = "capture-inside"
  elseif stage == "capture-inside" then
    screenshot(player, "inside")
    storage.cell_test_phase = "wide"
  elseif stage == "wide" then
    -- A chart wider than its tab must scroll inside the frame, not push it out of the window.
    local content = player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells
    CellsUI.fill(player, content, storage.ui[player.index].cells, 600, 520, true)
    local chart = content.ssk_cell_split.ssk_cell_views.ssk_cell_chart
    local sp = chart.ssk_cell_plot.ssk_sp
    log("CELL WIDE: canvas " .. tostring(sp.ssk_canvas.style.minimal_width) .. " viewport max " .. tostring(sp.style.maximal_width))
    assert(sp.horizontal_scroll_policy == "auto", "A wide cell chart must scroll horizontally")
    assert(sp.style.maximal_width == 600 - math.min(236, math.floor(600 * 0.32)) - 8 - 2 * 8, "The chart viewport must stay inside its frame")
    storage.cell_test_phase = "capture-wide"
  elseif stage == "capture-wide" then
    screenshot(player, "inside-wide")
    storage.cell_test_phase = "map"
  elseif stage == "map" then
    UI.open(player)
    local views = cells_tab(player).ssk_cell_views
    assert(views.ssk_cell_map_tab.enabled)
    views.selected_tab_index = 2
    script.get_event_handler(defines.events.on_gui_selected_tab_changed){player_index = player.index, element = views}
    local state = storage.ui[player.index].cells
    views = cells_tab(player).ssk_cell_views
    assert(state.view == "map" and views.selected_tab_index == 2, "The Map tab must stay selected")
    local map = views.ssk_cell_map
    local camera = map.ssk_cell_camera
    local center = CellsUI.area(storage.production_cells.records[state.selected])
    assert(camera.surface_index == player.surface.index and math.abs(camera.position.x - center.x) < 0.01
      and math.abs(camera.position.y - center.y) < 0.01, "The map must centre on the cell")
    local bar = map.ssk_cell_map_bar
    assert(bar.ssk_cell_jump_button.sprite == "utility/map" and find(cells_tab(player), "ssk_ui", "cell_edit")
      and bar.ssk_cell_map_delete.enabled, "Shared Edit and Map Delete are enabled")
    local last = bar.children[#bar.children]
    assert(last.name == "ssk_cell_map_delete", "Delete sits at the right of the Map heading")
    local record, members = storage.production_cells.records[state.selected], 0
    for _ in pairs(record.positions) do members = members + 1 end
    local shown = assert(outlines(player), "The map must outline the cell's machines")
    assert(#shown.objects >= members + 1 and shown.objects[1].valid, "Every member needs an outline and the cell a label")
    local filter = shown.objects[2].players
    assert(#filter == 1 and filter[1].index == player.index, "Only the viewing player sees the outlines")
    log("CELL OUTLINES: " .. #shown.objects .. " objects for " .. members .. " members")
    local slider = bar.ssk_cell_map_zoom
    slider.slider_value = 1
    script.get_event_handler(defines.events.on_gui_value_changed){player_index = player.index, element = slider}
    assert(math.abs(camera.zoom - 1) < 0.001, "Zoom must apply to the map")
    local before = camera.position.x
    click(player, map, "dx", 1)
    camera = cells_tab(player).ssk_cell_views.ssk_cell_map.ssk_cell_camera
    assert(camera.position.x > before and math.abs(camera.zoom - 1) < 0.001, "Moving the view keeps the zoom")
    storage.cell_test_phase = "capture-map"
  elseif stage == "capture-map" then
    screenshot(player, "map")
    storage.cell_test_phase = "fit"
  elseif stage == "fit" then
    local state = storage.ui[player.index].cells
    click(player, cells_tab(player).ssk_cell_views.ssk_cell_map, "ssk_ui", "cell_map_fit")
    local camera = cells_tab(player).ssk_cell_views.ssk_cell_map.ssk_cell_camera
    local center = CellsUI.area(storage.production_cells.records[state.selected])
    assert(math.abs(camera.position.x - center.x) < 0.01 and math.abs(camera.zoom - state.fitted.zoom) < 0.001
      and not state.maps[state.selected], "Fit must return to the machines")
    log("CELL MAP: fitted zoom " .. state.fitted.zoom .. " at " .. serpent.line({ state.fitted.x, state.fitted.y }))
    storage.cell_test_phase = "capture-fit"
  elseif stage == "capture-fit" then
    screenshot(player, "map-fit")
    storage.cell_test_phase = "map-all"
  elseif stage == "map-all" then
    local rows = cells_tab(player).ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list
    rows.selected_index = 1
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = rows}
    local state = storage.ui[player.index].cells
    assert(not state.selected and state.view == "map", "All keeps the Map tab")
    local game_labels, chart_labels = 0, 0
    for _, object in ipairs(outlines(player).objects) do
      if object.type == "text" then
        if object.render_mode == "chart" then chart_labels = chart_labels + 1 else game_labels = game_labels + 1 end
      end
    end
    assert(game_labels == #state.ids and chart_labels == #state.ids, "All labels every listed cell on the map")
    storage.cell_test_phase = "capture-map-all"
  elseif stage == "capture-map-all" then
    screenshot(player, "map-all")
    local rows = cells_tab(player).ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list
    rows.selected_index = row_of(player, 1)
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = rows}
    storage.cell_test_phase = "jump"
  elseif stage == "jump" then
    cells_tab(player)
    click(player, player.gui.screen.ssk_main, "ssk_ui", "cell_jump")
    assert(not player.gui.screen.ssk_main, "Jump must close the window")
    assert(outlines(player) and outlines(player).remote and outlines(player).objects[1].valid,
      "Outlines stay visible in remote view after a jump")
    assert(player.controller_type == defines.controllers.remote and player.surface.index == storage.production_cells.records[storage.ui[player.index].cells.selected].surface_index,
      "Jump must open remote view on the cell's surface")
    storage.cell_test_phase = "capture-jump"
  elseif stage == "capture-jump" then
    -- Screenshots render at the end of the tick, so return to the character next tick.
    screenshot(player, "jump")
    storage.cell_test_phase = "return"
  elseif stage == "return" then
    player.exit_remote_view()
    assert(player.controller_type == defines.controllers.character, "Leaving remote view returns to the character")
    storage.cell_test_phase = "returned"
  elseif stage == "returned" then
    -- The controller-changed event arrives after exit_remote_view returns.
    assert(not outlines(player), "Leaving remote view clears the jump's outlines")
    UI.open(player)
    assert(outlines(player) and not outlines(player).remote, "Reopening on the Map tab outlines the cell again")
    local split = cells_tab(player)
    assert(split.ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == row_of(player, 1), "Reopening keeps the selected cell")
    assert(split.ssk_cell_views.selected_tab_index == 2, "Reopening keeps the Map tab")
    split.ssk_cell_views.selected_tab_index = 1
    script.get_event_handler(defines.events.on_gui_selected_tab_changed){player_index = player.index, element = split.ssk_cell_views}
    assert(not storage.ui[player.index].cells.view and find(cells_tab(player).ssk_cell_views.ssk_cell_chart, "key", "recipe/electronic-circuit"),
      "Flow must chart the cell again")
    assert(not outlines(player), "Leaving the Map tab clears the outlines")
    storage.cell_test_phase = "capacity"
  elseif stage == "capacity" then
    local main = player.gui.screen.ssk_main
    local switch = assert(find(main, "ssk_ui", "cell_mode"))
    assert(switch.switch_state == "left" and main.ssk_window_bar.ssk_period_picker.visible,
      "Measured must be the default and use the selected period")
    local period_index = main.ssk_window_bar.ssk_period_picker.selected_index
    switch.switch_state = "right"
    script.get_event_handler(defines.events.on_gui_switch_state_changed){player_index = player.index, element = switch}
    main = player.gui.screen.ssk_main
    assert(main.ssk_window_bar.ssk_period_picker.visible and main.ssk_window_bar.ssk_period_picker.selected_index == period_index,
      "Capacity keeps the period picker and its selection")
    local chart = main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split.ssk_cell_views.ssk_cell_chart
    assert(find(chart, "key", "recipe/electronic-circuit"), "Capacity must chart the configured recipe")
    storage.cell_test_phase = "capture-capacity"
  elseif stage == "capture-capacity" then
    screenshot(player, "inside-capacity")
    storage.cell_test_phase = "measured-again"
  elseif stage == "measured-again" then
    local main = player.gui.screen.ssk_main
    local switch = assert(find(main, "ssk_ui", "cell_mode"))
    switch.switch_state = "left"
    script.get_event_handler(defines.events.on_gui_switch_state_changed){player_index = player.index, element = switch}
    assert(player.gui.screen.ssk_main.ssk_window_bar.ssk_period_picker.visible)
    local split = cells_tab(player)
    local bar = split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar.ssk_cell_title
    assert(find(split, "ssk_ui", "cell_edit") and bar.ssk_cell_delete_button.enabled)
    assert(bar.children[#bar.children].name == "ssk_cell_delete_button", "Delete sits at the right of the Flow heading")
    assert(not split.ssk_cell_sidebar.ssk_cell_list_bar.ssk_cell_edit_button, "The cell list keeps only New")
    click(player, player.gui.screen.ssk_main, "cell_id", 1)
    local draft = storage.production_cells.drafts[player.index]
    assert(not player.gui.screen.ssk_main and draft and draft.id == 1 and window(), "Edit must open the cell's editor")
    click(player, window(), "ssk_cell", "list")
    click(player, window(), "ssk_cell", "close")
    UI.open(player)
    assert(cells_tab(player).ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == row_of(player, 1), "Reopening keeps the selected cell")
    click(player, player.gui.screen.ssk_main, "ssk_ui", "cell_new")
    assert(not player.gui.screen.ssk_main and player.cursor_stack.valid_for_read
      and player.cursor_stack.name == Selection.tool, "New must hand over the selection tool")
    player.cursor_stack.clear()
    UI.open(player)
    cells_tab(player)
    storage.cell_test_phase = "prompt-delete"
  elseif stage == "prompt-delete" then
    local main = player.gui.screen.ssk_main
    click(player, main, "ssk_ui", "cell_delete")
    assert(player.gui.screen.ssk_cell_delete and storage.production_cells.records[1],
      "Opening confirmation must leave the cell intact")
    storage.cell_test_phase = "capture-delete"
  elseif stage == "capture-delete" then
    screenshot(player, "delete")
    storage.cell_test_phase = "finish-delete"
  elseif stage == "finish-delete" then
    local function confirmation() return assert(player.gui.screen.ssk_cell_delete) end
    click(player, confirmation(), "ssk_cell_delete_answer", "cancel")
    local cells, machines = storage.production_cells, storage.cell_test_machines
    local main = assert(player.gui.screen.ssk_main)
    local function sidebar()
      return player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split.ssk_cell_sidebar
    end
    assert(cells.records[1] and sidebar().ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == row_of(player, 1), "Cancel must restore the selected cell")
    click(player, main, "ssk_ui", "cell_delete")
    click(player, confirmation(), "ssk_cell_delete_answer", "delete")
    assert(not cells.records[1] and cells.records[2] and machines[2].valid)
    local side = sidebar()
    assert(side.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == 1 and #side.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.items == 2)
    local title = player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar.ssk_cell_title
    assert(not title.ssk_cell_delete_button.enabled, "All cannot be deleted")
    local main_after = player.gui.screen.ssk_main
    click(player, main_after, "ssk_ui", "cells")
    click(player, window(), "ssk_cell_delete_request", 2)
    script.get_event_handler(defines.events.on_gui_closed){player_index = player.index, element = confirmation()}
    assert(window() and cells.records[2], "Closing the dialog must cancel deletion")
    click(player, window(), "ssk_cell_delete_request", 2)
    click(player, confirmation(), "ssk_cell_delete_answer", "delete")
    assert(window() and not next(cells.records) and machines[1].valid and machines[5].valid)
    assert(not next(cells.deletions))
    storage.cell_test_phase = "clone"
  elseif stage == "clone" then
    -- Engine cloning to another surface, as Space Exploration moves a spaceship.
    local machines = storage.cell_test_machines
    player.cursor_stack.set_stack{name = Selection.tool}
    select_area(player, {machines[1], machines[2], machines[5]})
    window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = "Ship"
    click(player, window(), "ssk_cell", "save")
    local id, record = next(storage.production_cells.records)
    assert(record and record.name == "Ship" and table_size(record.members) == 3)
    local vacant = { unit = machines[5].unit_number, position = machines[5].position, name = machines[5].name }
    machines[5].destroy()
    local ship = game.create_surface("cells-clone-test")
    ship.request_to_generate_chunks({0, 0}, 2)
    ship.force_generate_chunk_requests()
    local tiles = {}
    for x = -12, 16 do for y = 0, 16 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end end
    ship.set_tiles(tiles)
    -- clone_entities returns nothing; the copies are found on the destination.
    local dy = 5
    player.surface.clone_entities{entities = {machines[1], machines[2]},
      destination_offset = {0, dy}, destination_surface = ship}
    local copies = {}
    for i = 1, 2 do
      local position = machines[i].position
      copies[i] = ship.find_entity(machines[i].name, {position.x, position.y + dy})
    end
    assert(copies[1] and copies[2] and copies[1] ~= copies[2], "Engine clone failed")
    assert(storage.production_cells.clones and storage.production_cells.clones[id], "Clone events must be recorded")
    storage.cell_test_clone = {id = id, surface = ship.index, copies = copies, vacant = vacant, dy = dy}
    storage.cell_test_clone_tick = game.tick
    machines[1].destroy()
    machines[2].destroy()
    storage.cell_test_phase = "clone-check"
  elseif stage == "clone-check" then
    -- This hook runs before the mod resolves clones within a tick.
    if storage.production_cells.clones and game.tick < storage.cell_test_clone_tick + 5 then return end
    local clone = storage.cell_test_clone
    local record = storage.production_cells.records[clone.id]
    local a, b = clone.copies[1], clone.copies[2]
    assert(record.surface_index == clone.surface and record.members[a.unit_number] == a
      and record.members[b.unit_number] == b and Cells.missing(record) == 1,
      "A cell must follow machines moved to another surface")
    local vacant = clone.vacant
    local position = assert(record.positions[vacant.unit])
    assert(position.x == vacant.position.x and position.y == vacant.position.y + clone.dy,
      "The vacant slot must follow the live machines' translation")
    local ship = game.surfaces[clone.surface]
    local unrelated = assert(ship.create_entity{name = vacant.name, position = vacant.position, force = "player", raise_built = true})
    assert(not record.members[unrelated.unit_number], "A machine at the old position must stay outside the cell")
    local rebuilt = assert(ship.create_entity{name = vacant.name, position = {position.x, position.y}, force = "player", raise_built = true})
    assert(record.members[rebuilt.unit_number] == rebuilt and Cells.missing(record) == 0,
      "A machine built at the translated position must fill the slot")
    rebuilt.set_recipe("iron-gear-wheel")
    assert(not storage.production_cells.clones, "Resolved clones must be cleared")
    assert(Flow.build(nil, CAPACITY).nodes["recipe/cell-" .. clone.id].context == "cells-clone-test",
      "The All view must place a moved cell on its new surface")
    log("CELL CLONE PASS: engine clone preserved the translated slot and reattached the correct replacement")
    storage.cell_test_phase = "show-moved"
  elseif stage == "show-moved" then
    -- Show switches the header to the cell's surface, as choosing it from the picker would.
    if player.gui.screen.ssk_main then UI.close(player) end
    if not player.gui.screen.ssk_cells then Cells.open(player) end
    click(player, window(), "ssk_cell", "show")
    local clone = storage.cell_test_clone
    local us = storage.ui[player.index]
    local picker = player.gui.screen.ssk_main.ssk_window_bar.ssk_surface_picker
    assert(us.surface == "cells-clone-test" and picker.selected_index > 1
      and us.surface_names[picker.selected_index] == "cells-clone-test", "Show must select the cell's surface")
    assert(cells_tab(player).ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.selected_index == 2)
    assert(Flow.ids(clone.surface)[1] == clone.id and #Flow.ids(player.surface.index) == 0)
    storage.cell_test_phase = "capture-moved"
  elseif stage == "capture-moved" then
    screenshot(player, "moved")
    storage.cell_test_phase = "empty-surface"
  elseif stage == "empty-surface" then
    local main = player.gui.screen.ssk_main
    local picker = main.ssk_window_bar.ssk_surface_picker
    picker.selected_index = 1
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = picker}
    local split = cells_tab(player)
    assert(#split.ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list.items == 1, "Only All is listed on a surface without cells")
    assert(has_caption(split.ssk_cell_views.ssk_cell_chart, "production-flow.cells-empty-surface"), "Empty surfaces need their own message")
    storage.cell_test_phase = "capture-empty"
  elseif stage == "capture-empty" then
    screenshot(player, "empty-surface")
    storage.cell_test_phase = "help"
  elseif stage == "help" then
    click(player, player.gui.screen.ssk_main, "ssk_ui", "help")
    local tabs = player.gui.screen.ssk_help.ssk_help_inner.ssk_help_tabs
    assert(tabs.tabs[4].tab.caption[1] == "production-flow.cells-tab", "Help needs a Cells topic")
    tabs.selected_tab_index = 4
    storage.cell_test_phase = "capture-help"
  elseif stage == "capture-help" then
    screenshot(player, "help-cells")
    storage.cell_test_phase = "refinery-editor"
  elseif stage == "refinery-editor" then
    edit_refinery(player, UI)
    storage.cell_test_phase = "capture-refinery-editor"
  elseif stage == "capture-refinery-editor" then
    screenshot(player, "refinery-editor")
    storage.cell_test_phase = "refinery-inside"
  elseif stage == "refinery-inside" then
    click(player, window(), "ssk_cell", "save")
    local id = storage.cell_test_refinery
    local graph = Flow.build(id, CAPACITY)
    local recipe = "recipe/advanced-oil-processing"
    assert(graph.links["fluid/crude-oil>" .. recipe].rate == 100)
    assert(graph.links["fluid/water>" .. recipe].rate == 50)
    assert(graph.links["fluid/heavy-oil>recipe/heavy-oil-cracking"].rate == 20)
    assert(graph.links["fluid/heavy-oil>fluid/heavy-oil#cell-output"].rate == 5)
    for material, rate in pairs(REFINERY_OUTPUTS) do
      local key = "fluid/" .. material
      local node = graph.nodes[material == "heavy-oil" and key .. "#cell-output" or key]
      assert(node.cell_output and math.abs(node.prod - rate) < 1e-7)
    end
    UI.open(player)
    assert(find(cells_tab(player).ssk_cell_views.ssk_cell_chart, "key", recipe))
    storage.cell_test_phase = "capture-refinery-inside"
  elseif stage == "capture-refinery-inside" then
    screenshot(player, "refinery-inside")
    storage.cell_test_phase = "refinery-overview"
  elseif stage == "refinery-overview" then
    local rows = cells_tab(player).ssk_cell_sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list
    rows.selected_index = 1
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = rows}
    check_refinery_overview(player, storage.production_cells.records[storage.cell_test_refinery])
    storage.cell_test_phase = "capture-refinery-overview"
  elseif stage == "capture-refinery-overview" then
    screenshot(player, "refinery-overview")
    storage.cell_test_phase = script.active_mods["space-age"] and "bioflux" or "recipe-returns"
  elseif stage == "bioflux" then
    show_bioflux_fuel(player, UI)
    storage.cell_test_phase = "capture-bioflux"
  elseif stage == "capture-bioflux" then
    screenshot(player, "bioflux-fuel")
    storage.cell_test_phase = "enable-bioflux-markers"
  elseif stage == "enable-bioflux-markers" then
    player.mod_settings["ssk-return-direction-markers"] = { value = true }
    script.get_event_handler(defines.events.on_runtime_mod_setting_changed) {
      player_index = player.index, setting = "ssk-return-direction-markers",
    }
    local chart = cells_tab(player).ssk_cell_views.ssk_cell_chart
    assert(find(chart, "ssk_return_direction", "left"), "The setting refreshes the Bioflux chart with leftward markers")
    assert(not find(chart, "ssk_return_direction", "right"))
    storage.cell_test_phase = "capture-bioflux-markers"
  elseif stage == "capture-bioflux-markers" then
    screenshot(player, "bioflux-fuel-markers")
    storage.cell_test_phase = "open-bioflux-editor"
  elseif stage == "open-bioflux-editor" then
    click(player, cells_tab(player), "ssk_ui", "cell_edit")
    local items = ports(player, "outputs").slots.scroll.materials.children
    assert(items[1].sprite == "item/bioflux" and items[1].toggled)
    assert(items[#items - 1].sprite == "item/nutrients" and not items[#items - 1].toggled)
    assert(items[#items].tags.ssk_cell == "port_add")
    storage.cell_test_phase = "capture-bioflux-editor"
  elseif stage == "capture-bioflux-editor" then
    screenshot(player, "bioflux-editor")
    storage.cell_test_phase = "add-bioflux-fuel-input"
  elseif stage == "add-bioflux-fuel-input" then
    add_port(player, "inputs", "item/nutrients")
    local items = ports(player, "inputs").slots.scroll.materials.children
    assert(items[1].sprite == "item/nutrients" and items[1].toggled, "A selected fuel input ranks first")
    storage.cell_test_phase = "capture-bioflux-inputs"
  elseif stage == "capture-bioflux-inputs" then
    screenshot(player, "bioflux-inputs")
    storage.cell_test_phase = "recipe-returns"
  elseif stage == "recipe-returns" then
    player.mod_settings["ssk-return-direction-markers"] = { value = false }
    show_recipe_returns(player, UI)
    assert(not find(player.gui.screen.ssk_main, "ssk_return_direction", "left"))
    storage.cell_test_phase = "capture-recipe-returns"
  elseif stage == "capture-recipe-returns" then
    screenshot(player, "recipe-returns")
    storage.cell_test_phase = "enable-recipe-markers"
  elseif stage == "enable-recipe-markers" then
    player.mod_settings["ssk-return-direction-markers"] = { value = true }
    show_recipe_returns(player, UI)
    assert(find(player.gui.screen.ssk_main, "ssk_return_direction", "left"), "The barrel return shows the marker")
    assert(not find(player.gui.screen.ssk_main, "ssk_return_direction", "right"))
    storage.cell_test_phase = "capture-recipe-markers"
  elseif stage == "capture-recipe-markers" then
    screenshot(player, "recipe-returns-markers")
    storage.cell_test_phase = "finish"
  elseif stage == "finish" then
    storage.cell_test_phase = "done"
    log("PRODUCTION CELLS NATIVE PASS")
  end
end

return T
