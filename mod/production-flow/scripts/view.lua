-- M4 view model + layout: turns the measured Model into a drawable Sankey.
--
-- Display graph (D1):
--   * single-output recipes are elided: each ingredient links straight to the product
--   * multi-output recipes (oil processing, uranium, scrap…) stay as small recipe nodes
--   * ribbons carry the SOURCE item's units (x/s of the item leaving the node)
--   * reversing recipes (recycling, unbarrel) and cycle back-edges become ↺ badges, not ribbons
-- Filters: preset roots (+ancestors) → hidden → collapsed groups → tier range (D19, D20)
-- Stubs:   right = consumption not shown (other uses), left = production not from shown
--          recipes (mining, handcraft, recycling…) — so every node keeps its full flow.
-- Layout:  x = column (longest path, system-owned); y = group-clustered, barycenter-ordered,
--          player order keys override (D10–D12); linear fit scale × zoom (D14).

local Model = require("scripts.model")
local Gr = require("scripts.groups")
local Graph = require("scripts.graph")
local Default = require("shared.groups_default")
local palette = require("shared.palette")
local S = require("shared.sprites")
local Neighborhood = require("scripts.neighborhood")

local V = {}
V.MAX_INPUT_DEPTH = Neighborhood.MAX_DEPTH

local EPS = 1e-4
V.NODE_W = 32      -- node bar width (= icon size)
V.HEADER_W = 176   -- reserved horizontal band for readable item headers
V.F_LABEL = 18     -- single-line name strip above the icon
V.ICON_GAP = 4     -- short connecting stem between icon and flow bar
V.NODE_HEAD = V.F_LABEL + V.NODE_W + V.ICON_GAP
V.SLOT_MIN = 30    -- minimum vertical slot per node (icon never overlaps a neighbour)
V.PAD_L = 60
V.PAD_R = 150
V.PAD_TOP = 34     -- room for the tier headers
V.PAD_BOTTOM = 16
V.GAP_IN = 16      -- gap between nodes in the same sub-lane column
V.LANE_GAP = 26    -- gap between packed lanes
V.SUB_GAP = 10     -- gap between sub-lanes inside a lane
V.FLOW_SHARE = 0.45 -- flows get at least this share of the total height (canvas scrolls if needed)
V.LANE_HEAD = 24   -- lane title height
V.SUB_HEAD = 16    -- sub-lane title height
V.LANE_PAD = 6
V.LANE_LEFT = 48   -- lane rect starts this far left of its first column
V.LANE_RIGHT = 118 -- ... and ends this far right of its last column's node bar
V.STUB = 14

local function kind(key) return string.match(key, "^(%a+)/") end

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

---------------------------------------------------------------------------
-- presets (D19)
---------------------------------------------------------------------------
local function lab_inputs()
  local set, list = {}, {}
  for _, e in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "lab" } })) do
    for _, n in pairs(e.lab_inputs or {}) do
      if type(n) == "table" then n = n.name end
      local k = "item/" .. n
      if not set[k] then set[k] = true; list[#list + 1] = n end
    end
  end
  table.sort(list)
  return set, list
end

function V.presets()
  local _, packs = lab_inputs()
  local out = {
    { id = "all", name = "Everything" },
    { id = "science", name = "Sciences only" },
  }
  for _, n in ipairs(packs) do
    out[#out + 1] = { id = "pack:" .. n, name = "  [item=" .. n .. "] " .. n }
  end
  out[#out + 1] = { id = "super:oil", name = "Oil chain" }
  out[#out + 1] = { id = "roots:item/processing-unit", name = "Electronics" }
  out[#out + 1] = { id = "roots:item/copper-plate", name = "Copper chain" }
  out[#out + 1] = { id = "roots:item/rocket-part", name = "Rocket" }
  out[#out + 1] = { id = "super:nuclear", name = "Nuclear" }
  return out
end

local function preset_roots(pi, preset, nodes)
  if preset == "all" or not preset then return nil end
  local roots = {}
  if preset == "science" then
    roots = lab_inputs()
  elseif string.sub(preset, 1, 5) == "pack:" then
    roots["item/" .. string.sub(preset, 6)] = true
  elseif string.sub(preset, 1, 6) == "roots:" then
    roots[string.sub(preset, 7)] = true
  elseif string.sub(preset, 1, 6) == "super:" then
    local sup = string.sub(preset, 7)
    for k in pairs(nodes) do
      if Gr.info(pi, Gr.of(pi, k)).super == sup then roots[k] = true end
    end
  end
  return roots
end

---------------------------------------------------------------------------
-- display graph
---------------------------------------------------------------------------
local function build_graph(pi, m, us)
  local nodes, links = {}, {}
  local function node(k)
    local n = nodes[k]
    if not n then
      local r = m.residuals[k]
      n = { key = k, kind = kind(k), prod = r and r.prod or 0, cons = r and r.cons or 0,
            shown_in = 0, loops = {}, members = nil }
      nodes[k] = n
    end
    return n
  end
  local function link(a, b, rate)
    if rate <= EPS or a == b then return end
    local id = a .. ">" .. b
    local l = links[id]
    if not l then l = { from = a, to = b, rate = 0 }; links[id] = l end
    l.rate = l.rate + rate
  end

  local by_recipe = {}
  for _, e in ipairs(m.edges) do
    local r, side
    if kind(e.from) == "recipe" then r, side = e.from, "outs" else r, side = e.to, "ins" end
    local x = by_recipe[r]
    if not x then x = { ins = {}, outs = {}, reversing = e.reversing }; by_recipe[r] = x end
    table.insert(x[side], e)
  end

  -- catalysts: an item that a recipe both consumes and produces (Kovarex U-235, coal
  -- liquefaction heavy oil, bacteria…) is netted, so only the real gain/loss is drawn
  for _, r in ipairs(sorted_keys(by_recipe)) do
    local x = by_recipe[r]
    if not x.reversing then
      local inr, outr = {}, {}
      for _, e in ipairs(x.ins) do inr[e.from] = (inr[e.from] or 0) + e.rate end
      for _, e in ipairs(x.outs) do outr[e.to] = (outr[e.to] or 0) + e.rate end
      local ni, no = {}, {}
      for _, e in ipairs(x.ins) do
        local both = outr[e.from]
        if both then
          local net = inr[e.from] - both
          if net > EPS then ni[#ni + 1] = { from = e.from, to = e.to, rate = net, reversing = e.reversing } end
          x.catalyst = x.catalyst or {}
          x.catalyst[e.from] = math.min(inr[e.from], both)
        else
          ni[#ni + 1] = e
        end
      end
      for _, e in ipairs(x.outs) do
        local both = inr[e.to]
        if both then
          local net = outr[e.to] - both
          if net > EPS then no[#no + 1] = { from = e.from, to = e.to, rate = net, reversing = e.reversing } end
        else
          no[#no + 1] = e
        end
      end
      x.ins, x.outs = ni, no
    end
  end

  for _, r in ipairs(sorted_keys(by_recipe)) do
    local x = by_recipe[r]
    if x.reversing then
      for _, o in ipairs(x.outs) do
        if o.rate > EPS then table.insert(node(o.to).loops, { what = r, rate = o.rate }) end
      end
    end
    if x.catalyst and not x.reversing then
      for k, amt in pairs(x.catalyst) do
        local nn = node(k)
        nn.catalyst = (nn.catalyst or 0) + amt
      end
    end
    if x.reversing then
      -- handled above
    elseif #x.outs == 1 then
      local o = x.outs[1]
      local pn = node(o.to)
      pn.shown_in = pn.shown_in + o.rate
      -- remember which drawn links carry this production, so the "other sources" stub can
      -- grow again when those links are filtered out (focus, presets, hidden items)
      local via = {}
      for _, i in ipairs(x.ins) do node(i.from); link(i.from, o.to, i.rate); via[#via + 1] = i.from end
      pn.contrib = pn.contrib or {}
      table.insert(pn.contrib, { rate = o.rate, via = via })
    elseif #x.outs > 1 then
      local rn = node(r)
      for _, i in ipairs(x.ins) do node(i.from); link(i.from, r, i.rate) end
      for _, o in ipairs(x.outs) do
        local pn = node(o.to)
        pn.shown_in = pn.shown_in + o.rate
        link(r, o.to, o.rate)
        pn.contrib = pn.contrib or {}
        table.insert(pn.contrib, { rate = o.rate, via = { r } })
      end
      rn.shown_in = math.huge -- recipe nodes have no stubs
    end
  end
  return nodes, links
end

local function drop_nodes(nodes, links, keep_fn)
  for k in pairs(nodes) do if not keep_fn(k) then nodes[k] = nil end end
  for id, l in pairs(links) do
    if not (nodes[l.from] and nodes[l.to]) then links[id] = nil end
  end
end

local function apply_preset(pi, nodes, links, preset)
  local roots = preset_roots(pi, preset, nodes)
  if not roots then return end
  local rev = {}
  for _, l in pairs(links) do
    rev[l.to] = rev[l.to] or {}
    table.insert(rev[l.to], l.from)
  end
  local keep, stack = {}, {}
  for k in pairs(roots) do if nodes[k] then keep[k] = true; stack[#stack + 1] = k end end
  while #stack > 0 do
    local k = table.remove(stack)
    for _, p in ipairs(rev[k] or {}) do
      if not keep[p] then keep[p] = true; stack[#stack + 1] = p end
    end
  end
  drop_nodes(nodes, links, function(k) return keep[k] end)
end

local function apply_collapse(pi, nodes, links, collapsed)
  if not next(collapsed) then return nodes, links, {} end
  local map = {}
  for k in pairs(nodes) do
    local g = Gr.of(pi, k)
    if collapsed[g] and nodes[k].kind ~= "recipe" then
      map[k] = "group/" .. g .. (nodes[k].kind == "fluid" and "#fluid" or "")
    end
  end
  if not next(map) then return nodes, links, {} end
  local nn, nl = {}, {}
  for _, k in ipairs(sorted_keys(nodes)) do
    local n = nodes[k]
    local t = map[k]
    if t then
      local g = nn[t]
      if not g then
        g = { key = t, kind = "group", flow_kind = n.kind, group_id = Gr.of(pi, k),
          prod = 0, cons = 0, shown_in = math.huge, loops = {}, members = {} }
        nn[t] = g
      end
      g.prod = g.prod + n.prod
      g.cons = g.cons + n.cons
      table.insert(g.members, k)
      for _, lp in ipairs(n.loops) do table.insert(g.loops, lp) end
    else
      nn[k] = n
    end
  end
  for _, id in ipairs(sorted_keys(links)) do
    local l = links[id]
    local a, b = map[l.from] or l.from, map[l.to] or l.to
    if a ~= b then
      local nid = a .. ">" .. b
      local x = nl[nid]
      if not x then x = { from = a, to = b, rate = 0 }; nl[nid] = x end
      x.rate = x.rate + l.rate
    end
  end
  return nn, nl, map
end

-- Focus view: one item plus N item-steps upstream and downstream (recipe nodes are free).
-- Everything else is dropped; its share of the flow shows up as grey stubs.
local function apply_focus(nodes, links, focus, steps)
  if not (focus and nodes[focus]) then return false end
  local fwd, rev = {}, {}
  for _, l in pairs(links) do
    fwd[l.from] = fwd[l.from] or {}; table.insert(fwd[l.from], l.to)
    rev[l.to] = rev[l.to] or {};     table.insert(rev[l.to], l.from)
  end
  local keep = { [focus] = true }
  for _, adj in ipairs({ fwd, rev }) do
    local dist, queue, head = { [focus] = 0 }, { focus }, 1
    while queue[head] do
      local k = queue[head]; head = head + 1
      for _, nb in ipairs(adj[k] or {}) do
        local d = dist[k] + ((kind(nb) == "recipe") and 0 or 1)
        if d <= steps and (dist[nb] == nil or d < dist[nb]) then
          dist[nb] = d; keep[nb] = true; queue[#queue + 1] = nb
        end
      end
    end
  end
  -- a recipe node at the edge keeps only if it still connects two kept items
  drop_nodes(nodes, links, function(k) return keep[k] end)
  return true
end

-- Overview: each lane has separate item/fluid nodes; raw resources and recipes stay individual.
local function apply_overview(pi, nodes, links, opened)
  -- Expanding a group also exposes the specific materials feeding it, without
  -- expanding every unrelated member of the neighbouring groups.
  local roots, exposed, recipes = {}, {}, {}
  for k in pairs(nodes) do
    if (opened or {})[Gr.info(pi, Gr.of(pi, k)).super] then roots[k], exposed[k] = true, true end
  end
  for _, l in pairs(links) do
    if roots[l.to] then
      exposed[l.from] = true
      if nodes[l.from].kind == "recipe" then recipes[l.from] = true end
    end
  end
  for _, l in pairs(links) do if recipes[l.to] then exposed[l.from] = true end end
  local map = {}
  for k, n in pairs(nodes) do
    local g = Gr.of(pi, k)
    local info = Gr.info(pi, g)
    if n.kind ~= "recipe" and info.super ~= "raw" and not exposed[k] then
      map[k] = "group/@" .. info.super .. (n.kind == "fluid" and "#fluid" or "")
    end
  end
  local nn, nl = {}, {}
  for _, k in ipairs(sorted_keys(nodes)) do
    local n, t = nodes[k], map[k]
    if t then
      local g = nn[t]
      if not g then
        g = { key = t, kind = "group", flow_kind = n.kind,
          super_id = Gr.info(pi, Gr.of(pi, k)).super,
          prod = 0, cons = 0, shown_in = math.huge, loops = {}, members = {} }
        nn[t] = g
      end
      if n.kind ~= "recipe" then
        g.prod = g.prod + n.prod
        g.cons = g.cons + n.cons
      end
      table.insert(g.members, k)
    else
      nn[k] = n
    end
  end
  for _, id in ipairs(sorted_keys(links)) do
    local l = links[id]
    local a, b = map[l.from] or l.from, map[l.to] or l.to
    if a ~= b then
      local nid = a .. ">" .. b
      local x = nl[nid]
      if not x then x = { from = a, to = b, rate = 0 }; nl[nid] = x end
      x.rate = x.rate + l.rate
    end
  end
  return nn, nl, map
end

-- Top-N: keep only the N heaviest ribbons (fluids weighted by the fluid scale)
local function apply_top_n(nodes, links, n, ff)
  local list = {}
  for id, l in pairs(links) do
    local f = (kind(l.from) == "fluid" or (kind(l.from) == "recipe" and kind(l.to) == "fluid")) and ff or 1
    list[#list + 1] = { id = id, w = l.rate * f }
  end
  table.sort(list, function(a, b) if a.w ~= b.w then return a.w > b.w end return a.id < b.id end)
  for i = n + 1, #list do links[list[i].id] = nil end
  local touched = {}
  for _, l in pairs(links) do touched[l.from] = true; touched[l.to] = true end
  drop_nodes(nodes, links, function(k) return touched[k] end)
end

-- era of a display node (tech mode)
local function node_era(g, n)
  if n.kind == "recipe" then
    local r = g.recipes[string.sub(n.key, 8)]
    return r and r.era or 0
  elseif n.kind == "group" then
    local e = math.huge
    for _, mk in ipairs(n.members) do
      local nd = g.nodes[mk]
      if nd and nd.era < e then e = nd.era end
    end
    return (e == math.huge) and 0 or e
  end
  local nd = g.nodes[n.key]
  return nd and nd.era or 0
end

-- Tiers (D25). Sets n.tier (number) for every node; links that would point backwards
-- become ↺ loop badges. Returns the sorted list of distinct tier values.
--   depth: longest path from raw over the SCC condensation (integers)
--   tech : era (tech tree) + fractional production depth inside the era:
--          E(n) = max(era(n), E(p) for inputs p whose own era ≤ era(n))
--          (a producer from a LATER era, e.g. Vulcanus molten iron → iron plate, is a
--           late alternative and is shown as a loop badge, not a backwards ribbon)
--          d(n) = longest chain of same-E inputs;  tier = E + d / (D_E + 1)
local function tiers(nodes, links, mode)
  local verts = sorted_keys(nodes)
  local adjset = {}
  for _, l in pairs(links) do
    adjset[l.from] = adjset[l.from] or {}
    adjset[l.from][l.to] = true
  end
  local adj = {}
  for k, s in pairs(adjset) do adj[k] = sorted_keys(s) end
  local comp, ncomp = Model._tarjan(verts, adj)
  local members = {}
  for _, v in ipairs(verts) do
    local c = comp[v]
    members[c] = members[c] or {}
    table.insert(members[c], v)
  end

  -- Break each cycle with a minimal-weight feedback set (Eades–Lin–Smyth, rate-weighted):
  -- only the feedback links become ↺ badges, every other link in the loop is drawn.
  local inner = {}
  for id, l in pairs(links) do
    if comp[l.from] == comp[l.to] then
      local c = comp[l.from]
      inner[c] = inner[c] or {}
      inner[c][#inner[c] + 1] = id
    end
  end
  for c, ids in pairs(inner) do
    local rem, outw, inw = {}, {}, {}
    for _, v in ipairs(members[c]) do rem[v] = true; outw[v] = 0; inw[v] = 0 end
    for _, id in ipairs(ids) do
      local l = links[id]
      outw[l.from] = outw[l.from] + l.rate
      inw[l.to] = inw[l.to] + l.rate
    end
    local s1, s2, left = {}, {}, #members[c]
    local function drop(v)
      rem[v] = nil
      left = left - 1
      for _, id in ipairs(ids) do
        local l = links[id]
        if l.from == v and rem[l.to] then inw[l.to] = inw[l.to] - l.rate end
        if l.to == v and rem[l.from] then outw[l.from] = outw[l.from] - l.rate end
      end
    end
    while left > 0 do
      local changed = true
      while changed do
        changed = false
        for _, v in ipairs(members[c]) do
          if rem[v] and outw[v] <= 1e-9 then table.insert(s2, 1, v); drop(v); changed = true
          elseif rem[v] and inw[v] <= 1e-9 then s1[#s1 + 1] = v; drop(v); changed = true end
        end
      end
      if left > 0 then
        local best, bd
        for _, v in ipairs(members[c]) do
          if rem[v] then
            local dlt = outw[v] - inw[v]
            if not bd or dlt > bd then best, bd = v, dlt end
          end
        end
        s1[#s1 + 1] = best
        drop(best)
      end
    end
    local pos = {}
    for i, v in ipairs(s1) do pos[v] = i end
    for i, v in ipairs(s2) do pos[v] = #s1 + i end
    for _, id in ipairs(ids) do
      local l = links[id]
      if pos[l.from] >= pos[l.to] then
        table.insert(nodes[l.to].loops, { what = l.from, rate = l.rate, back = true })
        table.insert(nodes[l.from].loops, { what = l.to, rate = l.rate, back = true, out = true })
        nodes[l.from].loop_out = (nodes[l.from].loop_out or 0) + l.rate
        links[id] = nil
      end
    end
  end

  -- recompute on the now acyclic graph
  adjset = {}
  for _, l in pairs(links) do
    adjset[l.from] = adjset[l.from] or {}
    adjset[l.from][l.to] = true
  end
  adj = {}
  for k, s in pairs(adjset) do adj[k] = sorted_keys(s) end
  comp, ncomp = Model._tarjan(verts, adj)
  members = {}
  for _, v in ipairs(verts) do
    local c = comp[v]
    members[c] = members[c] or {}
    table.insert(members[c], v)
  end
  -- predecessors per component (topological order = ncomp .. 1)
  local preds = {}
  for _, l in pairs(links) do
    local d = comp[l.to]
    preds[d] = preds[d] or {}
    table.insert(preds[d], l)
  end

  local ctier = {}
  if mode ~= "tech" then
    local g = Graph.get()
    for c = ncomp, 1, -1 do
      -- nothing flowing in right now (idle item, or fed from stock): use its static
      -- recipe depth instead of drawing it as a raw resource
      local t = 0
      if not preds[c] then
        for _, v in ipairs(members[c]) do
          local nd = g.nodes[nodes[v].base or v]
          if nd and nd.depth and nd.depth > t then t = nd.depth end
        end
      end
      for _, l in ipairs(preds[c] or {}) do
        local p = ctier[comp[l.from]] + 1
        if p > t then t = p end
      end
      ctier[c] = t
    end
    for k, n in pairs(nodes) do n.tier = ctier[comp[k]] end
  else
    local g = Graph.get()
    local cera, E = {}, {}
    for c = ncomp, 1, -1 do
      local e = math.huge
      for _, v in ipairs(members[c]) do
        local x = node_era(g, nodes[v])
        if x < e then e = x end
      end
      cera[c] = (e == math.huge) and 0 or e
      local t = cera[c]
      for _, l in ipairs(preds[c] or {}) do
        local pc = comp[l.from]
        if cera[pc] <= cera[c] and E[pc] > t then t = E[pc] end
      end
      E[c] = t
    end
    local d, D = {}, {}
    for c = ncomp, 1, -1 do
      local x = 0
      for _, l in ipairs(preds[c] or {}) do
        local pc = comp[l.from]
        if E[pc] == E[c] and d[pc] + 1 > x then x = d[pc] + 1 end
      end
      d[c] = x
      if not D[E[c]] or x > D[E[c]] then D[E[c]] = x end
    end
    for k, n in pairs(nodes) do
      local c = comp[k]
      n.era = E[c]
      n.tier = E[c] + d[c] / (D[E[c]] + 1)
    end
    -- anything that still points backwards is a late alternative producer
    for id, l in pairs(links) do
      if nodes[l.from].tier >= nodes[l.to].tier then
        table.insert(nodes[l.to].loops, { what = l.from, rate = l.rate, late = true })
        local src = nodes[l.from]
        src.late_outs = src.late_outs or {}
        table.insert(src.late_outs, { key = l.to, rate = l.rate })
        links[id] = nil
      end
    end
  end

  local set, list = {}, {}
  for _, n in pairs(nodes) do
    local key = math.floor(n.tier * 1000 + 0.5) / 1000
    n.tier = key
    if not set[key] then set[key] = true; list[#list + 1] = key end
  end
  table.sort(list)
  return list
end

function V.tier_label(t)
  if t == math.floor(t) then return string.format("T%d", t) end
  local s = string.format("T%.2f", t)
  s = string.gsub(s, "0+$", "")
  return s
end

---------------------------------------------------------------------------
-- public: build everything needed to draw
---------------------------------------------------------------------------
function V.build(player, us, W, viewH)
  local pi = player.index
  local sidx = us.sidx or player.surface.index -- surfaces are never combined
  local m = Model.build(sidx, us.period)

  local nodes, links = build_graph(pi, m, us)
  local ff = player.mod_settings["ssk-fluid-scale"].value
  local focused
  if us.neighborhood and us.focus then
    nodes, links = Neighborhood.build(nodes, links, m, us.focus, us.input_depth)
    focused = true
  else focused = (us.view == "focus") and apply_focus(nodes, links, us.focus, us.focus_steps or 2) end
  if not focused then apply_preset(pi, nodes, links, us.preset) end
  drop_nodes(nodes, links, function(k) return not us.hidden[k] or k == us.focus end)
  local kmap
  if us.view == "overview" then
    nodes, links, kmap = apply_overview(pi, nodes, links, us.overview_open)
    local collapsed_map
    nodes, links, collapsed_map = apply_collapse(pi, nodes, links, us.collapsed)
    for key, target in pairs(kmap) do kmap[key] = collapsed_map[target] or target end
    for key, target in pairs(collapsed_map) do kmap[key] = target end
  else
    nodes, links, kmap = apply_collapse(pi, nodes, links, us.collapsed)
  end
  -- Aggregate keys only exist after grouping. Hide both unit variants together,
  -- matching the selection toolbar's group key.
  drop_nodes(nodes, links, function(k)
    return k == us.focus or not us.hidden[k] and not us.hidden[(k:gsub("#fluid$", ""))]
  end)
  if us.top_n and us.top_n > 0 then apply_top_n(nodes, links, us.top_n, ff) end
  -- A group's members span tech eras. Production depth keeps the overview's
  -- raw inputs before their groups instead of hiding them as later-era sources.
  local tier_list
  if us.neighborhood then
    tier_list = {}
    -- Keep Materials / Selected / Uses, but don't reserve empty upstream
    -- columns when the requested expansion has already reached a raw input.
    local first_tier = (us.input_depth or 1) - 1
    for _, n in pairs(nodes) do first_tier = math.min(first_tier, n.neighborhood_tier) end
    for i = first_tier, (us.input_depth or 1) + 1 do tier_list[#tier_list + 1] = i end
    for _, n in pairs(nodes) do n.tier = n.neighborhood_tier end
  else tier_list = tiers(nodes, links, (focused or us.view == "overview") and "depth" or (us.tier_mode or "depth")) end

  -- drop isolated idle nodes
  local touched = {}
  for _, l in pairs(links) do touched[l.from] = true; touched[l.to] = true end
  drop_nodes(nodes, links, function(k)
    local n = nodes[k]
    return us.neighborhood and k == us.focus or touched[k] or n.prod > EPS or n.cons > EPS
  end)

  -- tier range (values; nil = open)
  local present = {}
  for _, n in pairs(nodes) do present[n.tier] = true end
  local all_tiers = {}
  for _, t in ipairs(tier_list) do if us.neighborhood or present[t] then all_tiers[#all_tiers + 1] = t end end
  local lo = us.tier_lo or -math.huge
  local hi = us.tier_hi or math.huge
  if hi < lo then hi = lo end
  drop_nodes(nodes, links, function(k) local t = nodes[k].tier; return t >= lo and t <= hi end)

  -- per-node sums, stubs, value
  for _, n in pairs(nodes) do n.ins, n.outs, n.sin, n.sout = {}, {}, 0, 0 end
  local link_list = {}
  for _, id in ipairs(sorted_keys(links)) do
    local l = links[id]
    local a, b = nodes[l.from], nodes[l.to]
    l.a, l.b = a, b
    table.insert(a.outs, l); table.insert(b.ins, l)
    a.sout = a.sout + l.rate
    b.sin = b.sin + l.rate
    link_list[#link_list + 1] = l
  end

  -- drawing weight: fluids are drawn at a fraction of their rate (setting);
  -- "sqrt" height mode draws every ribbon at the square root of its rate
  local sq = ((us.heights or us.height_mode) == "sqrt") and math.sqrt or function(x) return x end
  local function factor_of(n)
    if n.kind == "fluid" then return ff end
    if n.kind == "group" and (n.flow_kind == "fluid" or (n.members and kind(n.members[1]) == "fluid")) then return ff end
    return 1
  end
  for _, l in ipairs(link_list) do
    -- units: an item/fluid/group source carries its own units; a recipe node's outputs carry the product's
    local f = (l.a.kind == "recipe") and factor_of(l.b) or factor_of(l.a)
    l.w = sq(l.rate * f)
  end
  for _, n in pairs(nodes) do
    local f = factor_of(n)
    local cat = n.catalyst or 0
    n.stub_out = (n.kind == "item" or n.kind == "fluid") and math.max(0, n.cons - n.sout - (n.loop_out or 0) - cat) or 0
    -- production that reaches this node through a drawn link; the rest is "other sources"
    local shown = 0
    local looped = {}
    for _, lp in ipairs(n.loops) do if (lp.back or lp.late) and not lp.out then looped[lp.what] = true end end
    for _, c in ipairs(n.contrib or {}) do
      for _, from in ipairs(c.via) do
        local f = (kmap or {})[from] or from
        if links[f .. ">" .. n.key] or looped[f] then shown = shown + c.rate; break end
      end
    end
    n.stub_in = (n.kind == "item" or n.kind == "fluid") and math.max(0, n.prod - shown - cat) or 0
    if n.stub_out < EPS then n.stub_out = 0 end
    if n.stub_in < EPS then n.stub_in = 0 end
    n.w_stub_out, n.w_stub_in = sq(n.stub_out * f), sq(n.stub_in * f)
    local win, wout = n.w_stub_in, n.w_stub_out
    for _, l in ipairs(n.ins) do win = win + l.w end
    for _, l in ipairs(n.outs) do wout = wout + l.w end
    n.wvalue = math.max(win, wout)
    if n.kind == "group" and string.sub(n.key, 7, 7) == "@" then
      -- overview node: a whole lane
      local sup = n.super_id or string.match(string.sub(n.key, 8), "^([^#]+)")
      local mi
      for _, mk in ipairs(n.members) do
        if kind(mk) ~= "recipe" then mi = Gr.info(pi, Gr.of(pi, mk)); break end
      end
      n.group = "@" .. sup
      n.ginfo = { id = n.group, name = mi and mi.super_name or sup, super = sup,
                  super_name = mi and mi.super_name or sup, color = mi and mi.color or 17,
                  order = 0, super_order = mi and mi.super_order or 99 }
    elseif n.kind == "group" then
      n.group = n.group_id or string.match(string.sub(n.key, 7), "^([^#]+)")
    elseif n.kind == "recipe" then
      -- a multi-output recipe lives in the lane of its biggest product
      local best, bw = nil, -1
      for _, l in ipairs(n.outs) do if l.rate > bw then best, bw = l.to, l.rate end end
      n.group = best and Gr.of(pi, best) or "recipes"
    else
      n.group = Gr.of(pi, n.group_key or n.key)
    end
    n.ginfo = n.ginfo and n.ginfo.id == n.group and n.ginfo or Gr.info(pi, n.group)
    n.lane = n.ginfo.super
  end

  -- columns = distinct tiers still shown
  local idx, col_tiers = {}, {}
  for _, t in ipairs(all_tiers) do
    if t >= lo and t <= hi then col_tiers[#col_tiers + 1] = t; idx[t] = #col_tiers end
  end
  for _, n in pairs(nodes) do n.ci = idx[n.tier] end

  -- recipe nodes live with their product; if every product is raw (asteroid crushing → ore)
  -- or hidden as a later-tech producer, they follow the products' then the inputs' lane
  for _, k in ipairs(sorted_keys(nodes)) do
    local n = nodes[k]
    if n.kind == "recipe" then
      local function pick(cands)
        local best, bw = nil, -1
        for _, c in ipairs(cands) do
          if c.node and c.node.lane and c.node.lane ~= "raw" and c.rate > bw then best, bw = c.node, c.rate end
        end
        return best
      end
      local outs, late, ins = {}, {}, {}
      for _, l in ipairs(n.outs) do outs[#outs + 1] = { node = l.b, rate = l.rate } end
      for _, x in ipairs(n.late_outs or {}) do late[#late + 1] = { node = nodes[x.key], rate = x.rate } end
      for _, l in ipairs(n.ins) do ins[#ins + 1] = { node = l.a, rate = l.rate } end
      local best = pick(outs) or pick(late) or pick(ins)
      if best then n.lane, n.group, n.ginfo = best.lane, best.group, best.ginfo end
    end
  end
  -- raw items that are only produced here (fish breeding, coal synthesis…) sit with their
  -- biggest non-raw input, in that lane's Inputs sub-lane
  for _, k in ipairs(sorted_keys(nodes)) do
    local n = nodes[k]
    if (n.kind == "item" or n.kind == "fluid") and n.lane == "raw" and #n.outs == 0 and #n.ins > 0 then
      local best, bw = nil, -1
      for _, l in ipairs(n.ins) do
        if l.a.lane and l.a.lane ~= "raw" and l.rate > bw then best, bw = l.a, l.rate end
      end
      if best then
        local sup = Default.supers[best.lane]
        n.lane = best.lane
        n.ginfo = { id = "inputs@" .. best.lane, name = "Inputs", super = best.lane,
                    super_name = sup and sup.name or best.ginfo.super_name, color = n.ginfo.color,
                    order = -1, super_order = sup and Default.super_order[best.lane] or 99 }
        n.group = n.ginfo.id
      end
    end
  end
  if us.split_raw ~= false and not focused then
    V.split_raw(nodes, link_list, pi)
    -- a copy whose consumer was itself a raw item (steam → water) follows that consumer's
    -- final lane
    for _ = 1, 3 do
      for _, k in ipairs(sorted_keys(nodes)) do
        local n = nodes[k]
        if n.lane == "raw" and #n.outs > 0 then
          local best, bw = nil, -1
          for _, l in ipairs(n.outs) do
            if l.b.lane ~= "raw" and l.rate > bw then best, bw = l.b, l.rate end
          end
          if best then
            local sup = Default.supers[best.lane]
            n.lane = best.lane
            n.ginfo = { id = "inputs@" .. best.lane, name = "Inputs", super = best.lane,
                        super_name = sup and sup.name or best.ginfo.super_name, color = n.ginfo.color,
                        order = -1, super_order = sup and Default.super_order[best.lane] or 99 }
            n.group = n.ginfo.id
          end
        end
      end
    end
  end

  local cols = {}
  for i = 1, #col_tiers do cols[i] = {} end
  for _, k in ipairs(sorted_keys(nodes)) do
    local n = nodes[k]
    table.insert(cols[n.ci], n)
  end

  local L = { nodes = nodes, links = link_list, cols = cols, col_tiers = col_tiers, all_tiers = all_tiers,
              seconds = m.seconds, recipe_rates=m.rates and m.rates.recipes or {}, W = W, fluid_factor = ff,
              min_t = player.mod_settings["ssk-min-ribbon-px"].value }
  -- Rates change every sample; topology and explicit layout controls define when
  -- it is useful to optimise again. Renderer changes do not invalidate geometry.
  local signature = { "readable-fit-v3", tostring(sidx), tostring(us.period), tostring(W), tostring(viewH),
    us.view or "detail", tostring(us.neighborhood), us.layout or "clean", us.heights or "sqrt", us.lines or "metro",
    tostring(us.zoom), tostring(us.reflow), tostring(L.min_t), tostring(ff) }
  for _, k in ipairs(sorted_keys(nodes)) do
    local n = nodes[k]
    signature[#signature + 1] = k .. ":" .. n.ci .. ":" .. n.group
  end
  for _, l in ipairs(link_list) do signature[#signature + 1] = l.from .. ">" .. l.to end
  for _, field in ipairs({ "pos", "gpos", "lpos" }) do
    for _, k in ipairs(sorted_keys(us[field] or {})) do signature[#signature + 1] = field .. k .. "=" .. us[field][k] end
  end
  signature = table.concat(signature, "|")
  us.keep_layout = us.layout_snapshot and us.layout_snapshot.signature == signature or false
  if us.neighborhood then Neighborhood.layout(L, us, W, viewH, V)
  elseif focused or (us.view ~= "focus" and us.layout ~= "lanes") then V.layout_focus(L, us, W, viewH, not focused)
  else V.layout(L, us, W, viewH) end
  local snap = { signature = signature, scale = L.scale, content_h = L.content_h, tops = {}, col_x = L.col_x, lanes = {}, subs = {} }
  for k, y in pairs(us.auto_rank or {}) do snap.tops[k] = y end
  for i, lane in ipairs(L.lane_list) do
    snap.lanes[lane.id] = i
    for j, sub in ipairs(lane.sub_list) do snap.subs[sub.id] = j end
  end
  us.layout_snapshot = snap
  return L
end

---------------------------------------------------------------------------
-- raw inputs follow their consumers (D30)
--   A raw input (Raw lane or a pure-source fluid, nothing drawn flowing into it) is split
--   into one copy per consuming lane. Each copy sits in that lane, one column before its
--   earliest consumer there, in an "Inputs" sub-lane. Mining (stub_in) is shared out in
--   proportion; "other uses" stays on the biggest copy.
---------------------------------------------------------------------------
function V.split_raw(nodes, links, pi)
  for _, key in ipairs(sorted_keys(nodes)) do
    local n = nodes[key]
    local raw = (n.kind == "item" or n.kind == "fluid") and #n.outs > 0
                and (n.lane == "raw" or (n.kind == "fluid" and #n.ins == 0))
    if (n.kind == "item" or n.kind == "fluid") and n.lane == "raw" and #n.outs == 0 and #n.ins > 0 then
      -- a raw item that is only produced here: show it next to its producer
      local p = n.ins[1].a
      n.lane = p.lane
      n.ginfo = { id = "inputs@" .. p.lane, name = "Inputs", super = p.lane, super_name = p.ginfo.super_name,
                  color = n.ginfo.color, order = -1, super_order = p.ginfo.super_order }
      n.group = n.ginfo.id
    end
    if raw then
      -- consumers grouped by lane
      local by_lane, order = {}, {}
      for _, l in ipairs(n.outs) do
        local lane = l.b.lane
        if not by_lane[lane] then by_lane[lane] = { links = {}, rate = 0, w = 0, ci = l.b.ci }; order[#order + 1] = lane end
        local g = by_lane[lane]
        table.insert(g.links, l)
        g.rate, g.w = g.rate + l.rate, g.w + l.w
        if l.b.ci < g.ci then g.ci = l.b.ci end
      end
      table.sort(order, function(a, b) return by_lane[a].rate > by_lane[b].rate end)
      local total = n.sout
      local copies = #order
      nodes[key] = nil
      for i, lane in ipairs(order) do
        local g = by_lane[lane]
        local share = (total > 0) and (g.rate / total) or (1 / copies)
        local ck = (copies > 1) and (key .. "#" .. lane) or key
        local sup = Default.supers[lane]
        local c = {
          key = ck, base = key, kind = n.kind, loops = (i == 1) and n.loops or {}, members = nil,
          prod = n.prod * share, cons = g.rate + ((i == 1) and n.stub_out or 0),
          total_prod = n.prod, total_cons = n.cons, copies = copies, share = share,
          stub_in = n.stub_in * share, stub_out = (i == 1) and n.stub_out or 0,
          w_stub_in = n.w_stub_in * share, w_stub_out = (i == 1) and n.w_stub_out or 0,
          ins = (i == 1) and n.ins or {}, outs = g.links, sin = (i == 1) and n.sin or 0, sout = g.rate,
          tier = n.tier, era = n.era, shown_in = n.shown_in,
          ci = math.max(1, g.ci - 1),
          group = "inputs@" .. lane, lane = lane,
        }
        c.ginfo = { id = c.group, name = "Inputs", super = lane,
                    super_name = sup and sup.name or (n.ginfo and n.ginfo.super_name) or lane,
                    color = n.ginfo.color, order = -1, super_order = sup and Default.super_order[lane] or 99 }
        c.origin_ginfo = n.ginfo
        local wout, win = c.w_stub_out, c.w_stub_in
        for _, l in ipairs(g.links) do l.a, l.from = c, ck; wout = wout + l.w end
        for _, l in ipairs(c.ins) do l.b, l.to = c, ck; win = win + l.w end
        c.wvalue = math.max(win, wout)
        nodes[ck] = c
      end
    end
  end
end

---------------------------------------------------------------------------
-- layout: packed swimlanes (D24)
--   lane     = super-group; spans only the columns it has nodes in
--   sub-lane = group inside a lane (titled when the lane has ≥ 2 groups)
--   packing  = skyline per column: a lane sits as high as all its columns allow,
--              so lanes that share no column share a height
--   nodes    = stacked per (sub-lane, column); order = player keys, else barycenter
---------------------------------------------------------------------------
local function center(n) return n.y + n.h / 2 end

-- skyline packing of items {px0, px1, h} (in order) at BIN px resolution, using each box's
-- real pixel extent (so boxes that only touch neighbouring columns can't overlap)
local BIN = 8
local function pack(items, _, gap)
  local sky = {}
  local total = 0
  for _, it in ipairs(items) do
    local b0, b1 = math.floor(it.px0 / BIN), math.floor(it.px1 / BIN)
    local y = 0
    for b = b0, b1 do if (sky[b] or 0) > y then y = sky[b] end end
    it.y = y
    for b = b0, b1 do sky[b] = y + it.h + gap end
    if y + it.h > total then total = y + it.h end
  end
  return total
end

local function build_structure(L, us)
  local lanes, lane_list = {}, {}
  for ci, col in ipairs(L.cols) do
    for _, n in ipairs(col) do
      local ln = lanes[n.lane]
      if not ln then
        ln = { id = n.lane, name = n.ginfo.super_name, color = n.ginfo.color, order = n.ginfo.super_order,
               subs = {}, sub_list = {}, c0 = ci, c1 = ci }
        lanes[n.lane] = ln
        lane_list[#lane_list + 1] = ln
      end
      if ci < ln.c0 then ln.c0 = ci end
      if ci > ln.c1 then ln.c1 = ci end
      local sb = ln.subs[n.group]
      if not sb then
        sb = { id = n.group, name = n.ginfo.name, color = n.ginfo.color, order = n.ginfo.order,
               cols = {}, c0 = ci, c1 = ci, lane = ln }
        ln.subs[n.group] = sb
        ln.sub_list[#ln.sub_list + 1] = sb
      end
      if ci < sb.c0 then sb.c0 = ci end
      if ci > sb.c1 then sb.c1 = ci end
      sb.cols[ci] = sb.cols[ci] or {}
      table.insert(sb.cols[ci], n)
      n.sub = sb
    end
  end
  local lpos, gpos = us.lpos or {}, us.gpos or {}
  if us.keep_layout then lpos, gpos = us.layout_snapshot.lanes, us.layout_snapshot.subs end
  table.sort(lane_list, function(a, b)
    local ka, kb = lpos[a.id] or a.order, lpos[b.id] or b.order
    if ka ~= kb then return ka < kb end
    return a.id < b.id
  end)
  for _, ln in ipairs(lane_list) do
    table.sort(ln.sub_list, function(a, b)
      local ka, kb = gpos[a.id] or a.order, gpos[b.id] or b.order
      if ka ~= kb then return ka < kb end
      return a.id < b.id
    end)
    ln.titled = #ln.sub_list >= 2
  end
  L.lane_list = lane_list
end

-- node heights for a given scale (ribbons clamped to min_t; node grows to fit its ribbons)
local function size_nodes(L, scale)
  for _, l in ipairs(L.links) do l.t = math.max(L.min_t, l.w * scale) end
  for _, col in ipairs(L.cols) do
    for _, n in ipairs(col) do
      local tin = (n.w_stub_in > 0) and math.max(L.min_t, n.w_stub_in * scale) or 0
      local tout = (n.w_stub_out > 0) and math.max(L.min_t, n.w_stub_out * scale) or 0
      n.t_stub_in, n.t_stub_out = tin, tout
      for _, l in ipairs(n.ins) do tin = tin + l.t end
      for _, l in ipairs(n.outs) do tout = tout + l.t end
      n.h = math.max(L.min_t, n.wvalue * scale, tin, tout)
      n.icon_above = true
      n.slot = V.NODE_HEAD + math.max(n.h, V.SLOT_MIN)
    end
  end
end

-- sizes + packing; returns total height
local function measure(L)
  local ncol = #L.cols
  local cx = L.col_x
  for _, ln in ipairs(L.lane_list) do
    ln.px0 = cx[ln.c0] - V.LANE_LEFT
    ln.px1 = cx[ln.c1] + V.NODE_W + V.LANE_RIGHT
    for _, sb in ipairs(ln.sub_list) do
      sb.px0 = cx[sb.c0] - V.LANE_LEFT + 10
      sb.px1 = cx[sb.c1] + V.NODE_W + V.LANE_RIGHT - 10
      local h = 0
      for _, list in pairs(sb.cols) do
        local s = -V.GAP_IN
        for _, n in ipairs(list) do s = s + n.slot + V.GAP_IN end
        if s > h then h = s end
      end
      sb.body = h
      sb.h = h + (ln.titled and V.SUB_HEAD or 0)
    end
    local body = pack(ln.sub_list, ncol, V.SUB_GAP)
    ln.h = V.LANE_HEAD + body + V.LANE_PAD
  end
  return pack(L.lane_list, ncol, V.LANE_GAP)
end

local function place_nodes(L)
  for _, ln in ipairs(L.lane_list) do
    ln.y0 = V.PAD_TOP + ln.y
    ln.y1 = ln.y0 + ln.h
    for _, sb in ipairs(ln.sub_list) do
      sb.y0 = ln.y0 + V.LANE_HEAD + sb.y
      sb.y1 = sb.y0 + sb.h
      local top = sb.y0 + (ln.titled and V.SUB_HEAD or 0)
      for _, list in pairs(sb.cols) do
        local y = top
        for _, n in ipairs(list) do
          n.top = y
          n.y = y + V.NODE_HEAD + (n.slot - V.NODE_HEAD - n.h) / 2
          y = y + n.slot + V.GAP_IN
        end
      end
    end
  end
end

local function order_bucket(list, us)
  local pos = us.pos or {}
  local keyed = {}
  for _, n in ipairs(list) do if pos[n.key] then keyed[#keyed + 1] = n end end
  for _, n in ipairs(list) do
    n.key_sort = pos[n.key]
    if not n.key_sort then
      local best = -1
      for _, k in ipairs(keyed) do
        if (k.bc or 0) <= (n.bc or 0) and pos[k.key] > best then best = pos[k.key] end
      end
      n.key_sort = best + 0.5 + (n.bc or 0) * 1e-7
    end
  end
  table.sort(list, function(a, b)
    if a.key_sort ~= b.key_sort then return a.key_sort < b.key_sort end
    return a.key < b.key
  end)
end

local function sweep(L, us, forward)
  local ncol = #L.cols
  local first, last, step = 2, ncol, 1
  if not forward then first, last, step = ncol - 1, 1, -1 end
  for c = first, last, step do
    for _, n in ipairs(L.cols[c]) do
      local ls = forward and n.ins or n.outs
      local sw, sy = 0, 0
      for _, l in ipairs(ls) do
        local o = forward and l.a or l.b
        sw = sw + l.w; sy = sy + l.w * center(o)
      end
      n.bc = (sw > 0) and (sy / sw) or center(n)
    end
    for _, ln in ipairs(L.lane_list) do
      for _, sb in ipairs(ln.sub_list) do
        if sb.cols[c] then order_bucket(sb.cols[c], us) end
      end
    end
    place_nodes(L)
  end
end

---------------------------------------------------------------------------
-- overlap minimisation on the backend geometry
---------------------------------------------------------------------------
-- crossings between the links of two nodes u, v in the same column (u above v).
-- Links on the same side cross when their far ends are in the opposite order.
local function pair_crossings(u, v)
  local c = 0
  for _, side in ipairs({ "ins", "outs" }) do
    local far = (side == "ins") and "a" or "b"
    for _, lu in ipairs(u[side]) do
      local yu = center(lu[far])
      for _, lv in ipairs(v[side]) do
        if center(lv[far]) < yu then c = c + math.min(lu.t, lv.t) end
      end
    end
  end
  return c
end

-- transpose heuristic: swap adjacent nodes in a bucket while it reduces weighted crossings
function V.optimise(L, us)
  local pos = us.pos or {}
  local improved, passes = true, 0
  while improved and passes < 4 do
    improved, passes = false, passes + 1
    for _, ln in ipairs(L.lane_list) do
      for _, sb in ipairs(ln.sub_list) do
        for _, list in pairs(sb.cols) do
          for i = 1, #list - 1 do
            local u, v = list[i], list[i + 1]
            if not pos[u.key] and not pos[v.key] then
              if pair_crossings(v, u) + 0.01 < pair_crossings(u, v) then
                list[i], list[i + 1] = v, u
                improved = true
              end
            end
          end
        end
      end
    end
    if improved then place_nodes(L) end
  end
  -- total crossings for the info line
  local total = 0
  for _, col in ipairs(L.cols) do
    table.sort(col, function(a, b) return a.y < b.y end)
    for i = 1, #col do
      for j = i + 1, math.min(#col, i + 12) do total = total + pair_crossings(col[i], col[j]) end
    end
  end
  L.crossing_cost = total
end

-- long links (spanning several columns): flat segment + one curve. Choose the variant whose
-- flat segment overlaps fewer node slots: flat at the source height then curve into the
-- target ("late"), or curve out of the source then flat at the target height ("early").
function V.route(L, us)
  -- right-angle preference: more ribbons take the metro route (90° crossings)
  local steep = (us and us.lines == "metro") and 0.3 or 0.9
  local cx = L.col_x
  local function overlap(ci0, ci1, y0, y1)
    local o = 0
    for ci = ci0, ci1 do
      for _, n in ipairs(L.cols[ci] or {}) do
        local a = math.max(y0, (n.top or n.y) - 4)
        local b = math.min(y1, (n.top or n.y) + n.slot + 4)
        if b > a then o = o + (b - a) end
      end
    end
    return o
  end
  for _, l in ipairs(L.links) do
    local ca, cb = l.a.ci, l.b.ci
    if cb - ca > 1 then
      local late = overlap(ca + 1, cb - 1, l.y1, l.y1 + l.t)
      local early = overlap(ca + 1, cb - 1, l.y2, l.y2 + l.t)
      if early < late then
        l.route = "early"
        l.curve_x0, l.curve_x1 = cx[ca] + V.NODE_W, cx[ca + 1]
      else
        l.route = "late"
        l.curve_x0, l.curve_x1 = cx[cb - 1] + V.NODE_W, cx[cb]
      end
    else
      l.route = "direct"
    end
    -- the curved part spans [cx0, cx1]
    if l.route == "direct" then l.cx0, l.cx1 = l.a.x + V.NODE_W, l.b.x
    else l.cx0, l.cx1 = l.curve_x0 or (cx[ca] + V.NODE_W), l.curve_x1 or cx[ca + 1] end
  end

  -- Orthogonal ("metro") routing for steep ribbons: an S-curve keeps a constant VERTICAL
  -- thickness, so a steep one turns into a hairline. Instead: bar → rounded corner →
  -- vertical bar → rounded corner → bar. Vertical runs get their own track in the gap.
  local gaps = {}
  for _, l in ipairs(L.links) do
    local w = l.cx1 - l.cx0
    local D = math.abs(l.y2 - l.y1)
    if w > 0 and D > steep * w then
      local k, q = S.elbow_index(math.min(0.7, l.t / (l.t + math.max(8, l.t * 0.6))))
      local R = l.t * (1 - q) / q
      if w >= 2 * R + l.t + 4 and D >= 2 * R + l.t + 2 then
        l.ortho = { k = k, R = R }
        local g = gaps[l.cx0]
        if not g then g = { x0 = l.cx0, x1 = l.cx1, links = {} }; gaps[l.cx0] = g end
        table.insert(g.links, l)
      end
    end
  end
  for _, g in pairs(gaps) do
    -- order tracks so ribbons going far down use the left tracks: fewer crossings at the corners
    table.sort(g.links, function(a, b)
      local da, db = a.y2 - a.y1, b.y2 - b.y1
      if (da > 0) ~= (db > 0) then return da > 0 end
      if da > 0 then return a.y1 > b.y1 end
      return a.y1 < b.y1
    end)
    local next_xv = g.x0
    for _, l in ipairs(g.links) do
      local R = l.ortho.R
      local xv = math.max(next_xv, g.x0 + R + 2)
      if xv + l.t + R > g.x1 - 2 then xv = g.x0 + R + 2 end -- out of room: start over
      l.ortho.xv = xv
      next_xv = xv + l.t + 4
    end
  end
end

-- Contrast colouring (graph colouring): nodes next to each other in a column, and ribbons
-- that enter the same node, never share a colour. Previous colours are kept when possible
-- so nothing flickers between refreshes.
function V.assign_colors(L, us)
  if us.color_mode ~= "contrast" then
    for _, n in pairs(L.nodes) do n.color = palette.material(n.key) end
    return
  end
  us.colors = us.colors or {}
  local K = palette.NCAT
  local nbr = {}
  local function add(a, b)
    if a == b then return end
    nbr[a] = nbr[a] or {}; nbr[b] = nbr[b] or {}
    nbr[a][b] = true; nbr[b][a] = true
  end
  for _, col in ipairs(L.cols) do
    local list = {}
    for _, n in ipairs(col) do list[#list + 1] = n end
    table.sort(list, function(a, b) return a.y < b.y end)
    for i = 1, #list - 1 do add(list[i], list[i + 1]) end
    for _, n in ipairs(col) do
      for i = 1, #n.ins do
        for j = i + 1, #n.ins do add(n.ins[i].a, n.ins[j].a) end
        if i > 1 then add(n.ins[i - 1].a, n.ins[i].a) end
      end
    end
  end
  for _, p in ipairs(L.extra_pairs or {}) do add(p[1], p[2]) end
  local order = {}
  for _, n in pairs(L.nodes) do order[#order + 1] = n end
  table.sort(order, function(a, b)
    local da, db = 0, 0
    for _ in pairs(nbr[a] or {}) do da = da + 1 end
    for _ in pairs(nbr[b] or {}) do db = db + 1 end
    if da ~= db then return da > db end
    return a.key < b.key
  end)
  local function hash(s)
    local h = 0
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 1000003 end
    return h % K + 1
  end
  for _, n in ipairs(order) do
    local base = n.base or n.key
    local used = {}
    for m in pairs(nbr[n] or {}) do if m.color then used[m.color] = true end end
    local pref = us.colors[base] or hash(base)
    local c = pref
    for i = 0, K - 1 do
      local cand = (pref - 1 + i) % K + 1
      if not used[cand] then c = cand; break end
    end
    n.color = c
    us.colors[base] = c
  end
end

-- lane order: hill-climb adjacent swaps that shorten the thickness-weighted vertical distance
-- between connected lanes (lanes the player moved with ▲/▼ stay put)
function V.optimise_lanes(L, us)
  local lpos = us.lpos or {}
  local pairs_w = {}
  for _, l in ipairs(L.links) do
    local a, b = l.a.lane, l.b.lane
    if a ~= b then
      local k = (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
      pairs_w[k] = (pairs_w[k] or 0) + l.t
    end
  end
  local function cost()
    measure(L)
    local cy = {}
    for _, ln in ipairs(L.lane_list) do cy[ln.id] = ln.y + ln.h / 2 end
    local c = 0
    for k, w in pairs(pairs_w) do
      local a, b = string.match(k, "^(.-)|(.*)$")
      if cy[a] and cy[b] then c = c + w * math.abs(cy[a] - cy[b]) end
    end
    return c
  end
  local list = L.lane_list
  local best = cost()
  for _ = 1, 12 do
    local improved = false
    for i = 1, #list - 1 do
      if not lpos[list[i].id] and not lpos[list[i + 1].id] then
        list[i], list[i + 1] = list[i + 1], list[i]
        local c = cost()
        if c + 1e-6 < best then best, improved = c, true
        else list[i], list[i + 1] = list[i + 1], list[i] end
      end
    end
    if not improved then break end
  end
  L.lane_cost = best
end

function V.layout(L, us, W, viewH)
  local ncol = #L.cols
  local span = math.max(W - V.PAD_L - V.PAD_R - V.NODE_W, (ncol - 1) * (V.NODE_W + V.F_MIN_GAP))
  for ci, col in ipairs(L.cols) do
    local x = V.PAD_L + ((ncol > 1) and math.floor(span * (ci - 1) / (ncol - 1) + 0.5) or math.floor(span / 2))
    for _, n in ipairs(col) do n.x = x end
  end
  L.col_x = {}
  for ci, col in ipairs(L.cols) do L.col_x[ci] = col[1].x end
  L.label_above, L.label_w = true, {}
  for ci = 1, ncol do
    L.label_w[ci] = ci < ncol and (L.col_x[ci + 1] - L.col_x[ci] - 8) or 260
  end
  L.content_w = (L.col_x[ncol] or V.PAD_L) + V.NODE_W + math.max(V.PAD_R, 270)

  build_structure(L, us)

  -- fit: find the scale where the packed height fills the viewport (then × zoom)
  size_nodes(L, 0)
  local H0 = measure(L)
  -- the viewport, but never so small that flows are squeezed to their minimum thickness
  local target = math.max(viewH - V.PAD_TOP - V.PAD_BOTTOM, H0 / (1 - V.FLOW_SHARE))
  local maxw = 0
  for _, l in ipairs(L.links) do if l.w > maxw then maxw = l.w end end
  local s = (maxw > 0) and (target * 0.25 / maxw) or 1
  for _ = 1, 3 do
    size_nodes(L, s)
    local H1 = measure(L)
    if H1 - H0 < 1 then break end
    s = s * math.max(0.05, (target - H0) / (H1 - H0))
  end
  if s <= 0 or s ~= s then s = 1e-6 end
  L.fit = s
  L.scale = us.keep_layout and us.layout_snapshot.scale or s * (us.zoom or 1)
  size_nodes(L, L.scale)
  L.H = measure(L)
  if not us.keep_layout then V.optimise_lanes(L, us) end
  L.H = measure(L)

  -- initial order: previous refresh's order (stability), then barycenter sweeps
  local prev = us.auto_rank or {}
  for _, col in ipairs(L.cols) do for _, n in ipairs(col) do n.bc = prev[n.key] or 1e6 end end
  for _, ln in ipairs(L.lane_list) do
    for _, sb in ipairs(ln.sub_list) do
      for _, list in pairs(sb.cols) do order_bucket(list, us) end
    end
  end
  place_nodes(L)
  for _ = 1, us.keep_layout and 0 or 3 do
    sweep(L, us, true)
    sweep(L, us, false)
  end
  if not us.keep_layout then V.optimise(L, us) end

  -- ribbon stacking at both ends (ordered by the other end's y), then stubs
  L.clamped = 0
  for _, l in ipairs(L.links) do if l.w * L.scale < L.min_t then L.clamped = L.clamped + 1 end end
  for _, col in ipairs(L.cols) do
    for _, n in ipairs(col) do
      table.sort(n.outs, function(a, b) if a.b.y ~= b.b.y then return a.b.y < b.b.y end return a.to < b.to end)
      table.sort(n.ins, function(a, b) if a.a.y ~= b.a.y then return a.a.y < b.a.y end return a.from < b.from end)
      local off = 0
      for _, l in ipairs(n.outs) do l.y1 = n.y + off; off = off + l.t end
      n.stub_out_y = n.y + off
      off = 0
      for _, l in ipairs(n.ins) do l.y2 = n.y + off; off = off + l.t end
      n.stub_in_y = n.y + off
    end
  end

  V.route(L, us)
  V.assign_colors(L, us)

  -- remember the automatic order (next refresh starts from it) and the displayed order for ▲/▼
  us.auto_rank = {}
  for _, col in ipairs(L.cols) do for _, n in ipairs(col) do us.auto_rank[n.key] = n.y end end
  L.order = {}
  for _, ln in ipairs(L.lane_list) do
    for _, sb in ipairs(ln.sub_list) do
      for ci, list in pairs(sb.cols) do
        local keys = {}
        for i, n in ipairs(list) do keys[i] = n.key end
        L.order[sb.id .. "@" .. ci] = keys
      end
    end
  end
  L.lane_order, L.sub_order = {}, {}
  for i, ln in ipairs(L.lane_list) do
    L.lane_order[i] = ln.id
    L.sub_order[ln.id] = {}
    for j, sb in ipairs(ln.sub_list) do L.sub_order[ln.id][j] = sb.id end
  end
  L.content_h = math.floor(V.PAD_TOP + L.H + V.PAD_BOTTOM + 0.5)
end

---------------------------------------------------------------------------
-- Layered layout with reserved header bands and via slots; crossings can remain.
--   * columns = longest path inside the focused subgraph
--   * a link that skips columns gets an invisible "via" slot in every column it passes,
--     stacked like a node, so its straight run can never lie on a node or another run
--   * order: barycenter sweeps + transpose over nodes AND vias (crossings minimised)
--   * y: stacked with gaps, then pulled toward their neighbours' ports (keeps vias straight)
--   * gaps between columns are widened until every vertical (right-angle) run has its own
--     track; ribbons only ever CROSS, never run on top of each other
--   * labels sit above their node, inside the node's slot
---------------------------------------------------------------------------
V.F_GAP = 14       -- vertical gap between slots
V.F_BAR_MIN = 22   -- a node bar is never thinner than this (ribbons are centred on it)
V.F_MIN_GAP = 140  -- minimum horizontal gap between columns
V.F_MAX_GAP = 420

function V.layout_focus(L, us, W, viewH, wide)
  local ncol = #L.cols
  -- the whole-base view is wide (scrolls sideways): tighter gaps, fewer dedicated tracks
  local MIN_GAP = (wide and 32 or V.F_MIN_GAP) + V.HEADER_W - V.NODE_W
  local MAX_GAP = wide and 300 or V.F_MAX_GAP
  local cols = {}
  for ci = 1, ncol do cols[ci] = {} end
  for ci, col in ipairs(L.cols) do
    for _, n in ipairs(col) do n.ci = ci; n.fins, n.fouts = {}, {}; table.insert(cols[ci], n) end
  end

  -- 1. split long links into segments through via slots
  local segs = {}
  for _, l in ipairs(L.links) do
    local a, b = l.a, l.b
    local prev = a
    for ci = a.ci + 1, b.ci - 1 do
      local v = { kind = "via", key = l.from .. ">" .. l.to .. "@" .. ci, ci = ci, link = l,
                  ins = {}, outs = {}, ginfo = a.ginfo, color = nil }
      table.insert(cols[ci], v)
      local s = { a = prev, b = v, link = l, from = l.from, to = l.to, rate = l.rate, w = l.w }
      if prev == a then l.first_seg = s end
      table.insert((prev.kind == "via") and prev.outs or prev.fouts, s); table.insert(v.ins, s); segs[#segs + 1] = s
      prev = v
    end
    local s = { a = prev, b = b, link = l, from = l.from, to = l.to, rate = l.rate, w = l.w }
    l.first_seg = (prev.kind == "via") and l.first_seg or s
    if prev.kind == "via" then table.insert(prev.outs, s) else table.insert(prev.fouts, s) end
    table.insert(b.fins, s); segs[#segs + 1] = s
  end

  -- Fit complete columns, including port stacks, headers and invisible long-link
  -- slots. Dense columns retain scrolling at the minimum readable geometry.
  local function packed(scale)
    local highest=0
    for _,col in ipairs(cols) do
      local h=0
      for _,n in ipairs(col) do
        if n.kind=="via" then h=h+math.max(L.min_t,n.link.w*scale)+V.F_GAP
        else
          local tin=n.w_stub_in>0 and math.max(L.min_t,n.w_stub_in*scale) or 0
          local tout=n.w_stub_out>0 and math.max(L.min_t,n.w_stub_out*scale) or 0
          for _,l in ipairs(n.ins) do tin=tin+math.max(L.min_t,l.w*scale) end
          for _,l in ipairs(n.outs) do tout=tout+math.max(L.min_t,l.w*scale) end
          h=h+V.NODE_HEAD+math.max(V.F_BAR_MIN,n.wvalue*scale,tin,tout)+V.F_GAP
        end
      end
      highest=math.max(highest,h-V.F_GAP)
    end
    return highest
  end
  local weight=0
  for _,n in pairs(L.nodes) do weight=math.max(weight,n.wvalue) end
  local lo,hi=0,weight>0 and 140/weight or 1
  local viewport_room=math.max(100,viewH-V.PAD_TOP-V.PAD_BOTTOM-24) -- scrollbars and pane padding
  local target=math.max(viewport_room,packed(0))
  for _=1,32 do
    local mid=(lo+hi)/2
    if packed(mid)<=target+0.01 then lo=mid else hi=mid end
  end
  local s=lo
  L.fit = s
  L.scale = us.keep_layout and us.layout_snapshot.scale or s * (us.zoom or 1)
  for _, l in ipairs(L.links) do l.t = math.max(L.min_t, l.w * L.scale) end
  for _, sg in ipairs(segs) do sg.t = sg.link.t end
  for ci = 1, ncol do
    for _, n in ipairs(cols[ci]) do
      if n.kind == "via" then
        n.h = n.link.t
        n.slot = n.h
      else
        local tin = (n.w_stub_in > 0) and math.max(L.min_t, n.w_stub_in * L.scale) or 0
        local tout = (n.w_stub_out > 0) and math.max(L.min_t, n.w_stub_out * L.scale) or 0
        n.t_stub_in, n.t_stub_out = tin, tout
        for _, l in ipairs(n.ins) do tin = tin + l.t end
        for _, l in ipairs(n.outs) do tout = tout + l.t end
        n.tin, n.tout = tin, tout
        n.h = math.max(V.F_BAR_MIN, L.min_t, n.wvalue * L.scale, tin, tout)
        -- a thin bar would hide behind its icon: then the icon sits above the bar
        n.icon_above = true
        n.slot = V.NODE_HEAD + n.h
      end
    end
  end
  L.clamped = 0
  for _, l in ipairs(L.links) do if l.w * L.scale < L.min_t then L.clamped = L.clamped + 1 end end

  -- port helpers: bar top of a slot, and centre of the bar
  local function bar_y(n)
    if n.kind == "via" then return n.top end
    return n.top + V.NODE_HEAD
  end
  local function mid(n) return bar_y(n) + n.h / 2 end
  local function ins_of(n) return (n.kind == "via") and n.ins or n.fins end
  local function outs_of(n) return (n.kind == "via") and n.outs or n.fouts end

  -- 3. order: previous order, then barycenter sweeps + transpose
  local function stack(ci)
    local y = V.PAD_TOP
    for _, n in ipairs(cols[ci]) do n.top = y; y = y + n.slot + V.F_GAP end
  end
  local prev = us.auto_rank or {}
  for ci = 1, ncol do
    table.sort(cols[ci], function(a, b)
      local pa, pb = prev[a.key] or 1e9, prev[b.key] or 1e9
      if pa ~= pb then return pa < pb end
      return a.key < b.key
    end)
    stack(ci)
  end
  local function bary(n, forward)
    local sw, sy = 0, 0
    for _, sg in ipairs(forward and ins_of(n) or outs_of(n)) do
      local o = forward and sg.a or sg.b
      sw = sw + sg.t; sy = sy + sg.t * mid(o)
    end
    return (sw > 0) and sy / sw or mid(n)
  end
  local function sweep_once(forward)
    local a0, a1, st = 2, ncol, 1
    if not forward then a0, a1, st = ncol - 1, 1, -1 end
    for ci = a0, a1, st do
      for _, n in ipairs(cols[ci]) do n.bc = bary(n, forward) end
      table.sort(cols[ci], function(a, b) if a.bc ~= b.bc then return a.bc < b.bc end return a.key < b.key end)
      stack(ci)
    end
  end
  for _ = 1, us.keep_layout and 0 or 4 do sweep_once(true); sweep_once(false) end
  -- crossings between two slots u (above) and v of the same column
  local function cross(u, v)
    local c = 0
    for _, side in ipairs({ true, false }) do
      local lu = side and ins_of(u) or outs_of(u)
      local lv = side and ins_of(v) or outs_of(v)
      for _, a in ipairs(lu) do
        local ya = mid(side and a.a or a.b)
        for _, b in ipairs(lv) do
          if mid(side and b.a or b.b) < ya then c = c + math.min(a.t, b.t) end
        end
      end
    end
    return c
  end
  for _ = 1, us.keep_layout and 0 or 4 do
    local improved = false
    for ci = 1, ncol do
      local list = cols[ci]
      for i = 1, #list - 1 do
        if cross(list[i + 1], list[i]) + 0.01 < cross(list[i], list[i + 1]) then
          list[i], list[i + 1] = list[i + 1], list[i]
          improved = true
        end
      end
      stack(ci)
    end
    if not improved then break end
  end

  -- 4. y: Brandes–Köpf coordinate assignment (as in dagre / ELK). Nodes are aligned into
  --    vertical "blocks" with their median neighbour (so a long ribbon's vias line up into
  --    one straight run), blocks are compacted with real slot sizes, and the four
  --    alignments (left/right neighbours × top/bottom bias) are balanced.
  local function ports()
    for ci = 1, ncol do
      for _, n in ipairs(cols[ci]) do
        n.y = bar_y(n)
        local o, i = outs_of(n), ins_of(n)
        table.sort(o, function(a, b) local ya, yb = mid(a.b), mid(b.b); if ya ~= yb then return ya < yb end return a.to < b.to end)
        table.sort(i, function(a, b) local ya, yb = mid(a.a), mid(b.a); if ya ~= yb then return ya < yb end return a.from < b.from end)
        local off = (n.kind == "via") and 0 or (n.h - (n.tout or 0)) / 2
        for _, sg in ipairs(o) do sg.y1 = n.y + off; off = off + sg.t end
        off = (n.kind == "via") and 0 or (n.h - (n.tin or 0)) / 2
        for _, sg in ipairs(i) do sg.y2 = n.y + off; off = off + sg.t end
      end
    end
  end
  for ci = 1, ncol do for p_, n in ipairs(cols[ci]) do n.pos = p_ end end
  -- type-1 conflicts: a non-inner segment crossing an inner (via→via) segment loses
  local marked = {}
  local by_gap = {}
  for _, sg in ipairs(segs) do
    local ci = sg.a.ci
    by_gap[ci] = by_gap[ci] or {}
    table.insert(by_gap[ci], sg)
  end
  for _, list in pairs(by_gap) do
    for _, s1 in ipairs(list) do
      if s1.a.kind == "via" and s1.b.kind == "via" then
        for _, s2 in ipairs(list) do
          if not (s2.a.kind == "via" and s2.b.kind == "via") then
            if (s1.a.pos - s2.a.pos) * (s1.b.pos - s2.b.pos) < 0 then marked[s2] = true end
          end
        end
      end
    end
  end
  local function delta(u, v) return u.slot / 2 + V.F_GAP + v.slot / 2 end
  local results = {}
  for _, vdir in ipairs({ "pred", "succ" }) do
    for _, hdir in ipairs({ 1, -1 }) do
      local root, align, sink, shift, x = {}, {}, {}, {}, {}
      local all = {}
      for ci = 1, ncol do for _, n in ipairs(cols[ci]) do all[#all + 1] = n; root[n] = n; align[n] = n; sink[n] = n; shift[n] = math.huge end end
      local function mp(n) return (hdir == 1) and n.pos or (#cols[n.ci] + 1 - n.pos) end
      local function at(ci, k) -- k-th node of column ci in mirrored order
        local list = cols[ci]
        return (hdir == 1) and list[k] or list[#list + 1 - k]
      end
      -- vertical alignment
      local c0, c1, st = 2, ncol, 1
      if vdir == "succ" then c0, c1, st = ncol - 1, 1, -1 end
      for ci = c0, c1, st do
        local r = -math.huge
        for k = 1, #cols[ci] do
          local v = at(ci, k)
          local nb = {}
          local lst = (vdir == "pred") and ins_of(v) or outs_of(v)
          for _, sg in ipairs(lst) do nb[#nb + 1] = { n = (vdir == "pred") and sg.a or sg.b, sg = sg } end
          if #nb > 0 then
            table.sort(nb, function(p1, p2) return mp(p1.n) < mp(p2.n) end)
            local d = #nb
            for _, m in ipairs({ math.floor((d + 1) / 2), math.ceil((d + 1) / 2) }) do
              if align[v] == v then
                local u, sg = nb[m].n, nb[m].sg
                if not marked[sg] and r < mp(u) then
                  align[u] = v; root[v] = root[u]; align[v] = root[v]; r = mp(u)
                end
              end
            end
          end
        end
      end
      -- horizontal compaction (Lua recursion depth is fine for a few thousand blocks)
      local function place_block(v)
        if x[v] then return end
        x[v] = 0
        local w = v
        repeat
          local k = mp(w)
          if k > 1 then
            local pw = at(w.ci, k - 1)
            local u = root[pw]
            place_block(u)
            if sink[v] == v then sink[v] = sink[u] end
            if sink[v] ~= sink[u] then
              shift[sink[u]] = math.min(shift[sink[u]], x[v] - x[u] - delta(pw, w))
            else
              x[v] = math.max(x[v], x[u] + delta(pw, w))
            end
          end
          w = align[w]
        until w == v
      end
      for _, n in ipairs(all) do if root[n] == n then place_block(n) end end
      local out = {}
      for _, n in ipairs(all) do
        local rv = root[n]
        local y = x[rv]
        local sh = shift[sink[rv]]
        if sh < math.huge then y = y + sh end
        out[n] = y * hdir
      end
      results[#results + 1] = { y = out, h = hdir }
    end
  end
  -- balance: align all four to the narrowest, then average the two median values
  local function extent(r)
    local lo, hi = math.huge, -math.huge
    for n, y in pairs(r.y) do
      if y - n.slot / 2 < lo then lo = y - n.slot / 2 end
      if y + n.slot / 2 > hi then hi = y + n.slot / 2 end
    end
    return lo, hi
  end
  local best, bw
  for _, r in ipairs(results) do
    r.lo, r.hi = extent(r)
    if not bw or r.hi - r.lo < bw then best, bw = r, r.hi - r.lo end
  end
  for _, r in ipairs(results) do
    local d = (r.h == 1) and (best.lo - r.lo) or (best.hi - r.hi)
    for n, y in pairs(r.y) do r.y[n] = y + d end
  end
  for ci = 1, ncol do
    for _, n in ipairs(cols[ci]) do
      local v = {}
      for k, r in ipairs(results) do v[k] = r.y[n] end
      table.sort(v)
      n.top = us.keep_layout and us.layout_snapshot.tops[n.key] or (v[2] + v[3]) / 2 - n.slot / 2
    end
    -- safety: keep order and gaps (balancing can squeeze neighbours)
    local list = cols[ci]
    for i = 2, #list do
      local lim = list[i - 1].top + list[i - 1].slot + V.F_GAP
      if list[i].top < lim then list[i].top = lim end
    end
  end
  -- The balanced alignment can leave large empty stretches between branches.
  -- Project it into the measured packed height, retaining order and all reserved
  -- slots. This fits the finished geometry, not just the sum of flow weights.
  if not us.keep_layout then
    local low,high=math.huge,-math.huge
    for _,col in ipairs(cols) do for _,n in ipairs(col) do
      low=math.min(low,n.top); high=math.max(high,n.top+n.slot)
    end end
    local available=math.max(viewport_room,packed(L.scale))
    if high-low>available+0.01 then
      for _,col in ipairs(cols) do
        local bottom=V.PAD_TOP
        for _,n in ipairs(col) do
          local desired=V.PAD_TOP+(n.top-low)/math.max(1,high-low-n.slot)*math.max(0,available-n.slot)
          n.top=math.max(bottom,desired)
          bottom=n.top+n.slot+V.F_GAP
        end
        bottom=V.PAD_TOP+available
        for j=#col,1,-1 do
          local n=col[j]
          n.top=math.min(n.top,bottom-n.slot)
          bottom=n.top-V.F_GAP
        end
      end
    end
  end
  ports()
  -- Center the finished bounds when they fit. Retain live positions after the
  -- first layout; graphs that exceed the viewport start at the readable top.
  local miny,maxy = math.huge,-math.huge
  for _,col in ipairs(cols) do for _,n in ipairs(col) do
    miny=math.min(miny,n.top); maxy=math.max(maxy,n.top+n.slot)
  end end
  local dy=us.keep_layout and math.max(0,V.PAD_TOP-miny)
    or V.PAD_TOP-miny+math.max(0,(viewport_room-(maxy-miny))/2)
  local H = 0
  for ci = 1, ncol do
    for _, n in ipairs(cols[ci]) do
      n.top = n.top + dy
      n.y = bar_y(n)
      if n.top + n.slot > H then H = n.top + n.slot end
    end
  end

  -- 5. port stacking (ordered by the far end's y), stubs below
  for ci = 1, ncol do
    for _, n in ipairs(cols[ci]) do
      local o, i = outs_of(n), ins_of(n)
      table.sort(o, function(a, b) local ya, yb = mid(a.b), mid(b.b); if ya ~= yb then return ya < yb end return a.to < b.to end)
      table.sort(i, function(a, b) local ya, yb = mid(a.a), mid(b.a); if ya ~= yb then return ya < yb end return a.from < b.from end)
      -- ribbons + stub are centred on the bar on each side
      local off = (n.kind == "via") and 0 or (n.h - (n.tout or 0)) / 2
      for _, sg in ipairs(o) do sg.y1 = n.y + off; off = off + sg.t end
      if n.kind ~= "via" then n.stub_out_y = n.y + off end
      off = (n.kind == "via") and 0 or (n.h - (n.tin or 0)) / 2
      for _, sg in ipairs(i) do sg.y2 = n.y + off; off = off + sg.t end
      if n.kind ~= "via" then n.stub_in_y = n.y + off end
    end
  end

  -- 6. columns' x: every gap gets room for its vertical tracks (right angles) + stubs
  local metro = us.lines == "metro"
  local gap_need = {}
  for ci = 1, ncol - 1 do gap_need[ci] = MIN_GAP end
  local function ortho_params(sg)
    local k, q = S.elbow_index(math.min(0.7, sg.t / (sg.t + math.max(8, sg.t * 0.6))))
    return k, sg.t * (1 - q) / q
  end
  local gap_segs = {}
  for _, sg in ipairs(segs) do
    local ci = sg.a.ci
    gap_segs[ci] = gap_segs[ci] or {}
    table.insert(gap_segs[ci], sg)
  end
  if metro then
    for ci, list in pairs(gap_segs) do
      local need, rmax = 0, 0
      for _, sg in ipairs(list) do
        local D = math.abs(sg.y2 - sg.y1)
        if D > 0.3 * MIN_GAP then
          local _, R = ortho_params(sg)
          need = need + sg.t + 6
          if R > rmax then rmax = R end
        end
      end
      gap_need[ci] = math.max(MIN_GAP, V.HEADER_W - V.NODE_W + need + 2 * rmax + 2 * V.STUB + 16)
    end
  end
  local right_pad = V.HEADER_W + 8 - V.NODE_W
  local avail = W - V.PAD_L - right_pad - ncol * V.NODE_W
  local sum = 0
  for ci = 1, ncol - 1 do sum = sum + gap_need[ci] end
  local extra = (ncol > 1) and math.max(0, (avail - sum) / (ncol - 1)) or 0
  local x = V.PAD_L
  if ncol == 1 then x = math.max(V.PAD_L,math.floor((W-V.HEADER_W)/2)) end
  if us.keep_layout then x=us.layout_snapshot.col_x[1] or x end
  L.col_x = {}
  for ci = 1, ncol do
    L.col_x[ci] = math.floor(x + 0.5)
    for _, n in ipairs(cols[ci]) do n.x = L.col_x[ci] end
    if ci < ncol then
      x = math.floor(L.col_x[ci] + V.NODE_W + math.max(gap_need[ci], math.min(MAX_GAP, gap_need[ci] + extra)) + 0.5)
      if us.keep_layout then
        x = math.max(us.layout_snapshot.col_x[ci + 1] or x,
          math.floor(L.col_x[ci] + V.NODE_W + gap_need[ci] + 0.5))
      end
    end
  end
  L.content_w = x + V.NODE_W + right_pad
  if ncol>1 and not us.keep_layout and L.content_w<W then
    local dx=math.floor((W-L.content_w)/2)
    for ci,col in ipairs(cols) do
      L.col_x[ci]=L.col_x[ci]+dx
      for _,n in ipairs(col) do n.x=L.col_x[ci] end
    end
    L.content_w=L.content_w+dx
  end
  L.content_w=math.max(W,L.content_w)

  -- 7. routes: straight if level, else S-curve or right-angle track inside the gap
  for ci, list in pairs(gap_segs) do
    local x0, x1 = L.col_x[ci] + V.HEADER_W, L.col_x[ci + 1]
    local tracks = {}
    for _, sg in ipairs(list) do
      -- Stay level throughout the header band; all turns happen beyond labels.
      sg.route, sg.curve_x0, sg.cx0, sg.cx1 = "late", x0, x0, x1
      local D = math.abs(sg.y2 - sg.y1)
      if metro and D > 0.3 * (x1 - x0) then
        local k, R = ortho_params(sg)
        if D >= 2 * R + sg.t + 2 then
          sg.ortho = { k = k, R = R }
          tracks[#tracks + 1] = sg
        end
      end
    end
    -- downward runs on the left, ordered so corners nest instead of crossing
    table.sort(tracks, function(a, b)
      local da, db = a.y2 - a.y1, b.y2 - b.y1
      if (da > 0) ~= (db > 0) then return da > 0 end
      if da > 0 then return a.y1 > b.y1 end
      return a.y1 < b.y1
    end)
    -- a route's departure leg (at its source height, x0 → corner) must not lie on another
    -- route's arrival leg (corner → x1) when their heights overlap: the one that leaves
    -- has to turn before the other one comes in
    local placed = {}
    local function yover(a0, a1, b0, b1) return math.min(a1, b1) - math.max(a0, b0) > 0.5 end
    local xv = x0 + V.STUB + 8
    for _, sg in ipairs(tracks) do
      local R, t = sg.ortho.R, sg.t
      local lo = math.max(xv, x0 + V.STUB + 8 + R)
      local hi = x1 - V.STUB - 8 - t - R
      for _, p in ipairs(placed) do
        if yover(sg.y1, sg.y1 + t, p.y2, p.y2 + p.t) then
          hi = math.min(hi, p.ortho.xv + p.t + p.ortho.R + R)       -- turn before p arrives
        end
        if yover(sg.y2, sg.y2 + t, p.y1, p.y1 + p.t) then
          lo = math.max(lo, p.ortho.xv - p.ortho.R - t - R)          -- arrive after p left
        end
      end
      if lo > hi then
        sg.ortho = nil -- no clean track: an S-curve crosses instead
      else
        sg.ortho.xv = lo
        xv = lo + t + 6
        placed[#placed + 1] = sg
      end
    end
  end

  -- 8. hand the drawer real nodes + segments (vias stay invisible)
  local real = {}
  for ci = 1, ncol do
    real[ci] = {}
    for _, n in ipairs(cols[ci]) do if n.kind ~= "via" then table.insert(real[ci], n) end end
  end
  L.cols = real
  for _, sg in ipairs(segs) do
    sg.via_from = sg.a.kind == "via"
    sg.src = sg.link.a
  end
  L.segments = segs
  L.label_above = true
  L.label_w = {}
  for ci = 1, ncol do
    L.label_w[ci] = V.HEADER_W - 8
  end
  L.lane_list = {}
  -- ribbons that cross inside a gap get different colours
  L.extra_pairs = {}
  for _, list in pairs(gap_segs) do
    for i = 1, #list do
      for j = i + 1, #list do
        local a, b = list[i], list[j]
        if (a.y1 - b.y1) * (a.y2 - b.y2) < 0 then
          L.extra_pairs[#L.extra_pairs + 1] = { a.link.a, b.link.a }
        end
      end
    end
  end
  V.assign_colors(L, us)
  for _, sg in ipairs(segs) do sg.color = sg.link.a.color end

  local total = 0
  for ci = 1, ncol do
    local list = cols[ci]
    for i = 1, #list do for j = i + 1, math.min(#list, i + 12) do total = total + cross(list[i], list[j]) end end
  end
  L.crossing_cost = total
  us.auto_rank = {}
  for ci = 1, ncol do for _, n in ipairs(cols[ci]) do us.auto_rank[n.key] = n.top end end
  L.order, L.lane_order, L.sub_order = {}, {}, {}
  L.H = H
  L.content_h = math.floor(H + V.PAD_BOTTOM + 0.5)
end

return V
