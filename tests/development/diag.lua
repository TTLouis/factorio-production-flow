-- Local diagnostic fixture, loaded only by offline/native test harnesses.
-- Never packaged in the mod. Exports test snapshots for local replay and evidence.

local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local Model = require("scripts.model")
local Gr = require("scripts.groups")
local Su = require("scripts.surfaces")

local D = {}
local DIR = "production-flow/"
local LOG_MAX = 300

local function target_player()
  -- write only on one machine in multiplayer
  for _, p in pairs(game.connected_players) do return p.index end
  return nil
end

function D.log(msg)
  storage.log = storage.log or {}
  local line = string.format("[%d] %s", game.tick, msg)
  local l = storage.log
  l[#l + 1] = line
  if #l > LOG_MAX then table.remove(l, 1) end
  local pi = target_player()
  if pi then helpers.write_file(DIR .. "log.txt", line .. "\n", true, pi) end
end

local function r3(x)
  if x ~= x or x == math.huge or x == -math.huge then return nil end
  return math.floor(x * 1000 + 0.5) / 1000
end

local function recipe_block(g, rates, sidx)
  -- aggregate machine facts per recipe
  local per = {}
  for _, rec in pairs(storage.machines) do
    local e = rec.e
    if rec.r and e.valid and (not sidx or rec.s == sidx) then
      local x = per[rec.r]
      if not x then x = { machines = 0, max_cps = 0, prod_sum = 0, samples = {} }; per[rec.r] = x end
      local proto = prototypes.recipe[rec.r]
      x.machines = x.machines + 1
      if proto and proto.energy > 0 then x.max_cps = x.max_cps + e.crafting_speed / proto.energy end
      local pb = e.productivity_bonus or 0
      x.prod_sum = x.prod_sum + pb
      if #x.samples < 3 then
        local s = { unit = e.unit_number, name = e.name, type = e.type, surface = e.surface.name,
                    speed = r3(e.crafting_speed), prod_bonus = r3(pb), products_finished = e.products_finished }
        if e.type == "rocket-silo" then s.rocket_parts = e.rocket_parts end
        x.samples[#x.samples + 1] = s
      end
    end
  end

  local out = {}
  local names = {}
  for r in pairs(per) do names[#names + 1] = r end
  for r in pairs(rates.recipes) do if not per[r] then names[#names + 1] = r end end
  table.sort(names)
  local force = game.forces["player"]
  for _, r in ipairs(names) do
    local x = per[r] or { machines = 0, max_cps = 0, prod_sum = 0, samples = {} }
    local rr = rates.recipes[r] or { cps = 0, prod = 0 }
    local rec = g.recipes[r]
    local fr = force and force.recipes[r]
    local products = {}
    if rec then
      for _, p in ipairs(rec.products) do
        local per_craft = p.amount + p.prod * rr.prod
        local st = rates.nodes[p.key]
        products[#products + 1] = {
          key = p.key, amount = r3(p.amount), prod_eligible = r3(p.prod),
          rate_if_pf_normal_only = r3(rr.cps * per_craft),
          rate_if_pf_includes_bonus = r3(rr.cps * per_craft / (1 + rr.prod)),
          stats_produced = st and r3(st.prod) or 0,
        }
      end
    end
    out[#out + 1] = {
      recipe = r, category = rec and rec.category, reversing = rec and rec.reversing or false,
      machines = x.machines, crafts_per_s = r3(rr.cps), max_crafts_per_s = r3(x.max_cps),
      utilisation = x.max_cps > 0 and r3(rr.cps / x.max_cps) or nil,
      avg_entity_prod = r3(rr.prod), avg_entity_prod_now = x.machines > 0 and r3(x.prod_sum / x.machines) or 0,
      force_recipe_prod = fr and r3(fr.productivity_bonus) or 0,
      energy = rec and r3(rec.energy), products = products, samples = x.samples,
    }
  end
  return out
end

-- Surfaces are never combined: every block is for one surface. The main block is the
-- surface with the most crafting machines; replay_surfaces has one replay per surface.
function D.snapshot()
  local g = Graph.get()
  local counts = {}
  for _, rec in pairs(storage.machines) do counts[rec.s] = (counts[rec.s] or 0) + 1 end
  local main, best = nil, -1
  for si, n in pairs(counts) do if n > best then main, best = si, n end end
  main = main or 1
  local rates, secs = Sampler.rates(main)
  local m = Model.build(main)

  local nodes = {}
  local keys = {}
  for k in pairs(m.residuals) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local r = m.residuals[k]
    local v = m.vertices[k]
    nodes[#nodes + 1] = {
      key = k, tier = v and v.tier, comp = v and v.comp,
      produced = r3(r.prod), measured_in = r3(r.meas_in), other_source = r3(r.other_src),
      consumed = r3(r.cons), measured_out = r3(r.meas_out), other_sink = r3(r.other_sink),
    }
  end

  local surfaces = {}
  for _, s in pairs(game.surfaces) do
    local n = 0
    for _, rec in pairs(storage.machines) do if rec.s == s.index then n = n + 1 end end
    surfaces[#surfaces + 1] = { index = s.index, name = s.name, label = Su.label(s),
                                platform = Su.platform_name(s), machines = n }
  end

  local st = Sampler.status()
  return {
    mod_version = script.active_mods["production-flow"],
    game_version = script.active_mods["base"],
    space_age = script.active_mods["space-age"] ~= nil,
    tick = game.tick,
    window_seconds = secs,
    assumptions = { pf_includes_bonus = Sampler.PF_INCLUDES_BONUS },
    sampler = st,
    graph = { nodes = g.n_nodes, recipes = g.n_recipes, reversing = g.n_reversing },
    model = { in_use_recipes = #m.used, vertices = #m.verts, edges = #m.edges, sccs = #m.sccs,
              max_tier = m.max_tier },
    sccs = m.sccs,
    surfaces = surfaces,
    surface = game.surfaces[main] and game.surfaces[main].name or tostring(main),
    recipes = recipe_block(g, rates, main),
    nodes = nodes,
    log = storage.log or {},
    replay = D.replay_block(g, m),
    replay_surfaces = (function()
      local out = {}
      for si in pairs(counts) do
        local sf = game.surfaces[si]
        if sf then
          out[sf.name] = D.replay_block(g, Model.build(si))
          out[sf.name].label = Su.label(sf)
        end
      end
      return out
    end)(),
  }
end

-- everything the layout engine needs, so a base can be replayed offline
function D.replay_block(g, m)
  local pi = 1
  for _, p in pairs(game.connected_players) do pi = p.index; break end
  local edges = {}
  for _, e in ipairs(m.edges) do
    edges[#edges + 1] = { e.from, e.to, r3(e.rate), e.reversing and 1 or 0 }
  end
  local res, era, groups = {}, {}, {}
  for k, r in pairs(m.residuals) do
    res[k] = { r3(r.prod), r3(r.cons) }
    local nd = g.nodes[k]
    era[k] = nd and nd.era or 0
    local gid = Gr.of(pi, k)
    local info = Gr.info(pi, gid)
    groups[k] = { gid, info.name, info.super, info.super_name, info.color, info.order, info.super_order }
  end
  local recipe_era = {}
  for _, r in ipairs(m.used) do recipe_era[r] = g.recipes[r] and g.recipes[r].era or 0 end
  return { edges = edges, residuals = res, era = era, recipe_era = recipe_era, groups = groups, seconds = m.seconds }
end

function D.export(player, reason)
  local ok, data = pcall(D.snapshot)
  if not ok then
    D.log("export failed: " .. tostring(data))
    if player then player.print("[Production Flow] Export failed: " .. tostring(data)) end
    return
  end
  local pi = player and player.index or target_player()
  if not pi then return end
  local json = helpers.table_to_json(data)
  helpers.write_file(DIR .. "latest.json", json, false, pi)
  if reason == "manual" then
    local name = DIR .. "export-" .. game.tick .. ".json"
    helpers.write_file(name, json, false, pi)
    if player then player.print("[Production Flow] Exported diagnostics to script-output/" .. name) end
  end
end

return D
