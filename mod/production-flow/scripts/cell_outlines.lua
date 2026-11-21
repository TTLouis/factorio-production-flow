-- Outlines cell machines, linked train stops and associated buffers for one player.
-- Two independent slots:
--   map   - the Cells tab's Map, kept after Jump while the player stays in remote view;
--   draft - the entities selected while creating or editing a cell, kept while
--           the player drags with the selection tool.
-- Each cell has its own colour; missing entities are outlined in red.
-- Paired "game" and "chart" render objects keep highlights visible when zoomed out.
local Palette = require("shared.palette")

local O = {}
local MISSING = { r = 0.95, g = 0.2, b = 0.15 }
local FILL = 0.18
local CHART_FILL = 0.45

local function slots(player_index, create)
  if create then storage.cell_outlines = storage.cell_outlines or {} end
  local all = storage.cell_outlines
  if not all then return end
  if create then all[player_index] = all[player_index] or {} end
  return all[player_index]
end

function O.color(id)
  local c = Palette.colors[((id or 1) - 1) % Palette.NCAT + 1]
  return { r = c[1] / 255, g = c[2] / 255, b = c[3] / 255 }
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

-- What the outlines depend on: the cells, their names and surfaces, which
-- members are present, and their linked stops and storage buffers.
local function signature(entries)
  local parts = {}
  for _, entry in ipairs(entries) do
    local record = entry.record
    parts[#parts + 1] = tostring(entry.id) .. "@" .. record.surface_index .. "=" .. tostring(record.name)
    for _, unit in ipairs(sorted_keys(record.positions)) do
      local entity = record.members[unit]
      parts[#parts + 1] = unit .. ((entity and entity.valid) and "+" or "-")
    end
    for _, unit in ipairs(sorted_keys(record.stops)) do
      local stop = record.stops[unit]
      local live = stop and stop.entity and stop.entity.valid
      parts[#parts + 1] = "stop:" .. unit .. (live and "+" or "-")
      for _, buf_unit in ipairs(sorted_keys(stop and stop.buffers)) do
        local buf = stop.buffers[buf_unit]
        parts[#parts + 1] = "buf:" .. buf_unit .. ((buf and buf.valid) and "+" or "-")
      end
    end
  end
  return table.concat(parts, ",")
end

local function box_of(entity, spot)
  local box = entity and entity.valid and entity.selection_box
  if box then return box.left_top, box.right_bottom end
  if not spot then return nil, nil end
  local w = spot.w or (entity and entity.valid and entity.tile_width) or 3
  local h = spot.h or (entity and entity.valid and entity.tile_height) or 3
  return { x = spot.x - w / 2, y = spot.y - h / 2 }, { x = spot.x + w / 2, y = spot.y + h / 2 }
end

local function draw_box(surface, player, lt, rb, color, fill, chart_fill, width, live, objects)
  local border = live and color or MISSING
  if live then
    objects[#objects + 1] = rendering.draw_rectangle { surface = surface, left_top = lt, right_bottom = rb,
      color = fill, filled = true, players = { player }, render_mode = "game" }
    objects[#objects + 1] = rendering.draw_rectangle { surface = surface, left_top = lt, right_bottom = rb,
      color = chart_fill, filled = true, players = { player }, render_mode = "chart" }
  end
  objects[#objects + 1] = rendering.draw_rectangle { surface = surface, left_top = lt, right_bottom = rb,
    color = border, width = width, filled = false, players = { player }, render_mode = "game" }
  objects[#objects + 1] = rendering.draw_rectangle { surface = surface, left_top = lt, right_bottom = rb,
    color = border, width = 2, filled = false, players = { player }, render_mode = "chart" }
end

local function draw(player, entry, objects)
  local record = entry.record
  local surface = game.surfaces[record.surface_index]
  if not surface then return end
  local color = O.color(entry.id)
  local fill = { r = color.r * FILL, g = color.g * FILL, b = color.b * FILL, a = FILL }
  local chart_fill = { r = color.r * CHART_FILL, g = color.g * CHART_FILL, b = color.b * CHART_FILL, a = CHART_FILL }
  local top, left, right
  for _, unit in ipairs(sorted_keys(record.positions)) do
    local entity = record.members[unit]
    local live = entity and entity.valid
    local lt, rb = box_of(entity, record.positions[unit])
    if lt and rb then
      draw_box(surface, player, lt, rb, color, fill, chart_fill, 4, live, objects)
      top = math.min(top or lt.y, lt.y)
      left, right = math.min(left or lt.x, lt.x), math.max(right or rb.x, rb.x)
    end
  end
  for _, unit in ipairs(sorted_keys(record.stops)) do
    local stop = record.stops[unit]
    local entity = stop and stop.entity
    if entity and entity.valid then
      local lt, rb = box_of(entity)
      if lt and rb then
        draw_box(surface, player, lt, rb, color, fill, chart_fill, 4, true, objects)
      end
    end
    for _, buf_unit in ipairs(sorted_keys(stop and stop.buffers)) do
      local buf = stop.buffers[buf_unit]
      if buf and buf.valid then
        local lt, rb = box_of(buf)
        if lt and rb then
          draw_box(surface, player, lt, rb, color, fill, chart_fill, 2.5, true, objects)
        end
      end
    end
  end
  if top and record.name and record.name ~= "" then
    local cx = (left + right) / 2
    objects[#objects + 1] = rendering.draw_text { surface = surface, text = record.name,
      target = { x = cx, y = top - 0.25 }, color = color, scale = 1.5, scale_with_zoom = true,
      alignment = "center", vertical_alignment = "bottom", players = { player }, render_mode = "game" }
    objects[#objects + 1] = rendering.draw_text { surface = surface, text = record.name,
      target = { x = cx, y = top - 0.5 }, color = color, scale = 1.5, scale_with_zoom = false,
      alignment = "center", vertical_alignment = "bottom", players = { player }, render_mode = "chart" }
  end
end

-- Clears one slot, or every slot when none is named.
function O.clear(player_index, slot)
  local mine = slots(player_index)
  if not mine then return end
  for name, shown in pairs(mine) do
    if not slot or name == slot then
      for _, object in ipairs(shown.objects) do
        if object.valid then object.destroy() end
      end
      mine[name] = nil
    end
  end
  if not next(mine) then storage.cell_outlines[player_index] = nil end
end

function O.current(player_index, slot)
  local mine = slots(player_index)
  return mine and mine[slot or "map"]
end

-- entries: { { id = cell id (colour), record = { surface_index, name, members, positions, stops } } }
local function show(player, slot, entries)
  local sig = signature(entries)
  local shown = O.current(player.index, slot)
  if shown and shown.sig == sig then return shown end
  O.clear(player.index, slot)
  shown = { sig = sig, objects = {} }
  for _, entry in ipairs(entries) do draw(player, entry, shown.objects) end
  slots(player.index, true)[slot] = shown
  return shown
end

-- Outlines the given saved cells on the Map.
function O.show(player, records, ids)
  local entries = {}
  for _, id in ipairs(ids) do entries[#entries + 1] = { id = id, record = records[id] } end
  local shown = show(player, "map", entries)
  shown.remote = nil
  return shown
end

-- Outlines every saved cell on the player's current surface while a selection
-- tool is held in the cursor.
function O.show_surface(player, records, surface_index, exclude_id)
  local ids, entries = {}, {}
  for id, record in pairs(records or {}) do
    if record.surface_index == surface_index and id ~= exclude_id then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do entries[#entries + 1] = { id = id, record = records[id] } end
  if #entries == 0 then O.clear(player.index, "cursor"); return nil end
  return show(player, "cursor", entries)
end

-- Outlines the machines, stops and buffers of a cell being created or edited.
function O.show_draft(player, draft, next_id)
  local positions = {}
  for unit, entity in pairs(draft.members or {}) do
    if entity.valid then
      positions[unit] = { x = entity.position.x, y = entity.position.y, w = entity.tile_width, h = entity.tile_height }
    end
  end
  for unit, spot in pairs(draft.vacant or {}) do positions[unit] = spot end
  return show(player, "draft", { { id = draft.id or next_id, record = { surface_index = draft.surface_index,
    name = draft.name, members = draft.members or {}, positions = positions, stops = draft.stops } } })
end

-- Keeps the Map's outlines when the window closes for a jump to remote view.
function O.hold(player_index)
  local shown = O.current(player_index, "map")
  if shown then shown.remote = true end
end

function O.on_window_closed(player_index)
  local shown = O.current(player_index, "map")
  if shown and not shown.remote then O.clear(player_index, "map") end
end

function O.on_controller_changed(e)
  local shown = O.current(e.player_index, "map")
  if shown and shown.remote and e.old_type == defines.controllers.remote then O.clear(e.player_index, "map") end
end

return O
