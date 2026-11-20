local Loc = require("scripts.locale")
local Selection = require("shared.cell_selection")
local Sampler = require("scripts.sampler")
local Picker = require("scripts.material_picker")
local Su = require("scripts.surfaces")

local Cells = { NAME = "ssk_cells", DELETE_NAME = "ssk_cell_delete" }
local selection_prompts = {
  select = Loc("cells-drag"),
  add = Loc("cells-add-drag"),
  remove = Loc("cells-remove-drag"),
}
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

local function positions_of(members)
  local positions = {}
  for unit, entity in pairs(members) do
    if entity.valid then positions[unit] = { x = entity.position.x, y = entity.position.y } end
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
  local slots, units = {}, {}
  local ids = {}
  for id in pairs(cells.records) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local record = cells.records[id]
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
  cells.slots = slots
  storage.cell_units = next(units) and units or nil
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
      record.positions[unit] = { x = entity.position.x, y = entity.position.y }
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
    if record then
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
          positions[copy.unit_number] = { x = copy.position.x, y = copy.position.y }
        end
        record.members, record.positions, record.surface_index = members, positions, surface
        changed = true
      end
    end
    if not waiting then pending[id] = nil end
  end
  if not next(pending) then cells.clones = nil end
  if changed then Cells.reindex() end
end

-- Rank by configured production capacity; activity or idle time does not rename a cell.
local function final_items(members)
  local recipes = storage.graph and storage.graph.recipes
  if not recipes then return {} end
  local consumed, output = {}, {}
  local ids = {}
  for id in pairs(members) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local machine = members[id]
    local recipe_name, force_recipe = Sampler.current_recipe(machine)
    local recipe = recipes[recipe_name]
    if recipe and recipe.energy > 0 then
      for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.amount > 0 then consumed[ingredient.key] = true end
      end
      local crafts = machine.crafting_speed / recipe.energy
      local bonus = Sampler.craft_productivity(machine, recipe_name, force_recipe, recipe)
      for _, product in ipairs(recipe.products) do
        if product.key:sub(1, 5) == "item/" then
          output[product.key] = (output[product.key] or 0) + crafts * (product.amount + bonus * product.prod)
        end
      end
    end
  end
  local names = {}
  for key, rate in pairs(output) do
    if not consumed[key] and rate > 0 and prototypes.item[key:sub(6)] then
      names[#names + 1] = key
    end
  end
  table.sort(names, function(a, b)
    if output[a] ~= output[b] then return output[a] > output[b] end
    return a < b
  end)
  for i, key in ipairs(names) do names[i] = key:sub(6) end
  return names
end

-- Boundary suggestions at configured full speed: net consumption is an input,
-- net production an output. Players remove the ones that do not really cross
-- the cell boundary; the rest are locked into the saved cell.
local SIDES = { "inputs", "outputs" }
Cells.SIDES = SIDES

function Cells.suggest_ports(members)
  local recipes = storage.graph and storage.graph.recipes
  local net = {}
  if recipes then
    local ids = {}
    for id in pairs(members) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local machine = members[id]
      local recipe_name, force_recipe = Sampler.current_recipe(machine)
      local recipe = recipes[recipe_name]
      if recipe and recipe.energy > 0 then
        local crafts = machine.crafting_speed / recipe.energy
        local bonus = Sampler.craft_productivity(machine, recipe_name, force_recipe, recipe)
        for _, ingredient in ipairs(recipe.ingredients) do
          net[ingredient.key] = (net[ingredient.key] or 0) - crafts * ingredient.amount
        end
        for _, product in ipairs(recipe.products) do
          net[product.key] = (net[product.key] or 0) + crafts * (product.amount + bonus * product.prod)
        end
      end
    end
  end
  local ports = { inputs = {}, outputs = {} }
  for key, amount in pairs(net) do
    if amount < -1e-9 then ports.inputs[#ports.inputs + 1] = key
    elseif amount > 1e-9 then ports.outputs[#ports.outputs + 1] = key end
  end
  for _, side in ipairs(SIDES) do
    table.sort(ports[side], function(a, b)
      local x, y = math.abs(net[a]), math.abs(net[b])
      if x ~= y then return x > y end
      return a < b
    end)
  end
  return ports
end

local function copy_excluded(excluded)
  local out = { inputs = {}, outputs = {} }
  for _, side in ipairs(SIDES) do
    for key in pairs(excluded and excluded[side] or {}) do out[side][key] = true end
  end
  return out
end

local function port_prototype(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  return kind == "item" and prototypes.item[name] or kind == "fluid" and prototypes.fluid[name] or nil
end

local function remember_name(player, draft)
  local window = player.gui.screen[Cells.NAME]
  local form = window and window.ssk_cell_panel.ssk_cell_form
  if form then draft.name = form.ssk_cell_name_column.ssk_cell_name.text end
end

function Cells.members(record)
  return live_members(record.members, record.surface_index)
end

function Cells.display_item(record, members)
  if record.display_item ~= nil then
    return record.display_item and prototypes.item[record.display_item] and record.display_item or nil
  end
  -- Cells saved before the picker was added use the first eligible item.
  return final_items(members)[1]
end

function Cells.close(player)
  local picker = player.gui.screen.ssk_material_picker
  if picker and picker.tags.target == "cell" then Picker.close(player) end
  local window = player.gui.screen[Cells.NAME]
  if window then window.destroy() end
end

local function clear_confirmation(player)
  local cells = storage.production_cells
  if cells and cells.deletions then cells.deletions[player.index] = nil end
  local confirmation = player.gui.screen[Cells.DELETE_NAME]
  if confirmation then confirmation.destroy() end
end

function Cells.cancel(player)
  clear_confirmation(player)
  if storage.production_cells then state().drafts[player.index] = nil end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.name == Selection.tool then cursor.clear() end
  Cells.close(player)
end

local function action(parent, name, sprite, tooltip, style, id)
  return parent.add { type = "sprite-button", sprite = sprite, style = style or "tool_button",
    tooltip = tooltip, tags = { ssk_cell = name, cell_id = id } }
end

function Cells.open(player)
  Cells.close(player)
  if player.force ~= game.forces.player then return end
  local cells = state()
  local draft = cells.drafts[player.index]
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

    local options = final_items(members)
    local allowed = {}
    for _, name in ipairs(options) do allowed["item/" .. name] = true end
    if not draft.display_item or not allowed["item/" .. draft.display_item] then draft.display_item = options[1] end
    draft.display_options = allowed
    local item_column = form.add { type = "flow", name = "ssk_cell_item_column", direction = "vertical" }
    item_column.add { type = "label", caption = Loc("cells-display-item") }
    local key = draft.display_item and "item/" .. draft.display_item
    local picker = Picker.button(item_column, key, "cell", "ssk_cell_display_item")
    picker.enabled = key ~= nil
    if not key then picker.tooltip = Loc("cells-no-display-item") end

    -- Locked boundary: suggested from the recipes; clicking an item removes it.
    draft.excluded = draft.excluded or copy_excluded()
    local suggested = Cells.suggest_ports(members)
    local ports = panel.add { type = "flow", name = "ssk_cell_ports", direction = "vertical" }
    ports.style.left_padding, ports.style.right_padding, ports.style.bottom_padding = 8, 8, 8
    ports.style.vertical_spacing = 4
    ports.add { type = "label", style = "caption_label", caption = Loc("cells-ports"), tooltip = Loc("cells-ports-tip") }
    for _, side in ipairs(SIDES) do
      local row = ports.add { type = "flow", name = "ssk_cell_" .. side, direction = "horizontal" }
      row.style.vertical_align = "center"
      row.style.horizontally_stretchable = true
      local label = row.add { type = "label", caption = Loc(side == "inputs" and "cells-inputs" or "cells-outputs") }
      label.style.width = 96
      local kept, hidden = {}, 0
      for _, port in ipairs(suggested[side]) do
        if draft.excluded[side][port] then hidden = hidden + 1 else kept[#kept + 1] = port end
      end
      if #kept > 0 then
        local slots = row.add { type = "frame", style = "slot_button_deep_frame" }
        local grid = slots.add { type = "table", name = "ssk_cell_port_grid", style = "filter_slot_table", column_count = 6 }
        for _, port in ipairs(kept) do
          local proto = port_prototype(port)
          grid.add { type = "sprite-button", style = "slot_button", sprite = port,
            tooltip = { "", proto and proto.localised_name or port, "\n", Loc("cells-port-remove") },
            tags = { ssk_cell = "port", side = side, key = port } }
        end
      else
        row.add { type = "label", style = "grey_label", caption = Loc("cells-ports-none") }
      end
      local gap = row.add { type = "empty-widget" }
      gap.style.horizontally_stretchable = true
      if hidden > 0 then
        row.add { type = "sprite-button", style = "tool_button", sprite = "utility/reset",
          tooltip = Loc("cells-ports-restore", hidden), tags = { ssk_cell = "ports_reset", side = side } }
      end
    end

    local footer = frame.add { type = "flow", style = "dialog_buttons_horizontal_flow" }
    footer.add { type = "button", style = "back_button", caption = Loc("cells-cancel"), tags = { ssk_cell = "list" } }
    local gap = footer.add { type = "empty-widget", style = "draggable_space" }
    gap.style.horizontally_stretchable = true
    footer.add { type = "button", style = "confirm_button", caption = Loc("cells-save"), tags = { ssk_cell = "save" } }
  else
    bar.add { type = "label", style = "subheader_caption_label", caption = Loc("cells-saved") }
    local gap = bar.add { type = "empty-widget" }
    gap.style.horizontally_stretchable = true
    action(bar, "select", "utility/add", Loc("cells-new"))
    local rows = panel.add { type = "scroll-pane", style = "naked_scroll_pane", direction = "vertical", horizontal_scroll_policy = "never" }
    rows.style.maximal_height = 350
    rows.style.padding = 8
    rows.style.horizontally_stretchable = true
    local ids = {}
    for id in pairs(cells.records) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then rows.add { type = "label", style = "grey_label", caption = Loc("cells-empty") } end
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
  if draft then
    frame.auto_center = true
  else
    -- The saved-cells list docks at the left edge, below the top-left buttons.
    local scale = player.display_scale
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
        display_item = record.display_item, vacant = vacant_slots(record),
        excluded = copy_excluded(record.excluded) }
      Cells.open(player)
    end
  elseif tag == "forget" and draft then
    remember_name(player, draft)
    draft.vacant = nil
    Cells.open(player)
  elseif (tag == "port" or tag == "ports_reset") and draft then
    local side = element.tags.side
    if side ~= "inputs" and side ~= "outputs" then return true end
    remember_name(player, draft)
    draft.excluded = draft.excluded or copy_excluded()
    if tag == "port" then
      draft.excluded[side][element.tags.key] = true
    else
      draft.excluded[side] = {}
    end
    Cells.open(player)
  elseif selection_prompts[tag] then
    if draft and draft.surface_index ~= player.surface.index then
      player.print(Loc("cells-wrong-surface"))
      return true
    end
    local cursor = player.cursor_stack
    if not cursor then return true end
    local window = player.gui.screen[Cells.NAME]
    if draft and window then
      local form = window.ssk_cell_panel.ssk_cell_form
      draft.name = form.ssk_cell_name_column.ssk_cell_name.text
    end
    if cursor.valid_for_read and not player.clear_cursor() then return true end
    Cells.close(player)
    if not cursor.set_stack { name = Selection.tool } then
      Cells.open(player)
      return true
    end
    if draft then draft.selection_mode = tag end
    player.print(selection_prompts[tag])
  elseif tag == "save" and draft then
    local window = player.gui.screen[Cells.NAME]
    if not window then return true end
    local form = window.ssk_cell_panel.ssk_cell_form
    local name = form.ssk_cell_name_column.ssk_cell_name.text:match("^%s*(.-)%s*$")
    if name == "" or #name > 120 then player.print(Loc("cells-name-required")); return true end
    if draft.id and cells.records[draft.id] ~= draft.original then
      player.print(Loc("cells-changed"))
      cells.drafts[player.index] = nil
      Cells.open(player)
      return true
    end
    local members, count = live_members(draft.members, draft.surface_index)
    if count == 0 then player.print(Loc("cells-no-machines")); return true end
    local id = draft.id or cells.next_id
    if not draft.id then cells.next_id = id + 1 end
    local display_item = draft.display_item
    local options = final_items(members)
    local still_available = false
    for _, option in ipairs(options) do
      if option == display_item then still_available = true; break end
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
    -- Lock the boundary the player kept; exclusions are remembered for later edits.
    local excluded = copy_excluded(draft.excluded)
    local suggested = Cells.suggest_ports(members)
    local locked = { inputs = {}, outputs = {} }
    for _, side in ipairs(SIDES) do
      for _, port in ipairs(suggested[side]) do
        if not excluded[side][port] then locked[side][port] = true end
      end
    end
    -- Measured history continues across edits; a new cell starts measuring now.
    cells.records[id] = { id = id, name = name, surface_index = draft.surface_index, members = members,
      positions = positions, since = draft.original and draft.original.since or game.tick,
      display_item = (still_available and display_item) or options[1] or false,
      ports = locked, excluded = excluded }
    cells.drafts[player.index] = nil
    Cells.reindex()
    Cells.open(player)
  end
  return true
end

function Cells.on_selected(e)
  if e.item ~= Selection.tool then return end
  local player = game.get_player(e.player_index)
  if not player or player.force ~= game.forces.player or player.surface ~= e.surface then return end
  local cursor = player.cursor_stack
  if not (cursor and cursor.valid_for_read and cursor.name == Selection.tool) then return end
  local cells = state()
  local draft = cells.drafts[player.index]
  local surface_index = e.surface.index
  if draft and surface_index ~= draft.surface_index then player.print(Loc("cells-wrong-surface")); return end
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
  draft.members, draft.selection_mode = members, nil
  if not draft.id and (draft.name == "" or draft.name == draft.suggested_name) then
    local primary = final_items(members)[1]
    local item = primary and prototypes.item[primary]
    draft.suggested_name = item and item.name:gsub("-", " "):gsub("^%l", string.upper) or ""
    draft.name = draft.suggested_name
    draft.translation = item and player.request_translation(item.localised_name)
  end
  cells.drafts[player.index] = draft
  Cells.open(player)
  cursor.clear()
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
  if not (draft and draft.display_item and player.gui.screen[Cells.NAME]) then return end
  Picker.open(player, "cell", "item/" .. draft.display_item, draft.display_options)
end

function Cells.pick_display_item(player, key)
  local cells = storage.production_cells
  local draft = cells and cells.drafts[player.index]
  local window = player.gui.screen[Cells.NAME]
  if not (window and draft and draft.display_options[key]) then return end
  draft.display_item = key:sub(6)
  local button = window.ssk_cell_panel.ssk_cell_form.ssk_cell_item_column.ssk_cell_display_item
  Picker.update_button(button, key, "cell")
end

function Cells.on_cursor_changed(player)
  if player.gui.screen[Cells.NAME] then return end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read and cursor.name == Selection.tool then return end
  local cells = storage.production_cells
  local draft = cells and cells.drafts[player.index]
  if draft and draft.selection_mode then
    draft.selection_mode = nil
    Cells.open(player)
  end
end

function Cells.on_player_removed(index)
  local cells = storage.production_cells
  if not cells then return end
  cells.drafts[index] = nil
  if cells.deletions then cells.deletions[index] = nil end
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
