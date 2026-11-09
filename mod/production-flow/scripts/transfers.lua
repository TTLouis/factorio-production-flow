-- Cargo pod arrivals. A platform's movement does not itself move cargo between
-- surfaces. The rocket up and the pod down are independent deliveries.
local Surfaces = require("scripts.surfaces")

local T = {}
local HISTORY_TICKS = 10 * 3600 * 60
local HISTORY_LIMIT = 32768
local PENDING_TICKS = 10 * 60 * 60
local PENDING_LIMIT = 4096

function T.available()
  return script and script.active_mods and script.active_mods["space-age"] ~= nil
    and defines.events.on_cargo_pod_finished_ascending ~= nil
    and defines.events.on_cargo_pod_finished_descending ~= nil
    and defines.events.on_cargo_pod_delivered_cargo ~= nil
end

local function ledger()
  if not storage.transfers then
    storage.transfers = { pending = {}, pending_count = 0, endpoints = {}, serial = 0,
      history = {}, first = 1, count = 0, dropped = {} }
  end
  return storage.transfers
end

local function surface_name(surface)
  local platform = Surfaces.platform_name(surface)
  if platform then return platform, "item/space-platform-hub" end
  local planet = surface.planet
  return Surfaces.label(surface), planet and "space-location/" .. planet.name
end

function T.describe(endpoint)
  if endpoint.surface.valid then
    local name, icon = surface_name(endpoint.surface)
    -- Factorio removes the platform before raising on_pre_surface_deleted.
    -- Preserve the last observed platform name instead of its internal ID.
    if endpoint.icon ~= "item/space-platform-hub" or icon == endpoint.icon then
      endpoint.name, endpoint.icon = name, icon
    end
  end
  return endpoint.name, endpoint.icon
end

local function endpoint_for(state, surface)
  local endpoint = state.endpoints[surface.index]
  if not endpoint or endpoint.surface ~= surface then
    state.serial = state.serial + 1
    local name, icon = surface_name(surface)
    endpoint = { id = state.serial, surface = surface, name = name, icon = icon }
    state.endpoints[surface.index] = endpoint
  else
    T.describe(endpoint)
  end
  return endpoint
end

function T.on_surface_deleted(event)
  local state = storage.transfers
  local endpoint = state and state.endpoints[event.surface_index]
  if not endpoint then return end
  T.describe(endpoint)
  -- Surface indices are reusable. The archived endpoint keeps its own identity.
  state.endpoints[event.surface_index] = nil
end

local function pod_of(event)
  local pod = event.cargo_pod
  if pod and pod.valid and pod.name == "cargo-pod" and pod.unit_number then return pod end
end

local function forget(state, id)
  state.pending[id] = nil
  state.pending_count = state.pending_count - 1
end

function T.on_departed(event)
  local pod = pod_of(event)
  if not pod or pod.cargo_pod_state ~= "ascending" then return end
  local origin = pod.cargo_pod_origin
  if not (origin and origin.valid and origin.surface == pod.surface and origin.force == pod.force) then return end
  if origin.type ~= "rocket-silo" and origin.type ~= "space-platform-hub" then return end
  local inventory = pod.get_inventory(defines.inventory.cargo_unit)
  if not inventory or inventory.is_empty() then return end

  local state = ledger()
  local id = pod.unit_number
  if state.pending[id] or state.pending_count >= PENDING_LIMIT then return end
  state.pending[id] = { pod = pod, force = pod.force, from = endpoint_for(state, pod.surface),
    tick = event.tick }
  state.pending_count = state.pending_count + 1
end

local function manifest(inventory)
  if not inventory or not inventory.valid then return nil end
  local items, first_spoil = {}, nil
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then
      items[stack.name] = (items[stack.name] or 0) + stack.count
      local spoil = stack.spoil_tick
      if spoil > 0 then first_spoil = first_spoil and math.min(first_spoil, spoil) or spoil end
    end
  end
  if next(items) then return items, first_spoil end
end

local function pending_for(state, pod, tick)
  local pending = state and pod and state.pending[pod.unit_number]
  if pending and pending.pod == pod and pending.force == pod.force and
      tick >= pending.tick and tick - pending.tick <= PENDING_TICKS then return pending end
end

function T.on_landed(event)
  local state, pod = storage.transfers, pod_of(event)
  local pending = pending_for(state, pod, event.tick)
  if not pending or pending.to or pending.from.surface == pod.surface then return end

  -- The pod has crossed surfaces, but may still be waiting for the hatch.
  -- Its destination is reset and its inventory emptied by the delivery event.
  local destination = pod.cargo_pod_destination
  local types = defines.cargo_destination
  local station = destination.station
  if destination.type == types.station then
    if not (station and station.valid and station.surface == pod.surface and station.force == pod.force) then return end
    if station.type ~= "cargo-landing-pad" and station.type ~= "space-platform-hub" then return end
  elseif destination.type ~= types.surface or destination.surface ~= pod.surface then
    return
  end
  local items, spoil_tick = manifest(pod.get_inventory(defines.inventory.cargo_unit))
  if not items then return end
  pending.to = endpoint_for(state, pod.surface)
  pending.landed_tick, pending.station = event.tick, station
  pending.items, pending.spoil_tick = items, spoil_tick
end

local function discard_oldest(state)
  local record = state.history[state.first]
  state.history[state.first] = nil
  state.first = state.first % HISTORY_LIMIT + 1
  state.count = state.count - 1
  return record
end

local function expire_history(state, tick)
  while state.count > 0 and state.history[state.first].tick < tick - HISTORY_TICKS do
    discard_oldest(state)
  end
end

local function add_arrival(state, record)
  expire_history(state, record.tick)
  if state.count == HISTORY_LIMIT then
    local removed = discard_oldest(state)
    if removed.force.valid then state.dropped[removed.force.index] = { force = removed.force, tick = removed.tick } end
  end
  local tail = (state.first - 1 + state.count) % HISTORY_LIMIT + 1
  state.history[tail] = record
  state.count = state.count + 1
end

function T.on_delivered(event)
  local state, pod = storage.transfers, pod_of(event)
  local pending = pending_for(state, pod, event.tick)
  if not pending then return end
  forget(state, pod.unit_number)
  if not pending.to or pending.to.surface ~= pod.surface or event.tick < pending.landed_tick then return end

  local items = pending.items
  local container = event.spawned_container
  if container then
    if not container.valid or container.surface ~= pod.surface or container.force ~= pod.force then return end
    items = manifest(container.get_inventory(defines.inventory.chest))
  else
    local station = pending.station
    if not (station and station.valid and station.surface == pod.surface and station.force == pod.force) then return end
    if pod.cargo_pod_state ~= "parking" then return end
    -- A native station delivery unloads the pod onto the destination surface.
    -- Items that exceed station capacity spill onto that same surface. If any
    -- stack could spoil before the hatch unloaded, its manifest is uncertain.
    if pending.spoil_tick and pending.spoil_tick <= event.tick then return end
    local inventory = pod.get_inventory(defines.inventory.cargo_unit)
    if not inventory or not inventory.is_empty() then return end
  end
  if not items then return end
  add_arrival(state, { force = pending.force, from = pending.from, to = pending.to, tick = event.tick, items = items })
end

function T.on_housekeeping(tick)
  local state = storage.transfers
  if not state then return end
  for id, pending in pairs(state.pending) do
    if not pending.pod.valid or tick - pending.tick > PENDING_TICKS then forget(state, id) end
  end
  expire_history(state, tick)
  for index, dropped in pairs(state.dropped) do
    if not dropped.force.valid or dropped.tick < tick - HISTORY_TICKS then state.dropped[index] = nil end
  end
end

local function row_order(a, b)
  if a.count ~= b.count then return a.count > b.count end
  if a.last ~= b.last then return a.last > b.last end
  if a.from.id ~= b.from.id then return a.from.id < b.from.id end
  if a.to.id ~= b.to.id then return a.to.id < b.to.id end
  return a.material < b.material
end

-- Choices cover the whole period so each filter can be changed independently.
-- An arrival is one pod even if it contributed more than one material row.
function T.query(force, tick, seconds, filters)
  local result = { rows = {}, sources = {}, destinations = {}, materials = {},
    routes = 0, arrivals = 0, items = 0 }
  local state = storage.transfers
  if not state then return result end
  filters = filters or {}
  local since = tick - math.min(seconds * 60, HISTORY_TICKS)
  local dropped = state.dropped[force.index]
  result.truncated = dropped and dropped.force == force and dropped.tick >= since
  local routes = {}
  for i = state.count - 1, 0, -1 do
    local record = state.history[(state.first - 1 + i) % HISTORY_LIMIT + 1]
    if record.tick < since then break end
    if record.force == force and record.tick <= tick then
      local from, to = record.from, record.to
      result.sources[from.id], result.destinations[to.id] = from, to
      local matches = (not filters.from or from.id == filters.from) and (not filters.to or to.id == filters.to)
      local route, arrival = from.id .. "/" .. to.id, false
      for material, count in pairs(record.items) do
        result.materials[material] = true
        if matches and (not filters.material or filters.material == material) then
          local by_material = routes[route]
          if not by_material then
            by_material = {}
            routes[route] = by_material
            result.routes = result.routes + 1
          end
          local row = by_material[material]
          if not row then
            row = { from = from, to = to, material = material, count = 0, last = record.tick }
            by_material[material] = row
            result.rows[#result.rows + 1] = row
          end
          row.count = row.count + count
          result.items = result.items + count
          arrival = true
        end
      end
      if arrival then result.arrivals = result.arrivals + 1 end
    end
  end
  table.sort(result.rows, row_order)
  return result
end

return T
