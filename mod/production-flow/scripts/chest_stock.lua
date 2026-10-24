-- Physical chest contents. Cached registry; bounded reads; publish complete scans only.
local C = {}
C.TYPES = {"container", "logistic-container"}
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
  if storage.stock_basis ~= "physical-chests-v1" then
    storage.stock, storage.chest_stock = {}, nil
    storage.stock_basis = "physical-chests-v1"
  end
  storage.chest_stock = storage.chest_stock or {list={}, entities={}, next_tick=0}
end

function C.add(e)
  if not (e and e.valid and (e.type=="container" or e.type=="logistic-container")) then return end
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

function C.request(tick)
  local s = state()
  if s.batch or tick < s.next_tick then return end
  local surfaces = {}
  for _, surface in pairs(game.surfaces) do surfaces[surface.index] = {} end
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
        local inv = e.get_inventory(defines.inventory.chest)
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
