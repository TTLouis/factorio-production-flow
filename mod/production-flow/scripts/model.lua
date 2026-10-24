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

-- sidx: surface index, or nil for all surfaces
function M.build(sidx, period)
  local g = Graph.get()
  local rates, secs = Sampler.rates(sidx, period)
  local mcount = Sampler.machine_counts(sidx)

  -- in-use recipes: measured activity OR at least one machine set to it
  local used = {}
  for r in pairs(rates.recipes) do if g.recipes[r] then used[r] = true end end
  for r in pairs(mcount) do if g.recipes[r] then used[r] = true end end
  local used_list = sorted_keys(used)

  local verts, vset = {}, {}
  local function addv(v)
    if not vset[v] then vset[v] = true; verts[#verts + 1] = v end
  end

  local edges = {}
  local adjset = {} -- tiering adjacency, reversing recipes excluded
  local meas_in, meas_out = {}, {}
  local function link(a, b, tier_edge)
    if not tier_edge then return end
    local s = adjset[a]
    if not s then s = {}; adjset[a] = s end
    s[b] = true
  end

  for _, r in ipairs(used_list) do
    local rec = g.recipes[r]
    local rv = "recipe/" .. r
    local rr = rates.recipes[r]
    local cps = rr and rr.cps or 0
    local prod = rr and rr.prod or 0
    -- crafts counted by products_finished include bonus crafts: normal crafts consume inputs
    local normal = Sampler.PF_INCLUDES_BONUS and cps / (1 + prod) or cps
    local tier_edge = not rec.reversing
    addv(rv)
    for _, ing in ipairs(rec.ingredients) do
      addv(ing.key)
      local rate = normal * ing.amount
      edges[#edges + 1] = { from = ing.key, to = rv, rate = rate, reversing = rec.reversing }
      meas_out[ing.key] = (meas_out[ing.key] or 0) + rate
      link(ing.key, rv, tier_edge)
    end
    for _, p in ipairs(rec.products) do
      addv(p.key)
      local rate = normal * (p.amount + p.prod * prod)
      edges[#edges + 1] = { from = rv, to = p.key, rate = rate, reversing = rec.reversing }
      meas_in[p.key] = (meas_in[p.key] or 0) + rate
      link(rv, p.key, tier_edge)
    end
  end

  -- deterministic adjacency arrays
  table.sort(verts)
  local adj = {}
  for _, v in ipairs(verts) do
    if adjset[v] then adj[v] = sorted_keys(adjset[v]) end
  end

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

  -- residuals: force-stat totals minus measured recipe edges (D6)
  local residuals = {}
  for _, v in ipairs(verts) do
    if vertices[v].kind ~= "recipe" then
      local tot = rates.nodes[v] or { prod = 0, cons = 0 }
      local mi, mo = meas_in[v] or 0, meas_out[v] or 0
      residuals[v] = {
        prod = tot.prod, meas_in = mi, other_src = math.max(0, tot.prod - mi),
        cons = tot.cons, meas_out = mo, other_sink = math.max(0, tot.cons - mo),
      }
    end
  end

  return {
    seconds = secs,
    used = used_list,
    vertices = vertices,
    verts = verts,
    edges = edges,
    sccs = sccs,
    max_tier = max_tier,
    residuals = residuals,
    machines = mcount,
    rates = rates,
  }
end

return M
