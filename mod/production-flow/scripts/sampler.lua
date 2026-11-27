-- M2: entity registry + round-robin sampler (D6, D7)
--
-- Edge measurement : products_finished deltas per crafting machine, attributed to the
--                    recipe seen at BOTH ends of the interval (changed recipe -> discard).
-- Node totals      : force production statistics, cumulative-count deltas per surface.
-- Both go into a ring of 1-second bins; rates are averaged over the full bins.

local Sm = {}
local ChestStock = require("scripts.chest_stock")
local CANVAS_SURFACE = require("scripts.canvas").SURFACE

local function empty_stats()
  storage.empty_stat = storage.empty_stat or {}
  return storage.empty_stat
end

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
---@field pb number? Previous productivity bonus.
---@field cp number? Previous crafting progress, sampled on productive machines.
---@field bp number? Previous productivity bar progress, sampled on productive machines.
---@field spd number Last observed crafting speed.
---@field n string? Entity name, kept by recipe tooltips after their first read.
---@field q string? Quality name, kept with n.
---@field silo boolean? Whether rocket-part accounting applies.
---@field rp number? Previous rocket_parts counter.
---@field req number? Rocket parts required per rocket.
---@field status_due integer? Earliest tick to observe status again unless the recipe changes.
---@field status_row table? Shared recipe status aggregate for this machine's last observation.
---@field status_entity string? Prototype counted in the recipe's observed machine types.
---@field status_surface integer? Last observed surface for status.
---@field status_force integer? Last observed force for status.
---@field issue string? Last observed category of production issue.

---@class ProductionFlowRecipeSample
---@field c number Completed crafts, including productivity bonus crafts.
---@field n number? Normal crafts.
---@field p number? Legacy sum of completed crafts multiplied by productivity bonus.

---@class ProductionFlowNodeSample
---@field i number Produced quantity (statistics input_counts).
---@field o number Consumed quantity (statistics output_counts).

---@class ProductionFlowHistoryBin
---@field id integer Absolute bin index, not the ring slot.
---@field secs number? Recorded seconds in coarse bins; absent in fine bins.
---@field first integer? First observed second in a coarse bin.
---@field last integer? End of the last observed second in a coarse bin.
---@field coverage table<integer, integer[]>? Observed statistics runs as start/end pairs, with 0 for any surface.
---@field rec table<integer, table<string, ProductionFlowRecipeSample>> Surface -> recipe -> sample.
---@field stat table<integer, table<string, ProductionFlowNodeSample>> Surface -> material -> sample.

-- Query results are new tables; callers may use them without mutating history.
---@class ProductionFlowRecipeRate
---@field cps number Completed crafts per second, including productivity bonuses.
---@field normal_cps number Completed crafts per second that consumed ingredients.

---@class ProductionFlowNodeRate
---@field prod number Produced material units per second.
---@field cons number Consumed material units per second.

---@class ProductionFlowRates
---@field recipes table<string, ProductionFlowRecipeRate> Indexed by recipe name.
---@field nodes table<string, ProductionFlowNodeRate> Indexed by material key.

---@class ProductionFlowStockEntry
---@field count number Latest completed scan quantity, all qualities combined.
---@field per_min number? Change per game minute; absent without elapsed history.

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
  empty_stats()
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
local Loc = require("scripts.locale")
Sm.PERIOD_CAPTIONS = { Loc("period-minute", 1), Loc("period-minute", 10),
  Loc("period-hour", 1), Loc("period-hour", 10), Loc("period-hour", 50),
  Loc("period-hour", 250), Loc("period-hour", 1000) }

local RING_SPECS = { {60, 60}, {600, 60}, {3600, 51}, {18000, 51}, {72000, 51} }

function Sm.duration(seconds)
  if seconds >= 3600 then
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    return minutes > 0 and Loc("duration-hours-minutes", hours, minutes) or Loc("duration-hours", hours)
  end
  if seconds >= 60 then
    local minutes, remainder = math.floor(seconds / 60), math.floor(seconds % 60)
    return remainder > 0 and Loc("duration-minutes-seconds", minutes, remainder) or Loc("duration-minutes", minutes)
  end
  return Loc("duration-seconds", math.floor(seconds))
end

function Sm.normal_crafts(sample)
  if sample.n then return sample.n end
  if sample.c == 0 then return 0 end
  -- Older bins only recorded the total and a craft-weighted productivity bonus.
  return sample.c / (1 + sample.p / sample.c)
end

local function add_crafts(recipes, name, total, normal)
  local sample = recipes[name]
  if sample then
    sample.n = Sm.normal_crafts(sample) + normal
    sample.c = sample.c + total
    sample.p = nil
  else
    recipes[name] = { c = total, n = normal }
  end
end

local function add_cells(dst, src, field)
  local cells = src[field]
  if not cells then return end
  local out = dst[field]
  if not out then out = {}; dst[field] = out end
  for id, recs in pairs(cells) do
    local d = out[id]
    if not d then d = {}; out[id] = d end
    for r, a in pairs(recs) do add_crafts(d, r, a.c, a.n) end
  end
end

local function add_into(dst, src)
  local empty = empty_stats()
  for s, recs in pairs(src.rec) do
    local d = dst.rec[s]
    if not d then d = {}; dst.rec[s] = d end
    for r, a in pairs(recs) do
      add_crafts(d, r, a.c, Sm.normal_crafts(a))
    end
  end
  -- Production cells: bin.cell[id][recipe] holds every member's crafts and
  -- bin.cell_shared[id][recipe] the part made by machines in several siblings.
  add_cells(dst, src, "cell")
  add_cells(dst, src, "cell_shared")
  for s, keys in pairs(src.stat) do
    local d = dst.stat[s]
    if not d then d = empty; dst.stat[s] = d end
    for k, a in pairs(keys) do
      if d == empty then d = {}; dst.stat[s] = d end
      local x = d[k]
      if not x then x = { i = 0, o = 0 }; d[k] = x end
      x.i = x.i + a.i
      x.o = x.o + a.o
    end
  end
end

local function add_run(coverage, surface, first, last)
  local runs = coverage[surface]
  if not runs then
    coverage[surface] = { first, last }
  elseif runs[#runs] == first then
    runs[#runs] = last
  else
    runs[#runs + 1], runs[#runs + 2] = first, last
  end
end

local function add_coverage(coverage, stat, first, last)
  if next(stat) then add_run(coverage, 0, first, last) end
  for surface in pairs(stat) do add_run(coverage, surface, first, last) end
end

local function legacy_coverage(bin, first, last, source_width)
  local coverage = {}
  if source_width == 1 then
    -- The active minute and ten-minute buckets fit in the fine ring. On the
    -- first append after an upgrade, recover each surface's observed runs.
    for second = first, last - 1 do
      local fine = storage.bins[second % storage.nbins + 1]
      if not fine or fine.id ~= second then
        coverage = {}
        add_coverage(coverage, bin.stat, first, last)
        return coverage
      end
      add_coverage(coverage, fine.stat, second, second + 1)
    end
  else
    add_coverage(coverage, bin.stat, first, last)
  end
  return coverage
end

local function add_to_ring(ring, source, source_width)
  local source_end = source.last or (source.id + 1) * source_width
  local seconds = source.secs or source_width
  local source_start = source.first or source_end - seconds
  local id = math.floor(source.id * source_width / ring.secs)
  local slot = id % ring.n + 1
  local bin = ring.bins[slot]
  if not bin or bin.id ~= id then
    bin = { id = id, secs = 0, rec = {}, stat = {}, first = source_start, coverage = {} }
    ring.bins[slot] = bin
  elseif not bin.coverage then
    -- An old active bin only recorded duration. Preserve its accumulated prefix
    -- before appending observations from the new sampler.
    bin.first = source_start - bin.secs
    bin.coverage = legacy_coverage(bin, bin.first, source_start, source_width)
  end
  if source.coverage then
    for surface, runs in pairs(source.coverage) do
      for i = 1, #runs, 2 do add_run(bin.coverage, surface, runs[i], runs[i + 1]) end
    end
  else
    add_coverage(bin.coverage, source.stat, source_start, source_end)
  end
  bin.secs = bin.secs + seconds
  bin.last = source_end
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
        -- Seed upgrades from closed retained bins. The active bin will be
        -- sent onward by the normal rollup when its interval ends.
        local active = math.floor((storage.last_bin_id or game.tick / BIN_TICKS) / previous.secs)
        local completed = {}
        for _, bin in pairs(previous.bins) do
          if bin.id < active then completed[#completed + 1] = bin end
        end
        table.sort(completed, function(a, b) return a.id < b.id end)
        for _, bin in ipairs(completed) do add_to_ring(ring, bin, previous.secs) end
      end
    end
  end
end

local function roll_up(b, next_id)
  if not storage.rings or #storage.rings < #RING_SPECS then init_rings() end
  local rings = storage.rings
  local seconds = BIN_TICKS / 60
  add_to_ring(rings[1], b, seconds)
  local bin = add_to_ring(rings[2], b, seconds)
  -- Keep the 1h and 10h resolutions up to date as before. The longer rings
  -- receive each closed lower-resolution bin once, including partial bins.
  for i = 3, #rings do
    local span = rings[i - 1].secs
    if bin.id == math.floor(next_id / span) then break end
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
      if prev and prev.id == pid then roll_up(prev, id) end
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
  if r then return r.name, r end
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

local function craft_productivity(e, name, force_recipe, recipe)
  if not name then return 0 end
  if not force_recipe then
    -- A furnace can finish its last craft and report only its previous recipe.
    local force = e.force
    force_recipe = force and force.recipes[name]
  end
  local bonus = (e.productivity_bonus or 0) + (force_recipe and force_recipe.productivity_bonus or 0)
  if bonus <= 0 then return 0 end
  -- Recipe research is separate from the entity's effects. Cap the combined bonus.
  return math.min(bonus, recipe and recipe.max_productivity or bonus)
end

Sm.craft_productivity = craft_productivity

-- Registry scans call this for every machine. Comparing `force_index` avoids
-- creating a LuaForce wrapper and an `__eq` bridge call per entity; callers
-- that loop pass the player force and its index once.
local function player_machine(e, player_force, player_force_index)
  local force = player_force
  if not force then
    force = game.forces and game.forces.player
    player_force_index = force and force.index
  end
  if not (force and e and e.valid) then return false end
  if player_force_index then
    local index = e.force_index
    if index ~= nil then return index == player_force_index end
  end
  return e.force == force
end

local function player_scope()
  local force = game.forces and game.forces.player
  return force, force and force.index
end

local function seed_machine(rec,e)
  local name,force_recipe=Sm.current_recipe(e)
  local recipes=storage.graph and storage.graph.recipes
  rec.s,rec.r,rec.pf,rec.spd=e.surface.index,name,e.products_finished,e.crafting_speed
  rec.pb=craft_productivity(e,name,force_recipe,recipes and recipes[name])
  rec.cp,rec.bp=nil,nil
  if rec.pb>0 then rec.cp,rec.bp=e.crafting_progress,e.bonus_progress end
  rec.eligible=true
  if e.type=='rocket-silo' then
    rec.silo=true;rec.rp=e.rocket_parts;rec.req=e.prototype.rocket_parts_required or 50
  end
end

function Sm.add(e)
  ChestStock.add(e)
  if not (e and e.valid and TYPESET[e.type]) then return end
  local u = e.unit_number
  if not u or storage.machines[u] then return end
  -- Retain foreign entities only as budgeted ownership-change candidates: the
  -- runtime has no generic entity-force-changed event. Never sample their crafts.
  local rec = {e=e,u=u,s=e.surface.index,eligible=false}
  if player_machine(e) then seed_machine(rec,e) end
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
  local name = rec.status_entity
  if name then
    local remaining = ((row.entities and row.entities[name]) or 1) - 1
    row.entities = row.entities or {}
    row.entities[name] = remaining > 0 and remaining or nil
    rec.status_entity = nil
  end
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
  if e.name and not rec.status_entity then
    row.entities = row.entities or {}
    row.entities[e.name] = (row.entities[e.name] or 0) + 1
    rec.status_entity = e.name
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
local function normal_crafts_between(rec, total, productivity, crafting, bonus, speed, recipe)
  if productivity > 0 and rec.pb == productivity and rec.bp and bonus then
    -- Each normal craft (including partial progress) adds productivity to the
    -- bonus bar. Each bonus craft subtracts one and is also in the total.
    local divisor = 1 + productivity
    local wraps = ((total + crafting - rec.cp) * productivity + rec.bp - bonus) / divisor
    local lower, upper = wraps - 1e-4, wraps + 1e-4
    if (rec.bp == 1 or bonus == 1) and recipe and recipe.energy > 0 then
      -- The API clamps a pending payout to 1. The hidden overflow comes from
      -- the update that filled the bar, so allow up to one tick of progress.
      local scale = productivity / (60 * recipe.energy * divisor)
      if bonus == 1 then lower = lower - speed * scale end
      if rec.bp == 1 then upper = upper + rec.spd * scale end
    end
    local first = math.max(0, math.ceil(lower))
    local last = math.min(total, math.floor(upper))
    if first == last then return total - first end
  end
  -- A changed effect or interrupted progress can leave an ambiguous interval.
  return total / (1 + productivity)
end

local function sample_machine(rec, e, tick, bin, recipes, cell_units)
  local r, force_recipe = Sm.current_recipe(e)
  local recipe = recipes and recipes[r]
  local pf = e.products_finished
  local speed = e.crafting_speed
  local productivity = craft_productivity(e, r, force_recipe, recipe)
  local crafting, bonus
  if productivity > 0 then crafting, bonus = e.crafting_progress, e.bonus_progress end
  local rp
  if rec.silo then rp = e.rocket_parts end
  if r and r == rec.r then
    local d = pf - rec.pf
    -- rocket silo: products_finished counts rockets, so count parts instead
    if rec.silo then d = d * rec.req + (rp - (rec.rp or rp)) end
    if d > 0 then
      local bs = bin.rec[rec.s]
      if not bs then bs = {}; bin.rec[rec.s] = bs end
      local normal = normal_crafts_between(rec, d, productivity, crafting, bonus, speed, recipe)
      add_crafts(bs, r, d, normal)
      local cell_ids = cell_units and cell_units[rec.u]
      if cell_ids then
        local all = bin.cell
        if not all then all = {}; bin.cell = all end
        local shared = storage.cell_shared_units and storage.cell_shared_units[rec.u]
        for i = 1, #cell_ids do
          local id = cell_ids[i]
          local cr = all[id]
          if not cr then cr = {}; all[id] = cr end
          add_crafts(cr, r, d, normal)
          if shared and shared[id] then
            local sh = bin.cell_shared
            if not sh then sh = {}; bin.cell_shared = sh end
            local sr = sh[id]
            if not sr then sr = {}; sh[id] = sr end
            add_crafts(sr, r, d, normal)
          end
        end
      end
    end
  end
  if entity_status and (r ~= rec.r or not rec.status_due or tick >= rec.status_due) then
    observe_status(rec, e, r, tick)
  end
  rec.r, rec.pf = r, pf
  rec.pb, rec.cp, rec.bp = productivity, crafting, bonus
  rec.spd = speed
  if rec.silo then rec.rp = rp end
end

local function same_membership(previous, current, old_shared, new_shared)
  if not current or #previous ~= #current then return false end
  for i, id in ipairs(previous) do
    if id ~= current[i] or (old_shared and old_shared[id]) ~= (new_shared and new_shared[id]) then return false end
  end
  return true
end

-- Close changed machines' sample intervals against their old membership before
-- installing the new one. Use the same counters for surface and cell totals so
-- neither loses or repeats crafts when a cell changes between sampler visits.
function Sm.set_cell_membership(units, shared)
  local old_units, old_shared = storage.cell_units or {}, storage.cell_shared_units or {}
  if storage.nbins and storage.machines then
    local tick = game.tick
    local recipes = storage.graph and storage.graph.recipes
    local bin
    local function flush(unit)
      local rec = storage.machines[unit]
      if not (rec and player_machine(rec.e)) then return end
      if rec.eligible ~= true then
        remove_observation(rec)
        seed_machine(rec, rec.e)
        return
      end
      if not bin then
        init_machine_status()
        bin = cur_bin(tick)
      end
      sample_machine(rec, rec.e, tick, bin, recipes, old_units)
    end
    for unit, ids in pairs(old_units) do
      if not same_membership(ids, units and units[unit], old_shared[unit], shared and shared[unit]) then flush(unit) end
    end
    for unit in pairs(units or {}) do
      if not old_units[unit] then flush(unit) end
    end
  end
  storage.cell_units, storage.cell_shared_units = units, shared
end

function Sm.on_tick(tick)
  ChestStock.tick(tick)
  local list = storage.mlist
  if #list == 0 then return end
  init_machine_status() -- Also supports loading a save made before status sampling was added.
  local per = settings.global["ssk-entities-per-tick"].value
  local bin = cur_bin(tick)
  local cur = storage.mcursor
  local machines = storage.machines
  local recipes = storage.graph and storage.graph.recipes
  local cell_units = storage.cell_units
  local player_force, player_force_index = player_scope()

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
    elseif not player_machine(e, player_force, player_force_index) then
      remove_observation(rec)
      rec.eligible,rec.r,rec.pf=false,nil,nil
      cur=cur+1
    elseif rec.eligible~=true then
      -- Do not count crafts completed while another force owned this machine.
      remove_observation(rec)
      seed_machine(rec,e)
      cur=cur+1
    else
      sample_machine(rec, e, tick, bin, recipes, cell_units)
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
  local empty = empty_stats()
  for _, s in pairs(game.surfaces) do
    if s.name ~= CANVAS_SURFACE then
      local last = storage.stat_last[s.index]
      local first = last == nil
      if first then last = {}; storage.stat_last[s.index] = last end
      -- An empty per-surface entry is a known-zero coverage marker. Keep it,
      -- but share the immutable map until this bin receives a positive delta.
      local out = bin.stat[s.index]
      if not out then out = empty; bin.stat[s.index] = out end
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
              if out == empty then out = {}; bin.stat[s.index] = out end
              local a = out[key]
              if not a then a = { i = 0, o = 0 }; out[key] = a end
              a[side] = a[side] + d
            end
          end
        end
      end
    end
  end
end

-- Called before deletion, while stock entities still expose their surface.
-- Factorio may reuse surface indexes; no retained sample or alert may follow
-- the removed surface into its replacement.
function Sm.on_surface_deleted(index)
  if storage.stat_last then storage.stat_last[index] = nil end
  local function purge(bin)
    if bin.rec then bin.rec[index] = nil end
    if bin.stat then bin.stat[index] = nil end
    if bin.coverage and bin.coverage[index] then
      bin.coverage[index] = nil
      -- The combined-surface duration is the union of surviving observations.
      local intervals = {}
      for surface, runs in pairs(bin.coverage) do
        if surface ~= 0 then
          for i = 1, #runs, 2 do intervals[#intervals + 1] = { runs[i], runs[i + 1] } end
        end
      end
      table.sort(intervals, function(a, b) return a[1] < b[1] end)
      local union = {}
      for _, span in ipairs(intervals) do
        if #union == 0 or span[1] > union[#union] then
          union[#union + 1], union[#union + 2] = span[1], span[2]
        else union[#union] = math.max(union[#union], span[2]) end
      end
      bin.coverage[0] = #union > 0 and union or nil
    end
  end
  for _, bin in pairs(storage.bins or {}) do purge(bin) end
  for _, ring in ipairs(storage.rings or {}) do
    for _, bin in pairs(ring.bins) do purge(bin) end
  end
  local removed = {}
  for unit, rec in pairs(storage.machines or {}) do
    if rec.s == index then
      remove_observation(rec)
      removed[unit], storage.machines[unit] = true, nil
    elseif rec.status_surface == index then
      remove_observation(rec)
      rec.status_due = nil
    end
  end
  if storage.machine_status then storage.machine_status[index] = nil end
  local list, cursor = {}, 1
  for i, unit in ipairs(storage.mlist or {}) do
    if not removed[unit] then
      list[#list + 1] = unit
      if i < (storage.mcursor or 1) then cursor = cursor + 1 end
    end
  end
  storage.mlist, storage.mcursor = list, cursor
  ChestStock.on_surface_deleted(index)
  -- Watch configuration belongs to each player's UI state. Purge only the
  -- deleted scope, preserving their favourites and other surfaces' thresholds.
  for _, us in pairs(storage.ui or {}) do
    if us.bal_watches then
      us.bal_watches[index] = nil
      if not next(us.bal_watches) then us.bal_watches = nil end
    end
  end
end

---------------------------------------------------------------------------
-- queries
---------------------------------------------------------------------------
local function source_bins(bins, size, sidx, start_tick, end_tick, stats_only, coarse_totals)
  local sources = {}
  local width = size * BIN_TICKS
  local complete_tick = math.floor(end_tick / BIN_TICKS) * BIN_TICKS
  for _, bin in pairs(bins) do
    local base = bin.id * width
    local limit = base + width
    local first = bin.first and bin.first * BIN_TICKS or base
    local last = bin.last and bin.last * BIN_TICKS or limit
    if size > 1 and not bin.last and bin.secs < size then
      -- Legacy closed partial buckets started recording late in the interval.
      -- Use an active legacy bucket for totals only if its whole prefix exists.
      if limit <= end_tick then
        first = last - bin.secs * BIN_TICKS
      elseif coarse_totals and base + bin.secs * BIN_TICKS == complete_tick then
        last = complete_tick
      end
    end
    if first < end_tick and last <= end_tick and last > start_tick then
      local runs = bin.coverage and bin.coverage[sidx or 0]
      local known = runs ~= nil or (not bin.coverage and
        (sidx and bin.stat[sidx] ~= nil or not sidx and next(bin.stat) ~= nil))
      -- Some older history contains crafts but has no production stats.
      if not known and not stats_only and not next(bin.stat) then
        known = (sidx and bin.rec[sidx] ~= nil) or (not sidx and next(bin.rec) ~= nil)
      end
      local scope_gap
      if runs then
        local from, to = runs[1] * BIN_TICKS, runs[#runs] * BIN_TICKS
        scope_gap = from > first or to < last or #runs > 2
        first, last = from, to
      end
      if last > start_tick then
        sources[#sources + 1] = { base = base, limit = limit, first = first, last = last,
          bin = bin, known = known, runs = runs, scope_gap = scope_gap }
      end
    end
  end
  table.sort(sources, function(a, b) return a.base < b.base end)
  return sources
end

local function source_ticks(source, start_tick)
  local runs = source.runs
  if not runs or #runs == 2 then return math.max(0, source.last - math.max(source.first, start_tick)) end
  local ticks = 0
  for i = 1, #runs, 2 do
    local first, last = runs[i] * BIN_TICKS, runs[i + 1] * BIN_TICKS
    ticks = ticks + math.max(0, last - math.max(first, start_tick))
  end
  return ticks
end

-- The resolutions nest on the same absolute time grid. Charts prefer detail.
-- Totals can use a whole coarse bucket unless the finer bins preserve more
-- coverage or avoid approximating the older edge of the requested window.
local function merge_sources(fine, coarse, start_tick, coarse_totals)
  local result, index = {}, 1
  for _, wide in ipairs(coarse) do
    while fine[index] and fine[index].base < wide.base do
      result[#result + 1] = fine[index]
      index = index + 1
    end
    local first, covered, missing = index, 0, false
    while fine[index] and fine[index].base < wide.limit do
      local narrow = fine[index]
      if narrow.known then covered = covered + source_ticks(narrow, start_tick) end
      missing = missing or not narrow.known or narrow.scope_gap
      index = index + 1
    end
    local duration = wide.known and source_ticks(wide, start_tick) or 0
    local need_detail = not coarse_totals or start_tick > wide.first
    if covered > duration or (covered == duration and need_detail)
      or (wide.known and missing and not wide.bin.coverage) then
      for i = first, index - 1 do result[#result + 1] = fine[i] end
    else
      result[#result + 1] = wide
    end
  end
  for i = index, #fine do result[#result + 1] = fine[i] end
  return result
end

local function select_sources(sidx, start_tick, end_tick, stats_only, coarse_totals, fine_only)
  local sources = source_bins(storage.bins or {}, 1, sidx, start_tick, end_tick, stats_only, coarse_totals)
  if not fine_only then
    for _, ring in ipairs(storage.rings or {}) do
      local coarse = source_bins(ring.bins, ring.secs, sidx, start_tick, end_tick, stats_only, coarse_totals)
      sources = merge_sources(sources, coarse, start_tick, coarse_totals)
    end
  end
  return sources
end

function Sm.history_sources(sidx, start_tick, end_tick, stats_only)
  local result = {}
  for _, source in ipairs(select_sources(sidx, start_tick, end_tick, stats_only)) do
    local runs = source.runs
    if runs and #runs > 2 then
      local duration = source_ticks(source, -math.huge)
      for i = 1, #runs, 2 do
        local first, last = runs[i] * BIN_TICKS, runs[i + 1] * BIN_TICKS
        if last > start_tick then
          result[#result + 1] = { first = first, last = last, duration = duration, bin = source.bin, known = true }
        end
      end
    else
      result[#result + 1] = source
    end
  end
  return result
end

local function rate_sources(sidx, period)
  local end_tick = math.floor(game.tick / BIN_TICKS) * BIN_TICKS
  local fine_only = not period or period <= 0
  local requested = fine_only and settings.global["ssk-window-seconds"].value or period
  local start_tick = end_tick - requested * BIN_TICKS
  return select_sources(sidx, start_tick, end_tick, false, true, fine_only), start_tick
end

function Sm.coverage(sidx, period)
  local sources, start_tick = rate_sources(sidx, period)
  local ticks = 0
  for _, source in ipairs(sources) do
    if source.known then ticks = ticks + source_ticks(source, start_tick) end
  end
  return ticks / BIN_TICKS
end

-- returns {recipes = {[r] = {cps, normal_cps}}, nodes = {[key] = {prod, cons}}}, seconds
-- period: seconds to average over (nil / 0 = the fine rate window)
---@param sidx integer? Surface index; nil combines all recorded surfaces.
---@param period number? Requested observation period in seconds.
---@return ProductionFlowRates rates
---@return number seconds Actual recorded duration used as the denominator.
function Sm.rates(sidx, period)
  local rc, st, secs = {}, {}, 0
  local function crafts(recs, fraction)
    for r, a in pairs(recs) do
      add_crafts(rc, r, a.c * fraction, Sm.normal_crafts(a) * fraction)
    end
  end
  local function totals(keys, fraction)
    for k, a in pairs(keys) do
      local x = st[k]
      if not x then x = { i = 0, o = 0 }; st[k] = x end
      x.i = x.i + a.i * fraction
      x.o = x.o + a.o * fraction
    end
  end
  local sources, start_tick = rate_sources(sidx, period)
  for _, source in ipairs(sources) do
    if source.known then
      local bin = source.bin
      local ticks = source_ticks(source, start_tick)
      local fraction = start_tick <= source.first and 1 or ticks / source_ticks(source, -math.huge)
      if sidx then
        if bin.rec[sidx] then crafts(bin.rec[sidx], fraction) end
        if bin.stat[sidx] then totals(bin.stat[sidx], fraction) end
      else
        for _, recs in pairs(bin.rec) do crafts(recs, fraction) end
        for _, keys in pairs(bin.stat) do totals(keys, fraction) end
      end
      secs = secs + ticks / BIN_TICKS
    end
  end
  local out = { recipes = {}, nodes = {} }
  if secs > 0 then
    for r, x in pairs(rc) do
      out.recipes[r] = { cps = x.c / secs, normal_cps = x.n / secs }
    end
    for k, x in pairs(st) do
      out.nodes[k] = { prod = x.i / secs, cons = x.o / secs }
    end
  end
  return out, secs
end

-- Measured crafts of one production cell. Attribution starts when the cell is
-- created, so the window is clipped to `since_tick`; a bin that straddles that
-- start holds only crafts made after it and is counted whole. With `exclusive`,
-- crafts by machines that also belong to another cell are left out.
---@return table<string, {cps:number, normal_cps:number}> recipes
---@return number seconds Measured duration used as the denominator.
---@return number requested Requested window in seconds.
function Sm.cell_rates(cell_id, sidx, period, since_tick, exclusive, pre_sources, pre_period_start)
  local sources, period_start
  if pre_sources then
    sources, period_start = pre_sources, pre_period_start
  else
    sources, period_start = rate_sources(sidx, period)
  end
  local end_tick = math.floor(game.tick / BIN_TICKS) * BIN_TICKS
  local since = since_tick and math.floor(since_tick / BIN_TICKS) * BIN_TICKS or period_start
  local start_tick = math.max(period_start, since)
  local totals, secs = {}, 0
  local function add(recs, sign, fraction)
    for r, a in pairs(recs) do add_crafts(totals, r, sign * a.c * fraction, sign * a.n * fraction) end
  end
  for _, source in ipairs(sources) do
    local ticks = source.known and source_ticks(source, start_tick) or 0
    if ticks > 0 then
      local bin = source.bin
      local fraction = 1
      if start_tick > source.first and since < period_start then
        fraction = ticks / source_ticks(source, -math.huge)
      end
      local all = bin.cell and bin.cell[cell_id]
      if all then add(all, 1, fraction) end
      local shared = exclusive and bin.cell_shared and bin.cell_shared[cell_id]
      if shared then add(shared, -1, fraction) end
      secs = secs + ticks / BIN_TICKS
    end
  end
  local out = {}
  if secs > 0 then
    for r, x in pairs(totals) do
      if x.c > 1e-9 then out[r] = { cps = x.c / secs, normal_cps = x.n / secs } end
    end
  end
  return out, secs, (end_tick - period_start) / BIN_TICKS
end

-- A deleted cell's attribution is dropped from every resolution.
function Sm.purge_cell(cell_id)
  local function purge(bin)
    if bin.cell then bin.cell[cell_id] = nil; if not next(bin.cell) then bin.cell = nil end end
    if bin.cell_shared then
      bin.cell_shared[cell_id] = nil
      if not next(bin.cell_shared) then bin.cell_shared = nil end
    end
  end
  for _, bin in pairs(storage.bins or {}) do purge(bin) end
  for _, ring in ipairs(storage.rings or {}) do
    for _, bin in pairs(ring.bins) do purge(bin) end
  end
end

Sm.rate_sources = rate_sources

local function flush_unit_membership(unit, old_units, old_shared)
  if not (storage.nbins and storage.machines) then return end
  local rec = storage.machines[unit]
  if not (rec and player_machine(rec.e)) then return end
  if rec.eligible ~= true then
    remove_observation(rec)
    seed_machine(rec, rec.e)
    return
  end
  init_machine_status()
  local bin = cur_bin(game.tick)
  local recipes = storage.graph and storage.graph.recipes
  sample_machine(rec, rec.e, game.tick, bin, recipes, old_units)
end

-- Incremental update for machine slot replacement (avoids full Cells.reindex).
function Sm.update_cell_units(affected_units, new_units, new_shared)
  local old_units = storage.cell_units or {}
  local old_shared = storage.cell_shared_units or {}
  local sorted = {}
  for unit in pairs(affected_units) do sorted[#sorted + 1] = unit end
  table.sort(sorted)
  for _, unit in ipairs(sorted) do
    if not same_membership(old_units[unit] or {}, new_units[unit], old_shared[unit], new_shared[unit]) then
      flush_unit_membership(unit, old_units, old_shared)
    end
    old_units[unit] = new_units[unit]
    old_shared[unit] = new_shared[unit]
  end
  storage.cell_units = next(old_units) and old_units or nil
  storage.cell_shared_units = next(old_shared) and old_shared or nil
end

-- Machine validity and ownership can change between callbacks on the same tick.
function Sm.machine_summary(sidx)
  local m, cap = {}, {}
  local g = storage.graph
  local recipes = g and g.recipes
  local player_force, player_force_index = player_scope()
  for _, rec in pairs(storage.machines) do
    if rec.r and (not sidx or rec.s == sidx) and player_machine(rec.e, player_force, player_force_index) then
      local rname = rec.r
      m[rname] = (m[rname] or 0) + 1
      local r = recipes and recipes[rname]
      local energy = r and r.energy or 0
      if energy > 0 and rec.spd then cap[rname] = (cap[rname] or 0) + rec.spd / energy end
    end
  end
  return m, cap
end

---@param sidx integer? Surface index; nil combines all registered surfaces.
---@return table<string, integer> counts Recipe name -> registered machine count.
function Sm.machine_counts(sidx)
  local m = {}
  local player_force, player_force_index = player_scope()
  for _, rec in pairs(storage.machines) do
    if rec.r and (not sidx or rec.s == sidx) and player_machine(rec.e, player_force, player_force_index) then m[rec.r] = (m[rec.r] or 0) + 1 end
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
  local candidates = {}
  for unit in pairs(issue.units) do
    if unit ~= latest then candidates[#candidates + 1] = unit end
  end
  table.sort(candidates)
  local checked = 0
  for _, unit in ipairs(candidates) do
    local e = Sm.status_machine(unit, sidx, force, recipe, category)
    if e then return e end
    checked = checked + 1
    if checked == PREVIEW_CHECKS then return end
  end
end

-- capacity in NORMAL crafts/s per recipe if every machine ran at 100 % (Balance tab)
---@param sidx integer? Surface index; nil combines all registered surfaces.
---@return table<string, number> capacity Recipe name -> normal crafts per second.
function Sm.capacity(sidx)
  local g = storage.graph
  local cap = {}
  local player_force, player_force_index = player_scope()
  for _, rec in pairs(storage.machines) do
    if rec.r and (not sidx or rec.s == sidx) and player_machine(rec.e, player_force, player_force_index) then
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
