local Cells = require("scripts.cells")
local Loc = require("scripts.locale")
local Selection = require("shared.cell_selection")

local T = { interface = "production-flow-cell-tips" }
local CIRCUIT, CABLE = "electronic-circuit", "copper-cable"
local SCIENCE, BELT, INSERTER, GEAR = "logistic-science-pack", "transport-belt", "inserter", "iron-gear-wheel"
local VIEWPORT = { width = 872, height = 440, mode = "capacity", chart_fit = true }
local EDITOR_WIDTH = 480
local DOCK = { 8, 8 }
local CIRCUIT_CELL = { first = { -7.25, -6.25 }, last = { 1.75, 5.5 }, name = CIRCUIT }
local RAIL_CELL = { first = { -7.25, -13.25 }, last = { 10.5, 9.5 }, name = CIRCUIT }
local SCIENCE_CELL = { first = { -10.5, -6.25 }, last = { 5.5, 6.25 }, name = "green-science" }
local SCIENCE_CHILDREN = {
  { first = { -10.5, -6.25 }, last = { -2.75, -2.6 }, name = "belts" },
  { first = { -10.5, -1.3 }, last = { 1.25, 6.25 }, name = "inserters" },
}
local CAMERA = {
  create = { x = -5.5, zoom = 1 },
  subdivision = { x = -11.5, zoom = 0.8 },
  rail = { x = -10, y = -1.5, zoom = 0.55 },
}
local RAIL_COLOR = { 0.95, 0.74, 0.34 }
local LOCATOR = "\226\128\139" -- Zero-width caption for the native widget locator.
local OPENING_PAUSE = 150 -- 2.5 seconds at 60 updates per second.
local BEFORE_CLICK = 36
local AFTER_TOOL_CLICK = 42

local function sample_name(recipe)
  return (recipe:gsub("-", " "):gsub("^%l", string.upper))
end

local function find_action(element, key, value)
  if not element then return end
  if element.tags[key] == value then return element end
  for _, child in ipairs(element.children) do
    local found = find_action(child, key, value)
    if found then return found end
  end
end

local function name_field(player)
  local frame = player.gui.screen.ssk_cells
  local form = frame and frame.ssk_cell_panel.ssk_cell_form
  return form and form.ssk_cell_name_column.ssk_cell_name
end

local function aim_widget(spec)
  local sim = game.simulation
  local position = sim.get_widget_position(spec)
  return position and sim.move_cursor { position = position, speed = 0.6 }
end

-- LuaSimulation locates text buttons by caption. Give the real sprite button
-- a temporary invisible caption, then click it through engine hit testing.
local function aim_icon(button)
  if not button then return false end
  button.caption = LOCATOR
  if not aim_widget { type = "text-button", text = LOCATOR } then return false end
  button.caption = ""
  return true
end

local function build_science(place, assemble)
  for _, pole in ipairs { { -6.5, -1.5 }, { -2.5, -1.5 }, { 1.5, -1.5 }, { -2.5, 2.5 } } do
    place("medium-electric-pole", pole[1], pole[2])
  end
  local power = place("hidden-electric-energy-interface", -2.5, -1.5)
  power.energy = 1000000000

  assemble(GEAR, -8.5, -4.5)
  assemble(BELT, -4.5, -4.5)
  assemble(CABLE, -8.5, 0.5)
  assemble(CIRCUIT, -4.5, 0.5)
  assemble(INSERTER, -0.5, 0.5)
  assemble(GEAR, -0.5, 4.5)
  assemble(SCIENCE, 3.5, 0.5)

  for _, link in ipairs { { -6.5, -4.5 }, { -2.5, -4.5 }, { -6.5, 0.5 }, { -2.5, 0.5 }, { 1.5, 0.5 } } do
    place("fast-inserter", link[1], link[2], defines.direction.west)
  end
  place("fast-inserter", -0.5, 2.5, defines.direction.south)
  for x = -2, 2 do place(BELT, x + 0.5, -4.5, defines.direction.east) end
  for _, y in ipairs { -4.5, -3.5, -2.5 } do place(BELT, 3.5, y, defines.direction.south) end
  place("fast-inserter", 3.5, -1.5, defines.direction.north)
end

local function build_factory(player, lesson)
  local surface = player.surface
  surface.always_day = true
  surface.build_checkerboard { { -72, -36 }, { 72, 36 } }

  local function place(name, x, y, direction)
    return surface.create_entity { name = name, position = { x, y }, force = player.force,
      direction = direction, raise_built = true }
  end
  local machines = {}
  local function assemble(recipe, x, y)
    local machine = place("assembling-machine-2", x, y)
    machine.set_recipe(recipe)
    machines[#machines + 1] = machine
  end
  if lesson == "subdivision" then
    build_science(place, assemble)
    return machines
  end

  place("medium-electric-pole", -2.5, -0.5)
  local power = place("hidden-electric-energy-interface", -2.5, -0.5)
  power.energy = 1000000000

  -- Stagger the assemblers so the middle cable machine can feed both circuits.
  for _, column in ipairs { { -4.5, CABLE, { -4.5, -0.5, 3.5 } }, { -0.5, CIRCUIT, { -2.5, 1.5 } } } do
    local x, recipe, rows = table.unpack(column)
    for _, y in ipairs(rows) do assemble(recipe, x, y) end
  end
  for _, y in ipairs { -3.5, -1.5, 0.5, 2.5 } do
    place("fast-inserter", -2.5, y, defines.direction.west)
  end
  if lesson == "rail" then
    for _, station in ipairs { { "copper-plate", -12, { 5.5 } }, { "iron-plate", -8, { 5.5 } },
        { CIRCUIT, 8, { 4.5, 5.5 } } } do
      local item, rail_y, buffers = table.unpack(station)
      local exporting = item == CIRCUIT
      local y = rail_y + (exporting and -2 or 2)
      for x = -10, 12, 2 do place("straight-rail", x, rail_y, defines.direction.east) end
      local stop = place("train-stop", 8, y, exporting and defines.direction.west or defines.direction.east)
      stop.backer_name = "[item=" .. item .. "]"
      for _, x in ipairs(buffers) do
        local chest = place("steel-chest", x, y + (exporting and -0.5 or 0.5))
        chest.insert { name = item, count = 50 }
      end
    end
  end
  return machines
end

local function feed(machines)
  for _, machine in ipairs(machines) do
    local input, output = machine.get_inventory(defines.inventory.crafter_input), machine.get_output_inventory()
    input.clear()
    output.clear()
    for _, ingredient in ipairs(machine.get_recipe().ingredients) do
      if ingredient.name == "copper-plate" or ingredient.name == "iron-plate" then
        input.insert { name = ingredient.name, count = 100 }
      end
    end
  end
end

local function select_area(player, first, last, tool, types)
  local area = { left_top = { x = first[1], y = first[2] },
    right_bottom = { x = last[1], y = last[2] } }
  local entities = player.surface.find_entities_filtered { area = area, type = types, force = player.force }
  Cells.on_selected { player_index = player.index, item = tool, surface = player.surface,
    entities = entities, area = area }
end

local function seed_draft(player, cell)
  local window = player.gui.screen.ssk_cells
  Cells.on_click(player, find_action(window, "ssk_cell", "select"))
  select_area(player, cell.first, cell.last, Selection.tool, Selection.types)
  name_field(player).text = sample_name(cell.name)
end

local function seed_parent(player)
  seed_draft(player, SCIENCE_CELL)
  local cells = storage.production_cells
  -- Give the example parent the boundaries of the whole science line.
  cells.drafts[player.index].ports = {
    inputs = { ["item/copper-plate"] = true, ["item/iron-plate"] = true },
    outputs = { ["item/logistic-science-pack"] = true },
  }
  local id = cells.next_id
  Cells.on_click(player, find_action(player.gui.screen.ssk_cells, "ssk_cell", "save"))
  return id
end

local function parent_toolbar(player)
  local split = player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_cells.ssk_cell_split
  return split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar.ssk_cell_title
end

local function show_parent(player, state, ui)
  ui.show_cell(player, state.parent, VIEWPORT)
  local bar = parent_toolbar(player)
  -- The full chart toolbar is wider than the small Tips and tricks viewport.
  for _, element in ipairs(bar.children) do
    if element.type == "sprite-button" and element.tags.ssk_ui ~= "cell_subdivide"
        and element.tags.ssk_ui ~= "cell_delete" then
      element.visible = false
    end
  end
end

local function compact_editor(player, lesson)
  local frame = player.gui.screen.ssk_cells
  if not frame then return end
  frame.location = DOCK
  if lesson == "rail" then
    frame.ssk_cell_panel.ssk_cell_ports.visible = false
  else
    local stops = find_action(frame, "ssk_cell", "pick_stops")
    if stops then stops.parent.visible = false end
  end
  if lesson == "subdivision" then frame.style.width = EDITOR_WIDTH end
end

local function begin(state, player, ui)
  if state.box and state.box.valid then state.box.destroy() end
  state.box = nil
  ui.close(player)
  Cells.cancel(player)
  Cells.on_surface_deleted(player.surface.index)
  feed(state.machines)
  game.simulation.camera_player_cursor_position = { 0, 5 }
  Cells.open(player)
  player.gui.screen.ssk_cells.location = DOCK
  if state.lesson == "subdivision" then
    state.parent = seed_parent(player)
    state.child = 1
    show_parent(player, state, ui)
  elseif state.lesson == "rail" then
    seed_draft(player, CIRCUIT_CELL)
    compact_editor(player, state.lesson)
  end
  state.step, state.after = 1, game.tick + OPENING_PAUSE
end

local function mouse_click()
  game.simulation.mouse_click()
  return true
end

local function selected_cell(state)
  if state.lesson == "subdivision" then return SCIENCE_CHILDREN[state.child] end
  return state.lesson == "rail" and RAIL_CELL or CIRCUIT_CELL
end

local function move_cursor(position, speed)
  return game.simulation.move_cursor { position = position, speed = speed }
end

local function start_box(state, player, first, color)
  -- The simulation host can move the cursor and click GUI widgets. The box
  -- supplies the world-area drag to the normal selection handler.
  state.box = rendering.draw_rectangle { surface = player.surface, players = { player },
    left_top = first, right_bottom = first, width = 3, color = color }
end

local function extend_box(state, last)
  local reached = move_cursor(last, 0.22)
  state.box.right_bottom = reached and last or game.simulation.camera_player_cursor_position
  return reached
end

local function finish_box(state)
  state.box.destroy()
  state.box = nil
end

local function aim_save()
  return aim_widget { type = "text-button-localised-substring", text = Loc("cells-save") }
end

-- Each step returns true once its input is complete. The delay gives the
-- engine time to lay out the editor and gives viewers time to read each change.
local steps = {
  { BEFORE_CLICK, function(state, player)
    if state.lesson == "subdivision" then
      return aim_icon(parent_toolbar(player).ssk_cell_edit_button_subdivide)
    end
    return aim_icon(find_action(player.gui.screen.ssk_cells, "ssk_cell", "select"))
  end },
  { AFTER_TOOL_CLICK, mouse_click },
  { 8, function(state)
    return move_cursor(selected_cell(state).first, 0.6)
  end },
  { 10, function(state, player)
    start_box(state, player, selected_cell(state).first, { 0.3, 0.8, 1 })
    return true
  end },
  { 18, function(state)
    return extend_box(state, selected_cell(state).last)
  end },
  { 120, function(state, player)
    finish_box(state)
    local cell = selected_cell(state)
    select_area(player, cell.first, cell.last, Selection.tool, Selection.initial_types)
    compact_editor(player, state.lesson)
    return true
  end },
  { BEFORE_CLICK, function(_, player)
    local field = name_field(player)
    return field and aim_widget { type = "textfield", text = field.text }
  end },
  { 30, mouse_click },
  { 65, function(state)
    game.simulation.write { text = sample_name(selected_cell(state).name) }
    return true
  end },
  { BEFORE_CLICK, aim_save },
  { 75, mouse_click },
}

local function reopen_parent(state, player, ui)
  show_parent(player, state, ui)
  return true
end

local subdivision_steps = { table.unpack(steps) }
subdivision_steps[#subdivision_steps + 1] = { 105, function(state, player, ui)
  state.child = 2
  return reopen_parent(state, player, ui)
end }
for _, step in ipairs(steps) do subdivision_steps[#subdivision_steps + 1] = step end
subdivision_steps[#subdivision_steps + 1] = { 30, reopen_parent }

local function add_rail_drag(sequence, action, first, last, tool, types)
  local drag = {
    { BEFORE_CLICK, function(_, player)
      return aim_icon(find_action(player.gui.screen.ssk_cells, "ssk_cell", action))
    end },
    { AFTER_TOOL_CLICK, mouse_click },
    { 8, function() return move_cursor(first, 0.6) end },
    { 15, function(state, player)
      start_box(state, player, first, RAIL_COLOR)
      return true
    end },
    { 18, function(state) return extend_box(state, last) end },
    { 120, function(state, player)
      finish_box(state)
      select_area(player, first, last, tool, types)
      compact_editor(player, state.lesson)
      return true
    end },
  }
  for _, step in ipairs(drag) do sequence[#sequence + 1] = step end
end

local rail_steps = {}
add_rail_drag(rail_steps, "pick_stops", { 6.75, 4.75 }, { 10.5, 8.25 }, Selection.stop_tool, Selection.stop_types)
add_rail_drag(rail_steps, "pick_buffers", { 4, 5 }, { 6, 6 }, Selection.buffer_tool, Selection.buffer_types)
rail_steps[#rail_steps + 1] = { BEFORE_CLICK, aim_save }
rail_steps[#rail_steps + 1] = { 75, mouse_click }
rail_steps[#rail_steps + 1] = { 120, function(_, player)
  Cells.cancel(player)
  Cells.on_surface_deleted(player.surface.index)
  Cells.open(player)
  player.gui.screen.ssk_cells.location = DOCK
  return true
end }
for _, step in ipairs(steps) do rail_steps[#rail_steps + 1] = step end
local sequences = { create = steps, subdivision = subdivision_steps, rail = rail_steps }

function T.register(ui)
  remote.add_interface(T.interface, {
    start = function(lesson)
      local sim = game.simulation
      local camera = CAMERA[lesson]
      local player = sim.create_test_player { name = "production-flow-tip" }
      player.teleport { 0, 6 }
      player.force.research_all_technologies()
      sim.camera_player = player
      sim.camera_position = { camera.x, camera.y or 0 }
      sim.camera_zoom = camera.zoom
      sim.camera_alt_info = true
      local state = { player = player.index, lesson = lesson, machines = build_factory(player, lesson) }
      storage.cell_tip = state
      begin(state, player, ui)
    end,
    update = function()
      local state = storage.cell_tip
      if not state or game.tick < state.after then return end
      local player = game.get_player(state.player)
      local sequence = sequences[state.lesson]
      local step = sequence[state.step]
      if not step or game.tick > state.after + 300 then
        begin(state, player, ui)
      elseif step[2](state, player, ui) then
        state.step = state.step + 1
        state.after = game.tick + (sequence[state.step] and step[1] or 210)
      end
    end,
  })
end

return T
