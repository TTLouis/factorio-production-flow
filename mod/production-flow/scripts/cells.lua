local Loc = require("scripts.locale")
local Selection = require("shared.cell_selection")
local Outlines = require("scripts.cell_outlines")
local Sampler = require("scripts.sampler")
local Capacity = require("scripts.cell_capacity")
local Model = require("scripts.model")
local Picker = require("scripts.material_picker")
local Su = require("scripts.surfaces")
local Rail = require("scripts.cell_rail")
local RailSuggestions = require("scripts.cell_rail_suggestions")
local BufferSuggestions = require("scripts.cell_rail_buffer_suggestions")
local PortSuggestions = require("scripts.cell_port_suggestions")

local Cells = { NAME = "ssk_cells", DELETE_NAME = "ssk_cell_delete" }
local selection_modes = { select = true, add = true, remove = true }
local supported = {}
for _, kind in ipairs(Selection.types) do supported[kind] = true end

local function state()
  storage.production_cells = storage.production_cells or { next_id = 1, records = {}, drafts = {} }
  return storage.production_cells
end

local function eligible(entity, surface_index)
  return entity.valid and supported[entity.type] and entity.unit_number
    and entity.surface.index == surface_index and entity.force == game.forces.player
end

local function live_members(entities, surface_index)
  local members, count = {}, 0
  for _, entity in pairs(entities) do
    if eligible(entity, surface_index) and not members[entity.unit_number] then
      members[entity.unit_number] = entity
      count = count + 1
    end
  end
  return members, count
end

-- Members are stored by unit number. A record also keeps each member's position so
-- that a machine built where a member was removed (upgrade, fast-replace, ghost
-- revival, manual re-placement) can take over its slot. Positions are half-tile
-- keys because machine centres sit on tile or half-tile coordinates.
local function position_key(position)
  return math.floor(position.x * 2 + 0.5) .. ":" .. math.floor(position.y * 2 + 0.5)
end

local function spot(entity)
  return { x = entity.position.x, y = entity.position.y, w = entity.tile_width, h = entity.tile_height }
end

local function positions_of(members)
  local positions = {}
  for unit, entity in pairs(members) do
    if entity.valid then positions[unit] = spot(entity) end
  end
  return positions
end

local function vacant_slots(record)
  local vacant = {}
  local positions = record.positions or {}
  for unit, entity in pairs(record.members) do
    if not entity.valid and positions[unit] then vacant[unit] = positions[unit] end
  end
  return vacant
end

local function count_keys(map)
  local count = 0
  for _ in pairs(map) do count = count + 1 end
  return count
end

-- storage.production_cells.slots[surface_index][position_key][cell_id] = unit_number
-- storage.cell_units[unit_number] = { cell_id, ... } is read by the sampler to
-- attribute measured crafts; ids are sorted so attribution order is stable.
function Cells.reindex()
  local cells = state()
  local slots, units, children = {}, {}, {}
  local ids = {}
  for id in pairs(cells.records) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local record = cells.records[id]
    local scope = record.parent_id or 0
    children[scope] = children[scope] or {}
    children[scope][#children[scope] + 1] = id
    if not record.positions then record.positions = positions_of(record.members) end
    record.since = record.since or game.tick
    local by_key = slots[record.surface_index] or {}
    slots[record.surface_index] = by_key
    for unit, position in pairs(record.positions) do
      local key = position_key(position)
      by_key[key] = by_key[key] or {}
      by_key[key][id] = unit
    end
    for unit in pairs(record.members) do
      local list = units[unit]
      if not list then list = {}; units[unit] = list end
      list[#list + 1] = id
    end
  end
  cells.slots, cells.children = slots, children
  -- Only peers compete in an overview; ancestor inclusion is intentional.
  local shared = {}
  for unit, list in pairs(units) do
    local counts = {}
    for _, id in ipairs(list) do
      local scope = cells.records[id].parent_id or 0
      counts[scope] = (counts[scope] or 0) + 1
    end
    for _, id in ipairs(list) do
      if counts[cells.records[id].parent_id or 0] > 1 then
        shared[unit] = shared[unit] or {}
        shared[unit][id] = true
      end
    end
  end
  storage.cell_shared_units = next(shared) and shared or nil
  storage.cell_units = next(units) and units or nil
  Rail.reindex(cells.records)
end

-- Validate inclusive membership, including vacant replacement slots.
function Cells.valid_hierarchy(records, record)
  local parent = record.parent_id and records[record.parent_id]
  if record.parent_id and (not parent or parent.surface_index ~= record.surface_index) then return false, "cells-parent-changed" end
  local seen, current = { [record.id] = true }, parent
  while current do
    if seen[current.id] then return false, "cells-parent-changed" end
    seen[current.id] = true
    current = current.parent_id and records[current.parent_id]
  end
  if parent then
    for unit in pairs(record.members) do
      if not parent.members[unit] then return false, "cells-outside-parent" end
    end
  end
  for _, child in pairs(records) do
    if child.parent_id == record.id then
      if child.surface_index ~= record.surface_index then return false, "cells-child-members" end
      for unit in pairs(child.members) do
        if not record.members[unit] then return false, "cells-child-members" end
      end
    end
  end
  return true
end

function Cells.missing(record)
  return count_keys(vacant_slots(record))
end

-- Called for every built or revived crafting machine. Re-attaches it to each cell
-- whose member at the same position is gone. Valid members are never replaced.
function Cells.on_built(entity)
  local cells = storage.production_cells
  if not (cells and next(cells.records) and entity and entity.valid and supported[entity.type]) then return end
  if not cells.slots then Cells.reindex() end
  local by_key = cells.slots[entity.surface.index]
  local slot = by_key and by_key[position_key(entity.position)]
  if not slot then return end
  local unit = entity.unit_number
  if not (unit and eligible(entity, entity.surface.index)) then return end
  local changed = false
  for id, old in pairs(slot) do
    local record = cells.records[id]
    local previous = record and record.members[old]
    if record and old ~= unit and not (previous and previous.valid) and not record.members[unit] then
      record.members[old], record.positions[old] = nil, nil
      record.members[unit] = entity
      record.positions[unit] = spot(entity)
      changed = true
    end
  end
  if changed then Cells.reindex() end
end

-- Space Exploration moves a spaceship by cloning its entities to another surface
-- and destroying the originals. A cell follows its machines only when every
-- member that was live when cloning began arrived on one surface and none of the
-- originals remains. Copies (originals kept) and partial moves leave the cell
-- where it is; members that left become missing slots.
local CLONE_GRACE_TICKS = 600

function Cells.on_cloned(source, destination)
  local units = storage.cell_units
  local ids = units and source and source.valid and source.unit_number and units[source.unit_number]
  if not (ids and destination and destination.valid and destination.unit_number) then return end
  local cells = state()
  local pending = cells.clones or {}
  cells.clones = pending
  for _, id in ipairs(ids) do
    local record = cells.records[id]
    if record then
      local move = pending[id]
      if not move then
        local live = {}
        for unit, entity in pairs(record.members) do
          if entity.valid then live[unit] = true end
        end
        move = { first = game.tick, live = live, map = {} }
        pending[id] = move
      end
      move.map[source.unit_number] = destination
    end
  end
end

---@param final boolean? Decide now (the source surface is being deleted).
function Cells.resolve_clones(final)
  local cells = storage.production_cells
  local pending = cells and cells.clones
  if not pending then return end
  local changed = false
  for id, move in pairs(pending) do
    local record = cells.records[id]
    local waiting = false
    if record and not record.parent_id then
      local remaining, surface, complete = false, nil, true
      for unit in pairs(move.live) do
        local original = record.members[unit]
        if original and original.valid then remaining = true end
        local copy = move.map[unit]
        if not (copy and copy.valid) then
          complete = false
        else
          surface = surface or copy.surface.index
          if not eligible(copy, surface) then complete = false end
        end
      end
      if remaining then
        waiting = not final and game.tick < move.first + CLONE_GRACE_TICKS
      elseif not final and game.tick <= move.first then
        waiting = true
      elseif complete and surface then
        local members, positions = {}, {}
        for unit in pairs(move.live) do
          local copy = move.map[unit]
          members[copy.unit_number] = copy
          positions[copy.unit_number] = spot(copy)
        end
        for unit, entity in pairs(record.members) do
          if not entity.valid and not move.live[unit] and record.positions[unit] then
            members[unit], positions[unit] = entity, record.positions[unit]
          end
        end
        record.members, record.positions, record.surface_index = members, positions, surface
        -- The root's complete move decides the whole tree. Descendants use the
        -- same mapping, never move independently on a partial child clone.
        local function move_children(parent_id)
          for _, child_id in ipairs((cells.children and cells.children[parent_id]) or {}) do
            local child = cells.records[child_id]
            local child_members, child_positions = {}, {}
            for unit in pairs(child.members) do
              local copy = move.map[unit]
              if copy and copy.valid then
                child_members[copy.unit_number], child_positions[copy.unit_number] = copy, spot(copy)
              elseif not move.live[unit] and child.positions[unit] then
                child_members[unit], child_positions[unit] = child.members[unit], child.positions[unit]
              end
            end
            child.members, child.positions, child.surface_index = child_members, child_positions, surface
            move_children(child_id)
          end
        end
        move_children(id)
        changed = true
      end
    end
    if not waiting then pending[id] = nil end
  end
  if not next(pending) then cells.clones = nil end
  if changed then Cells.reindex() end
end

-- The All view charts the inputs and outputs the player chose for the cell.
local SIDES = { "inputs", "outputs" }
Cells.SIDES = SIDES

local function boundary_flows(members, inputs)
  local net, produced, consumed = {}, {}, {}
  local rates, fuels = Capacity.rates(members, nil, inputs, inputs ~= nil)
  Capacity.flows(rates,
    function(_, key, rate)
      net[key] = (net[key] or 0) - rate
      if rate > 1e-9 then consumed[key] = true end
    end,
    function(_, key, rate)
      net[key] = (net[key] or 0) + rate
      if rate > 1e-9 then produced[key] = (produced[key] or 0) + rate end
    end)
  for key, users in pairs(fuels) do
    for _, rate in pairs(users) do net[key] = (net[key] or 0) - rate end
  end
  return net, produced, rates, fuels, consumed
end

local function net_ports(net)
  local ports = { inputs = {}, outputs = {} }
  for key, amount in pairs(net) do
    if amount < -1e-9 then ports.inputs[key] = true elseif amount > 1e-9 then ports.outputs[key] = true end
  end
  return ports
end

-- Inputs follow the production chain forward. Outputs follow it backward
-- from final products. Recipes making only burner fuel add no level.
local function material_order(net, produced, rates, fuels)
  local materials, feeds = {}, {}
  for key in pairs(produced) do
    if not fuels[key] then materials[key] = true end
  end
  for name, rate in pairs(rates) do
    local recipe = storage.graph.recipes[name]
    for _, product in ipairs(recipe.products) do
      local key = product.key
      if not fuels[key] and rate.normal * product.amount + rate.bonus * product.prod > 1e-9 then
        for _, ingredient in ipairs(recipe.ingredients) do
          local input = ingredient.key
          if input ~= key and ingredient.amount > 0 and not fuels[input] then
            materials[input] = true
            feeds[input] = feeds[input] or {}
            feeds[input][#feeds[input] + 1] = key
          end
        end
      end
    end
  end
  local keys = {}
  for key in pairs(materials) do keys[#keys + 1] = key end
  table.sort(keys)
  -- Each dependency lowers a product by a level. Rank recycling cycles
  -- together and keep a closed cycle below products that have no further use.
  local component, count = Model._tarjan(keys, feeds)
  local members, output_level, input_level = {}, {}, {}
  for _, key in ipairs(keys) do
    local id = component[key]
    members[id] = members[id] or {}
    members[id][#members[id] + 1] = key
  end
  for id = 1, count do
    local depth = #members[id] > 1 and 1 or 0
    for _, key in ipairs(members[id]) do
      for _, product in ipairs(feeds[key] or {}) do
        local next_id = component[product]
        if next_id ~= id then depth = math.max(depth, output_level[next_id] + 1) end
      end
    end
    output_level[id] = depth
  end
  for id = count, 1, -1 do
    local depth = input_level[id] or (#members[id] > 1 and 1 or 0)
    input_level[id] = depth
    for _, key in ipairs(members[id]) do
      for _, product in ipairs(feeds[key] or {}) do
        local next_id = component[product]
        if next_id ~= id then input_level[next_id] = math.max(input_level[next_id] or 0, depth + 1) end
      end
    end
  end
  return {
    inputs = function(a, b)
      if (fuels[a] ~= nil) ~= (fuels[b] ~= nil) then return fuels[a] ~= nil end
      local ra, rb = net[a] or 0, net[b] or 0
      local x = input_level[component[a]] or (ra < -1e-9 and 0 or math.huge)
      local y = input_level[component[b]] or (rb < -1e-9 and 0 or math.huge)
      if x ~= y then return x < y end
      if ra ~= rb then return ra < rb end
      return a < b
    end,
    outputs = function(a, b)
      if (fuels[a] ~= nil) ~= (fuels[b] ~= nil) then return not fuels[a] end
      local x, y = output_level[component[a]] or math.huge, output_level[component[b]] or math.huge
      if x ~= y then return x < y end
      local ra, rb = produced[a] or 0, produced[b] or 0
      if ra ~= rb then return ra > rb end
      return a < b
    end,
  }
end

local function main_product(produced, before, rates)
  local best
  for key in pairs(produced) do
    local kind, name = key:match("^(%a+)/(.+)$")
    local valid = kind == "item" and prototypes.item[name] or kind == "fluid" and prototypes.fluid[name]
    if valid and (not best or before(key, best)) then best = key end
  end
  if not best then return nil end
  if rates and storage.graph and storage.graph.recipes then
    local best_recipe, best_rate
    for name, rate in pairs(rates) do
      local recipe = storage.graph.recipes[name]
      if recipe then
        local out = 0
        for _, product in ipairs(recipe.products) do
          if product.key == best then out = out + rate.normal * product.amount + rate.bonus * product.prod end
        end
        if out > 1e-9 and (not best_recipe or out > best_rate or (out == best_rate and name < best_recipe)) then
          best_recipe, best_rate = name, out
        end
      end
    end
    if best_recipe and prototypes.recipe and prototypes.recipe[best_recipe]
      and best ~= "item/" .. best_recipe and best ~= "fluid/" .. best_recipe then
      return "recipe/" .. best_recipe
    end
  end
  return best:sub(1, 5) == "item/" and best:sub(6) or best
end

local function suggested_item(members, inputs)
  local net, produced, rates, fuels = boundary_flows(members, inputs or {})
  return main_product(produced, material_order(net, produced, rates, fuels).outputs, rates)
end

local function copy_ports(ports)
  local out = { inputs = {}, outputs = {} }
  for _, side in ipairs(SIDES) do
    for key in pairs(ports and ports[side] or {}) do out[side][key] = true end
  end
  return out
end

local function port_prototype(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  return kind == "item" and prototypes.item[name] or kind == "fluid" and prototypes.fluid[name] or nil
end

local function display_prototype(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  if kind == "recipe" then return prototypes.recipe and prototypes.recipe[name] or nil end
  return port_prototype(key)
end

local function remember_name(player, draft)
  local window = player.gui.screen[Cells.NAME]
  local form = window and window.ssk_cell_panel.ssk_cell_form
  if form then draft.name = form.ssk_cell_name_column.ssk_cell_name.text end
end

-- A saved cell's boundary. Cells saved before boundaries were chosen by hand
-- keep every net flow of their machines.
function Cells.boundary(record)
  if record.ports then return record.ports end
  local members = Cells.members(record)
  local net = boundary_flows(members)
  return net_ports(net)
end

function Cells.members(record)
  return live_members(record.members, record.surface_index)
end

-- Display items are stored as an item name (older cells and items) or a typed
-- key such as fluid/petroleum-gas or recipe/advanced-oil-processing; this
-- returns the typed key if it still exists.
local function display_key(value)
  if not value then return nil end
  local key = value:find("/", 1, true) and value or "item/" .. value
  return display_prototype(key) and key or nil
end

-- The typed key of the cell's display item or fluid.
function Cells.display_item(record, members)
  if record.display_item ~= nil then return display_key(record.display_item) end
  return display_key(suggested_item(members, record.ports and record.ports.inputs))
end

function Cells.close(player)
  local picker = player.gui.screen.ssk_material_picker
  if picker and (picker.tags.target or ""):sub(1, 4) == "cell" then Picker.close(player) end
  local window = player.gui.screen[Cells.NAME]
  if window then
    -- The window reopens where the player left it while they edit.
    local cells = storage.production_cells
    if cells then
      cells.places = cells.places or {}
      cells.places[player.index] = { x = window.location.x, y = window.location.y }
    end
    window.destroy()
  end
end

local function clear_confirmation(player)
  local cells = storage.production_cells
  if cells and cells.deletions then cells.deletions[player.index] = nil end
  local confirmation = player.gui.screen[Cells.DELETE_NAME]
  if confirmation then confirmation.destroy() end
end

local function holding_tool(player)
  local cursor = player and player.cursor_stack
  return cursor and cursor.valid_for_read and (cursor.name == Selection.tool
    or cursor.name == Selection.stop_tool or cursor.name == Selection.buffer_tool) or false
end

local function sync_cursor_outlines(player)
  if not player then return end
  local cells = storage.production_cells
  if player.force == game.forces.player and holding_tool(player) and cells and next(cells.records) then
    local draft = cells.drafts and cells.drafts[player.index]
    Outlines.show_surface(player, cells.records, player.surface.index, draft and draft.id)
  else
    Outlines.clear(player.index, "cursor")
  end
end

function Cells.cancel(player)
  clear_confirmation(player)
  if storage.production_cells then state().drafts[player.index] = nil end
  Outlines.clear(player.index, "draft")
  Outlines.clear(player.index, "cursor")
  local cursor = player.cursor_stack
  if holding_tool(player) then cursor.clear() end
  Cells.close(player)
end

local function action(parent, name, sprite, tooltip, style, id)
  return parent.add { type = "sprite-button", sprite = sprite, style = style or "tool_button",
    tooltip = tooltip, tags = { ssk_cell = name, cell_id = id } }
end

local function rail_editor(panel, draft)
  local title = panel.add { type = "frame", style = "subheader_frame" }
  title.style.horizontally_stretchable = true
  title.add { type = "label", style = "subheader_caption_label", caption = Loc("rail-stops") }
  title.add { type = "empty-widget" }.style.horizontally_stretchable = true
  action(title, "pick_stops", "utility/cross_select", Loc("rail-pick-stops"))
  if not next(draft.stops or {}) then return end
  local scroll = panel.add { type = "scroll-pane", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
  scroll.style.maximal_height, scroll.style.horizontally_stretchable = 155, true
  local units = {}
  for unit in pairs(draft.stops) do units[#units + 1] = unit end
  table.sort(units)
  for _, unit in ipairs(units) do
    local stop = draft.stops[unit]
    local row = scroll.add { type = "flow", direction = "horizontal" }
    row.style.vertical_align = "center"
    local live = Rail.live_stop(stop, draft.surface_index)
    local caption = live and Rail.name(stop) or Loc("rail-missing-stop", Rail.name(stop))
    local name = row.add { type = "label", caption = caption, tooltip = caption }
    name.style.width, name.style.single_line = 138, true
    local index = stop.role == "both" and 3 or stop.role == "export" and 2 or 1
    row.add { type = "drop-down", items = { Loc("rail-import"), Loc("rail-export"), Loc("rail-both") },
      selected_index = index, tags = { ssk_rail_role = unit } }.style.width = 96
    local count, missing = 0, 0
    for _, entity in pairs(stop.buffers) do
      if entity.valid and entity.surface.index == draft.surface_index and entity.force == game.forces.player then count = count + 1
      else missing = missing + 1 end
    end
    action(row, "pick_buffers", "utility/cross_select", Loc("rail-pick-buffers"), nil, unit).enabled = live ~= nil
    local stock = row.add { type = "label", caption = count + missing > 0 and tostring(count) or "",
      tooltip = Loc("rail-buffer-count", count) }
    stock.style.width = 52
    if missing > 0 then
      row.add { type = "sprite", sprite = "utility/warning_icon", tooltip = Loc("rail-missing-buffers", missing) }
    end
    if count + missing > 0 then action(row, "clear_buffers", "utility/reset", Loc("rail-clear-buffers"), nil, unit) end
    action(row, "unlink_stop", "utility/trash", Loc("rail-unlink-stop"), "tool_button_red", unit)
  end
end

function Cells.on_rail_role(player, element)
  local draft = state().drafts[player.index]
  local stop = draft and draft.stops and draft.stops[element.tags.ssk_rail_role]
  local role = Rail.roles[element.selected_index]
  if player.force == game.forces.player and stop and role then stop.role = role end
end

function Cells.open(player, focus_side, focus_key)
  Cells.close(player)
  if player.force ~= game.forces.player then return end
  local cells = state()
  local draft = cells.drafts[player.index]
  -- The machines being selected stay outlined until the draft is saved or cancelled.
  if draft then Outlines.show_draft(player, draft, cells.next_id) else Outlines.clear(player.index, "draft") end
  local frame = player.gui.screen.add { type = "frame", name = Cells.NAME, direction = "vertical" }
  local title = frame.add { type = "flow", style = "frame_header_flow" }
  title.drag_target = frame
  title.add { type = "label", style = "frame_title", caption = Loc("cells-title"), ignored_by_interaction = true }
  local spacer = title.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  action(title, "close", "utility/close", Loc("help-close"), "frame_action_button")

  local panel = frame.add { type = "frame", name = "ssk_cell_panel", direction = "vertical", style = "inside_shallow_frame" }
  panel.style.minimal_width = 368
  panel.style.horizontally_stretchable = true
  local bar = panel.add { type = "frame", style = "subheader_frame" }
  bar.style.horizontally_stretchable = true
  if draft then
    local members, count = live_members(draft.members, draft.surface_index)
    bar.add { type = "label", style = "subheader_caption_label", caption = Loc("cells-machine-count", count) }
    local missing = draft.vacant and count_keys(draft.vacant) or 0
    if missing > 0 then
      bar.add { type = "label", name = "ssk_cell_missing", style = "subheader_caption_label",
        caption = Loc("cells-missing-count", missing), tooltip = Loc("cells-missing-tip") }
    end
    local right = bar.add { type = "empty-widget" }
    right.style.horizontally_stretchable = true
    action(bar, "add", "utility/add", Loc("cells-add-machines"))
    action(bar, "remove", "utility/close", Loc("cells-remove-machines"), "tool_button_red").enabled = count > 0
    action(bar, "select", "utility/cross_select", Loc("cells-reselect"))
    if missing > 0 then action(bar, "forget", "utility/trash", Loc("cells-forget-missing"), "tool_button_red") end
    do
      local session = draft.session
      local group = panel.add { type = "flow", direction = "vertical" }
      group.style.padding = 8
      group.style.horizontally_stretchable = true
      group.add { type = "label", caption = Loc("cells-draft-bounds", session and session.active > 0
        and ((session.staged[draft.parent_draft] or session.root).name) or Loc("cells-whole")) }
      if session then
        local nav = group.add { type = "scroll-pane", style = "naked_scroll_pane",
          horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
        nav.style.horizontally_stretchable = true
        nav.style.maximal_height = 120
        nav = nav.add { type = "flow", direction = "vertical" }
        nav.style.horizontally_stretchable = true
        local root_button = nav.add { type = "button", style = "tool_button", caption = session.root.name ~= "" and session.root.name or Loc("cells-whole"), tags = { ssk_cell = "draft_switch", draft_index = 0 } }
        root_button.toggled = session.active == 0
        for i, child in ipairs(session.staged) do
          local button = nav.add { type = "button", style = "tool_button", caption = child.name ~= "" and child.name or Loc("cells-subdivision"), tags = { ssk_cell = "draft_switch", draft_index = i } }
          button.toggled = session.active == i
        end
      end
      local add = group.add { type = "sprite-button", style = "tool_button", sprite = "utility/add",
        tooltip = Loc("cells-add-subdivision"), tags = { ssk_cell = "draft_add" } }
      add.enabled = count > 0
    end
    local form = panel.add { type = "flow", name = "ssk_cell_form", direction = "horizontal" }
    form.style.padding = 8
    form.style.horizontal_spacing = 8
    form.style.horizontally_stretchable = true
    local name_column = form.add { type = "flow", name = "ssk_cell_name_column", direction = "vertical" }
    name_column.style.horizontally_stretchable = true
    name_column.add { type = "label", caption = Loc("cells-name") }
    local field = name_column.add { type = "textfield", name = "ssk_cell_name", text = draft.name }
    field.style.horizontally_stretchable = true
    field.focus()

    local net, produced, rates, fuels, consumed = boundary_flows(members, draft.ports and draft.ports.inputs or {})
    local candidates = net_ports(net)
    local order = material_order(net, produced, rates, fuels)
    if not draft.ports then
      draft.ports = copy_ports(PortSuggestions.suggest(net, produced, consumed, rates, fuels, game.surfaces[draft.surface_index], draft.selection_area))
      for fuel in pairs(fuels) do draft.ports.outputs[fuel] = nil end
    end
    -- Offer internal ingredients and products as excluded choices as well.
    for key in pairs(consumed) do candidates.inputs[key] = true end
    for key in pairs(produced) do candidates.outputs[key] = true end
    -- A linked stop remains a source of optional named ports after Save/Edit.
    if next(draft.stops or {}) then
      local rail_net = RailSuggestions.net(members)
      for _, stop in pairs(draft.stops) do
        local suggested = RailSuggestions.ports(Rail.name(stop), stop.role, rail_net)
        for _, side in ipairs(SIDES) do
          for key in pairs(suggested[side]) do candidates[side][key] = true end
        end
      end
    end

    -- Any item or fluid can represent the cell. Until the player picks one, it
    -- follows the cell's main product.
    if not (draft.display_chosen and display_key(draft.display_item)) then
      draft.display_item, draft.display_chosen = main_product(produced, order.outputs, rates), nil
    end
    local item_column = form.add { type = "flow", name = "ssk_cell_item_column", direction = "vertical" }
    item_column.add { type = "label", caption = Loc("cells-display-item") }
    Picker.button(item_column, display_key(draft.display_item), "cell", "ssk_cell_display_item")

    local ports = panel.add { type = "flow", name = "ssk_cell_ports", direction = "vertical" }
    ports.style.padding = 8
    ports.style.vertical_spacing = 8
    ports.style.horizontally_stretchable = true
    for _, side in ipairs(SIDES) do
      local selected = draft.ports[side]
      local opposite = draft.ports[side == "inputs" and "outputs" or "inputs"]
      local section = ports.add { type = "flow", name = side, direction = "vertical" }
      section.style.vertical_spacing = 4
      section.style.horizontally_stretchable = true
      section.add { type = "label", style = "caption_label", tooltip = Loc("cells-ports-tip"),
        caption = side == "inputs" and Loc("cells-inputs") or Loc("cells-outputs") }
      local options, listed = candidates[side], {}
      for key in pairs(selected) do options[key] = true end
      for key in pairs(draft.off_ports and draft.off_ports[side] or {}) do options[key] = true end
      for key in pairs(options) do
        if not opposite[key] and port_prototype(key) then listed[#listed + 1] = key end
      end
      table.sort(listed, order[side])
      local slots = section.add { type = "frame", name = "slots", style = "slot_button_deep_frame" }
      local scroll = slots.add { type = "scroll-pane", name = "scroll", style = "naked_scroll_pane",
        horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
      scroll.style.minimal_width, scroll.style.minimal_height, scroll.style.maximal_height = 320, 40, 120
      local grid = scroll.add { type = "table", name = "materials", style = "filter_slot_table", column_count = 8 }
      for _, key in ipairs(listed) do
        local included = selected[key] == true
        local hint = included and Loc("cells-port-deselect") or Loc("cells-port-select")
        local button = grid.add { type = "sprite-button", style = "slot_button", sprite = key,
          tooltip = { "", port_prototype(key).localised_name, "\n", hint },
          tags = { ssk_cell = "port", side = side, key = key } }
        button.toggled = included
        button.style.draw_grayscale_picture = not included
        if side == focus_side and key == focus_key then scroll.scroll_to_element(button) end
      end
      grid.add { type = "sprite-button", name = "add_material", style = "slot_button", sprite = "utility/add_white",
        tooltip = side == "inputs" and Loc("cells-ports-add-inputs") or Loc("cells-ports-add-outputs"),
        tags = { ssk_cell = "port_add", side = side } }
    end

    rail_editor(panel, draft)
    local footer = frame.add { type = "flow", style = "dialog_buttons_horizontal_flow" }
    footer.add { type = "button", style = "back_button", caption = Loc("cells-cancel"), tags = { ssk_cell = "list" } }
    local gap = footer.add { type = "empty-widget", style = "draggable_space" }
    gap.style.horizontally_stretchable = true
    footer.add { type = "button", style = "confirm_button", caption = Loc(draft.session and "cells-apply" or "cells-save"), tags = { ssk_cell = "save" } }
  else
    bar.add { type = "label", style = "subheader_caption_label", caption = Loc("cells-saved") }
    local gap = bar.add { type = "empty-widget" }
    gap.style.horizontally_stretchable = true
    -- Like the Production Flow window, the list shows one surface: where the
    -- player is, or another surface that has cells.
    local counts, listed = {}, {}
    for _, record in pairs(cells.records) do
      counts[record.surface_index] = (counts[record.surface_index] or 0) + 1
    end
    for index in pairs(counts) do
      if game.surfaces[index] then listed[#listed + 1] = index end
    end
    table.sort(listed)
    local chosen = cells.list_surfaces and cells.list_surfaces[player.index]
    if chosen and not counts[chosen] then chosen = nil end
    local items, selected = { Loc("ui-where-i-am", Su.rich(player.surface)) }, 1
    for i, index in ipairs(listed) do
      items[i + 1] = Loc.join(Su.rich(game.surfaces[index]), " (", tostring(counts[index]), ")")
      if index == chosen then selected = i + 1 end
    end
    local surfaces = bar.add { type = "drop-down", name = "ssk_cell_list_surface", items = items,
      selected_index = selected, tooltip = Loc("cells-list-surface-tip"),
      tags = { ssk_cell_list_surface = true, surfaces = listed } }
    surfaces.style.width = 180
    action(bar, "select", "utility/add", Loc("cells-new"))
    local rows = panel.add { type = "scroll-pane", style = "naked_scroll_pane", direction = "vertical", horizontal_scroll_policy = "never" }
    rows.style.maximal_height = 350
    rows.style.padding = 8
    rows.style.horizontally_stretchable = true
    local shown_surface = chosen and game.surfaces[chosen] or player.surface
    local ids = {}
    for id, record in pairs(cells.records) do
      if record.surface_index == shown_surface.index then ids[#ids + 1] = id end
    end
    table.sort(ids)
    if #ids == 0 then
      local empty = rows.add { type = "label", style = "grey_label",
        caption = next(cells.records) and Loc("cells-empty-surface", Su.rich(shown_surface)) or Loc("cells-empty") }
      empty.style.single_line = false
      empty.style.maximal_width = 340
    end
    for _, id in ipairs(ids) do
      local record = cells.records[id]
      local _, count = live_members(record.members, record.surface_index)
      local missing = Cells.missing(record)
      local surface = game.surfaces[record.surface_index]
      local row = rows.add { type = "flow" }
      -- Same surface label as the Production Flow header's surface picker.
      local where = Su.rich(surface)
      local caption = missing > 0 and Loc("cells-row-missing", record.name, where, count, missing)
        or Loc("cells-row", record.name, where, count)
      local label = row.add { type = "label", caption = caption }
      label.style.single_line = false
      label.style.maximal_width = 290
      row.style.horizontally_stretchable = true
      row.style.vertical_align = "center"
      local space = row.add { type = "empty-widget" }
      space.style.horizontally_stretchable = true
      action(row, "show", "ssk-icon", Loc("cells-show"), nil, id)
      action(row, "edit", "utility/rename_icon", Loc("cells-edit"), nil, id)
      row.add { type = "sprite-button", style = "tool_button_red", sprite = "utility/trash",
        tooltip = Loc("cells-delete"), tags = { ssk_cell_delete_request = id } }
    end
  end
  -- The editor and the saved-cells list dock at the left edge, below the top-left
  -- buttons, so the cells stay in view. A window the player moved stays there.
  local scale, screen = player.display_scale, player.display_resolution
  local at = cells.places and cells.places[player.index]
  if at and at.x >= 0 and at.y >= 0 and at.x < screen.width - 64 * scale and at.y < screen.height - 64 * scale then
    frame.location = at
  else
    frame.location = { x = math.floor(8 * scale), y = math.floor(64 * scale) }
  end
  player.opened = frame
end

-- A click anywhere outside the saved-cells list closes it; the editor (a draft)
-- stays open until it is saved or cancelled.
function Cells.on_click_anywhere(e)
  local player = game.get_player(e.player_index)
  local window = player and player.gui.screen[Cells.NAME]
  if not window then return end
  local cells = storage.production_cells
  if cells and cells.drafts[player.index] then return end
  local element = e.element
  while element do
    if element == window then return end
    element = element.parent
  end
  Cells.close(player)
end

-- Build the complete tree in memory first. No ids or saved records are changed
-- until all names, memberships, surfaces and stop ownership pass validation.
function Cells.apply_composite(player, root)
  local cells = state()
  if root.id and cells.records[root.id] ~= root.original then player.print(Loc("cells-changed")); return false end
  if root.parent_id and cells.records[root.parent_id] ~= root.parent_original then
    player.print(Loc("cells-parent-changed")); return false
  end
  local entries = { root }
  for _, child in ipairs(root.staged or {}) do entries[#entries + 1] = child end
  local records, stop_units, buffer_units = {}, {}, {}
  for index, draft in ipairs(entries) do
    local name = (draft.name or ""):match("^%s*(.-)%s*$")
    if name == "" or #name > 120 then player.print(Loc("cells-name-required")); return false end
    local members, count = live_members(draft.members or {}, draft.surface_index)
    if count == 0 then player.print(Loc("cells-no-machines")); return false end
    local parent_index = index > 1 and draft.parent_draft
    if index > 1 and (type(parent_index) ~= "number" or parent_index < 0 or parent_index >= index - 1 or parent_index % 1 ~= 0) then
      player.print(Loc("cells-parent-changed")); return false
    end
    local parent = index > 1 and records[parent_index + 1] or nil
    if parent then
      if parent.surface_index ~= draft.surface_index then player.print(Loc("cells-wrong-surface")); return false end
      for unit in pairs(members) do
        if not parent.members[unit] then player.print(Loc("cells-outside-parent")); return false end
      end
    end
    if Rail.conflict(index == 1 and root.id or nil, draft.stops) then player.print(Loc("rail-selection-conflict")); return false end
    for unit, stop in pairs(draft.stops or {}) do
      if stop_units[unit] then player.print(Loc("rail-selection-conflict")); return false end
      stop_units[unit] = true
      for buffer in pairs(stop.buffers) do
        if buffer_units[buffer] then player.print(Loc("rail-selection-conflict")); return false end
        buffer_units[buffer] = true
      end
    end
    local locked = { inputs = {}, outputs = {} }
    for _, side in ipairs(SIDES) do
      for port in pairs(draft.ports and draft.ports[side] or {}) do
        if port_prototype(port) then locked[side][port] = true end
      end
    end
    local display = draft.display_chosen and display_key(draft.display_item) and draft.display_item
      or suggested_item(members, locked.inputs)
    local positions = positions_of(members)
    if index == 1 and root.id then
      local occupied = {}
      for _, position in pairs(positions) do occupied[position_key(position)] = true end
      for unit, position in pairs(root.vacant or {}) do
        local previous = root.original.members[unit]
        local key = position_key(position)
        if previous and not previous.valid and not occupied[key] then
          members[unit], positions[unit], occupied[key] = previous, position, true
        end
      end
      local valid, reason = Cells.valid_hierarchy(cells.records, {
        id = root.id, parent_id = root.parent_id, surface_index = root.surface_index, members = members })
      if not valid then
        if reason == "cells-outside-parent" then player.print(Loc("cells-outside-parent"))
        elseif reason == "cells-child-members" then player.print(Loc("cells-child-members"))
        else player.print(Loc("cells-parent-changed")) end
        return false
      end
    end
    local id = index == 1 and root.id or cells.next_id + index - (root.id and 2 or 1)
    records[index] = { id = id, parent_id = parent and parent.id or (index == 1 and root.parent_id or nil), name = name,
      surface_index = draft.surface_index, members = members, positions = positions, since = index == 1 and root.original and root.original.since or game.tick,
      display_item = display or false, ports = locked, stops = draft.stops }
  end
  for _, record in ipairs(records) do cells.records[record.id] = record end
  cells.next_id = cells.next_id + #records - (root.id and 1 or 0)
  cells.drafts[player.index] = nil
  Cells.reindex()
  Cells.open(player)
  return true
end

function Cells.prompt_delete(player, id, from_tab, close_origin)
  if player.force ~= game.forces.player then return end
  local cells = state()
  local record = cells.records[id]
  if not record then return end
  close_origin(player)
  clear_confirmation(player)
  cells.deletions = cells.deletions or {}
  cells.deletions[player.index] = { id = id, record = record, from_tab = from_tab }

  local window = player.gui.screen.add { type = "frame", name = Cells.DELETE_NAME, direction = "vertical" }
  local title = window.add { type = "flow", style = "frame_header_flow" }
  title.drag_target = window
  title.add { type = "label", style = "frame_title", caption = Loc("cells-delete") }
  local drag = title.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  title.add { type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = Loc("cells-cancel"), tags = { ssk_cell_delete_answer = "cancel" } }

  local panel = window.add { type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" }
  local text = panel.add { type = "label", caption = Loc("cells-delete-question", record.name) }
  text.style.single_line = false
  text.style.maximal_width = 360
  panel.add { type = "label", style = "grey_label", caption = Loc("cells-delete-machines-stay") }

  local footer = window.add { type = "flow", style = "dialog_buttons_horizontal_flow" }
  footer.add { type = "button", style = "back_button", caption = Loc("cells-cancel"),
    tags = { ssk_cell_delete_answer = "cancel" } }
  local gap = footer.add { type = "empty-widget", style = "draggable_space" }
  gap.style.horizontally_stretchable = true
  footer.add { type = "button", style = "red_confirm_button", caption = Loc("cells-delete-button"),
    tags = { ssk_cell_delete_answer = "delete" } }
  window.auto_center = true
  player.opened = window
end

function Cells.finish_delete(player, confirm)
  local cells = storage.production_cells
  local pending = cells and cells.deletions and cells.deletions[player.index]
  if not pending then return end
  clear_confirmation(player)
  if confirm and player.force == game.forces.player then
    if cells.records[pending.id] == pending.record then
      if cells.children and cells.children[pending.id] and #cells.children[pending.id] > 0 then
        player.print(Loc("cells-has-children")); return pending
      end
      cells.records[pending.id] = nil
      Sampler.purge_cell(pending.id)
      Cells.reindex()
    else
      player.print(Loc("cells-changed"))
    end
  end
  return pending
end

function Cells.on_click(player, element)
  local tag = element.tags.ssk_cell
  if not tag then return false end
  if player.force ~= game.forces.player then Cells.cancel(player); return true end
  local cells = state()
  local draft = cells.drafts[player.index]
  if tag == "close" then
    Cells.cancel(player)
  elseif tag == "list" then
    Cells.cancel(player)
    Cells.open(player)
  elseif tag == "edit" then
    local record = cells.records[element.tags.cell_id]
    if record then
      cells.drafts[player.index] = { id = record.id, name = record.name,
        surface_index = record.surface_index, members = record.members, original = record,
        parent_id = record.parent_id, parent_original = record.parent_id and cells.records[record.parent_id],
        display_item = record.display_item, display_chosen = record.display_item and true or nil,
        vacant = vacant_slots(record), ports = copy_ports(Cells.boundary(record)), stops = Rail.copy(record.stops), suggested_stops = {} }
      for unit in pairs(record.stops or {}) do cells.drafts[player.index].suggested_stops[unit] = true end
      Cells.open(player)
    end
  elseif tag == "draft_switch" and draft and draft.session then
    remember_name(player, draft)
    local session, index = draft.session, element.tags.draft_index
    local target = index == 0 and session.root or session.staged[index]
    if target then session.active = index; cells.drafts[player.index] = target; Cells.open(player) end
  elseif tag == "draft_add" and draft then
    remember_name(player, draft)
    local session = draft.session
    if not session then
      session = { root = draft, staged = {}, active = 0 }
      draft.session, draft.staged = session, session.staged
    end
    local child = { name = "", surface_index = draft.surface_index, members = {},
      parent_draft = session.active, session = session }
    session.staged[#session.staged + 1] = child
    session.active = #session.staged
    cells.drafts[player.index] = child
    Cells.on_click(player, { tags = { ssk_cell = "select" } })
  elseif tag == "forget" and draft then
    remember_name(player, draft)
    draft.vacant = nil
    Cells.open(player)
  elseif (tag == "port" or tag == "port_suggestion" or tag == "port_add") and draft then
    local side = element.tags.side
    if side ~= "inputs" and side ~= "outputs" then return true end
    draft.ports = draft.ports or copy_ports()
    if tag == "port_add" then
      Picker.open(player, "cell-" .. side)
      return true
    end
    local key = element.tags.key
    if not key then return true end
    if tag == "port" and draft.ports[side][key] then
      remember_name(player, draft)
      draft.ports[side][key] = nil
      draft.off_ports = draft.off_ports or copy_ports()
      draft.off_ports[side][key] = true
      draft.port_overrides = draft.port_overrides or {}
      draft.port_overrides[key] = true
      Cells.open(player, side, key)
    else
      Cells.pick_port(player, side, key)
    end
  elseif draft and (tag == "unlink_stop" or tag == "clear_buffers") then
    local unit = element.tags.cell_id
    local stop = draft.stops and draft.stops[unit]
    if stop then
      remember_name(player, draft)
      if tag == "unlink_stop" then draft.stops[unit] = nil else stop.buffers = {} end
      Cells.open(player)
    end
  elseif selection_modes[tag] or (draft and (tag == "pick_stops" or tag == "pick_buffers")) then
    if draft and draft.surface_index ~= player.surface.index then
      player.print(Loc("cells-wrong-surface"))
      return true
    end
    local cursor = player.cursor_stack
    if not cursor then return true end
    local buffer_stop = element.tags.cell_id
    if draft then remember_name(player, draft) end
    if cursor.valid_for_read and not player.clear_cursor() then return true end
    Cells.close(player)
    local tool = tag == "pick_stops" and Selection.stop_tool or tag == "pick_buffers" and Selection.buffer_tool or Selection.tool
    if not cursor.set_stack { name = tool } then
      Cells.open(player)
      return true
    end
    if draft then draft.selection_mode, draft.buffer_stop = tag, buffer_stop end
    sync_cursor_outlines(player)
  elseif tag == "save" and draft then
    local window = player.gui.screen[Cells.NAME]
    if not window then return true end
    local form = window.ssk_cell_panel.ssk_cell_form
    local name = form.ssk_cell_name_column.ssk_cell_name.text:match("^%s*(.-)%s*$")
    if name == "" or #name > 120 then player.print(Loc("cells-name-required")); return true end
    draft.name = name
    if draft.session then
      Cells.apply_composite(player, draft.session.root)
      return true
    end
    if draft.id and cells.records[draft.id] ~= draft.original then
      player.print(Loc("cells-changed"))
      cells.drafts[player.index] = nil
      Cells.open(player)
      return true
    end
    local members, count = live_members(draft.members, draft.surface_index)
    if count == 0 then player.print(Loc("cells-no-machines")); return true end
    if Rail.conflict(draft.id, draft.stops) then player.print(Loc("rail-selection-conflict")); return true end
    local id = draft.id or cells.next_id
    local display_item = draft.display_item
    if not (draft.display_chosen and display_key(display_item)) then
      display_item = suggested_item(members, draft.ports and draft.ports.inputs)
    end
    local positions = positions_of(members)
    local occupied = {}
    for _, position in pairs(positions) do occupied[position_key(position)] = true end
    -- Keep removed members' slots so a replacement built there rejoins the cell,
    -- unless the player chose to forget them or a member already stands there.
    local previous = draft.original and draft.original.members or {}
    for unit, position in pairs(draft.vacant or {}) do
      local key = position_key(position)
      if previous[unit] and not previous[unit].valid and not members[unit] and not occupied[key] then
        members[unit], positions[unit], occupied[key] = previous[unit], position, true
      end
    end
    local parent = draft.parent_id and cells.records[draft.parent_id]
    if draft.parent_id and (not parent or (draft.parent_original and parent ~= draft.parent_original)) then
      player.print(Loc("cells-parent-changed")); return true
    end
    local valid, reason = Cells.valid_hierarchy(cells.records,
      { id = id, parent_id = draft.parent_id, surface_index = draft.surface_index, members = members })
    if not valid then
      if reason == "cells-outside-parent" then player.print(Loc("cells-outside-parent"))
      elseif reason == "cells-child-members" then player.print(Loc("cells-child-members"))
      else player.print(Loc("cells-parent-changed")) end
      return true
    end
    -- Save the boundary the player chose.
    local locked = { inputs = {}, outputs = {} }
    for _, side in ipairs(SIDES) do
      for port in pairs(draft.ports and draft.ports[side] or {}) do
        if port_prototype(port) then locked[side][port] = true end
      end
    end
    -- Measured history continues across edits; a new cell starts measuring now.
    if not draft.id then cells.next_id = id + 1 end
    cells.records[id] = { id = id, name = name, parent_id = draft.parent_id, surface_index = draft.surface_index, members = members,
      positions = positions, since = draft.original and draft.original.since or game.tick,
      display_item = display_item or false, ports = locked, stops = draft.stops }
    cells.drafts[player.index] = nil
    Cells.reindex()
    Cells.open(player)
  end
  return true
end

function Cells.start_child(player, id)
  local cells = state()
  local parent = cells.records[id]
  if not parent or player.force ~= game.forces.player then return end
  cells.drafts[player.index] = { name = "", surface_index = parent.surface_index, members = {},
    parent_id = id, parent_original = parent, selection_mode = "select" }
  Cells.on_click(player, { tags = { ssk_cell = "select" } })
end

-- Suggestions are applied only when a stop first enters this draft.  A redraw,
-- a repeated drag, or returning to a staged layer cannot reset the player's work.
local function staged_claims(draft)
  local stops, buffers = {}, {}
  local session = draft.session
  if session then
    local function collect(other)
      if other ~= draft then
        for unit, stop in pairs(other.stops or {}) do
          stops[unit] = true
          for buffer in pairs(stop.buffers or {}) do buffers[buffer] = true end
        end
      end
    end
    collect(session.root)
    for _, other in ipairs(session.staged) do collect(other) end
  end
  return stops, buffers
end

local function suggest_stop(draft, unit, claimed, net)
  draft.suggested_stops = draft.suggested_stops or {}
  if draft.suggested_stops[unit] then return end
  draft.suggested_stops[unit] = true
  local stop = draft.stops[unit]
  local name = Rail.name(stop)
  local role = RailSuggestions.role(name, net)
  if role then stop.role = role end
  local ports = RailSuggestions.ports(name, role or stop.role, net)
  draft.ports = draft.ports or copy_ports()
  local materials = RailSuggestions.materials(name)
  for _, side in ipairs({"inputs", "outputs"}) do
    local opposite = side == "inputs" and "outputs" or "inputs"
    for key in pairs(ports[side]) do
      local untouched = not (draft.port_overrides and draft.port_overrides[key])
        and not (draft.off_ports and (draft.off_ports.inputs[key] or draft.off_ports.outputs[key]))
      if untouched and not draft.ports[opposite][key] and port_prototype(key) then
        draft.ports[opposite][key] = nil
        draft.ports[side][key] = true
      end
    end
  end
  for id, entity in pairs(BufferSuggestions.suggest(draft, unit, materials, claimed)) do
    stop.buffers[id] = entity
    claimed[id] = true
  end
end

local function reserve_selected_storage(entities, claimed)
  local reserved, physical = {}, {}
  for id in pairs(claimed) do physical[id] = true end
  for _, entity in ipairs(entities) do
    if entity.valid and entity.unit_number and (entity.type == "container" or entity.type == "logistic-container"
      or entity.type == "storage-tank") then
      reserved[entity.unit_number], physical[entity.unit_number] = true, true
    end
  end
  return reserved, physical
end

local function record_physical_buffers(draft, unit, claimed, reserved)
  for id in pairs(draft.stops[unit].buffers) do if not reserved[id] then claimed[id] = true end end
end

-- Storage included in a station drag is an explicit request to associate it.
-- Consider all selected stations together so ambiguous material matches stay free.
local function add_selected_buffers(draft, entities, claimed)
  local materials = {}
  for _, entity in ipairs(entities) do
    local unit = entity.valid and entity.unit_number
    if unit and entity.type == "train-stop" and draft.stops and draft.stops[unit] and not materials[unit] then
      materials[unit] = RailSuggestions.materials(Rail.name(draft.stops[unit]))
    end
  end
  for unit, buffers in pairs(BufferSuggestions.suggest_selected(draft, claimed, entities, materials, true)) do
    for id, entity in pairs(buffers) do draft.stops[unit].buffers[id] = entity end
  end
end

local function merge_area(a, b)
  if not a then return b end
  if not b then return a end
  local alt, arb = a.left_top or a[1], a.right_bottom or a[2]
  local blt, brb = b.left_top or b[1], b.right_bottom or b[2]
  if not (alt and arb and blt and brb) then return b end
  return {
    left_top = { x = math.min(alt.x or alt[1], blt.x or blt[1]), y = math.min(alt.y or alt[2], blt.y or blt[2]) },
    right_bottom = { x = math.max(arb.x or arb[1], brb.x or brb[1]), y = math.max(arb.y or arb[2], brb.y or brb[2]) },
  }
end

local function refresh_suggested_ports(draft, members, surface)
  local net, produced, rates, fuels, consumed = boundary_flows(members, {})
  local suggested = PortSuggestions.suggest(net, produced, consumed, rates, fuels, surface, draft.selection_area)
  if not draft.ports then
    draft.ports = copy_ports(suggested)
    for fuel in pairs(fuels) do draft.ports.outputs[fuel] = nil end
    return
  end
  if draft.id then return end
  local overrides = draft.port_overrides or {}
  local off = draft.off_ports or { inputs = {}, outputs = {} }
  local all = {}
  for _, side in ipairs(SIDES) do
    for key in pairs(draft.ports[side]) do all[key] = true end
    for key in pairs(suggested[side]) do all[key] = true end
  end
  for key in pairs(all) do
    if not overrides[key] and not off.inputs[key] and not off.outputs[key] then
      draft.ports.inputs[key] = suggested.inputs[key] and true or nil
      draft.ports.outputs[key] = suggested.outputs[key] and not fuels[key] and true or nil
    end
  end
end

function Cells.on_selected(e)
  if e.item ~= Selection.tool and e.item ~= Selection.stop_tool and e.item ~= Selection.buffer_tool then return end
  local player = game.get_player(e.player_index)
  if not player or player.force ~= game.forces.player or player.surface ~= e.surface then return end
  local cursor = player.cursor_stack
  if not (cursor and cursor.valid_for_read and cursor.name == e.item) then return end
  local cells = state()
  local draft = cells.drafts[player.index]
  local surface_index = e.surface.index
  if draft and surface_index ~= draft.surface_index then player.print(Loc("cells-wrong-surface")); return end
  if e.item ~= Selection.tool then
    if not draft then return end
    local found
    local claimed_stops, claimed_buffers = staged_claims(draft)
    local candidates = {}
    for _, entity in ipairs(e.entities) do
      if not (e.item == Selection.stop_tool and claimed_stops[entity.unit_number])
        and not (e.item == Selection.buffer_tool and claimed_buffers[entity.unit_number]) then
        candidates[#candidates + 1] = entity
      end
    end
    if e.item == Selection.stop_tool and draft.selection_mode == "pick_stops" then
      local existing = {}
      for unit in pairs(draft.stops or {}) do existing[unit] = true end
      found = Rail.select_stops(draft, candidates)
      local net
      local reserved, physical = reserve_selected_storage(candidates, claimed_buffers)
      local live, live_count = live_members(draft.members or {}, surface_index)
      for _, entity in ipairs(candidates) do
        local unit = entity.unit_number
        if live_count > 0 and unit and draft.stops[unit] and not existing[unit]
          and not (draft.suggested_stops and draft.suggested_stops[unit]) then
          net = net or RailSuggestions.net(live)
          suggest_stop(draft, unit, physical, net)
          record_physical_buffers(draft, unit, claimed_buffers, reserved)
        end
      end
      add_selected_buffers(draft, candidates, claimed_buffers)
    elseif e.item == Selection.buffer_tool and draft.selection_mode == "pick_buffers" then
      found = Rail.select_buffers(draft, draft.buffer_stop, candidates)
    end
    if not found then player.print(Loc("rail-no-selection")); return end
    draft.selection_mode, draft.buffer_stop = nil, nil
    Cells.open(player)
    cursor.clear()
    Outlines.clear(player.index, "cursor")
    return
  end
  local members, count = live_members(e.entities, surface_index)
  draft = draft or { name = "", surface_index = surface_index }
  if draft.selection_mode == "remove" then
    local remaining = live_members(draft.members, surface_index)
    local removed = false
    for id in pairs(members) do
      if remaining[id] then
        remaining[id] = nil
        removed = true
      end
    end
    if not removed then player.print(Loc("cells-no-members-in-area")); return end
    members = remaining
  elseif count == 0 then
    player.print(Loc("cells-no-machines"))
    return
  elseif draft.selection_mode == "add" then
    local merged = live_members(draft.members, surface_index)
    for id, entity in pairs(members) do merged[id] = entity end
    members = merged
  else
    draft.vacant = nil -- replacing the selection starts from the dragged machines only
  end
  if draft.session and draft ~= draft.session.root then
    local parent_index = draft.parent_draft
    local parent = parent_index == 0 and draft.session.root or draft.session.staged[parent_index]
    if not parent or parent.surface_index ~= surface_index then player.print(Loc("cells-parent-changed")); return end
    for unit in pairs(members) do
      if not parent.members[unit] then player.print(Loc("cells-outside-parent")); return end
    end
  end
  if draft.parent_id then
    local parent = cells.records[draft.parent_id]
    if not parent or (draft.parent_original and draft.parent_original ~= parent) then
      player.print(Loc("cells-parent-changed")); return
    end
    for unit in pairs(members) do
      if not parent.members[unit] then player.print(Loc("cells-outside-parent")); return end
    end
  end
  local first_selection = not draft.id and not draft.initial_selection_completed
  local mode = draft.selection_mode
  if mode == "add" then
    draft.selection_area = merge_area(draft.selection_area, e.area)
  elseif mode ~= "remove" then
    draft.selection_area = e.area
  end
  draft.members, draft.selection_mode = members, nil
  if first_selection then
    draft.initial_selection_completed = true
    local claimed_stops = staged_claims(draft)
    local stops = {}
    for _, entity in ipairs(e.entities) do
      if entity.valid and entity.unit_number and not claimed_stops[entity.unit_number] then stops[#stops + 1] = entity end
    end
    table.sort(stops, function(a, b) return a.unit_number < b.unit_number end)
    Rail.select_stops(draft, stops)
  end
  if next(members) then
    refresh_suggested_ports(draft, members, e.surface)
    local _, claimed = staged_claims(draft)
    local reserved, physical = reserve_selected_storage(first_selection and e.entities or {}, claimed)
    local net, units = nil, {}
    for unit in pairs(draft.stops or {}) do units[#units + 1] = unit end
    table.sort(units)
    for _, unit in ipairs(units) do
      if not (draft.suggested_stops and draft.suggested_stops[unit]) then
        net = net or RailSuggestions.net(members)
        suggest_stop(draft, unit, physical, net)
        record_physical_buffers(draft, unit, claimed, reserved)
      end
    end
    if first_selection then add_selected_buffers(draft, e.entities, claimed) end
  end
  if not draft.id and (draft.name == "" or draft.name == draft.suggested_name) then
    local primary = suggested_item(members, draft.ports and draft.ports.inputs)
    local key = display_key(primary)
    local proto = key and display_prototype(key)
    draft.suggested_name = proto and proto.name:gsub("-", " "):gsub("^%l", string.upper) or ""
    draft.name = draft.suggested_name
    draft.translation = proto and player.request_translation(proto.localised_name)
  end
  cells.drafts[player.index] = draft
  Cells.open(player)
  cursor.clear()
  Outlines.clear(player.index, "cursor")
end

function Cells.on_string_translated(e)
  local cells = storage.production_cells
  local draft = cells and cells.drafts[e.player_index]
  if not draft or draft.translation ~= e.id then return end
  draft.translation = nil
  if not e.translated or #e.result > 120 then return end
  local window = game.get_player(e.player_index).gui.screen[Cells.NAME]
  local field = window and window.ssk_cell_panel.ssk_cell_form.ssk_cell_name_column.ssk_cell_name
  if field and field.text == draft.suggested_name then
    field.text = e.result
    draft.suggested_name, draft.name = e.result, e.result
  end
end

function Cells.open_display_picker(player)
  local cells = storage.production_cells
  local draft = cells and cells.drafts[player.index]
  if not (draft and player.gui.screen[Cells.NAME]) then return end
  Picker.open(player, "cell", display_key(draft.display_item))
end

function Cells.pick_display_item(player, key)
  local cells = storage.production_cells
  local draft = cells and cells.drafts[player.index]
  local window = player.gui.screen[Cells.NAME]
  if not (window and draft and display_prototype(key)) then return end
  -- Items keep the plain name older cells use; fluids and recipes keep their typed key.
  draft.display_item = key:sub(1, 5) == "item/" and key:sub(6) or key
  draft.display_chosen = true
  local button = window.ssk_cell_panel.ssk_cell_form.ssk_cell_item_column.ssk_cell_display_item
  Picker.update_button(button, key, "cell")
end

-- Adds an item or fluid the player chose to a boundary side.
function Cells.pick_port(player, side, key)
  local cells = storage.production_cells
  local draft = cells and cells.drafts[player.index]
  if not (draft and (side == "inputs" or side == "outputs") and port_prototype(key)) then return end
  remember_name(player, draft)
  draft.ports = draft.ports or copy_ports()
  draft.ports[side][key] = true
  draft.port_overrides = draft.port_overrides or {}
  draft.port_overrides[key] = true
  -- An item is either an input or an output of the cell.
  draft.ports[side == "inputs" and "outputs" or "inputs"][key] = nil
  Cells.open(player, side, key)
end

function Cells.on_cursor_changed(player)
  sync_cursor_outlines(player)
  if player.gui.screen[Cells.NAME] then return end
  if holding_tool(player) then return end
  local cells = storage.production_cells
  local draft = cells and cells.drafts[player.index]
  if draft and draft.selection_mode then
    draft.selection_mode, draft.buffer_stop = nil, nil
    Cells.open(player)
  end
end

-- The saved-cells list's surface drop-down.
function Cells.on_list_surface(player, element)
  local cells = state()
  local index = element.selected_index
  cells.list_surfaces = cells.list_surfaces or {}
  cells.list_surfaces[player.index] = index > 1 and element.tags.surfaces[index - 1] or nil
  Cells.open(player)
end

function Cells.on_player_removed(index)
  Outlines.clear(index)
  local cells = storage.production_cells
  if not cells then return end
  cells.drafts[index] = nil
  if cells.deletions then cells.deletions[index] = nil end
  if cells.places then cells.places[index] = nil end
  if cells.list_surfaces then cells.list_surfaces[index] = nil end
end

function Cells.on_surface_deleted(index)
  if not storage.production_cells then return end
  -- A spaceship's old surface is deleted after the move; let its cells follow first.
  Cells.resolve_clones(true)
  local cells = state()
  for id, record in pairs(cells.records) do
    if record.surface_index == index then
      cells.records[id] = nil
      Sampler.purge_cell(id)
    end
  end
  Cells.reindex()
  for player_index, draft in pairs(cells.drafts) do
    if draft.surface_index == index then
      local player = game.get_player(player_index)
      if player then Cells.cancel(player) else cells.drafts[player_index] = nil end
    end
  end
end

return Cells
