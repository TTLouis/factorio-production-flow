-- Private K2SE playtest hook. It groups existing machines, train stops and
-- nearby storage through the native editor and observes unmodified train cargo.
local Cells = require("scripts.cells")
local Rail = require("scripts.cell_rail")
local Suggestions = require("scripts.cell_rail_suggestions")
local Selection = require("shared.cell_selection")
local Config = require("scripts.modded_gui_config")

local T = {}
local started_here = false
function T.init() game.tick_paused = false end
function T.unpause()
  local test = storage.rail_native
  if test and test.phase ~= "done" then game.tick_paused = false end
end

local function event(player, name, data)
  data.player_index = player.index
  script.get_event_handler(defines.events[name])(data)
end

local function find(element, key, value, predicate)
  if element.tags[key] == value and (not predicate or predicate(element)) then return element end
  for _, child in ipairs(element.children) do
    local hit = find(child, key, value, predicate)
    if hit then return hit end
  end
end

local function click(player, parent, key, value, predicate)
  event(player, "on_gui_click", { element = assert(find(parent, key, value, predicate), tostring(value)),
    button = defines.mouse_button_type.left })
end

local function select_nav(player, id)
  local us = storage.ui[player.index].cells
  local index
  for i, row in ipairs(us.nav_rows) do if row.ancestor and (row.id or 0) == id then index = i; break end end
  assert(index, "Missing ancestor row")
  local list = assert(find(player.gui.screen.ssk_main, "ssk_ui", "cell_list"))
  list.selected_index = index
  event(player, "on_gui_selection_state_changed", { element = list })
end

local function select_cell(player, id)
  local state = storage.ui[player.index].cells
  local index
  for i, row in ipairs(state.nav_rows) do if not row.ancestor and row.id == id then index = i; break end end
  assert(index, "Missing selectable cell row")
  local list = assert(find(player.gui.screen.ssk_main, "ssk_ui", "cell_list"))
  list.selected_index = index
  event(player, "on_gui_selection_state_changed", { element = list })
  assert(storage.ui[player.index].cells.selected == id, "Selected parent row must remain selected")
end

local function assert_root_caption(player, key)
  local list = assert(find(player.gui.screen.ssk_main, "ssk_ui", "cell_list"))
  assert(serpent.line(list.items[1]):find("production-flow." .. key, 1, true),
    "Unexpected root-return caption at current depth")
end

local function select_area(player, tool, entities, area)
  assert(player.cursor_stack.valid_for_read and player.cursor_stack.name == tool)
  event(player, "on_player_selected_area", { item = tool, entities = entities, surface = player.surface, area = area })
end

local function squared(a, b)
  return (a.x - b.x)^2 + (a.y - b.y)^2
end

local function nearby(entity, types, radius)
  local p = entity.position
  local found = entity.surface.find_entities_filtered { type = types, position = p, radius = radius, force = entity.force }
  table.sort(found, function(a, b)
    local x, y = squared(a.position, p), squared(b.position, p)
    if x ~= y then return x < y end
    return a.unit_number < b.unit_number
  end)
  return found
end

local function candidates(force)
  local active, traffic, total = {}, {}, 0
  for _, train in ipairs(game.train_manager.get_trains { force = force }) do
    local front = train.front_stock
    if front and not train.manual_mode then
      local index = front.surface.index
      active[index], total = (active[index] or 0) + 1, total + 1
      local stop = train.station or train.has_path and train.path_end_stop
      if stop then traffic[stop.unit_number] = (traffic[stop.unit_number] or 0) + 1 end
    end
  end
  local best
  for index, count in pairs(active) do
    if not best or count > active[best] or count == active[best] and index < best then best = index end
  end
  assert(best and total > 1, "K2SE save must contain automatic trains")
  local surface = game.surfaces[best]
  local list = {}
  for _, stop in ipairs(surface.find_entities_filtered { type = "train-stop", force = force }) do
    local scheduled = #stop.get_train_stop_trains()
    if scheduled > 0 or traffic[stop.unit_number] then
      list[#list + 1] = { entity = stop, traffic = traffic[stop.unit_number] or 0, scheduled = scheduled }
    end
  end
  table.sort(list, function(a, b)
    if a.traffic ~= b.traffic then return a.traffic > b.traffic end
    if a.scheduled ~= b.scheduled then return a.scheduled > b.scheduled end
    return a.entity.unit_number < b.entity.unit_number
  end)
  return surface, list, active[best], total
end

local function create_group(player, candidates, index, reserved, label)
  local stops, machines, buffers, seen_machine = {}, {}, {}, {}
  for _, candidate in ipairs(candidates) do
    local stop = candidate.entity
    local machine = nearby(stop, Selection.types, 160)[1]
    if machine then
      stops[#stops + 1] = stop
      if not seen_machine[machine.unit_number] then
        seen_machine[machine.unit_number] = true
        machines[#machines + 1] = machine
      end
      local found = nearby(stop, Selection.buffer_types, 18)
      local chosen = {}
      for _, entity in ipairs(found) do
        if not reserved[entity.unit_number] then
          chosen[#chosen + 1] = entity
          reserved[entity.unit_number] = true
          if #chosen == 5 then break end
        end
      end
      buffers[stop.unit_number] = chosen
    end
  end
  if #machines == 0 then return nil end
  Cells.open(player)
  click(player, player.gui.screen.ssk_cells, "ssk_cell", "select")
  select_area(player, Selection.tool, machines)
  local function window() return assert(player.gui.screen.ssk_cells) end
  window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = label .. " production area " .. index
  click(player, window(), "ssk_cell", "pick_stops")
  select_area(player, Selection.stop_tool, stops)
  for _, stop in ipairs(stops) do
    local unit = stop.unit_number
    if #buffers[unit] > 0 then
      click(player, window(), "ssk_cell", "pick_buffers", function(el) return el.tags.cell_id == unit end)
      select_area(player, Selection.buffer_tool, buffers[unit])
    end
  end
  local id = storage.production_cells.next_id
  click(player, window(), "ssk_cell", "save")
  local result = assert(storage.production_cells.records[id])
  assert(table_size(result.stops) == #stops)
  for unit, entries in pairs(buffers) do assert(table_size(result.stops[unit].buffers) == #entries) end
  return id
end

-- The initial primary selection links eligible stops in the same draft.
local function initial_stop_fixture(player, s)
  if s.initial_stop_checked then return end
  local surface = game.surfaces[s.surface]
  local owned = {}
  for _, record in pairs(storage.production_cells.records) do
    for unit in pairs(record.stops or {}) do owned[unit] = true end
  end
  local stop, machine
  for _, candidate in ipairs(surface.find_entities_filtered { type = "train-stop", force = player.force }) do
    if not owned[candidate.unit_number] then
      local found = nearby(candidate, Selection.types, 160)[1]
      if found then stop, machine = candidate, found; break end
    end
  end
  assert(stop and machine, "Need an unowned stop and machine for initial selection")
  Cells.cancel(player)
  Cells.open(player)
  click(player, player.gui.screen.ssk_cells, "ssk_cell", "select")
  select_area(player, Selection.tool, { machine, stop })
  local draft = assert(storage.production_cells.drafts[player.index])
  assert(draft.members[machine.unit_number] and draft.stops[stop.unit_number], "Initial primary selection links the stop")
  player.gui.screen.ssk_cells.ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = "Initial stop selection witness"
  local id = storage.production_cells.next_id
  click(player, player.gui.screen.ssk_cells, "ssk_cell", "save")
  assert(storage.production_cells.records[id].stops[stop.unit_number], "Explicitly linked stop must persist on Apply")
  s.initial_stop_checked = true
end

-- Exercise the same selection and draft controls as a player, in this private save.
local function layered_fixture(player, s)
  if s.layered then return end
  local machines, seen = {}, {}
  for _, id in ipairs(s.groups) do
    for _, entity in pairs(storage.production_cells.records[id].members) do
      if entity.valid and not seen[entity.unit_number] then
        seen[entity.unit_number] = true
        machines[#machines + 1] = entity
      end
    end
  end
  assert(#machines > 0, "Layered fixture needs live machines")
  local function window() return assert(player.gui.screen.ssk_cells) end
  local function name(value) window().ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = value end
  local before = storage.production_cells.next_id
  Cells.open(player)
  click(player, window(), "ssk_cell", "select")
  select_area(player, Selection.tool, machines)
  name("Layered production campus with extended processing lines")
  click(player, window(), "ssk_cell", "draft_add")
  select_area(player, Selection.tool, { machines[1] })
  name("Production subdivision")
  click(player, window(), "ssk_cell", "list")
  assert(storage.production_cells.next_id == before, "Cancel must discard every staged selection")
  click(player, window(), "ssk_cell", "select")
  select_area(player, Selection.tool, machines)
  name("Layered production campus with extended processing lines")
  click(player, window(), "ssk_cell", "draft_add")
  select_area(player, Selection.tool, { machines[1] })
  name("Production subdivision")
  click(player, window(), "ssk_cell", "draft_add")
  select_area(player, Selection.tool, { machines[1] })
  name("Machine group")
  click(player, window(), "ssk_cell", "save")
  assert(storage.production_cells.records[before + 1].parent_id == before)
  assert(storage.production_cells.records[before + 2].parent_id == before + 1)
  Cells.on_click(player, { tags = { ssk_cell = "edit", cell_id = before } })
  click(player, window(), "ssk_cell", "draft_add")
  select_area(player, Selection.tool, { machines[2] or machines[1] })
  name("Additional subdivision")
  click(player, window(), "ssk_cell", "save")
  assert(storage.production_cells.records[before + 3].parent_id == before,
    "Applying an existing parent edit must append the subdivision")
  s.layered = before
end

-- Build a deterministic rail witness on a disposable surface in the private save.
local function start_suggestion_fixture(player, s)
  local surface = game.create_surface("cell-suggestion-witness")
  surface.request_to_generate_chunks({0, 0}, 5)
  surface.force_generate_chunk_requests()
  player.force.chart(surface, {{-96, -96}, {96, 96}})
  for _, entity in pairs(surface.find_entities_filtered {area = {{-12,-100},{12,100}}, type = {"tree","simple-entity","cliff"}}) do entity.destroy() end
  for y = -80, 80, 2 do
    assert(surface.create_entity {name = "straight-rail", position = {0,y}, direction = defines.direction.north, force = player.force})
  end
  local stop = assert(surface.create_entity {name = "train-stop", position = {2,0}, direction = defines.direction.north, force = player.force})
  stop.backer_name = "[item=iron-plate]"
  assert(stop.connected_rail)
  local loco = assert(surface.create_entity {name = "locomotive", position = {0,50}, orientation = 0, force = player.force})
  local wagon = assert(surface.create_entity {name = "cargo-wagon", position = {0,57}, orientation = 0, force = player.force})
  loco.get_fuel_inventory().insert {name = "coal", count = 50}
  local train = loco.train
  assert(#train.carriages == 2)
  train.schedule = {current = 1, records = {{station = stop.backer_name,
    wait_conditions = {{type = "time", compare_type = "and", ticks = 36000}}}}}
  train.manual_mode = false
  s.suggestion = {surface = surface.index, stop = stop, loco = loco, wagon = wagon, deadline = game.tick + 3600}
  player.set_controller {type = defines.controllers.remote, surface = surface, position = stop.position}
end

local function suggestion_fixture(player, s)
  local witness = s.suggestion
  local surface, wagon, stop = game.surfaces[witness.surface], witness.wagon, witness.stop
  local y = math.floor(wagon.position.y) + 0.5
  local chest = assert(surface.create_entity {name = "steel-chest", position = {2.5,y}, force = player.force})
  chest.get_inventory(defines.inventory.chest).insert {name = "iron-plate", count = 12}
  local arm = assert(surface.create_entity {name = "inserter", position = {1.5,y}, direction = defines.direction.west, force = player.force})
  local selected = assert(surface.create_entity {name = "steel-chest", position = {8,12}, force = player.force})
  selected.get_inventory(defines.inventory.chest).insert {name = "iron-plate", count = 7}
  witness.chest_entity, witness.selected_chest, witness.arm = chest, selected, arm
  return
end

local function finish_suggestion_fixture(player, s)
  local witness = s.suggestion
  local surface, stop, chest, arm, wagon = game.surfaces[witness.surface], witness.stop, witness.chest_entity, witness.arm, witness.wagon
  assert((arm.pickup_target == wagon and arm.drop_target == chest) or (arm.pickup_target == chest and arm.drop_target == wagon),
    "Real inserter must directly connect wagon and chest: " .. serpent.line {pickup = arm.pickup_position, drop = arm.drop_position,
      wagon = wagon.position, chest = chest.position, pickup_target = arm.pickup_target and arm.pickup_target.name,
      drop_target = arm.drop_target and arm.drop_target.name})
  local machine = assert(surface.create_entity {name = "assembling-machine-1", position = {8,0}, force = player.force})
  player.force.recipes["iron-gear-wheel"].enabled = true
  machine.set_recipe("iron-gear-wheel")
  -- Build a balanced copper-cable chain from real recipe rates, so the
  -- internally supplied cable starts excluded on both grid sides.
  player.force.recipes["copper-cable"].enabled = true
  player.force.recipes["electronic-circuit"].enabled = true
  local function assemble(x, y, recipe)
    local entity = assert(surface.create_entity {name = "assembling-machine-1", position = {x,y}, force = player.force})
    entity.set_recipe(recipe)
    return entity
  end
  local cable, circuit = assemble(-8, 0, "copper-cable"), assemble(-12, 0, "electronic-circuit")
  local made = Suggestions.net({[cable.unit_number] = cable})["item/copper-cable"] or 0
  local used = Suggestions.net({[circuit.unit_number] = circuit})["item/copper-cable"] or 0
  local cables, circuits
  for n = 1, 30 do
    for m = 1, 30 do
      if made > 0 and used < 0 and math.abs(n * made + m * used) < 1e-7 then cables, circuits = n, m; break end
    end
    if cables then break end
  end
  assert(cables and circuits, "Need real recipes with an exactly balanced copper-cable chain")
  local selected_machines = {machine, cable, circuit}
  local function add_more(count, recipe, start)
    for i = 2, count do
      local index = start + i
      selected_machines[#selected_machines + 1] = assemble(-8 - (index % 8) * 4, 20 + math.floor(index / 8) * 4, recipe)
    end
  end
  add_more(cables, "copper-cable", 0)
  add_more(circuits, "electronic-circuit", cables + 1)
  selected_machines[#selected_machines + 1] = stop
  selected_machines[#selected_machines + 1] = chest
  selected_machines[#selected_machines + 1] = witness.selected_chest
  Cells.cancel(player)
  Cells.open(player)
  click(player, player.gui.screen.ssk_cells, "ssk_cell", "select")
  select_area(player, Selection.tool, selected_machines)
  local draft = assert(storage.production_cells.drafts[player.index])
  local linked = assert(draft.stops[stop.unit_number])
  assert(linked.role == "import" and draft.ports.inputs["item/iron-plate"] and linked.buffers[chest.unit_number] and linked.buffers[witness.selected_chest.unit_number],
    "Named material, direction and physically matched stock must appear in one draft")
  assert(not storage.cell_rail.stops[stop.unit_number], "Draft must not persist before Save")
  witness.selected = witness.selected_chest.unit_number
  witness.unit, witness.chest, witness.key, witness.side, witness.role, witness.id = stop.unit_number, chest.unit_number,
    "item/iron-plate", "inputs", "import", storage.production_cells.next_id
  draft.name = "Suggested station witness"
  player.gui.screen.ssk_cells.ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name.text = draft.name
end

local function views(player)
  local tabs = player.gui.screen.ssk_main.ssk_inner.ssk_tabs
  for _, tab in ipairs(tabs.tabs) do
    if tab.content.name == "content_cells" then return tab.content.ssk_cell_split.ssk_cell_views end
  end
end

local function open_overview(player, UI, surface)
  Cells.cancel(player)
  local us = storage.ui[player.index] or {}
  storage.ui[player.index] = us
  us.tab_id, us.surface, us.period = "cells", surface.name, 600
  us.cells = { view = "train_stops", chart = {}, mode = "measured" }
  UI.open(player)
  assert(views(player).selected_tab_index == 3)
end

local function shoot(player, s, name, zoom)
  game.take_screenshot { player = player, path = "modded-gui/" .. name .. ".png",
    resolution = Config.resolution, show_gui = true, force_render = true, zoom = zoom }
  s.cases[#s.cases + 1] = { name = name, renderer = "sprites" }
end

local function pick_live(player, s, moving)
  local status = Rail.traffic(s.stops, s.surface, player.force)
  local best, best_count
  for unit, entry in pairs(status) do
    if moving and #entry.headed > 0 or not moving and entry.stopped then
      local stock = Rail.stock(s.stops[unit], s.surface)
      local n = #stock
      if not best or n > best_count or n == best_count and unit < best then best, best_count = unit, n end
    end
  end
  return best, best and status[best]
end

local function train_list(panel, kind)
  local sections = panel.ssk_rail_details.ssk_rail_detail_sections
  local section = sections["ssk_rail_" .. kind .. "_section"]
  return section.ssk_rail_section_body["ssk_rail_" .. kind .. "_trains"]
end

local function select_train(player, kind, id)
  local panel = views(player).ssk_cell_train_stops.ssk_rail_stop_view
  local picker = assert(train_list(panel, kind))
  for i, candidate in ipairs(picker.tags.ids) do
    if candidate == id then
      picker.selected_index = i
      event(player, "on_gui_selection_state_changed", {element = picker})
      local refreshed = views(player).ssk_cell_train_stops.ssk_rail_stop_view
      local camera = assert(refreshed.ssk_rail_preview.ssk_rail_camera)
      assert(camera.entity.train.id == id and storage.ui[player.index].cells.rail.train == id)
      assert(train_list(refreshed, kind) == picker, "Selection preserves the train list")
      return
    end
  end
  error("Train was absent from the " .. kind .. " list")
end

local function show_stop(player, UI, s, unit, train)
  open_overview(player, UI, game.surfaces[s.surface])
  click(player, views(player).ssk_cell_train_stops, "ssk_rail", "jump", function(el) return el.tags.unit == unit end)
  local ui = storage.ui[player.index].cells
  assert(ui.selected == s.owners[unit] and ui.rail.stop == unit, "All must jump to the exact physical stop")
  local panel = views(player).ssk_cell_train_stops.ssk_rail_stop_view
  local sections = panel.ssk_rail_details.ssk_rail_detail_sections
  assert(#sections.children == 3 and sections.style.vertical_spacing == panel.ssk_rail_roles.style.vertical_spacing)
  for _, section in ipairs(sections.children) do
    assert(#section.children == 1 and section.children[1].ssk_rail_section_title)
  end
  local selected_row
  for _, group in ipairs(panel.ssk_rail_roles.children) do
    assert(#group.children == 1 and group.children[1].ssk_rail_section_title)
    local rows = group.ssk_rail_section_body.ssk_rail_stop_rows.ssk_rail_stop_entries
    if rows then
      for _, row in ipairs(rows.children) do
        local button, text = row.ssk_rail_stop_button, row.ssk_rail_stop_text
        assert(#row.children == 2 and button.type == "button" and text.ignored_by_interaction)
        assert(text.ssk_rail_stop_station.ssk_rail_stop_name.caption == Rail.name(s.stops[button.tags.unit]))
        if button.tags.unit == unit then
          assert(button.toggled and text.tags.dark)
          selected_row = button
        else
          assert(not button.toggled)
          event(player, "on_gui_hover", {element = button})
          assert(text.tags.dark, "Hover keeps text readable on the orange row")
          event(player, "on_gui_leave", {element = button})
          assert(not text.tags.dark)
        end
      end
    end
  end
  event(player, "on_gui_click", {element = assert(selected_row), button = defines.mouse_button_type.left})
  assert(ui.rail.stop == unit, "The entire entry uses one stop selection target")
  assert(not panel.ssk_rail_preview.ssk_rail_train, "Train selection belongs in the details column")
  select_train(player, "local", train.id)
end

local function axis(player, mode)
  local element = assert(find(views(player).ssk_cell_train_history, "transfer_axis", true))
  element.switch_state = mode == "events" and "right" or "left"
  event(player, "on_gui_switch_state_changed", {element = element})
  assert(storage.ui[player.index].cells.rail.axis == mode)
end

local function select_view(player, index)
  local tabs = views(player)
  tabs.selected_tab_index = index
  event(player, "on_gui_selected_tab_changed", {element = tabs})
  assert(views(player).selected_tab_index == index)
end

local function role_for(unit, items, stop)
  local up, down = false, false
  for _, visit in ipairs(items) do
    if visit.stop == unit and not visit.pending then
      up, down = up or #visit.loaded > 0, down or #visit.unloaded > 0
    end
  end
  if up then return down and "both" or "export" end
  if down then return "import" end
  local name = Rail.name(stop):gsub("%b[]", ""):lower()
  if not name:find("unload", 1, true) and (name:find("loading", 1, true) or name:find("pickup", 1, true)) then
    return "export"
  end
  return "import"
end

local function edit_buffered_group(player, s)
  local most_buffers, editor = -1
  for _, id in ipairs(s.groups) do
    local count = 0
    for _, stop in pairs(storage.production_cells.records[id].stops) do count = count + table_size(stop.buffers) end
    if count > most_buffers then most_buffers, editor = count, id end
  end
  Cells.on_click(player, { tags = { ssk_cell = "edit", cell_id = editor } })
end

function T.tick(UI)
  local player = game.players[1]
  if not player or not player.connected or player.display_resolution.width < 1000 then return end
  local s = storage.rail_native
  if s and s.phase == "done" and not started_here then
    -- A second native capture can reload the already warmed private playtest.
    started_here = true
    s.cases, s.phase = {}, "replay_editor"
    -- These IDs were created by this private fixture; leave all other cells alone.
    for i, id in ipairs(s.groups) do
      local record = storage.production_cells.records[id]
      if record then record.name = "Production area " .. i end
    end
    local rows = Rail.read_history(s.stops, s.started)
    for unit, stop in pairs(s.stops) do stop.role = role_for(unit, rows, stop) end
    UI.close(player)
    edit_buffered_group(player, s)
    log("MODDED GUI HISTORY recapturing from the saved K2SE playtest")
  elseif not s then
    started_here = true
    assert(script.active_mods["space-exploration"], "This fixture expects the real SE save")
    local surface, stops, trains, all = candidates(player.force)
    assert(#stops >= 3, "Need multiple scheduled physical stops on the train surface")
    player.set_controller { type = defines.controllers.remote, surface = surface, position = stops[1].entity.position }
    player.mod_settings["ssk-allow-small-window"] = {value = true}
    UI.close(player)
    s = { phase = "editor", surface = surface.index, started = game.tick, trains = trains, all_trains = all,
      cases = {}, stops = {}, owners = {}, groups = {} }
    storage.rail_native = s
    local reserve = {}
    for i = 1, math.min(18, #stops), 3 do
      local cluster = {}
      for j = i, math.min(i + 2, #stops) do cluster[#cluster + 1] = stops[j] end
      local id = create_group(player, cluster, #s.groups + 1, reserve, surface.name:gsub("^%l", string.upper))
      if id then
        s.groups[#s.groups + 1] = id
        for unit, stop in pairs(storage.production_cells.records[id].stops) do s.stops[unit], s.owners[unit] = stop, id end
      end
    end
    assert(next(s.stops) and #s.groups > 1, "Attach multiple real SE cell stop groups")
    edit_buffered_group(player, s)
    log("MODDED GUI HISTORY linked " .. table_size(s.stops) .. " stops on " .. surface.name .. " with " .. trains .. " automatic trains")
  elseif s.phase == "replay_editor" then
    shoot(player, s, "rail-editor")
    s.phase = "review_prepare"
  elseif s.phase == "editor" then
    shoot(player, s, "rail-editor")
    s.phase = "warm_start"
  elseif s.phase == "warm_start" then
    Cells.cancel(player)
    player.opened = nil
    game.speed = 64
    s.phase = "warm"
  elseif s.phase == "warm" then
    game.speed = 64
    local elapsed = game.tick - s.started
    if game.tick % 60 ~= 0 then return end
    if elapsed >= (s.progress or 1800) then
      s.progress = elapsed + 1800
      log("MODDED GUI HISTORY simulated " .. math.floor(elapsed / 60) .. " seconds on the real rail network")
    end
    if elapsed < Config.warm_seconds * 60 then return end
    local rows = Rail.read_history(s.stops, s.started)
    local exchanges, loaded, unloaded = 0, 0, 0
    for _, row in ipairs(rows) do
      if not row.pending then
        if #row.loaded > 0 then loaded = loaded + 1 end
        if #row.unloaded > 0 then unloaded = unloaded + 1 end
        if #row.loaded + #row.unloaded > 0 then exchanges = exchanges + 1 end
      end
    end
    if exchanges < 3 and elapsed < math.max(Config.warm_seconds + 90, 180) * 60 then return end
    assert(exchanges > 0, "No real cargo exchanged at attached SE stops")
    s.exchanges, s.loaded, s.unloaded, s.warm_ticks = exchanges, loaded, unloaded, elapsed
    for unit, stop in pairs(s.stops) do stop.role = role_for(unit, rows, stop) end
    game.speed = 1
    s.phase = "review_prepare"
    game.auto_save("rail-warm")
    log("MODDED GUI HISTORY observed " .. exchanges .. " completed cargo exchanges")
  elseif s.phase == "review_prepare" then
    initial_stop_fixture(player, s)
    layered_fixture(player, s)
    start_suggestion_fixture(player, s)
    s.phase = "suggestion_wait"
  elseif s.phase == "suggestion_wait" then
    local witness = s.suggestion
    assert(game.tick < witness.deadline, "Fixture train did not reach its stop")
    if witness.stop.get_stopped_train() ~= witness.loco.train then return end
    suggestion_fixture(player, s)
    s.phase = "suggestion_connect"
  elseif s.phase == "suggestion_connect" then
    finish_suggestion_fixture(player, s)
    s.phase = "suggestion_capture"
  elseif s.phase == "suggestion_capture" then
    Cells.open(player)
    shoot(player, s, "rail-suggestion-draft")
    local shown = assert(storage.cell_outlines and storage.cell_outlines[player.index] and storage.cell_outlines[player.index].draft)
    local chart_count = 0
    for _, obj in ipairs(shown.objects) do
      if obj.valid and obj.render_mode == "chart" then chart_count = chart_count + 1 end
    end
    assert(chart_count > 0, "Draft outlines must include chart render_mode objects for zoomed-out map view")
    player.zoom = 0.08
    s.phase = "suggestion_chart_capture"
  elseif s.phase == "suggestion_chart_capture" then
    shoot(player, s, "rail-outlines-chart", 0.12)
    player.zoom = 1
    s.phase = "suggestion_save"
  elseif s.phase == "suggestion_save" then
    if not player.gui.screen.ssk_cells then Cells.open(player) end
    click(player, player.gui.screen.ssk_cells, "ssk_cell", "save")
    local witness = s.suggestion
    local saved = assert(storage.production_cells.records[witness.id])
    assert(saved.ports[witness.side][witness.key] and saved.stops[witness.unit].role == witness.role
      and saved.stops[witness.unit].buffers[witness.chest] and saved.stops[witness.unit].buffers[witness.selected], "The same dialog Save must persist all suggestions")
    Cells.on_click(player, {tags = {ssk_cell = "edit", cell_id = witness.id}})
    local draft = assert(storage.production_cells.drafts[player.index])
    assert(not draft.ports.outputs["item/stone"] and not draft.ports.inputs["item/stone"],
      "Dedicated witness must start without the copper port")
    local surface = game.surfaces[witness.surface]
    local stop = assert(surface.create_entity {name = "train-stop", position = {2,-20}, direction = defines.direction.north, force = player.force})
    stop.backer_name = "[item=iron-gear-wheel] [item=stone]"
    local chest = assert(surface.create_entity {name = "steel-chest", position = {8,-20}, force = player.force})
    chest.get_inventory(defines.inventory.chest).insert {name = "stone", count = 7}
    click(player, player.gui.screen.ssk_cells, "ssk_cell", "pick_stops")
    select_area(player, Selection.stop_tool, {stop, chest})
    draft = assert(storage.production_cells.drafts[player.index])
    assert(draft.stops[stop.unit_number].role == "export" and draft.ports.outputs["item/stone"]
      and draft.stops[stop.unit_number].buffers[chest.unit_number], "Dedicated drag must add the missing output and selected chest")
    witness.extra_stop, witness.extra_chest = stop.unit_number, chest.unit_number
    s.phase = "dedicated_capture"
  elseif s.phase == "dedicated_capture" then
    shoot(player, s, "rail-dedicated-ports")
    s.phase = "dedicated_save"
  elseif s.phase == "dedicated_save" then
    local output = player.gui.screen.ssk_cells.ssk_cell_panel.ssk_cell_ports.outputs
    click(player, output, "key", "item/stone")
    click(player, player.gui.screen.ssk_cells, "ssk_cell", "save")
    local witness = s.suggestion
    local saved = assert(storage.production_cells.records[witness.id])
    assert(not saved.ports.outputs["item/stone"] and saved.stops[witness.extra_stop].buffers[witness.extra_chest])
    Cells.on_click(player, {tags = {ssk_cell = "edit", cell_id = witness.id}})
    local panel = player.gui.screen.ssk_cells.ssk_cell_panel.ssk_cell_ports
    local stone = assert(find(panel.outputs, "key", "item/stone"))
    local cable_in = assert(find(panel.inputs, "key", "item/copper-cable"))
    local cable_out = assert(find(panel.outputs, "key", "item/copper-cable"))
    assert(not stone.toggled and stone.style.draw_grayscale_picture and not cable_in.toggled and cable_in.style.draw_grayscale_picture
      and not cable_out.toggled and cable_out.style.draw_grayscale_picture,
      "Excluded station-only material and balanced intermediate must remain gray after Save/Edit")
    assert(find(panel.inputs, "key", "item/iron-plate").toggled and find(panel.outputs, "key", "item/iron-gear-wheel").toggled)
    s.phase = "exclusion_capture"
  elseif s.phase == "exclusion_capture" then
    shoot(player, s, "rail-port-exclusions")
    s.phase = "exclusion_finish"
  elseif s.phase == "exclusion_finish" then
    Cells.cancel(player)
    -- Verify single-selection auto-config on real Factorio belts:
    -- unbalanced internal intermediate stays excluded until a boundary belt exports it.
    do
      local surface = game.surfaces[s.suggestion.surface]
      local area = { left_top = { x = -32, y = -32 }, right_bottom = { x = -18, y = -18 } }
      local m1 = assert(surface.create_entity { name = "assembling-machine-1", position = { -28, -24 }, force = player.force })
      m1.set_recipe("copper-cable")
      local m2 = assert(surface.create_entity { name = "assembling-machine-1", position = { -23, -24 }, force = player.force })
      m2.set_recipe("electronic-circuit")
      Cells.open(player)
      click(player, player.gui.screen.ssk_cells, "ssk_cell", "select")
      select_area(player, Selection.tool, { m1, m2 }, area)
      local draft = assert(storage.production_cells.drafts[player.index])
      assert(draft.ports.inputs["item/copper-plate"] and draft.ports.outputs["item/electronic-circuit"],
        "Pure input copper-plate and pure output electronic-circuit must be auto-selected")
      assert(not draft.ports.inputs["item/copper-cable"] and not draft.ports.outputs["item/copper-cable"],
        "Unbalanced internal copper-cable must stay excluded without a boundary belt")
      Cells.cancel(player)
      local b_in = assert(surface.create_entity { name = "transport-belt", position = { -18.5, -24.5 }, direction = defines.direction.east, force = player.force })
      assert(surface.create_entity { name = "transport-belt", position = { -17.5, -24.5 }, direction = defines.direction.east, force = player.force })
      assert(b_in.get_transport_line(1).insert_at_back({ name = "copper-cable", count = 1 }))
      assert(b_in.get_transport_line(2).insert_at_back({ name = "stone", count = 1 }))
      Cells.open(player)
      click(player, player.gui.screen.ssk_cells, "ssk_cell", "select")
      select_area(player, Selection.tool, { m1, m2 }, area)
      draft = assert(storage.production_cells.drafts[player.index])
      assert(draft.ports.outputs["item/copper-cable"] and not draft.ports.inputs["item/copper-cable"],
        "Outgoing boundary belt must promote copper-cable to output")
      assert(not draft.ports.outputs["item/stone"] and not draft.ports.inputs["item/stone"],
        "Unrelated pass-through item on boundary belt must be ignored")
      Cells.cancel(player)
    end
    log("CELL TRAIN SUGGESTIONS NATIVE PASS")
    player.set_controller {type = defines.controllers.remote, surface = game.surfaces[s.surface], position = {0, 0}}
    open_overview(player, UI, game.surfaces[s.surface])
    local state = storage.ui[player.index].cells
    state.selected = s.groups[1]
    UI.refresh(player)
    assert(views(player).selected_tab_index == 3 and next(storage.production_cells.records[state.selected].stops))
    assert(player.gui.screen.ssk_main.ssk_inner.ssk_tabs, "Cells window remains open")
    s.phase = "shared_edit_capture"
  elseif s.phase == "shared_edit_capture" then
    shoot(player, s, "cells-shared-edit")
    s.phase = "shared_edit_click"
  elseif s.phase == "shared_edit_click" then
    local main = player.gui.screen.ssk_main
    local edit = assert(find(main, "ssk_ui", "cell_edit", function(el) return el.tags.cell_id == s.groups[1] end))
    assert(edit.enabled and edit.sprite == "utility/rename_icon")
    click(player, main, "ssk_ui", "cell_edit", function(el) return el.tags.cell_id == s.groups[1] end)
    local draft = storage.production_cells.drafts[player.index]
    assert(draft and draft.id == s.groups[1], "Shared Edit must open the selected cell")
    open_overview(player, UI, game.surfaces[s.surface])
    s.phase = "overview"
  elseif s.phase == "overview" then
    shoot(player, s, "rail-overview")
    s.phase, s.wait_until = "select_stopped", game.tick + 3600
  elseif s.phase == "select_stopped" then
    local unit, entry = pick_live(player, s, false)
    if not unit then assert(game.tick < s.wait_until, "No stopped train to capture"); return end
    show_stop(player, UI, s, unit, entry.stopped)
    s.stopped, s.phase = entry.stopped.id, "stopped"
  elseif s.phase == "stopped" then
    shoot(player, s, "rail-stopped")
    s.phase, s.wait_until = "select_headed", game.tick + 3600
  elseif s.phase == "select_headed" then
    local unit, entry = pick_live(player, s, true)
    if not unit then assert(game.tick < s.wait_until, "No approaching train to capture"); return end
    show_stop(player, UI, s, unit, entry.headed[1])
    s.headed, s.phase = entry.headed[1].id, "headed"
  elseif s.phase == "headed" then
    shoot(player, s, "rail-heading")
    s.phase = "select_scheduled"
  elseif s.phase == "select_scheduled" then
    local panel = views(player).ssk_cell_train_stops.ssk_rail_stop_view
    local here = {}
    for _, id in ipairs(train_list(panel, "local").tags.ids) do here[id] = true end
    for _, id in ipairs(train_list(panel, "scheduled").tags.ids) do
      if not here[id] then s.scheduled = id; break end
    end
    assert(s.scheduled and not here[s.scheduled], "Need a scheduled train outside the physically targeted group")
    select_train(player, "scheduled", s.scheduled)
    s.phase = "scheduled"
  elseif s.phase == "scheduled" then
    shoot(player, s, "rail-scheduled")
    s.phase = "select_history"
  elseif s.phase == "select_history" then
    open_overview(player, UI, game.surfaces[s.surface])
    local control = views(player)
    control.selected_tab_index = 4
    event(player, "on_gui_selected_tab_changed", {element = control})
    local panel = views(player).ssk_cell_train_history
    local interval = assert(find(panel, "ssk_rail", "interval"))
    event(player, "on_gui_click", {element = interval, button = defines.mouse_button_type.left})
    assert(storage.ui[player.index].cells.rail.from)
    click(player, views(player).ssk_cell_train_history, "ssk_rail", "clear_range")
    s.phase = "time"
  elseif s.phase == "time" then
    shoot(player, s, "rail-history-time")
    s.phase = "select_events"
  elseif s.phase == "select_events" then
    axis(player, "events")
    click(player, views(player).ssk_cell_train_history, "ssk_rail", "exchange")
    local rail = storage.ui[player.index].cells.rail
    assert(rail.event and rail.event == rail.expanded)
    s.phase = "events"
  elseif s.phase == "events" then
    shoot(player, s, "rail-history-events")
    s.phase = "select_flow"
  elseif s.phase == "select_flow" then
    axis(player, "time")
    select_view(player, 1)
    s.phase = "flow"
  elseif s.phase == "flow" then
    shoot(player, s, "cells-flow")
    s.phase = "select_map"
  elseif s.phase == "select_map" then
    select_view(player, 2)
    s.phase = "map"
  elseif s.phase == "map" then
    shoot(player, s, "cells-map")
    s.phase = "save"
  elseif s.phase == "save" then
    open_overview(player, UI, game.surfaces[s.surface])
    local us = storage.ui[player.index]
    us.cells.view, us.cells.mode = nil, "measured"
    UI.refresh(player)
    local main = player.gui.screen.ssk_main
    local period = main.ssk_window_bar.ssk_period_picker
    local period_index = period.selected_index
    assert(period.visible, "Measured Flow shows the period picker")
    local switch = assert(find(main, "ssk_ui", "cell_mode"))
    switch.switch_state = "right"
    event(player, "on_gui_switch_state_changed", { element = switch })
    period = player.gui.screen.ssk_main.ssk_window_bar.ssk_period_picker
    assert(period.visible and period.selected_index == period_index, "Capacity preserves the visible period selection")
    s.phase = "layer_root"
  elseif s.phase == "layer_root" then
    assert_root_caption(player, "cells-all")
    shoot(player, s, "cells-layer-root")
    s.phase = "layer_select_root"
  elseif s.phase == "layer_select_root" then
    select_cell(player, s.layered)
    s.phase = "layer_selected_root"
  elseif s.phase == "layer_selected_root" then
    assert(find(views(player).ssk_cell_chart, "key", "recipe/cell-" .. (s.layered + 1)), "Selected root shows its direct child band")
    assert(find(views(player).ssk_cell_chart, "key", "recipe/cell-" .. (s.layered + 3)), "Selected root shows its other direct child band")
    shoot(player, s, "cells-layer-selected-root")
    s.phase = "layer_enter_one"
  elseif s.phase == "layer_enter_one" then
    click(player, player.gui.screen.ssk_main, "ssk_ui", "cell_drill", function(el) return el.tags.cell_id == s.layered end)
    assert(storage.ui[player.index].cells.scope == s.layered)
    s.phase = "layer_one"
  elseif s.phase == "layer_one" then
    assert_root_caption(player, "cells-return-all")
    shoot(player, s, "cells-layer-one")
    s.phase = "layer_select_one"
  elseif s.phase == "layer_select_one" then
    select_cell(player, s.layered + 1)
    s.phase = "layer_selected_one"
  elseif s.phase == "layer_selected_one" then
    assert(find(views(player).ssk_cell_chart, "key", "recipe/cell-" .. (s.layered + 2)), "Selected intermediate parent shows its direct child band")
    shoot(player, s, "cells-layer-selected-one")
    s.phase = "layer_enter_two"
  elseif s.phase == "layer_enter_two" then
    click(player, player.gui.screen.ssk_main, "ssk_ui", "cell_drill", function(el) return el.tags.cell_id == s.layered + 1 end)
    assert(storage.ui[player.index].cells.scope == s.layered + 1)
    s.phase = "layer_two"
  elseif s.phase == "layer_two" then
    assert_root_caption(player, "cells-return-all")
    shoot(player, s, "cells-layer-two")
    s.phase = "layer_returns"
  elseif s.phase == "layer_returns" then
    local us = storage.ui[player.index]
    select_nav(player, s.layered)
    assert(us.cells.scope == s.layered)
    select_nav(player, 0)
    assert(not us.cells.scope)
    assert_root_caption(player, "cells-all")
    s.phase = "layer_save"
  elseif s.phase == "layer_save" then
    s.phase = "done"
    game.auto_save("rail-playtest")
    helpers.write_file("modded-gui/results.json", helpers.table_to_json {
      cases = s.cases, display_scale = player.display_scale, surface = game.surfaces[s.surface].name,
      trains_on_surface = s.trains, automatic_trains = s.all_trains, stops = table_size(s.stops), cells = #s.groups,
      warm_ticks = s.warm_ticks, exchanges = s.exchanges, loaded = s.loaded, unloaded = s.unloaded,
      stopped_train = s.stopped, headed_train = s.headed, scheduled_train = s.scheduled,
    })
    log("MODDED GUI NATIVE PASS")
  end
end

return T
