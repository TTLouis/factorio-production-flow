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
local STATUS_TICKS = 300
local PREVIEW_CHECKS = 32

local entity_status = defines and defines.entity_status
local status_categories = {}
if entity_status then
  local categories = {
    input = { "item_ingredient_shortage", "fluid_ingredient_shortage", "no_ingredients",
              "input_fluid_too_cold", "input_fluid_too_hot" },
    output = { "full_output", "full_burnt_result_output", "waiting_for_space_in_destination",
               "waiting_for_space_in_platform_hub" },
    power = { "no_power", "low_power", "no_fuel", "low_temperature", "no_input_fluid" },
  }
  for category, names in pairs(categories) do
    for _, name in ipairs(names) do
      local status = entity_status[name]
      if status ~= nil then status_categories[status] = category end
    end
  end
end

-- Saved-state keys remain compact for compatibility with existing saves.
-- Material keys use "item/<name>" or "fluid/<name>"; recipe keys are bare names.
---@class ProductionFlowMachine
---@field e LuaEntity Tracked entity; validity is checked when sampled.
---@field u integer Unit number, also the key in storage.machines.
---@field s integer Surface index captured on registration.
---@field r string? Recipe observed at the previous sample.
---@field pf number Previous products_finished counter.
---@field spd number Last observed crafting speed.
---@field silo boolean? Whether rocket-part accounting applies.
---@field rp number? Previous rocket_parts counter.
---@field req number? Rocket parts required per rocket.
---@field status_due integer? Earliest tick to observe status again unless the recipe changes.
---@field status_row table? Shared recipe status aggregate for this machine's last observation.
---@field status_surface integer? Last observed surface for status.
---@field status_force integer? Last observed force for status.
---@field issue string? Last observed category of production issue.

---@class ProductionFlowRecipeSample
---@field c number Completed crafts, including productivity bonus crafts.
---@field p number Sum of completed crafts multiplied by productivity bonus.

---@class ProductionFlowNodeSample
---@field i number Produced quantity (statistics input_counts).
---@field o number Consumed quantity (statistics output_counts).

---@class ProductionFlowHistoryBin
---@field id integer Absolute bin index, not the ring slot.
---@field secs number? Recorded seconds in coarse bins; absent in fine bins.
---@field rec table<integer, table<string, ProductionFlowRecipeSample>> Surface -> recipe -> sample.
---@field stat table<integer, table<string, ProductionFlowNodeSample>> Surface -> material -> sample.

-- Query results are new tables; callers may use them without mutating history.
---@class ProductionFlowRecipeRate
---@field cps number Completed crafts per second, including productivity bonuses.
---@field prod number Craft-weighted productivity bonus, not a production rate.

---@class ProductionFlowNodeRate
---@field prod number Produced material units per second.
---@field cons number Consumed material units per second.

---@class ProductionFlowRates
---@field recipes table<string, ProductionFlowRecipeRate> Indexed by recipe name.
---@field nodes table<string, ProductionFlowNodeRate> Indexed by material key.

---@class ProductionFlowStockEntry
---@field count number Latest completed scan quantity, all qualities combined.
---@field per_min number? Change per game minute; absent without elapsed history.

-- Verified on a real base (v0.0.7 export): products_finished INCLUDES productivity bonus crafts.
-- normal crafts = pf / (1 + prod); inputs = normal * amount; outputs = normal * (amount + eligible * prod)
Sm.PF_INCLUDES_BONUS = true

Sm.TYPES = TYPES

---------------------------------------------------------------------------
-- storage
---------------------------------------------------------------------------
local function nbins()
  -- Keep 10 minutes of completed samples plus the currently accumulating bin.
  return math.max(600, settings.global["ssk-window-seconds"].value) + 1
end

local function init_machine_status()
  if not storage.machine_status then
    storage.machine_status = {} -- surface -> force -> recipe
    storage.machine_status_partial_pass = storage.mcursor > 1 or nil
  end
end

local init_rings

function Sm.init()
  ChestStock.init()
  storage.machines = storage.machines or {} -- unit_number -> {e, u, s, r, pf}
  storage.mlist = storage.mlist or {}       -- array of unit_numbers (round-robin order)
  storage.mcursor = storage.mcursor or 1
  init_machine_status()
  storage.stat_last = storage.stat_last or {} -- [surface][key] = cumulative {i, o}
  storage.cycle = storage.cycle or { start = game.tick, last = 0 }
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
  init_rings()
end

Sm.PERIODS = { 60, 600, 3600, 36000, 180000, 900000, 3600000 }
Sm.DEFAULT_PERIOD = 600
Sm.PERIOD_CAPTIONS = { "1m", "10m", "1H", "10H", "50H", "250H", "1000H" }

local RING_SPECS = { {60, 60}, {600, 60}, {3600, 51}, {18000, 51}, {72000, 51} }

function Sm.duration(seconds)
  if seconds >= 3600 then
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    return hours .. " h" .. (minutes > 0 and " " .. minutes .. " min" or "")
  end
  if seconds >= 60 then
    local minutes, remainder = math.floor(seconds / 60), math.floor(seconds % 60)
    return minutes .. " min" .. (remainder > 0 and " " .. remainder .. " s" or "")
  end
  return string.format("%d s", math.floor(seconds))
end

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

local function add_to_ring(ring, source, source_seconds)
  local id = math.floor(source.id * source_seconds / ring.secs)
  local slot = id % ring.n + 1
  local bin = ring.bins[slot]
  if not bin or bin.id ~= id then
    bin = { id = id, secs = 0, rec = {}, stat = {} }
    ring.bins[slot] = bin
  end
  bin.secs = bin.secs + source_seconds
  add_into(bin, source)
  return bin
end

init_rings = function()
  local rings = storage.rings or {}
  storage.rings = rings
  for i, spec in ipairs(RING_SPECS) do
    if not rings[i] then
      local ring = { secs = spec[1], n = spec[2], bins = {} }
      rings[i] = ring
      local previous = rings[i - 1]
      if previous then
        -- Seed upgrades from completed retained bins. The current partial bin
        -- will be sent onward by the normal rollup when it completes.
        local completed = {}
        for _, bin in pairs(previous.bins) do
          if bin.secs == previous.secs then completed[#completed + 1] = bin end
        end
        table.sort(completed, function(a, b) return a.id < b.id end)
        for _, bin in ipairs(completed) do add_to_ring(ring, bin, previous.secs) end
      end
    end
  end
end

local function roll_up(b)
  if not storage.rings or #storage.rings < #RING_SPECS then init_rings() end
  local rings = storage.rings
  local seconds = BIN_TICKS / 60
  add_to_ring(rings[1], b, seconds)
  local bin = add_to_ring(rings[2], b, seconds)
  -- Keep the 1h and 10h resolutions up to date as before. The longer rings
  -- receive completed lower-resolution bins instead of processing every second.
  for i = 3, #rings do
    local span = rings[i - 1].secs
    if bin.secs ~= span then break end
    bin = add_to_ring(rings[i], bin, span)
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
  storage.machine_status, storage.machine_status_ready, storage.machine_status_partial_pass = {}, nil, nil
  for _, s in pairs(game.surfaces) do
    for _, e in pairs(s.find_entities_filtered { type = TYPES }) do Sm.add(e) end
  end
  storage.cycle = { start = game.tick, last = 0 }
  return #storage.mlist
end

local function remove_issue(row, category, unit)
  if not category then return end
  local issue = row.issues[category]
  issue.count = issue.count - 1
  issue.units[unit] = nil
  if issue.latest_unit == unit then issue.latest_unit = nil end
  if issue.count == 0 then row.issues[category] = nil end
end

local function remove_observation(rec)
  local row = rec.status_row
  if not row then return end
  remove_issue(row, rec.issue, rec.u)
  row.observed = row.observed - 1
  if row.observed == 0 then
    local surfaces = storage.machine_status
    local forces = surfaces[rec.status_surface]
    local recipes = forces[rec.status_force]
    recipes[rec.r] = nil
    if not next(recipes) then forces[rec.status_force] = nil end
    if not next(forces) then surfaces[rec.status_surface] = nil end
  end
  rec.status_row, rec.status_surface, rec.status_force, rec.issue = nil, nil, nil, nil
end

local function observe_status(rec, e, recipe, tick)
  rec.status_due = tick + STATUS_TICKS
  if not recipe then
    remove_observation(rec)
    return
  end
  local surface, force = e.surface_index, e.force_index
  if rec.r ~= recipe or rec.status_surface ~= surface or rec.status_force ~= force then
    remove_observation(rec)
  end
  local row = rec.status_row
  if not row then
    local forces = storage.machine_status[surface]
    if not forces then forces = {}; storage.machine_status[surface] = forces end
    local recipes = forces[force]
    if not recipes then recipes = {}; forces[force] = recipes end
    row = recipes[recipe]
    if not row then row = { observed = 0, issues = {} }; recipes[recipe] = row end
    row.observed = row.observed + 1
    rec.status_row, rec.status_surface, rec.status_force = row, surface, force
  end
  row.sample_tick = tick
  local category = status_categories[e.status]
  if category ~= rec.issue then
    remove_issue(row, rec.issue, rec.u)
    if category then
      local issue = row.issues[category]
      if not issue then issue = { count = 0, units = {} }; row.issues[category] = issue end
      issue.count = issue.count + 1
      issue.units[rec.u] = true
    end
    rec.issue = category
  end
  if category then row.issues[category].latest_unit = rec.u end
end

---------------------------------------------------------------------------
-- per-tick sampling
---------------------------------------------------------------------------
function Sm.on_tick(tick)
  ChestStock.tick(tick)
  local list = storage.mlist
  if #list == 0 then return end
  init_machine_status() -- Also supports loading a save made before status sampling was added.
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
      if storage.machine_status_partial_pass then
        storage.machine_status_partial_pass = nil
      elseif not storage.machine_status_ready then
        storage.machine_status_ready = true
      end
    end
    local u = list[cur]
    local rec = machines[u]
    local e = rec and rec.e
    if not (e and e.valid) then
      if rec then remove_observation(rec) end
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
      if entity_status and (r ~= rec.r or not rec.status_due or tick >= rec.status_due) then
        observe_status(rec, e, r, tick)
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
local function source_bins(bins, size, sidx, start_tick, end_tick, stats_only)
  local sources = {}
  local width = size * 60
  for _, bin in pairs(bins) do
    local first = bin.id * width
    local last = first + width
    if first < end_tick and last <= end_tick and last > start_tick and (size == 1 or bin.secs == size) then
      local known = not stats_only or (sidx and bin.stat[sidx] ~= nil) or (not sidx and next(bin.stat) ~= nil)
      sources[#sources + 1] = { first = first, last = last, bin = bin, known = known }
    end
  end
  table.sort(sources, function(a, b) return a.first < b.first end)
  return sources
end

-- The resolutions nest on the same absolute time grid. Use the finer bins if
-- they cover the interval, or if they record a gap the coarse total cannot locate.
local function merge_sources(fine, coarse, start_tick)
  local result, index = {}, 1
  for _, wide in ipairs(coarse) do
    while fine[index] and fine[index].first < wide.first do
      result[#result + 1] = fine[index]
      index = index + 1
    end
    local first, covered, known, missing = index, 0, false, false
    while fine[index] and fine[index].first < wide.last do
      local narrow = fine[index]
      covered = covered + narrow.last - math.max(narrow.first, start_tick)
      known = known or narrow.known
      missing = missing or not narrow.known
      index = index + 1
    end
    local duration = wide.last - math.max(wide.first, start_tick)
    if covered == duration or (wide.known and missing) or (not wide.known and known) then
      for i = first, index - 1 do result[#result + 1] = fine[i] end
    else
      result[#result + 1] = wide
    end
  end
  for i = index, #fine do result[#result + 1] = fine[i] end
  return result
end

function Sm.history_sources(sidx, start_tick, end_tick, stats_only)
  local sources = source_bins(storage.bins or {}, 1, sidx, start_tick, end_tick, stats_only)
  for _, ring in ipairs(storage.rings or {}) do
    local coarse = source_bins(ring.bins, ring.secs, sidx, start_tick, end_tick, stats_only)
    sources = merge_sources(sources, coarse, start_tick)
  end
  return sources
end

-- returns {recipes = {[r] = {cps, prod}}, nodes = {[key] = {prod, cons}}}, seconds
-- period: seconds to average over (nil / 0 = the fine rate window)
---@param sidx integer? Surface index; nil combines all recorded surfaces.
---@param period number? Requested observation period in seconds.
---@return ProductionFlowRates rates
---@return number seconds Actual recorded duration used as the denominator.
function Sm.rates(sidx, period)
  local now_id = math.floor(game.tick / BIN_TICKS)
  local rc, st, secs = {}, {}, 0
  local requested = period and period > 0 and period or settings.global["ssk-window-seconds"].value
  local first_id = now_id - requested
  local function accumulate(bin, fraction)
    for s, recs in pairs(bin.rec) do
      if not sidx or s == sidx then
        for r, a in pairs(recs) do
          local x = rc[r]
          if not x then x = { c = 0, p = 0 }; rc[r] = x end
          x.c = x.c + a.c * fraction
          x.p = x.p + a.p * fraction
        end
      end
    end
    for s, keys in pairs(bin.stat) do
      if not sidx or s == sidx then
        for k, a in pairs(keys) do
          local x = st[k]
          if not x then x = { i = 0, o = 0 }; st[k] = x end
          x.i = x.i + a.i * fraction
          x.o = x.o + a.o * fraction
        end
      end
    end
  end
  local bins, fine_secs = storage.bins, 0
  for _, bin in pairs(bins) do
    if bin.id >= first_id and bin.id < now_id then fine_secs = fine_secs + 1 end
  end
  if fine_secs == requested or not period or period <= 0 or not storage.rings then
    secs = fine_secs
    for _, bin in pairs(bins) do
      if bin.id >= first_id and bin.id < now_id then accumulate(bin, 1) end
    end
  else
    local start_tick = first_id * BIN_TICKS
    for _, source in ipairs(Sm.history_sources(sidx, start_tick, now_id * BIN_TICKS)) do
      local ticks = source.last - math.max(source.first, start_tick)
      accumulate(source.bin, ticks / (source.last - source.first))
      secs = secs + ticks / 60
    end
  end
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

---@param sidx integer? Surface index; nil combines all registered surfaces.
---@return table<string, integer> counts Recipe name -> registered machine count.
function Sm.machine_counts(sidx)
  local m = {}
  for _, rec in pairs(storage.machines) do
    if rec.r and (not sidx or rec.s == sidx) then m[rec.r] = (m[rec.r] or 0) + 1 end
  end
  return m
end

-- Read-only view of the latest staggered observations, with first-pass state.
function Sm.machine_status(sidx, force)
  local surfaces = storage.machine_status
  local forces = surfaces and surfaces[sidx]
  local warming = not storage.machine_status_ready and storage.mlist and #storage.mlist > 0
  return forces and forces[force], warming
end

function Sm.status_machine(unit, sidx, force, recipe, category)
  local rec = storage.machines[unit]
  local e = rec and rec.e
  if e and e.valid and e.surface_index == sidx and e.force_index == force
     and status_categories[e.status] == category and Sm.current_recipe(e) == recipe then
    return e
  end
end

function Sm.find_status_machine(sidx, force, recipe, category)
  local recipes = Sm.machine_status(sidx, force)
  local row = recipes and recipes[recipe]
  local issue = row and row.issues[category]
  if not issue then return end
  local latest = issue.latest_unit
  if latest then
    local e = Sm.status_machine(latest, sidx, force, recipe, category)
    if e then return e end
  end
  local checked = 0
  for unit in pairs(issue.units) do
    if unit ~= latest then
      local e = Sm.status_machine(unit, sidx, force, recipe, category)
      if e then return e end
      checked = checked + 1
      if checked == PREVIEW_CHECKS then return end
    end
  end
end

-- capacity in NORMAL crafts/s per recipe if every machine ran at 100 % (Balance tab)
---@param sidx integer? Surface index; nil combines all registered surfaces.
---@return table<string, number> capacity Recipe name -> normal crafts per second.
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
function Sm.on_stock_interval_changed() ChestStock.reschedule() end
function Sm.stock_surfaces()
  local h=storage.stock or {};local last=h[#h];local out={}
  if last then for index,totals in pairs(last.s) do if next(totals) then out[index]=true end end end
  return out
end

-- { [key] = { count = now, per_min = trend } }
---@param sidx integer? Surface index; nil combines all scanned surfaces.
---@return table<string, ProductionFlowStockEntry> stock Indexed by material key.
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

return Sm
