-- Private native fixture. Dispatches registered handlers using real GUI and entities.
local T = {}
local Selection = require("shared.cell_selection")
local Flow = require("scripts.cell_flow")

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

local function select_area(player, entities)
  script.get_event_handler(defines.events.on_player_selected_area){
    player_index = player.index, item = Selection.tool, surface = player.surface, entities = entities,
  }
end

local function screenshot(player, name)
  game.take_screenshot{player = player, path = "cells/" .. name .. ".png",
    resolution = {1920, 1080}, show_gui = true, force_render = true}
end

function T.tick(UI)
  local player = game.connected_players[1]
  if not player or game.tick < 30 then return end
  local stage = storage.cell_test_phase
  local function window() return assert(player.gui.screen.ssk_cells) end
  if stage == nil then
    local surface = player.surface
    local function spawn(name, x, force)
      return assert(surface.create_entity{name = name, position = {x, 8}, force = force})
    end
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
    assert(not next(storage.production_cells.records))
    assert(window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text == "Electronic circuit",
      "Faster copper cable output is consumed inside the cell")
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
    storage.cell_test_phase = "capture-list"
  elseif stage == "capture-list" then
    screenshot(player, "saved")
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
    click(player, window(), "ssk_cell", "list")
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
    click(player, window(), "ssk_cell", "save")
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
    assert(popup.tags.allowed["item/iron-gear-wheel"] and popup.tags.allowed["item/copper-cable"])
    assert(not popup.tags.allowed["item/electronic-circuit"] and not popup.tags.allowed["fluid/water"])
    local item = assert(find(popup, "key", "item/iron-gear-wheel"))
    script.get_event_handler(defines.events.on_gui_click){player_index = player.index, element = item}
    assert(picker.sprite == "item/iron-gear-wheel")
    assert(not player.gui.screen.ssk_material_picker)
    click(player, window(), "ssk_cell", "save")
    click(player, window(), "ssk_cell", "close")

    local all = Flow.build()
    local copper = "item/copper-cable#surface-" .. player.surface.index
    assert(all.links["recipe/cell-2>" .. copper .. "-output"].rate == 2)
    assert(all.links[copper .. "-input>recipe/cell-1"].rate == 3)
    assert(cells.records[2].display_item == "iron-gear-wheel")
    assert(all.nodes["recipe/cell-2"].sprite == "item/iron-gear-wheel")
    assert(all.nodes["recipe/cell-1"].caption[1] == "production-flow.cells-node-name")
    local inside = Flow.build(1)
    assert(inside.links["item/copper-cable>recipe/electronic-circuit"].rate == 3)
    assert(inside.links["recipe/electronic-circuit>item/electronic-circuit"].rate == 1)
    local cable = storage.cell_test_machines[1]
    cells.records[1].members[cable.unit_number] = cable
    assert(Flow.build().overlap and not Flow.build().links["recipe/cell-2>" .. copper .. "-output"])
    cells.records[1].members[cable.unit_number] = nil

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
    assert(split.ssk_cell_sidebar.ssk_cell_list.selected_index == 1)
    assert(find(split.ssk_cell_chart, "key", "recipe/cell-2"), "Overview must render a single cell node")
    assert(find(split.ssk_cell_chart, "side", "inputs") and find(split.ssk_cell_chart, "side", "outputs"),
      "The cell renderer must draw both bar halves")
    storage.cell_test_phase = "capture-overview"
  elseif stage == "capture-overview" then
    screenshot(player, "overview")
    storage.cell_test_phase = "open-inside"
  elseif stage == "open-inside" then
    local tabs = player.gui.screen.ssk_main.ssk_inner.ssk_tabs
    local rows = tabs.content_cells.ssk_cell_split.ssk_cell_sidebar.ssk_cell_list
    rows.selected_index = 2
    script.get_event_handler(defines.events.on_gui_selection_state_changed){player_index = player.index, element = rows}
    local split = tabs.content_cells.ssk_cell_split
    assert(find(split.ssk_cell_chart, "key", "recipe/electronic-circuit"), "Individual cell must render its recipe")
    assert(not find(split.ssk_cell_chart, "key", "recipe/copper-cable"), "Another cell's recipe leaked into the view")
    storage.cell_test_phase = "capture-inside"
  elseif stage == "capture-inside" then
    screenshot(player, "inside")
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
    assert(cells.records[1] and sidebar().ssk_cell_list.selected_index == 2, "Cancel must restore the selected cell")
    click(player, main, "ssk_ui", "cell_delete")
    click(player, confirmation(), "ssk_cell_delete_answer", "delete")
    assert(not cells.records[1] and cells.records[2] and machines[2].valid)
    local side = sidebar()
    assert(side.ssk_cell_list.selected_index == 1 and #side.ssk_cell_list.items == 2)
    assert(not side.ssk_cell_list_bar.ssk_cell_delete_button.enabled, "All cannot be deleted")
    local main_after = player.gui.screen.ssk_main
    click(player, main_after, "ssk_ui", "cells")
    click(player, window(), "ssk_cell_delete_request", 2)
    script.get_event_handler(defines.events.on_gui_closed){player_index = player.index, element = confirmation()}
    assert(window() and cells.records[2], "Closing the dialog must cancel deletion")
    click(player, window(), "ssk_cell_delete_request", 2)
    click(player, confirmation(), "ssk_cell_delete_answer", "delete")
    assert(window() and not next(cells.records) and machines[1].valid and machines[5].valid)
    assert(not next(cells.deletions))
    storage.cell_test_phase = "done"
    log("PRODUCTION CELLS NATIVE PASS")
  end
end

return T
