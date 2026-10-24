-- M2: entity registry + round-robin sampler (D6, D7)
--
-- Edge measurement : products_finished deltas per crafting machine, attributed to the
--                    recipe seen at BOTH ends of the interval (changed recipe -> discard).
-- Node totals      : force production statistics, cumulative-count deltas per surface.
-- Both go into a ring of 1-second bins; rates are averaged over the full bins.

local Sm = {}
local ChestStock = require("scripts.chest_stock")

local TYPES = { "assembling-machine", "furnace", "rocket-silo" }
local TYPESET = { ["assembling-machine"] = true, furnace = true, ["rocket-silo"] = true }
local BIN_TICKS = 60

-- Verified on a real base (v0.0.7 export): products_finished INCLUDES productivity bonus crafts.
-- normal crafts = pf / (1 + prod); inputs = normal * amount; outputs = normal * (amount + eligible * prod)
Sm.PF_INCLUDES_BONUS = true

Sm.TYPES = TYPES
Sm.logger = nil -- set by control.lua (Diag.log)
local function log(msg) if Sm.logger then Sm.logger(msg) end end

---------------------------------------------------------------------------
-- storage
---------------------------------------------------------------------------
local function nbins()
  -- Keep 10 minutes of completed samples plus the currently accumulating bin.
  return math.max(600, settings.global["ssk-window-seconds"].value) + 1
end

function Sm.init()
  ChestStock.init()
  storage.machines = storage.machines or {} -- unit_number -> {e, u, s, r, pf}
  storage.mlist = storage.mlist or {}       -- array of unit_numbers (round-robin order)
  storage.mcursor = storage.mcursor or 1
  storage.stat_last = storage.stat_last or {} -- [surface][key] = cumulative {i, o}
  storage.cycle = storage.cycle or { start = game.tick, last = 0 }
  storage.probes = storage.probes or {}
  if storage.nbins ~= nbins() or not storage.bins then
    local old = storage.bins or {}
    storage.nbins = nbins()
    storage.bins = {}
    -- Preserve existing history when upgrading or changing the Live setting.
    for _, b in pairs(old) do
      local slot = b.id % storage.nbins + 1
      if not storage.bins[slot] or storage.bins[slot].id < b.id then storage.bins[slot] = b end
    end
  end
  -- coarse history for longer observation periods: completed 1 s bins are rolled up
  if not storage.rings then
    storage.rings = {
      { secs = 60,  n = 60, bins = {} },  -- 1 min bins  -> up to 1 h
      { secs = 600, n = 60, bins = {} },  -- 10 min bins -> up to 10 h
    }
  end
end

-- observation periods offered in the UI (seconds; "window" = the fine window setting)
Sm.PERIODS = { 0, 600, 3600, 36000 }
Sm.DEFAULT_PERIOD = 600
Sm.PERIOD_CAPTIONS = { "Recent (window)", "10 min", "1 hour", "10 hours" }

local function add_into(dst, src)
  for s, recs in pairs(src.rec) do
    local d = dst.rec[s]
    if not d then d = {}; dst.rec[s] = d end
    for r, a in pairs(recs) do
      local x = d[r]
      if not x then x = { c = 0, p = 0 }; d[r] = x end
      x.c = x.c + a.c
      x.p = x.p + a.p
    end
  end
  for s, keys in pairs(src.stat) do
    local d = dst.stat[s]
    if not d then d = {}; dst.stat[s] = d end
    for k, a in pairs(keys) do
      local x = d[k]
      if not x then x = { i = 0, o = 0 }; d[k] = x end
      x.i = x.i + a.i
      x.o = x.o + a.o
    end
  end
end

local function roll_up(b)
  for _, ring in ipairs(storage.rings or {}) do
    local per = ring.secs * 60 / BIN_TICKS
    local id = math.floor(b.id / per)
    local slot = id % ring.n + 1
    local c = ring.bins[slot]
    if not c or c.id ~= id then
      c = { id = id, secs = 0, rec = {}, stat = {} }
      ring.bins[slot] = c
    end
    c.secs = c.secs + BIN_TICKS / 60
    add_into(c, b)
  end
end

local function cur_bin(tick)
  local id = math.floor(tick / BIN_TICKS)
  local slot = id % storage.nbins + 1
  local b = storage.bins[slot]
  if not b or b.id ~= id then
    -- the previous 1 s bin is complete now: add it to the coarse history
    local pid = storage.last_bin_id
    if pid and pid < id then
      local prev = storage.bins[pid % storage.nbins + 1]
      if prev and prev.id == pid then roll_up(prev) end
    end
    b = { id = id, rec = {}, stat = {} }
    storage.bins[slot] = b
    storage.last_bin_id = id
  end
  return b
end

---------------------------------------------------------------------------
-- registry
---------------------------------------------------------------------------
function Sm.current_recipe(e)
  local r = e.get_recipe()
  if r then return r.name end
  if e.type == "furnace" then
    local pr = e.previous_recipe
    if pr then
      local n = pr.name
      if type(n) ~= "string" and n then n = n.name end
      return n
    end
  end
  return nil
end

function Sm.add(e)
  ChestStock.add(e)
  if not (e and e.valid and TYPESET[e.type]) then return end
  local u = e.unit_number
  if not u or storage.machines[u] then return end
  local rec = { e = e, u = u, s = e.surface.index, r = Sm.current_recipe(e), pf = e.products_finished,
                spd = e.crafting_speed }
  if e.type == "rocket-silo" then
    rec.silo = true
    rec.rp = e.rocket_parts
    rec.req = e.prototype.rocket_parts_required or 50
  end
  storage.machines[u] = rec
  storage.mlist[#storage.mlist + 1] = u
end

function Sm.rescan()
  ChestStock.rescan()
  storage.machines, storage.mlist, storage.mcursor = {}, {}, 1
  for _, s in pairs(game.surfaces) do
    for _, e in pairs(s.find_entities_filtered { type = TYPES }) do Sm.add(e) end
  end
  storage.cycle = { start = game.tick, last = 0 }
  log("rescan: " .. #storage.mlist .. " crafting machines")
  return #storage.mlist
end

---------------------------------------------------------------------------
-- per-tick sampling
---------------------------------------------------------------------------
function Sm.on_tick(tick)
  ChestStock.tick(tick)
  local list = storage.mlist
  if #list == 0 then return end
  local per = settings.global["ssk-entities-per-tick"].value
  local bin = cur_bin(tick)
  local cur = storage.mcursor
  local machines = storage.machines

  for _ = 1, per do
    local n = #list
    if n == 0 then break end
    if cur > n then
      cur = 1
      storage.cycle.last = tick - storage.cycle.start
      storage.cycle.start = tick
    end
    local u = list[cur]
    local rec = machines[u]
    local e = rec and rec.e
    if not (e and e.valid) then
      machines[u] = nil
      list[cur] = list[n]
      list[n] = nil
    else
      local r = Sm.current_recipe(e)
      local pf = e.products_finished
      local rp
      if rec.silo then rp = e.rocket_parts end
      if r and r == rec.r then
        local d = pf - rec.pf
        -- rocket silo: products_finished counts rockets, so count parts instead
        if rec.silo then d = d * rec.req + (rp - (rec.rp or rp)) end
        if d > 0 then
          local bs = bin.rec[rec.s]
          if not bs then bs = {}; bin.rec[rec.s] = bs end
          local a = bs[r]
          if not a then a = { c = 0, p = 0 }; bs[r] = a end
          a.c = a.c + d
          a.p = a.p + d * (e.productivity_bonus or 0)
        end
      end
      rec.r, rec.pf = r, pf
      rec.spd = e.crafting_speed
      if rec.silo then rec.rp = rp end
      cur = cur + 1
    end
  end
  storage.mcursor = cur
end

-- cumulative-count deltas from force production statistics (once per bin)
local function num(v)
  if type(v) == "number" then return v end
  local t = 0
  if type(v) == "table" then for _, x in pairs(v) do if type(x) == "number" then t = t + x end end end
  return t
end

function Sm.on_stats(tick)
  local force = game.forces["player"]
  if not force then return end
  local bin = cur_bin(tick)
  for _, s in pairs(game.surfaces) do
    local last = storage.stat_last[s.index]
    local first = last == nil
    if first then last = {}; storage.stat_last[s.index] = last end
    local out = bin.stat[s.index]
    if not out then out = {}; bin.stat[s.index] = out end
    for kind, st in pairs({ item = force.get_item_production_statistics(s),
                            fluid = force.get_fluid_production_statistics(s) }) do
      for side, counts in pairs({ i = st.input_counts, o = st.output_counts }) do
        for name, v in pairs(counts) do
          local key = kind .. "/" .. name
          local l = last[key]
          if not l then l = { i = 0, o = 0 }; last[key] = l end
          local now = num(v)
          local d = now - l[side]
          l[side] = now
          if not first and d > 0 then
            local a = out[key]
            if not a then a = { i = 0, o = 0 }; out[key] = a end
            a[side] = a[side] + d
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- queries
---------------------------------------------------------------------------
-- returns {recipes = {[r] = {cps, prod}}, nodes = {[key] = {prod, cons}}}, seconds
-- period: seconds to average over (nil / 0 = the fine rate window)
function Sm.rates(sidx, period)
  local now_id = math.floor(game.tick / BIN_TICKS)
  local rc, st, nfull = {}, {}, 0
  local requested = period and period > 0 and period or settings.global["ssk-window-seconds"].value
  local bins, unit = storage.bins, nil
  local take = function(b) return b.id < now_id and b.id >= now_id - requested end
  local fine_secs = 0
  for _, b in pairs(bins) do if take(b) then fine_secs = fine_secs + 1 end end
  -- An upgraded save may already have coarse history older than its fine bins.
  -- Prefer the fine window once complete; otherwise use the longer coverage.
  if requested > fine_secs and period and period > 0 and storage.rings then
    local ring = storage.rings[#storage.rings]
    for _, rg in ipairs(storage.rings) do
      if requested <= rg.secs * rg.n then ring = rg break end
    end
    local cid = math.floor(game.tick / 60 / ring.secs)
    local need = math.ceil(requested / ring.secs)
    local coarse_take = function(b) return b.id <= cid and b.id > cid - need end
    local coarse_secs = 0
    for _, b in pairs(ring.bins) do if coarse_take(b) then coarse_secs = coarse_secs + b.secs end end
    if coarse_secs > fine_secs then bins, take, unit = ring.bins, coarse_take, true end
  end
  for _, b in pairs(bins) do
    if take(b) then
      nfull = nfull + (unit and b.secs or 1)
      for s, recs in pairs(b.rec) do
        if not sidx or s == sidx then
          for r, a in pairs(recs) do
            local x = rc[r]
            if not x then x = { c = 0, p = 0 }; rc[r] = x end
            x.c = x.c + a.c
            x.p = x.p + a.p
          end
        end
      end
      for s, keys in pairs(b.stat) do
        if not sidx or s == sidx then
          for k, a in pairs(keys) do
            local x = st[k]
            if not x then x = { i = 0, o = 0 }; st[k] = x end
            x.i = x.i + a.i
            x.o = x.o + a.o
          end
        end
      end
    end
  end
  local secs = nfull * BIN_TICKS / 60
  local out = { recipes = {}, nodes = {} }
  if secs > 0 then
    for r, x in pairs(rc) do
      out.recipes[r] = { cps = x.c / secs, prod = (x.c > 0) and (x.p / x.c) or 0 }
    end
    for k, x in pairs(st) do
      out.nodes[k] = { prod = x.i / secs, cons = x.o / secs }
    end
  end
  return out, secs
end

function Sm.machine_counts(sidx)
  local m = {}
  for _, rec in pairs(storage.machines) do
    if rec.r and (not sidx or rec.s == sidx) then m[rec.r] = (m[rec.r] or 0) + 1 end
  end
  return m
end

-- capacity in NORMAL crafts/s per recipe if every machine ran at 100 % (Balance tab)
function Sm.capacity(sidx)
  local g = storage.graph
  local cap = {}
  for _, rec in pairs(storage.machines) do
    if rec.r and (not sidx or rec.s == sidx) then
      local r = g and g.recipes[rec.r]
      local energy = r and r.energy or 0
      if energy > 0 and rec.spd then cap[rec.r] = (cap[rec.r] or 0) + rec.spd / energy end
    end
  end
  return cap
end

---------------------------------------------------------------------------
-- physical chest stock (bounded across ticks; all qualities)
---------------------------------------------------------------------------
function Sm.on_stock(tick) ChestStock.request(tick) end
function Sm.stock_known(sidx) return ChestStock.known(sidx) end
function Sm.stock_status() return ChestStock.status() end
function Sm.stock_surfaces()
  local h=storage.stock or {};local last=h[#h];local out={}
  if last then for index,totals in pairs(last.s) do if next(totals) then out[index]=true end end end
  return out
end

-- { [key] = { count = now, per_min = trend } }
function Sm.stock(sidx)
  local h = storage.stock or {}
  local out = {}
  local last, first = h[#h], h[1]
  if not last then return out end
  local function sum(snap)
    local t = {}
    for s, tot in pairs(snap.s) do
      if not sidx or s == sidx then
        for k, c in pairs(tot) do t[k] = (t[k] or 0) + c end
      end
    end
    return t
  end
  local now, old = sum(last), sum(first)
  local mins = (last.tick - first.tick) / 3600
  for k, c in pairs(now) do
    out[k] = { count = c, per_min = (mins > 0) and ((c - (old[k] or 0)) / mins) or nil }
  end
  for k, c in pairs(old) do
    if not out[k] and mins > 0 then out[k] = { count = 0, per_min = -c / mins } end
  end
  return out
end

function Sm.status()
  return {
    tracked = #storage.mlist,
    per_tick = settings.global["ssk-entities-per-tick"].value,
    cycle = storage.cycle.last,
    window = storage.nbins,
  }
end

---------------------------------------------------------------------------
-- /sankey-probe : verify what products_finished counts
---------------------------------------------------------------------------
local PROBE_TICKS = 600

function Sm.probe_start(player)
  local e = player.selected
  if not (e and e.valid and TYPESET[e.type]) then
    player.print("[Production Flow] Hover a crafting machine (running at full speed, not output-blocked) and run /sankey-probe again.")
    return
  end
  local r = Sm.current_recipe(e)
  local fr = r and e.force.recipes[r]
  storage.probes[#storage.probes + 1] = {
    player = player.index, e = e, recipe = r, pf = e.products_finished, tick = game.tick,
  }
  log(string.format("probe start: %s unit %d recipe %s speed %.3f entity_prod %.3f force_recipe_prod %.3f pf %d",
    e.name, e.unit_number, tostring(r), e.crafting_speed, e.productivity_bonus or 0, fr and fr.productivity_bonus or 0, e.products_finished))
  player.print(string.format(
    "[Production Flow] Probing [entity=%s] recipe=%s  crafting_speed=%.3f  entity.productivity_bonus=%.3f  force recipe productivity_bonus=%.3f  products_finished=%d. Result in %d s...",
    e.name, tostring(r), e.crafting_speed, e.productivity_bonus or 0, fr and fr.productivity_bonus or 0,
    e.products_finished, PROBE_TICKS / 60))
end

function Sm.probe_tick(tick)
  local keep = {}
  for _, p in ipairs(storage.probes) do
    if tick - p.tick < PROBE_TICKS then
      keep[#keep + 1] = p
    else
      local player = game.get_player(p.player)
      local e = p.e
      if player and e.valid and p.recipe then
        local proto = prototypes.recipe[p.recipe]
        local secs = (tick - p.tick) / 60
        local d = e.products_finished - p.pf
        local base = e.crafting_speed * secs / proto.energy
        local prod = e.productivity_bonus or 0
        local verdict
        if base <= 0 then verdict = "?"
        elseif prod < 0.05 then
          verdict = "INCONCLUSIVE: machine has no productivity bonus - probe one with productivity modules"
        elseif math.abs(d / base - 1) < math.abs(d / (base * (1 + prod)) - 1) then
          verdict = "counts NORMAL crafts only (assumption holds)"
        else
          verdict = "INCLUDES productivity bonus crafts (flip PF_INCLUDES_BONUS)"
        end
        log(string.format("probe result: %s recipe %s pf +%d in %.0fs, expected %.2f normal / %.2f incl bonus, prod %.3f -> %s",
          e.name, p.recipe, d, secs, base, base * (1 + prod), prod, verdict))
        player.print(string.format(
          "[Production Flow] Probe result: products_finished +%d in %.0f s. Expected at 100%% uptime: %.1f normal / %.1f incl. bonus (prod %.0f%%). Ratio %.3f -> %s",
          d, secs, base, base * (1 + prod), prod * 100, base > 0 and d / base or 0, verdict))
      end
    end
  end
  storage.probes = keep
end

return Sm
