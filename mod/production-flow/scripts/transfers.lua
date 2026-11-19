-- Cargo pod arrivals. A platform's movement does not itself move cargo between
-- surfaces. The rocket up and the pod down are independent deliveries.
local Sampler = require("scripts.sampler")
local Surfaces = require("scripts.surfaces")
local Exchanges = require("scripts.transfer_exchanges")
local PhysicalEndpoints = require("scripts.transfer_endpoints")

local T = {}
local manifest
local HISTORY_TICKS = Sampler.PERIODS[#Sampler.PERIODS] * 60
local HISTORY_LIMIT = 32768
local PENDING_TICKS = 10 * 60 * 60
local PENDING_LIMIT = 4096
local ARRIVALS_PER_PAGE = 100
-- Derived, unsaved references: rebuild once after load, then maintain with the
-- ring. Query results still copy records, and landing edits remain visible.
local indexed_observations, shipment_boundaries
local function boundary_index(observations)
  if indexed_observations ~= observations then
    indexed_observations, shipment_boundaries = observations, {}
    for i = 0, observations.count - 1 do
      local record = observations.history[(observations.first - 1 + i) % HISTORY_LIMIT + 1]
      if record.kind ~= "receipt-gap" then
        local pair = shipment_boundaries[record.shipment_id] or {}
        shipment_boundaries[record.shipment_id] = pair
        pair[record.kind] = record
      end
    end
  end
  return shipment_boundaries
end
local BUCKET_SECONDS = { 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600,
  18000, 36000, 90000, 180000, 360000 }

function T.available()
  local active_mods = script and script.active_mods
  return active_mods and active_mods["space-age"] ~= nil
    and defines.events.on_cargo_pod_finished_ascending ~= nil
    and defines.events.on_cargo_pod_finished_descending ~= nil
    and defines.events.on_cargo_pod_delivered_cargo ~= nil
end

local function recording_start(state, tick)
  local first = state.history[state.first]
  return state.recording_start or (first and first.tick) or tick
end

local function ledger(tick)
  if not storage.transfers then
    storage.transfers = { pending = {}, pending_count = 0, endpoints = {}, serial = 0,
      history = {}, first = 1, count = 0, dropped = {} }
  end
  local state = storage.transfers
  if not state.recording_start then state.recording_start = recording_start(state, tick) end
  state.boundary_observations = state.boundary_observations or {
    history = {}, first = 1, count = 0, serial = 0, seen = {}, dropped = {}, start_tick = tick }
  state.boundary_observations.sent_by_pod=state.boundary_observations.sent_by_pod or {}
  return state
end

local function discard_boundary(observations, overflow)
  local record = observations.history[observations.first]
  if indexed_observations == observations and record.kind ~= "receipt-gap" then
    local pair = shipment_boundaries[record.shipment_id]
    if pair then
      pair[record.kind] = nil
      if not next(pair) then shipment_boundaries[record.shipment_id] = nil end
    end
  end
  observations.history[observations.first] = nil
  observations.first = observations.first % HISTORY_LIMIT + 1
  observations.count = observations.count - 1
  observations.seen[record.key] = nil
  if record.pod_id and observations.sent_by_pod and observations.sent_by_pod[record.pod_id]==record then
    observations.sent_by_pod[record.pod_id]=nil
  end
  if overflow and record.force.valid then
    observations.dropped[record.force.index] = { force = record.force, tick = record.tick }
  end
end

local function expire_boundaries(observations, tick)
  while observations.count > 0 and observations.history[observations.first].tick < tick - HISTORY_TICKS do
    discard_boundary(observations, false)
  end
  for index, dropped in pairs(observations.dropped) do
    if not dropped.force.valid or dropped.tick < tick - HISTORY_TICKS then observations.dropped[index] = nil end
  end
end

local function add_boundary(state, record)
  -- Older saves may have arrival history but no departure observations. Start
  -- this independent ledger now; never manufacture old origin manifests.
  local observations = state.boundary_observations
  if not observations then
    observations = { history = {}, first = 1, count = 0, serial = 0, seen = {}, dropped = {}, start_tick = record.tick }
    state.boundary_observations = observations
  end
  expire_boundaries(observations, record.tick)
  record.key = record.shipment_id .. ":" .. record.kind
  if observations.seen[record.key] then return nil end
  if observations.count == HISTORY_LIMIT then discard_boundary(observations, true) end
  observations.serial = observations.serial + 1
  record.id = observations.serial
  observations.history[(observations.first - 1 + observations.count) % HISTORY_LIMIT + 1] = record
  observations.count = observations.count + 1
  observations.seen[record.key] = true
  if indexed_observations == observations and record.kind ~= "receipt-gap" then
    local pair = shipment_boundaries[record.shipment_id] or {}
    shipment_boundaries[record.shipment_id] = pair
    pair[record.kind] = record
  end
  if record.kind=="sent" and record.pod_id then
    observations.sent_by_pod=observations.sent_by_pod or {}
    observations.sent_by_pod[record.pod_id]=record
  end
  return record
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

local function platform_visit(state,platform)
  if not defines.events.on_space_platform_changed_state then return nil end
  if not (platform and platform.valid and platform.index) then return nil end
  state.platform_visits=state.platform_visits or {}
  local location=platform.space_location
  if not location then state.platform_visits[platform.index]=nil;return nil end
  location=location.name
  local visit=state.platform_visits[platform.index]
  if not visit or visit.platform~=platform or visit.location~=location or visit.force~=platform.force then
    state.visit_serial=(state.visit_serial or 0)+1
    visit={platform=platform,location=location,force=platform.force,id=state.visit_serial}
    state.platform_visits[platform.index]=visit
  end
  return visit.id
end
function T.on_platform_changed_state(event)
  platform_visit(ledger(event.tick),event.platform)
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

local function empty_inventory(inventory)
  return inventory and inventory.valid and inventory.is_empty()
end

local function observe_departure(event,ordered)
  local pod = pod_of(event)
  if not pod or (pod.cargo_pod_state ~= "ascending" and not (ordered and pod.cargo_pod_state=="awaiting_launch")) then return end
  local origin = pod.cargo_pod_origin
  if not (origin and origin.valid and origin.surface == pod.surface and origin.force == pod.force) then return end
  if origin.type ~= "rocket-silo" and origin.type ~= "space-platform-hub" then return end
  local inventory = pod.get_inventory(defines.inventory.cargo_unit)
  if not (inventory and inventory.valid) then return end

  local state = ledger(event.tick)
  local id = pod.unit_number
  local previous = state.pending[id]
  if previous then
    if not previous.empty or previous.pod ~= pod or previous.force ~= pod.force then return end
    if inventory.is_empty() then return end
    -- Cargo can be added between launch order and the end of ascent. Replace
    -- the empty witness with the real manifest observed at this boundary.
    forget(state, id)
  end
  -- Start and finish of ascent can both raise dispatch handlers. Keep this
  -- guard even when the pending-delivery limit prevented endpoint tracking.
  if state.boundary_observations.sent_by_pod[id] then return end
  if inventory.is_empty() then
    if state.pending_count < PENDING_LIMIT then
      state.pending[id] = { pod=pod, force=pod.force, from=endpoint_for(state,pod.surface),
        tick=event.tick, shipment_id=tostring(id)..":"..tostring(event.tick), empty=true, empty_origin=true }
      state.pending_count=state.pending_count+1
    end
    return
  end
  local items, _, contents = manifest(inventory)
  if not items then return end
  local from = endpoint_for(state, pod.surface)
  local shipment_id = tostring(id) .. ":" .. tostring(event.tick)
  local dispatch = add_boundary(state, { shipment_id = shipment_id, pod_id=id, kind = "sent", tick = event.tick,
    force = pod.force, from = from, items = items, contents = contents, quality_exact = true,
    exchange_id=platform_visit(state,pod.surface.platform),sender=PhysicalEndpoints.snapshot(origin,origin.type) })
  if not dispatch or state.pending_count >= PENDING_LIMIT then return end
  state.pending[id] = { pod = pod, force = pod.force, from = from,
    tick = event.tick, shipment_id = shipment_id, dispatch = dispatch }
  state.pending_count = state.pending_count + 1
end

function T.on_departed(event) observe_departure(event) end

function T.on_rocket_launch_ordered(event)
  local rocket,silo=event.rocket,event.rocket_silo
  if not (rocket and rocket.valid and silo and silo.valid and silo.type=="rocket-silo") then return end
  local pod=rocket.attached_cargo_pod
  if not (pod and pod.valid and pod.cargo_pod_origin==silo) then return end
  -- The silo's attached-cargo inventory is emptied at launch order, before
  -- its animation finishes. Snapshot that real manifest at the same boundary.
  observe_departure({tick=event.tick,cargo_pod=pod},true)
end

manifest = function(inventory)
  if not inventory or not inventory.valid then return nil end
  local items, first_spoil, qualities = {}, nil, {}
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read then
      items[stack.name] = (items[stack.name] or 0) + stack.count
      local quality = stack.quality or "normal"
      if type(quality) ~= "string" then quality = quality.name end
      local key = stack.name .. "/" .. quality
      local item = qualities[key]
      if not item then item = { name = stack.name, quality = quality, count = 0 }; qualities[key] = item end
      item.count = item.count + stack.count
      local spoil = stack.spoil_tick
      if spoil > 0 then first_spoil = first_spoil and math.min(first_spoil, spoil) or spoil end
    end
  end
  if next(items) then
    local contents = {}
    for _, item in pairs(qualities) do contents[#contents + 1] = item end
    table.sort(contents, function(a, b) if a.name ~= b.name then return a.name < b.name end; return a.quality < b.quality end)
    return items, first_spoil, contents
  end
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
  local inventory=pod.get_inventory(defines.inventory.cargo_unit)
  local known_empty=pending.empty and empty_inventory(inventory)
  local items, spoil_tick, contents = manifest(inventory)
  if not items and not known_empty then return end
  -- A nonempty landing supersedes the empty origin observation. Its receipt
  -- can still be measured, while its unobserved sent manifest stays unknown.
  pending.empty=known_empty or nil
  pending.empty_landed=known_empty or nil
  pending.to = endpoint_for(state, pod.surface)
  pending.exchange_id=pending.dispatch and pending.dispatch.exchange_id or platform_visit(state,pod.surface.platform)
  if pending.dispatch then pending.dispatch.exchange_id=pending.exchange_id end
  if pending.dispatch then pending.dispatch.to = pending.to; pending.dispatch.destination_tick = event.tick end
  pending.landed_tick, pending.station = event.tick, station
  pending.receiver=station and PhysicalEndpoints.snapshot(station,station.type) or nil
  if pending.dispatch then pending.dispatch.receiver=pending.receiver;pending.dispatch.receiver_tick=event.tick end
  pending.items, pending.spoil_tick = items, spoil_tick
  pending.contents = contents
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
  if not (pod and pod.force.valid and pod.surface.valid) then return end
  local observations = state and state.boundary_observations
  local dispatch = observations and observations.sent_by_pod and observations.sent_by_pod[pod.unit_number]
  if dispatch and observations.seen[dispatch.shipment_id .. ":received"] then return end
  local function uncertain_receipt()
    -- The delivery callback proves that a receipt happened on this surface,
    -- even when its contents cannot be measured. Keep a bounded coverage gap,
    -- never an empty/zero manifest or a copy of the dispatch inventory.
    state = state or ledger(event.tick)
    add_boundary(state, { shipment_id = "receipt-gap:" .. pod.unit_number .. ":" .. event.tick,
      kind = "receipt-gap", tick = event.tick, force = pod.force, surface = pod.surface })
  end
  local pending = pending_for(state, pod, event.tick)
  if not pending then uncertain_receipt(); return end
  if pending.received then return end
  if pending.empty then
    local empty=pending.empty_landed and pending.to and pending.to.surface==pod.surface
      and event.tick>=pending.landed_tick and empty_inventory(pod.get_inventory(defines.inventory.cargo_unit))
    local container=event.spawned_container
    if container then
      empty=empty and container.valid and container.surface==pod.surface and container.force==pod.force
        and empty_inventory(container.get_inventory(defines.inventory.chest))
    else
      local station=pending.station
      empty=empty and station and station.valid and station.surface==pod.surface and station.force==pod.force
        and pod.cargo_pod_state=="parking"
    end
    if empty then
      -- Keep this bounded witness until pod destruction/timeout, so duplicate
      -- delivery callbacks cannot turn the confirmed empty pod into a gap.
      pending.empty_delivered_tick=event.tick
      return
    end
    forget(state,pod.unit_number);uncertain_receipt();return
  end
  forget(state, pod.unit_number)
  if not pending.to or pending.to.surface ~= pod.surface or event.tick < pending.landed_tick then
    uncertain_receipt(); return
  end

  local items, contents = pending.items, pending.contents
  local container = event.spawned_container
  if container then
    if not container.valid or container.surface ~= pod.surface or container.force ~= pod.force then uncertain_receipt(); return end
    local ignored_spoil
    items, ignored_spoil, contents = manifest(container.get_inventory(defines.inventory.chest))
  else
    local station = pending.station
    if not (station and station.valid and station.surface == pod.surface and station.force == pod.force) then uncertain_receipt(); return end
    if pod.cargo_pod_state ~= "parking" then uncertain_receipt(); return end
    -- A native station delivery unloads the pod onto the destination surface.
    -- Items that exceed station capacity spill onto that same surface. If any
    -- stack could spoil before the hatch unloaded, its manifest is uncertain.
    if pending.spoil_tick and pending.spoil_tick <= event.tick then uncertain_receipt(); return end
    local inventory = pod.get_inventory(defines.inventory.cargo_unit)
    if not inventory or not inventory.is_empty() then uncertain_receipt(); return end
  end
  if not items then uncertain_receipt(); return end
  local receiver=pending.receiver
  if container then
    receiver=PhysicalEndpoints.snapshot(container,container.type)
    if pending.dispatch then pending.dispatch.receiver=receiver;pending.dispatch.receiver_tick=event.tick end
  end
  local shipment_id = pending.shipment_id or (tostring(pod.unit_number) .. ":" .. tostring(pending.tick))
  add_arrival(state, { force = pending.force, from = pending.from, to = pending.to, tick = event.tick, items = items,
    shipment_id = shipment_id,exchange_id=pending.exchange_id,sender=pending.dispatch and pending.dispatch.sender,receiver=receiver })
  add_boundary(state, { shipment_id = shipment_id,
    kind = "received", tick = event.tick, force = pending.force, from = pending.from, to = pending.to,
    items = items, contents = contents, quality_exact = contents ~= nil,exchange_id=pending.exchange_id,
    sender=pending.dispatch and pending.dispatch.sender,receiver=receiver })
  if pending.empty_origin then
    -- A late-loaded pod has no dispatch record to guard delivery replays.
    -- Reuse its existing bounded slot until destruction/normal timeout.
    pending.received=true
    state.pending[pod.unit_number]=pending
    state.pending_count=state.pending_count+1
  end
end

function T.on_housekeeping(tick)
  local state = ledger(tick)
  for id, pending in pairs(state.pending) do
    if not pending.pod.valid or tick - pending.tick > PENDING_TICKS then forget(state, id) end
  end
  expire_history(state, tick)
  expire_boundaries(state.boundary_observations, tick)
  for id,visit in pairs(state.platform_visits or {}) do
    if not visit.platform.valid then state.platform_visits[id]=nil end
  end
  for index, dropped in pairs(state.dropped) do
    if not dropped.force.valid or dropped.tick < tick - HISTORY_TICKS then state.dropped[index] = nil end
  end
end

-- Independent physical boundary observations. Dispatches remain available after
-- a pending pod expires or is lost. Surface object identity protects reused IDs.
-- filters.companions also includes retained counterparts outside the selected
-- window, so history can keep each shipment's independent original timestamps.
function T.boundaries(force, surface, tick, seconds, filters)
  local result = { records = {}, from_tick = 0, to_tick = tick, period_seconds = 0,
    covered_seconds = 0, coverage = { sent = 0, received = 0 }, coverage_known = false, truncated = false }
  if not (force and force.valid and surface and surface.valid and type(tick) == "number" and tick >= 0
    and type(seconds) == "number" and seconds >= 0 and tick == tick and seconds == seconds
    and tick < math.huge and seconds < math.huge) then return result end
  result.from_tick = math.max(0, tick - math.min(seconds * 60, HISTORY_TICKS))
  result.period_seconds = (tick - result.from_tick) / 60
  local observations = storage.transfers and storage.transfers.boundary_observations
  if observations then
    local dropped = observations.dropped[force.index]
    result.truncated = dropped and dropped.force == force and dropped.tick >= result.from_tick or false
    result.dropped_tick = dropped and dropped.force == force and dropped.tick or nil
    local first = math.max(result.from_tick, observations.start_tick)
    if result.truncated then first = math.max(first, dropped.tick) end
    result.covered_seconds = math.max(0, (tick - math.min(tick, first)) / 60)
    result.coverage.sent, result.coverage.received = result.covered_seconds, result.covered_seconds
    result.coverage_known = true
  end
  filters = filters or {}
  local included = {}
  local function append(record, companion)
    if included[record.key] then return false end
    local to = record.to
    if record.destination_tick and record.destination_tick > tick then to = nil end
    if record.force == force and record.tick <= tick
      and (companion or record.tick >= result.from_tick)
      and record.tick >= tick - HISTORY_TICKS
      and (record.from.surface == surface or to and to.surface == surface)
      and (not to or record.from.surface ~= to.surface)
      and (not filters.kind or record.kind == filters.kind)
      and (not filters.material or record.items[filters.material]) then
      local copy = {}
      for key, value in pairs(record) do copy[key] = value end
      copy.from = {}; for key, value in pairs(record.from) do copy.from[key] = value end
      copy.to = nil
      if to then copy.to = {}; for key, value in pairs(to) do copy.to[key] = value end end
      copy.items = {}; for name, count in pairs(record.items) do copy.items[name] = count end
      for _,side in ipairs({"sender","receiver"}) do if record[side] then
        copy[side]={};for key,value in pairs(record[side]) do copy[side][key]=value end
        local position=record[side].position
        if position then copy[side].position={x=position.x,y=position.y} end
      end end
      if not to or record.receiver_tick and record.receiver_tick>tick then copy.receiver=nil end
      if record.contents then
        copy.contents = {}
        for _, item in ipairs(record.contents) do
          copy.contents[#copy.contents + 1] = { name = item.name, quality = item.quality, count = item.count }
        end
      end
      result.records[#result.records + 1] = copy
      included[record.key] = true
      return true
    end
  end
  if observations then
    local pairs_by_shipment = filters.companions and boundary_index(observations)
    for i = observations.count - 1, 0, -1 do
      local record = observations.history[(observations.first - 1 + i) % HISTORY_LIMIT + 1]
      if record.tick < result.from_tick then break end
      if record.kind == "receipt-gap" then
        if record.force == force and record.surface == surface and record.tick <= tick then
          result.received_gap_tick = math.max(result.received_gap_tick or record.tick, record.tick)
          result.received_partial = true
          result.coverage.received = math.min(result.coverage.received, math.max(0, (tick - record.tick) / 60))
        end
      else
        if append(record) and pairs_by_shipment then
          -- A recent receipt can belong to a much older dispatch. Retain its
          -- original manifest/time without scanning all retained shipments.
          local pair = pairs_by_shipment[record.shipment_id]
          local other = pair and pair[record.kind == "sent" and "received" or "sent"]
          if other then append(other, true) end
        end
      end
    end
  end
  -- Arrival history predating boundary recording contains real receipt evidence,
  -- but no origin manifest. Preserve each original time instead of using a
  -- route aggregate's latest time, and never duplicate new observed receipts.
  local state = storage.transfers
  if state then
    local dropped = state.dropped[force.index]
    if dropped and dropped.force == force then
      result.dropped_tick = math.max(result.dropped_tick or dropped.tick, dropped.tick)
      if dropped.tick >= result.from_tick then result.truncated = true end
    end
    for i = state.count - 1, 0, -1 do
      local slot = (state.first - 1 + i) % HISTORY_LIMIT + 1
      local record = state.history[slot]
      if record.tick < result.from_tick then break end
      if not record.shipment_id then
        local id = "legacy:" .. slot .. ":" .. record.tick
        append { id = id, key = id .. ":received", shipment_id = id, kind = "received", force = record.force,
          from = record.from, to = record.to, tick = record.tick, items = record.items, quality_exact = false, legacy = true }
      end
    end
  end
  table.sort(result.records, function(a, b)
    if a.tick ~= b.tick then return a.tick > b.tick end
    return a.key < b.key
  end)
  return result
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

local function platform_choices(force, selected_id)
  local choices, selected = {}, nil
  for _, platform in pairs(force.platforms or {}) do
    if platform.valid then
      local location = platform.space_location
      local choice = { id = platform.index, name = platform.name,
        icon = "item/space-platform-hub", surface = platform.surface,
        location = location and location.name or nil }
      choices[#choices + 1] = choice
      if choice.id == selected_id then selected = choice end
    end
  end
  table.sort(choices, function(a, b)
    local left, right = a.name:lower(), b.name:lower()
    if left ~= right then return left < right end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return choices, selected or choices[1]
end

local function measurement()
  return { pods = 0, count = 0, weight = 0, unknown_weight = false }
end

local function unit_weight(name, weights)
  if weights[name] == nil then
    local prototype = prototypes and prototypes.item and prototypes.item[name]
    weights[name] = prototype and prototype.weight or false
  end
  return weights[name]
end

local function measure_item(total, name, count, weights)
  local weight = unit_weight(name, weights)
  if weight then
    total.weight = total.weight + weight * count
  else
    total.unknown_weight = true
  end
end

local function summarize_items(total, manifest, weights, material)
  local items = {}
  for name, count in pairs(manifest) do
    items[#items + 1] = { name = name, count = count }
    if not material or material == name then measure_item(total, name, count, weights) end
  end
  table.sort(items, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  total.items = items
end

local function sum_weights(total, detail)
  total.weight = total.weight + detail.weight
  total.unknown_weight = total.unknown_weight or detail.unknown_weight
end

local function made_aboard(force, surface, seconds, material, materials, weights, exported)
  local made, items = measurement(), {}
  made.seconds = 0
  -- The sampler records production for the player force only.
  if surface and surface.valid and game and game.forces and game.forces["player"] == force and storage.bins then
    local rates, duration = Sampler.rates(surface.index, seconds)
    made.seconds = duration
    for key, rate in pairs(rates.nodes) do
      if key:sub(1, 5) == "item/" then
        local name = key:sub(6)
        local count = math.floor(rate.prod * duration + 0.5)
        if count > 0 and (not exported or exported[name]) then
          materials[name] = true
          if not material or material == name then
            items[name] = count
            made.count = made.count + count
          end
        end
      end
    end
  end
  summarize_items(made, items, weights)
  return made
end

local function make_buckets(result, requested, selected)
  local step = BUCKET_SECONDS[#BUCKET_SECONDS]
  for _, seconds in ipairs(BUCKET_SECONDS) do
    if requested <= seconds * 15 * 60 then
      step = seconds
      break
    end
  end
  step = step * 60
  local first = math.floor(result.from_tick / step) * step
  result.bucket_ticks = step
  for start_tick = first, result.to_tick, step do
    local bucket = { start_tick = start_tick, end_tick = start_tick + step,
      loaded = measurement(), unloaded = measurement() }
    bucket.loaded.manifest, bucket.unloaded.manifest = {}, {}
    result.buckets[#result.buckets + 1] = bucket
    if selected == start_tick then result.bucket = start_tick end
  end
  return first
end

local function route_for(routes, endpoint)
  local route = routes[endpoint.id]
  if not route then
    route = measurement()
    route.endpoint, route.manifest = endpoint, {}
    routes[endpoint.id] = route
  end
  return route
end

local function finish_routes(target, routes, summary, weights)
  for _, route in pairs(routes) do
    summarize_items(route, route.manifest, weights)
    route.manifest = nil
    sum_weights(summary, route)
    target[#target + 1] = route
  end
  table.sort(target, function(a, b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    if a.pods ~= b.pods then return a.pods > b.pods end
    return a.endpoint.id < b.endpoint.id
  end)
end

local function arrival_detail(entry, weights)
  local detail = { id = entry.id, tick = entry.record.tick, direction = entry.direction,
    endpoint = entry.endpoint, weight = 0, unknown_weight = false,exchange_key=entry.exchange_key }
  summarize_items(detail, entry.record.items, weights)
  return detail
end

-- View of a live platform. A load filter applies only to incoming legs, and an
-- unload filter only to outgoing legs. History preserves full pod manifests.
function T.platform_view(force, tick, seconds, filters)
  filters = filters or {}
  local platforms, platform = platform_choices(force, filters.platform)
  local requested = math.min(seconds * 60, HISTORY_TICKS)
  local result = { platforms = platforms, platform = platform, sources = {}, destinations = {}, materials = {},
    from_tick = math.max(0, tick - requested), to_tick = tick, loading = {}, unloading = {}, buckets = {},
    loaded = measurement(), unloaded = measurement(), arrivals = {}, arrival_count = 0, page = 1, pages = 1,exchanges={} }
  local flow, history = filters.view ~= "history", filters.view ~= "flow"
  local first_tick = history and make_buckets(result, requested,filters.axis~="events" and filters.bucket or nil)
  local surface, weights = platform and platform.surface, {}
  local loading, unloading, arrivals = {}, {}, {}
  local exchange_index={}
  local page = math.max(1, math.floor(filters.page or 1))
  local ledger_state = storage.transfers
  local earliest = ledger_state and recording_start(ledger_state, tick) or tick
  local dropped = ledger_state and ledger_state.dropped[force.index]
  result.truncated = dropped and dropped.force == force and dropped.tick >= result.from_tick
  if result.truncated then earliest = math.max(earliest, dropped.tick) end
  result.covered_seconds = (tick - math.min(tick, math.max(earliest, result.from_tick))) / 60
  if ledger_state and surface and surface.valid then
    local first_arrival = (page - 1) * ARRIVALS_PER_PAGE
    for i = ledger_state.count - 1, 0, -1 do
      local slot = (ledger_state.first - 1 + i) % HISTORY_LIMIT + 1
      local record = ledger_state.history[slot]
      if record.tick < result.from_tick then break end
      if record.force == force and record.tick <= tick then
        local endpoint, direction, filter, routes
        if record.to.surface == surface then
          endpoint, direction, filter, routes = record.from, "loaded", filters.from, loading
          result.sources[endpoint.id] = endpoint
        elseif record.from.surface == surface then
          endpoint, direction, filter, routes = record.to, "unloaded", filters.to, unloading
          result.destinations[endpoint.id] = endpoint
        end
        if endpoint then
          local material = filters.material
          local matches = (not filter or filter == endpoint.id) and (not material or record.items[material])
          local manifest, count = record.items, 0
          local route = flow and matches and route_for(routes, endpoint)
          local bucket = history and matches and result.buckets[math.floor((record.tick - first_tick) / result.bucket_ticks) + 1]
          local bin = bucket and bucket[direction]
          for name, amount in pairs(manifest) do
            result.materials[name] = true
            if not material or material == name then
              count = count + amount
              if route then route.manifest[name] = (route.manifest[name] or 0) + amount end
            end
            if bin then bin.manifest[name] = (bin.manifest[name] or 0) + amount end
          end
          if matches then
            local exchange_key=Exchanges.key(record,record.tick..":"..slot)
            if history and (filters.axis=="events" or filters.exchange) and count>0 then
              local exchange=exchange_index[exchange_key]
              if not exchange then
                exchange={key=exchange_key,start_tick=record.tick,end_tick=record.tick,loaded=measurement(),unloaded=measurement()}
                exchange.loaded.manifest,exchange.unloaded.manifest={},{}
                exchange_index[exchange_key]=exchange;result.exchanges[#result.exchanges+1]=exchange
              end
              exchange.start_tick=math.min(exchange.start_tick,record.tick);exchange.end_tick=math.max(exchange.end_tick,record.tick)
              local cargo=exchange[direction];cargo.pods=cargo.pods+1;cargo.count=cargo.count+count
              for name,amount in pairs(manifest) do cargo.manifest[name]=(cargo.manifest[name] or 0)+amount end
            end
            local total = result[direction]
            total.pods, total.count = total.pods + 1, total.count + count
            if route then route.pods, route.count = route.pods + 1, route.count + count end
            if bin then
              bin.pods, bin.count = bin.pods + 1, bin.count + count
              if (not result.bucket or result.bucket == bucket.start_tick) and (not filters.exchange or filters.exchange==exchange_key) then
                local position = result.arrival_count
                if position >= first_arrival and position < first_arrival + ARRIVALS_PER_PAGE then
                  arrivals[#arrivals + 1] = { id = record.tick .. ":" .. slot,
                    record = record, direction = direction, endpoint = endpoint,exchange_key=exchange_key }
                end
                result.arrival_count = position + 1
              end
            end
          end
        end
      end
    end
  end
  if flow then
    finish_routes(result.loading, loading, result.loaded, weights)
    finish_routes(result.unloading, unloading, result.unloaded, weights)
    local exported
    if not filters.show_all_production then
      exported = {}
      for _, route in ipairs(result.unloading) do
        for _, item in ipairs(route.items) do exported[item.name] = true end
      end
    end
    result.made = made_aboard(force, surface, seconds, filters.material, result.materials, weights, exported)
  end
  if history then
    if filters.exchange and not exchange_index[filters.exchange] then
      return T.platform_view(force,tick,seconds,setmetatable({exchange=false},{__index=filters}))
    end
    result.exchange=filters.exchange or nil
    table.sort(result.exchanges,function(a,b) if a.start_tick~=b.start_tick then return a.start_tick<b.start_tick end;return a.key<b.key end)
    for _,exchange in ipairs(result.exchanges) do for _,direction in ipairs({"loaded","unloaded"}) do
      local cargo=exchange[direction];summarize_items(cargo,cargo.manifest,weights,filters.material);cargo.manifest=nil
    end end
    for _, bucket in ipairs(result.buckets) do
      for _, direction in ipairs({ "loaded", "unloaded" }) do
        local bin = bucket[direction]
        summarize_items(bin, bin.manifest, weights, filters.material)
        bin.manifest = nil
        if not flow then sum_weights(result[direction], bin) end
      end
    end
    result.pages = math.max(1, math.ceil(result.arrival_count / ARRIVALS_PER_PAGE))
    result.page = math.min(page, result.pages)
    if page > result.pages and result.arrival_count > 0 then
      return T.platform_view(force, tick, seconds, setmetatable({ page = result.pages }, { __index = filters }))
    end
    for i, entry in ipairs(arrivals) do result.arrivals[i] = arrival_detail(entry, weights) end
  end
  return result
end

return T
