-- Suggest storage from exact train links or explicit, unambiguous selections.
-- This is a snapshot: it never changes a draft or claims an entity.
local Suggestions = {}
-- Long remote modded arms outside this search remain manual.
local INSERTER_PADDING = 8

local function eligible(entity, surface)
  return entity and entity.valid and entity.unit_number and entity.surface.index == surface
    and entity.force == game.forces.player
end

local function material_info(entity)
  local name, kind, ambiguous, known_empty = nil, 'item', false, false
  if entity.type == 'storage-tank' then
    kind, known_empty = 'fluid', true
    for fluid, amount in pairs(entity.get_fluid_contents()) do
      if amount > 0 then
        known_empty = false
        if name and name ~= fluid then ambiguous = true end
        name = fluid
      end
    end
  else
    local inventory = entity.get_inventory(defines.inventory.chest)
    if inventory then
      known_empty = true
      for _, stack in ipairs(inventory.get_contents()) do
        if stack.count > 0 then
          known_empty = false
          if name and name ~= stack.name then ambiguous = true end
          name = stack.name
        end
      end
      if not name and entity.type == 'logistic-container' and entity.prototype.logistic_mode == 'storage' then
        local filter = entity.storage_filter
        name = filter and filter.name and filter.name.name
      end
    end
  end
  return {name = name, kind = kind, ambiguous = ambiguous, empty = known_empty}
end

-- claimed includes buffers in other staged cells. Existing and saved allocations
-- are always excluded, even if they belong to the same cell or stop.
function Suggestions.suggest(draft, unit, materials, claimed, allowed, info)
  local result, stop = {}, draft.stops and draft.stops[unit]
  local station = stop and stop.entity
  if not eligible(station, draft.surface_index) or station.type ~= 'train-stop' then return result end
  local train = station.get_stopped_train()
  if not train or not train.valid then return result end
  local wagons, areas = {}, {}
  for _, carriage in ipairs(train.carriages) do
    if eligible(carriage, draft.surface_index) and carriage.type == 'cargo-wagon' then
      wagons[carriage.unit_number] = true
      local box = carriage.bounding_box
      if box then
        areas[#areas + 1] = {{box.left_top.x - INSERTER_PADDING, box.left_top.y - INSERTER_PADDING},
          {box.right_bottom.x + INSERTER_PADDING, box.right_bottom.y + INSERTER_PADDING}}
      end
    end
  end
  if not next(wagons) then return result end
  local occupied = {}
  for _, candidate in pairs(draft.stops) do
    for id in pairs(candidate.buffers or {}) do occupied[id] = true end
  end
  local saved = storage.cell_rail and storage.cell_rail.buffers or {}
  local seen = {}
  for _, area in ipairs(areas) do
    for _, inserter in ipairs(station.surface.find_entities_filtered {area = area, type = 'inserter', force = game.forces.player}) do
      if eligible(inserter, draft.surface_index) and not seen[inserter.unit_number] then
        seen[inserter.unit_number] = true
        local pickup, drop = inserter.pickup_target, inserter.drop_target
        local chest
        if pickup and pickup.valid and wagons[pickup.unit_number] then chest = drop
        elseif drop and drop.valid and wagons[drop.unit_number] then chest = pickup end
        if eligible(chest, draft.surface_index)
          and (chest.type == 'container' or chest.type == 'logistic-container')
          and not occupied[chest.unit_number] and not saved[chest.unit_number]
          and not (claimed and claimed[chest.unit_number]) and (not allowed or allowed[chest.unit_number]) then
          local material = info and info[chest.unit_number] or material_info(chest)
          if allowed or (material.name and not material.ambiguous and (materials or {})['item/' .. material.name]) then
            result[chest.unit_number] = chest
          end
        end
      end
    end
  end
  return result
end


-- Explicitly selected storage can also be assigned when its named contents or
-- storage filter identify exactly one of the stops in that selection. A direct
-- stopped-wagon link is stronger than a material shared by several stops.
function Suggestions.suggest_selected(draft, claimed, entities, stop_materials, allow_empty_pair)
  local result, candidates, info, stop_count, storage_count = {}, {}, {}, 0, 0
  for _ in pairs(stop_materials or {}) do stop_count = stop_count + 1 end
  if stop_count == 0 then return result end
  local occupied, saved = {}, storage.cell_rail and storage.cell_rail.buffers or {}
  for _, stop in pairs(draft.stops or {}) do
    for id in pairs(stop.buffers or {}) do occupied[id] = true end
  end
  for _, entity in ipairs(entities or {}) do
    if eligible(entity, draft.surface_index) and (entity.type == 'container'
      or entity.type == 'logistic-container' or entity.type == 'storage-tank') then
      storage_count = storage_count + 1
      local id = entity.unit_number
      if not occupied[id] and not saved[id] and not (claimed and claimed[id]) and not candidates[id] then
        candidates[id], info[id] = entity, material_info(entity)
      end
    end
  end
  local physical = {}
  for stop_id, ports in pairs(stop_materials) do
    for id in pairs(Suggestions.suggest(draft, stop_id, ports, claimed, candidates, info)) do
      if physical[id] == nil then physical[id] = stop_id else physical[id] = false end
    end
  end
  local function assign(stop_id, id, entity)
    result[stop_id] = result[stop_id] or {}
    result[stop_id][id] = entity
  end
  for id, entity in pairs(candidates) do
    local material = info[id]
    if physical[id] then
      assign(physical[id], id, entity)
    elseif physical[id] == nil then
      if material.name and not material.ambiguous then
        local key, owner, matches = material.kind .. '/' .. material.name, nil, 0
        for stop_id, ports in pairs(stop_materials) do
          if ports[key] then owner, matches = stop_id, matches + 1 end
        end
        if matches == 1 then assign(owner, id, entity) end
      elseif not material.name and not material.ambiguous and material.empty
        and allow_empty_pair and stop_count == 1 and storage_count == 1 then
        for stop_id, ports in pairs(stop_materials) do
          for key in pairs(ports) do
            if key:sub(1, #material.kind + 1) == material.kind .. '/' then
              assign(stop_id, id, entity)
              break
            end
          end
        end
      end
    end
  end
  return result
end

return Suggestions
