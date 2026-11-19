-- Physical storage and cargo buffers. Bounded reads; publish complete scans only.
local C = {}
C.TYPES = {"container", "logistic-container", "temporary-container", "cargo-landing-pad", "space-platform-hub", "rocket-silo", "cargo-pod"}
local INVENTORY={container="chest",["logistic-container"]="chest",["temporary-container"]="chest",["cargo-landing-pad"]="cargo_landing_pad_main",
  ["space-platform-hub"]="hub_main",["rocket-silo"]="rocket_silo_attached_cargo_unit",["cargo-pod"]="cargo_unit"}
C.PER_TICK = 32
local function state() return storage.chest_stock end

function C.interval()
  local setting=settings.global["ssk-stock-scan-minutes"]
  return math.max(1,setting and setting.value or 5)*3600
end

function C.reschedule()
  local s=state()
  if s.batch then return end -- The new cooldown applies when the active scan finishes.
  local h=storage.stock or {};local last=h[#h]
  s.next_tick=last and last.tick+C.interval() or 0
end

function C.init()
  if storage.stock_basis ~= "physical-storage-v2" then
    storage.stock, storage.chest_stock = {}, nil
    storage.stock_basis = "physical-storage-v2"
  end
  storage.chest_stock = storage.chest_stock or {list={}, entities={}, next_tick=0}
end

function C.add(e)
  if not (e and e.valid and INVENTORY[e.type]) then return end
  local s, u = state(), e.unit_number
  if not u or s.entities[u] then return end
  s.entities[u] = e
  s.list[#s.list+1] = u
end

function C.rescan()
  storage.chest_stock = {list={}, entities={}, next_tick=0}
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered{type=C.TYPES}) do C.add(e) end
  end
end

function C.on_surface_deleted(index)
  for _, snapshot in ipairs(storage.stock or {}) do snapshot.s[index] = nil end
  local s = state()
  if not s then return end
  local batch = s.batch
  local list, cursor, limit = {}, 1, 0
  for i, unit in ipairs(s.list) do
    local entity = s.entities[unit]
    if entity and entity.valid and entity.surface.index == index then
      s.entities[unit] = nil
    else
      list[#list + 1] = unit
      if batch and i < batch.cursor then cursor = cursor + 1 end
      if batch and i <= batch.limit then limit = limit + 1 end
    end
  end
  s.list = list
  if batch then
    batch.cursor, batch.limit, batch.s[index] = cursor, limit, nil
  end
end

function C.request(tick)
  local s = state()
  if s.batch or tick < s.next_tick then return end
  local surfaces = {}
  for _, surface in pairs(game.surfaces) do
    surfaces[surface.index] = {}
    -- Engine-created pods do not raise the normal entity-built events. Cargo
    -- waiting at a platform hatch has already left hub_main, but has not yet
    -- dispatched. Discover it before fixing this scan's bounded registry.
    for _,pod in pairs(surface.find_entities_filtered{type="cargo-pod",force=game.forces.player}) do C.add(pod) end
  end
  s.batch = {start=tick, cursor=1, limit=#s.list, s=surfaces, reads=0}
end

function C.tick(tick)
  local s = state()
  C.request(tick)
  local b = s.batch
  if not b then return end
  for _=1,C.PER_TICK do
    if b.cursor > b.limit then break end
    local u = s.list[b.cursor]
    local e = s.entities[u]
    if not (e and e.valid) then
      -- Keep new entries (after limit) outside this scan, without a full-list compaction.
      local n = #s.list
      s.entities[u] = nil
      s.list[b.cursor] = s.list[b.limit]
      s.list[b.limit] = s.list[n]
      s.list[n] = nil
      b.limit = b.limit-1
    else
      if e.force == game.forces.player then
        local eligible=true
        if e.type=="cargo-pod" then
          local origin=e.cargo_pod_origin
          eligible=e.cargo_pod_state=="awaiting_launch" and origin and origin.valid
            and (origin.type=="space-platform-hub" or origin.type=="cargo-landing-pad")
        end
        local id=eligible and defines.inventory[INVENTORY[e.type]]
        local inv = id and e.get_inventory(id)
        if inv and inv.valid then
          local index = e.surface.index
          local totals = b.s[index] or {}; b.s[index] = totals
          for _, item in pairs(inv.get_contents()) do
            local key = "item/"..item.name
            totals[key] = (totals[key] or 0)+item.count
          end
          b.reads = b.reads+1
        end
      end
      b.cursor = b.cursor+1
    end
  end
  if b.cursor > b.limit then
    local h = storage.stock
    h[#h+1] = {tick=tick, start=b.start, s=b.s}
    while #h>7 do table.remove(h,1) end
    s.last = {ticks=tick-b.start+1, reads=b.reads, tick=tick}
    s.next_tick, s.batch = tick+C.interval(), nil
  end
end

function C.known(sidx)
  local h = storage.stock or {}
  local last = h[#h]
  return last ~= nil and (not sidx or last.s[sidx] ~= nil)
end

function C.status()
  local s = state()
  local h=storage.stock or {};local snapshot=h[#h]
  return {tracked=#s.list, per_tick=C.PER_TICK, interval=C.interval(), updated_tick=snapshot and snapshot.tick,
          last=s.last, active=s.batch~=nil}
end

return C
