-- Station visits belong to physical stops. Train schedules and reservations
-- describe current game state and are never used to infer a fixed rail route.
local Rail = {}
local RETAIN = 2048
local DEPARTURE_DISTANCE_SQUARED = 4
local TYPES = { container = true, ["logistic-container"] = true, ["storage-tank"] = true }
Rail.roles = { "import", "export", "both" }

local function state()
  storage.cell_rail = storage.cell_rail or { stops = {}, buffers = {}, visits = {}, history = {}, serial = 0 }
  return storage.cell_rail
end

local function eligible(entity, surface)
  return entity and entity.valid and entity.unit_number and entity.surface.index == surface
    and entity.force == game.forces.player
end

function Rail.live_stop(stop, surface)
  local entity = stop.entity
  return eligible(entity, surface) and entity.type == "train-stop" and entity or nil
end

function Rail.name(stop)
  return stop.entity.valid and stop.entity.backer_name or stop.name
end

function Rail.copy(stops)
  local copy = {}
  for unit, stop in pairs(stops or {}) do
    local buffers = {}
    for id, entity in pairs(stop.buffers) do buffers[id] = entity end
    copy[unit] = { entity = stop.entity, name = Rail.name(stop), role = stop.role, buffers = buffers }
  end
  return copy
end

function Rail.reindex(records)
  local s = storage.cell_rail
  local stops, buffers = {}, {}
  for id, record in pairs(records) do
    for unit, stop in pairs(record.stops or {}) do
      stops[unit] = { cell = id, surface = record.surface_index, stop = stop }
      for buffer in pairs(stop.buffers) do buffers[buffer] = unit end
    end
  end
  if not s and not next(stops) then return end
  s = s or state()
  local function same_owner(unit)
    return stops[unit] and s.stops[unit] and stops[unit].cell == s.stops[unit].cell
      and stops[unit].surface == s.stops[unit].surface
  end
  for unit in pairs(s.history) do
    if not same_owner(unit) then s.history[unit] = nil end
  end
  for train, visit in pairs(s.visits) do
    if not same_owner(visit.stop) then s.visits[train] = nil end
  end
  s.stops, s.buffers = stops, buffers
end

function Rail.conflict(cell, stops)
  local s = storage.cell_rail
  local buffers = {}
  for unit, stop in pairs(stops or {}) do
    local owner = s and s.stops[unit]
    if owner and owner.cell ~= cell then return true end
    for id in pairs(stop.buffers) do
      local old = s and s.buffers[id]
      if buffers[id] or (old and old ~= unit and s.stops[old].cell ~= cell) then return true end
      buffers[id] = true
    end
  end
  return false
end

function Rail.select_stops(draft, entities)
  draft.stops = draft.stops or {}
  local s, found = storage.cell_rail, false
  for _, entity in ipairs(entities) do
    if eligible(entity, draft.surface_index) and entity.type == "train-stop" then
      local id = entity.unit_number
      local owner = s and s.stops[id]
      if not owner or owner.cell == draft.id then
        draft.stops[id] = draft.stops[id] or { entity = entity, name = entity.backer_name, role = "import", buffers = {} }
        found = true
      end
    end
  end
  return found
end

function Rail.select_buffers(draft, unit, entities)
  local stop = draft.stops and draft.stops[unit]
  if not stop then return false end
  local other, buffers = {}, {}
  for id, candidate in pairs(draft.stops) do
    if id ~= unit then for buffer in pairs(candidate.buffers) do other[buffer] = true end end
  end
  local s = storage.cell_rail
  for _, entity in ipairs(entities) do
    if eligible(entity, draft.surface_index) and TYPES[entity.type] then
      local id = entity.unit_number
      local owner = s and s.buffers[id]
      if not other[id] and (not owner or s.stops[owner].cell == draft.id) then buffers[id] = entity end
    end
  end
  if not next(buffers) then return false end
  stop.buffers = buffers
  return true
end

local function add(target, kind, name, quality, count)
  local key = kind .. "/" .. name .. "/" .. (quality or "")
  local old = target[key]
  if old then old.count = old.count + count
  else target[key] = { kind = kind, name = name, quality = quality, count = count } end
end

local function items(target, contents)
  for _, item in ipairs(contents) do add(target, "item", item.name, item.quality or "normal", item.count) end
end

local function fluids(target, contents)
  for name, count in pairs(contents) do add(target, "fluid", name, nil, count) end
end

function Rail.sorted(stock)
  local list = {}
  for _, item in pairs(stock or {}) do list[#list + 1] = item end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.kind ~= b.kind then return a.kind < b.kind end
    if a.name ~= b.name then return a.name < b.name end
    return (a.quality or "") < (b.quality or "")
  end)
  return list
end

function Rail.stock(stop, surface)
  local stock, count, missing = {}, 0, 0
  for _, entity in pairs(stop.buffers) do
    if eligible(entity, surface) and TYPES[entity.type] then
      count = count + 1
      if entity.type == "storage-tank" then
        fluids(stock, entity.get_fluid_contents())
      else
        local inventory = entity.get_inventory(defines.inventory.chest)
        if inventory then items(stock, inventory.get_contents()) end
      end
    else
      missing = missing + 1
    end
  end
  return Rail.sorted(stock), count, missing
end

local function cargo(train)
  local stock = {}
  items(stock, train.get_contents())
  fluids(stock, train.get_fluid_contents())
  return stock
end

local function record(s, visit, finish, tick)
  local loaded, unloaded = {}, {}
  for key, old in pairs(visit.cargo) do
    local new = finish[key]
    local difference = old.count - (new and new.count or 0)
    if difference > 1e-5 then add(unloaded, old.kind, old.name, old.quality, difference) end
  end
  for key, new in pairs(finish) do
    local old = visit.cargo[key]
    local difference = new.count - (old and old.count or 0)
    if difference > 1e-5 then add(loaded, new.kind, new.name, new.quality, difference) end
  end
  s.serial = s.serial + 1
  local history = s.history[visit.stop] or { next = 1, rows = {} }
  s.history[visit.stop] = history
  local previous = history.rows[history.next]
  if previous then history.lost_tick = previous.tick end
  history.rows[history.next] = { id = s.serial, stop = visit.stop, train = visit.train.id,
    arrival = visit.tick, tick = tick, loaded = Rail.sorted(loaded), unloaded = Rail.sorted(unloaded) }
  history.next = history.next % RETAIN + 1
end

function Rail.on_state(e)
  local s, train = storage.cell_rail, e.train
  if not s or not train.valid then return end
  local id, station = train.id, train.station
  local visit = s.visits[id]
  if train.manual_mode then s.visits[id] = nil; return end
  if train.state == defines.train_state.wait_station and station then
    local unit = station.unit_number
    if visit and visit.stop ~= unit then
      -- A different physical arrival confirms the previous departure. Its
      -- last stop-side snapshot was taken before this stop could exchange cargo.
      local previous = s.stops[visit.stop]
      if visit.exit and previous and Rail.live_stop(previous.stop, previous.surface) then
        record(s, visit, visit.exit, visit.exit_tick)
      end
      s.visits[id], visit = nil, nil
    end
    local owner = s.stops[unit]
    local front = train.front_stock
    if not visit and owner and front and Rail.live_stop(owner.stop, owner.surface) == station then
      local ends = { [front.unit_number] = front.position }
      local back = train.back_stock
      if back then ends[back.unit_number] = back.position end
      s.visits[id] = { train = train, stop = unit, ends = ends,
        tick = e.tick or game.tick, cargo = cargo(train) }
    elseif visit then
      visit.exit, visit.exit_tick = nil, nil
    end
  elseif visit and e.old_state == defines.train_state.wait_station then
    visit.exit, visit.exit_tick = cargo(train), e.tick or game.tick
  end
end

function Rail.on_train_created(e)
  local s = storage.cell_rail
  if not s then return end
  if e.old_train_id_1 then s.visits[e.old_train_id_1] = nil end
  if e.old_train_id_2 then s.visits[e.old_train_id_2] = nil end
end

function Rail.on_tick(tick)
  local s = storage.cell_rail
  if not s or tick % 10 ~= 0 or not next(s.visits) then return end
  for id, visit in pairs(s.visits) do
    local train, owner = visit.train, s.stops[visit.stop]
    local front = train.valid and train.front_stock
    local station = owner and Rail.live_stop(owner.stop, owner.surface)
    local origin = front and (visit.ends and visit.ends[front.unit_number] or visit.front == front.unit_number and visit.position)
    if not origin or not station or front.surface ~= station.surface or train.manual_mode then
      s.visits[id] = nil
    elseif visit.exit and train.station ~= station and train.speed ~= 0 then
      local x, y = front.position.x - origin.x, front.position.y - origin.y
      if x * x + y * y >= DEPARTURE_DISTANCE_SQUARED then
        record(s, visit, cargo(train), tick)
        s.visits[id] = nil
      end
    end
  end
end

function Rail.read_history(stops, from_tick)
  local s, rows, truncated = storage.cell_rail, {}, false
  if not s then return rows, truncated end
  for unit in pairs(stops) do
    local history = s.history[unit]
    if history then
      if history.lost_tick and history.lost_tick >= from_tick then truncated = true end
      for _, row in pairs(history.rows) do if row.tick >= from_tick then rows[#rows + 1] = row end end
    end
  end
  for id, visit in pairs(s.visits) do
    if stops[visit.stop] and visit.train.valid then
      rows[#rows + 1] = { stop = visit.stop, train = id, arrival = visit.tick, tick = visit.tick, pending = true }
    end
  end
  table.sort(rows, function(a, b)
    if a.tick ~= b.tick then return a.tick > b.tick end
    return (a.id or -a.train) > (b.id or -b.train)
  end)
  return rows, truncated
end

function Rail.summary(unit, from_tick)
  local rows, truncated = Rail.read_history({[unit] = true}, from_tick)
  local loaded, unloaded = {}, {}
  for _, row in ipairs(rows) do
    if not row.pending then
      for _, item in ipairs(row.loaded) do add(loaded, item.kind, item.name, item.quality, item.count) end
      for _, item in ipairs(row.unloaded) do add(unloaded, item.kind, item.name, item.quality, item.count) end
    end
  end
  return Rail.sorted(loaded), Rail.sorted(unloaded), truncated
end

function Rail.traffic(stops, surface, force, selected_stop)
  local status, targets = {}, {}
  for unit, stop in pairs(stops) do
    local entity = Rail.live_stop(stop, surface)
    local entry = { headed = {}, scheduled = 0 }
    status[unit] = entry
    if entity then
      targets[entity.unit_number] = entry
      local scheduled = entity.get_train_stop_trains()
      entry.scheduled = #scheduled
      if unit == selected_stop then
        table.sort(scheduled, function(a, b) return a.id < b.id end)
        entry.scheduled_trains = scheduled
      end
      entry.stopped = entity.get_stopped_train()
      local limit = entity.trains_limit
      if type(limit) == "number" and limit < 4294967295 then entry.limit = limit end
    end
  end
  if next(targets) then
    for _, train in ipairs(game.train_manager.get_trains { surface = surface, force = force }) do
      local destination = train.has_path and train.path_end_stop
      local entry = destination and destination.valid and targets[destination.unit_number]
      if entry and train.station ~= destination and train ~= entry.stopped then entry.headed[#entry.headed + 1] = train end
    end
    for _, entry in pairs(targets) do table.sort(entry.headed, function(a, b) return a.id < b.id end) end
  end
  return status
end

return Rail
