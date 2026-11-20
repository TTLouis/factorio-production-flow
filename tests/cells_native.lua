-- Private native fixture. Dispatches registered handlers using real GUI and entities.
local T = {}
local Selection = require("shared.cell_selection")
local Flow = require("scripts.cell_flow")
local Cells = require("scripts.cells")
local Sampler = require("scripts.sampler")
local CellsUI = require("scripts.cells_ui")
-- The construction checks assert full-speed rates; measured rates are checked
-- separately once the machines have run on real ingredients.
local CAPACITY = {mode = "capacity"}

local function find(parent, key, value)
  if parent.tags[key] == value then return parent end
  for _, element in ipairs(parent.children) do
    local found = find(element, key, value)
    if found then return found end
  end
end

local function click(player, parent, key, value)
  local element = assert(find(parent, key, value), value)
  script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = element}
end

-- Adds a boundary item through the editor's + button and the material picker.
local function add_port(player, side, key)
  local grid = player.gui.screen.ssk_cells.ssk_cell_panel.ssk_cell_ports.ssk_cell_port_table
  click(player, assert(grid["ssk_cell_" .. side .. "_add"]), "side", side)
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
  assert(not player.gui.screen.ssk_material_picker and find(player.gui.screen.ssk_cells, "key", key),
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
    local boxes = 0
    for _, object in ipairs(drafted.objects) do
      if object.type == "rectangle" and not object.filled then boxes = boxes + 1 end
    end
    assert(boxes == table_size(storage.production_cells.drafts[player.index].members),
      "Every selected machine gets one outline")
    log("CELL DRAFT OUTLINES: " .. #drafted.objects .. " objects")
    assert(not next(storage.production_cells.records))
    assert(window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text == "Electronic circuit",
      "Faster copper cable output is consumed inside the cell")
    assert(not find(window(), "ssk_cell", "port"), "A new cell's boundary starts empty")
    add_port(player, "inputs", "item/copper-plate")
    add_port(player, "inputs", "item/iron-plate")
    add_port(player, "outputs", "item/electronic-circuit")
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
      and split.ssk_cell_sidebar.ssk_cell_list.selected_index == row_of(player, 1),
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

    assert(cable.die())
    local ghost = surface.find_entity("entity-ghost", cable_position)
    storage.cell_test_death_ghost = ghost ~= nil
    ghost = ghost or assert(surface.create_entity{name = "entity-ghost", inner_name = "assembling-machine-1",
      position = cable_position, force = "player"})
    storage.cell_test_ghost = ghost
    assert(Cells.missing(record) == 1 and record.members[cable_unit], "A destroyed member must be kept as missing")
    assert(Flow.build(2, CAPACITY).links["recipe/copper-cable>item/copper-cable"] == nil, "A missing member must not be charted")

    UI.open(player)
    click(player, assert(player.gui.screen.ssk_main), "ssk_ui", "cells")
    local edit
    local function find_edit(element)
      if element.tags.ssk_cell == "edit" and element.tags.cell_id == 2 then edit = element end
      for _, child in ipairs(element.children) do find_edit(child) end
    end
    find_edit(window())
    script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = assert(edit)}
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
    local listed = cells_tab(player).ssk_cell_sidebar.ssk_cell_list.items
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
    local all_rows = split.ssk_cell_sidebar.ssk_cell_list
    if all_rows.selected_index ~= 1 then
      all_rows.selected_index = 1
      script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = all_rows}
      split = player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split
    end
    assert(split.ssk_cell_sidebar.ssk_cell_list.selected_index == 1)
    assert(has_caption(split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar, "production-flow.cells-flow-newest")
      or serpent.line(split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar.ssk_cell_scope.caption):find("cells-flow-newest", 1, true),
      "The All caption must say the newest cell has less data than the period")
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
    local rows = tabs.content_cells.ssk_cell_split.ssk_cell_sidebar.ssk_cell_list
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
    assert(sp.style.maximal_width == 600 - math.min(236, math.floor(600 * 0.32)) - 16, "The chart viewport must stay inside its frame")
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
    assert(bar.ssk_cell_jump_button.sprite == "utility/go_to_arrow" and bar.ssk_cell_map_edit.enabled
      and bar.ssk_cell_map_delete.enabled, "The Map heading carries Edit and Delete")
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
    local rows = cells_tab(player).ssk_cell_sidebar.ssk_cell_list
    rows.selected_index = 1
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = rows}
    local state = storage.ui[player.index].cells
    assert(not state.selected and state.view == "map", "All keeps the Map tab")
    local labels = 0
    for _, object in ipairs(outlines(player).objects) do
      if object.type == "text" then labels = labels + 1 end
    end
    assert(labels == #state.ids, "All labels every listed cell on the map")
    storage.cell_test_phase = "capture-map-all"
  elseif stage == "capture-map-all" then
    screenshot(player, "map-all")
    local rows = cells_tab(player).ssk_cell_sidebar.ssk_cell_list
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
    assert(split.ssk_cell_sidebar.ssk_cell_list.selected_index == row_of(player, 1), "Reopening keeps the selected cell")
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
    switch.switch_state = "right"
    script.get_event_handler(defines.events.on_gui_switch_state_changed){player_index = player.index, element = switch}
    main = player.gui.screen.ssk_main
    assert(not main.ssk_window_bar.ssk_period_picker.visible, "Capacity does not depend on the period")
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
    assert(bar.ssk_cell_edit_button.enabled and bar.ssk_cell_delete_button.enabled)
    assert(bar.children[#bar.children].name == "ssk_cell_delete_button", "Delete sits at the right of the Flow heading")
    assert(not split.ssk_cell_sidebar.ssk_cell_list_bar.ssk_cell_edit_button, "The cell list keeps only New")
    click(player, player.gui.screen.ssk_main, "ssk_ui", "cell_edit")
    local draft = storage.production_cells.drafts[player.index]
    assert(not player.gui.screen.ssk_main and draft and draft.id == 1 and window(), "Edit must open the cell's editor")
    click(player, window(), "ssk_cell", "list")
    click(player, window(), "ssk_cell", "close")
    UI.open(player)
    assert(cells_tab(player).ssk_cell_sidebar.ssk_cell_list.selected_index == row_of(player, 1), "Reopening keeps the selected cell")
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
    assert(cells.records[1] and sidebar().ssk_cell_list.selected_index == row_of(player, 1), "Cancel must restore the selected cell")
    click(player, main, "ssk_ui", "cell_delete")
    click(player, confirmation(), "ssk_cell_delete_answer", "delete")
    assert(not cells.records[1] and cells.records[2] and machines[2].valid)
    local side = sidebar()
    assert(side.ssk_cell_list.selected_index == 1 and #side.ssk_cell_list.items == 2)
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
    select_area(player, {machines[1], machines[2]})
    window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = "Ship"
    click(player, window(), "ssk_cell", "save")
    local id, record = next(storage.production_cells.records)
    assert(record and record.name == "Ship" and table_size(record.members) == 2)
    local ship = game.create_surface("cells-clone-test")
    ship.request_to_generate_chunks({0, 0}, 2)
    ship.force_generate_chunk_requests()
    local tiles = {}
    for x = -12, 16 do for y = 0, 16 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end end
    ship.set_tiles(tiles)
    -- clone_entities returns nothing; the copies are found on the destination.
    player.surface.clone_entities{entities = {machines[1], machines[2]},
      destination_offset = {0, 0}, destination_surface = ship}
    local copies = {}
    for i = 1, 2 do
      copies[i] = ship.find_entity(machines[i].name, machines[i].position)
    end
    assert(copies[1] and copies[2] and copies[1] ~= copies[2], "Engine clone failed")
    assert(storage.production_cells.clones and storage.production_cells.clones[id], "Clone events must be recorded")
    storage.cell_test_clone = {id = id, surface = ship.index, copies = copies}
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
      and record.members[b.unit_number] == b and Cells.missing(record) == 0,
      "A cell must follow machines moved to another surface")
    assert(not storage.production_cells.clones, "Resolved clones must be cleared")
    assert(Flow.build(nil, CAPACITY).nodes["recipe/cell-" .. clone.id].context == "cells-clone-test",
      "The All view must place a moved cell on its new surface")
    log("CELL CLONE PASS: engine clone to another surface moved the cell with both members")
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
    assert(cells_tab(player).ssk_cell_sidebar.ssk_cell_list.selected_index == 2)
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
    assert(#split.ssk_cell_sidebar.ssk_cell_list.items == 1, "Only All is listed on a surface without cells")
    assert(has_caption(split.ssk_cell_views.ssk_cell_chart, "production-flow.cells-empty-surface"), "Empty surfaces need their own message")
    assert(serpent.line(split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar.ssk_cell_scope.caption):find("duration-minutes", 1, true),
      "An empty surface's caption must name the selected period")
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
    storage.cell_test_phase = "done"
    log("PRODUCTION CELLS NATIVE PASS")
  end
end

return T
