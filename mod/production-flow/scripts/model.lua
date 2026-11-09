-- M3: in-use subgraph, measured edge flows, residuals, SCC collapse, tiering (D4, D5, D6)

local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")

local M = {}

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

-- iterative Tarjan. Components are numbered in reverse topological order.
local function tarjan(verts, adj)
  local index, low, onstack, stack, comp = {}, {}, {}, {}, {}
  local idx, ncomp = 0, 0
  for _, v0 in ipairs(verts) do
    if index[v0] == nil then
      index[v0], low[v0] = idx, idx
      idx = idx + 1
      stack[#stack + 1] = v0
      onstack[v0] = true
      local work = { { v0, 1 } }
      while #work > 0 do
        local top = work[#work]
        local v, i = top[1], top[2]
        local nb = adj[v]
        if nb and i <= #nb then
          top[2] = i + 1
          local w = nb[i]
          if index[w] == nil then
            index[w], low[w] = idx, idx
            idx = idx + 1
            stack[#stack + 1] = w
            onstack[w] = true
            work[#work + 1] = { w, 1 }
          elseif onstack[w] and index[w] < low[v] then
            low[v] = index[w]
          end
        else
          work[#work] = nil
          if #work > 0 then
            local u = work[#work][1]
            if low[v] < low[u] then low[u] = low[v] end
          end
          if low[v] == index[v] then
            ncomp = ncomp + 1
            local w
            repeat
              w = stack[#stack]
              stack[#stack] = nil
              onstack[w] = nil
              comp[w] = ncomp
            until w == v
          end
        end
      end
    end
  end
  return comp, ncomp
end
M._tarjan = tarjan

-- Table contracts used by the build phases:
-- rates (ProductionFlowRates) = { recipes = { [recipe_name] = { cps, prod } },
--           nodes = { [material_key] = { prod, cons } } } from Sampler.rates.
-- cps counts crafts per second; prod is the productivity bonus. Node totals and
-- edge rates are amounts per second. Keys use item/, fluid/ or recipe/ prefixes.
-- edges is an ordered array of { from, to, rate, reversing, cycle }; reversing
-- retains the recipe value (including nil), and cycle is filled after tiering.
-- meas_in sums recipe production; meas_out sums recipe consumption.
-- residuals[material_key] = { prod, cons, meas_in, meas_out, other_src,
-- other_sink }; only the unexplained source/sink amounts are clamped to zero.
-- The returned model retains the sampler tables as rates and machines. Its used
-- and verts arrays are sorted; vertices maps each key to { tier, comp, kind }.
-- sccs lists multi-member components in topological order, with sorted members.

local function used_recipes(graph, rates, machine_counts)
  -- in-use recipes: measured activity OR at least one machine set to it
  local used = {}
  for r in pairs(rates.recipes) do if graph.recipes[r] then used[r] = true end end
  for r in pairs(machine_counts) do if graph.recipes[r] then used[r] = true end end
  local used_list = sorted_keys(used)

  return used_list
end

local function assemble_graph(graph, rates, used_list)
  local verts, vertex_set = {}, {}
  local function add_vertex(v)
    if not vertex_set[v] then vertex_set[v] = true; verts[#verts + 1] = v end
  end

  local edges = {}
  local adjacency_sets = {} -- tiering adjacency, reversing recipes excluded
  local measured_inputs, measured_outputs = {}, {}
  local function link(a, b, tier_edge)
    if not tier_edge then return end
    local s = adjacency_sets[a]
    if not s then s = {}; adjacency_sets[a] = s end
    s[b] = true
  end

  for _, recipe_name in ipairs(used_list) do
    local recipe = graph.recipes[recipe_name]
    local recipe_key = "recipe/" .. recipe_name
    local recipe_rate = rates.recipes[recipe_name]
    local crafts_per_second = recipe_rate and recipe_rate.cps or 0
    local productivity = recipe_rate and recipe_rate.prod or 0
    -- products_finished includes bonus crafts; only normal crafts consume inputs.
    local normal_crafts_per_second = Sampler.PF_INCLUDES_BONUS and crafts_per_second / (1 + productivity) or crafts_per_second
    local tier_edge = not recipe.reversing
    add_vertex(recipe_key)
    for _, ingredient in ipairs(recipe.ingredients) do
      add_vertex(ingredient.key)
      local rate = normal_crafts_per_second * ingredient.amount
      edges[#edges + 1] = { from = ingredient.key, to = recipe_key, rate = rate, reversing = recipe.reversing }
      measured_outputs[ingredient.key] = (measured_outputs[ingredient.key] or 0) + rate
      link(ingredient.key, recipe_key, tier_edge)
    end
    for _, product in ipairs(recipe.products) do
      add_vertex(product.key)
      local rate = normal_crafts_per_second * (product.amount + product.prod * productivity)
      edges[#edges + 1] = { from = recipe_key, to = product.key, rate = rate, reversing = recipe.reversing }
      measured_inputs[product.key] = (measured_inputs[product.key] or 0) + rate
      link(recipe_key, product.key, tier_edge)
    end
  end

  -- deterministic adjacency arrays
  table.sort(verts)
  local adj = {}
  for _, v in ipairs(verts) do
    if adjacency_sets[v] then adj[v] = sorted_keys(adjacency_sets[v]) end
  end

  return verts, edges, adj, measured_inputs, measured_outputs
end

local function calculate_tiers(verts, edges, adj)
  -- SCC + longest-path tiering on the condensation
  local comp, ncomp = tarjan(verts, adj)
  local members = {}
  for _, v in ipairs(verts) do
    local c = comp[v]
    members[c] = members[c] or {}
    members[c][#members[c] + 1] = v
  end
  local ctier = {}
  for c = 1, ncomp do ctier[c] = 0 end
  for c = ncomp, 1, -1 do                 -- topological order
    for _, v in ipairs(members[c]) do
      for _, w in ipairs(adj[v] or {}) do
        local d = comp[w]
        if d ~= c and ctier[c] + 1 > ctier[d] then ctier[d] = ctier[c] + 1 end
      end
    end
  end

  local vertices, max_tier = {}, 0
  for _, v in ipairs(verts) do
    local t = ctier[comp[v]]
    vertices[v] = { tier = t, comp = comp[v], kind = string.match(v, "^(%a+)/") }
    if t > max_tier then max_tier = t end
  end
  for _, e in ipairs(edges) do
    e.cycle = (comp[e.from] == comp[e.to])
  end

  local sccs = {}
  for c = ncomp, 1, -1 do
    if #members[c] > 1 then sccs[#sccs + 1] = members[c] end
  end

  return vertices, max_tier, sccs
end

local function assemble_residuals(verts, vertices, rates, measured_inputs, measured_outputs)
  -- residuals: force-stat totals minus measured recipe edges (D6)
  local residuals = {}
  for _, v in ipairs(verts) do
    if vertices[v].kind ~= "recipe" then
      local tot = rates.nodes[v] or { prod = 0, cons = 0 }
      local mi, mo = measured_inputs[v] or 0, measured_outputs[v] or 0
      residuals[v] = {
        prod = tot.prod, meas_in = mi, other_src = math.max(0, tot.prod - mi),
        cons = tot.cons, meas_out = mo, other_sink = math.max(0, tot.cons - mo),
      }
    end
  end

  return residuals
end

-- sidx: surface index, or nil for all surfaces. period is passed through to
-- Sampler.rates, including nil. Statistics-only materials do not add vertices:
-- the model covers materials in the selected in-use recipes.
function M.build(sidx, period)
  local graph = Graph.get()
  local rates, seconds = Sampler.rates(sidx, period)
  local machine_counts = Sampler.machine_counts(sidx)
  local used_list = used_recipes(graph, rates, machine_counts)
  local verts, edges, adj, measured_inputs, measured_outputs = assemble_graph(graph, rates, used_list)
  local vertices, max_tier, sccs = calculate_tiers(verts, edges, adj)
  local residuals = assemble_residuals(verts, vertices, rates, measured_inputs, measured_outputs)

  return {
    seconds = seconds,
    used = used_list,
    vertices = vertices,
    verts = verts,
    edges = edges,
    sccs = sccs,
    max_tier = max_tier,
    residuals = residuals,
    machines = machine_counts,
    rates = rates,
  }
end

return M
