local Cells = require("scripts.cells")
local Capacity = require("scripts.cell_capacity")
local Sampler = require("scripts.sampler")
local Loc = require("scripts.locale")

local Flow = {}

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

function Flow.records()
  return storage.production_cells and storage.production_cells.records or {}
end

-- Production order. A cell is in stage 1 unless another cell on its surface
-- makes one of its inputs; then it comes one stage after the latest such cell.
-- Smelting therefore precedes casting, which precedes the cells using the
-- castings. Cells feeding each other in a loop are ordered by creation: the
-- oldest waiting cell is placed first.
function Flow.stages(ids, records, port_overrides)
  local makers, ports = {}, {}
  for _, id in ipairs(ids) do
    local record = records[id]
    ports[id] = port_overrides and port_overrides[id] or Cells.boundary(record)
    for key in pairs(ports[id].outputs) do
      local where = record.surface_index .. "|" .. key
      makers[where] = makers[where] or {}
      table.insert(makers[where], id)
    end
  end
  local feeds, fanout = {}, {}
  for _, id in ipairs(ids) do
    feeds[id], fanout[id] = {}, 0
    for key in pairs(ports[id].inputs) do
      for _, maker in ipairs(makers[records[id].surface_index .. "|" .. key] or {}) do
        if maker ~= id then feeds[id][maker] = true end
      end
    end
  end
  for _, id in ipairs(ids) do
    for maker in pairs(feeds[id]) do
      fanout[maker] = (fanout[maker] or 0) + 1
    end
  end
  local stage, waiting = {}, #ids
  while waiting > 0 do
    local placed = false
    for _, id in ipairs(ids) do
      if not stage[id] then
        local ready, at = true, 1
        for maker in pairs(feeds[id]) do
          if not stage[maker] then ready = false; break end
          at = math.max(at, stage[maker] + 1)
        end
        if ready then stage[id], waiting, placed = at, waiting - 1, true end
      end
    end
    if not placed then
      -- Break cycles by placing the cell with the widest downstream fanout
      -- first (fewest unplaced feeders, then creation order as tie-breakers).
      local best, best_fanout, best_waiting
      for _, id in ipairs(ids) do
        if not stage[id] then
          local unplaced = 0
          for maker in pairs(feeds[id]) do
            if not stage[maker] then unplaced = unplaced + 1 end
          end
          local f = fanout[id] or 0
          if not best or f > best_fanout or (f == best_fanout and unplaced < best_waiting) then
            best, best_fanout, best_waiting = id, f, unplaced
          end
        end
      end
      local at = 1
      for maker in pairs(feeds[best]) do
        if stage[maker] then at = math.max(at, stage[maker] + 1) end
      end
      stage[best], waiting = at, waiting - 1
    end
  end
  return stage
end

---@param surface_index integer? Only cells on this surface.
---@return integer[] ids In production order, then by creation.
---@return table<integer, integer> stage
function Flow.ids(surface_index, scope)
  local records, ids = Flow.records(), {}
  for _, id in ipairs(sorted_keys(records)) do
    if records[id].parent_id == scope and (not surface_index or records[id].surface_index == surface_index) then
      ids[#ids + 1] = id
    end
  end
  local stage = Flow.stages(ids, records)
  table.sort(ids, function(a, b)
    if stage[a] ~= stage[b] then return stage[a] < stage[b] end
    return a < b
  end)
  return ids, stage
end

-- Measured: crafts the sampler attributed to the cell over the period.
function Flow.measured_rates(record, period, exclusive, since, pre_sources, pre_period_start)
  local recipes, seconds, requested = Sampler.cell_rates(record.id, record.surface_index, period,
    math.max(record.since or 0, since or 0), exclusive, pre_sources, pre_period_start)
  local rates = {}
  for name, rate in pairs(recipes) do
    if storage.graph.recipes[name] then
      rates[name] = { normal = rate.normal_cps, bonus = math.max(0, rate.cps - rate.normal_cps) }
    end
  end
  return rates, seconds, requested
end

-- Share of capacity in use, weighted by crafting time so recipes of different
-- lengths compare fairly. nil when the cell has no capacity.
local function utilisation(measured, capacity)
  local used, available = 0, 0
  local recipes = storage.graph.recipes
  for name, rate in pairs(capacity) do available = available + rate.normal * recipes[name].energy end
  for name, rate in pairs(measured) do
    if recipes[name] then used = used + rate.normal * recipes[name].energy end
  end
  if available <= 1e-9 then return nil end
  return used / available
end
Flow.utilisation = utilisation

local function percent(fraction)
  return Loc("cells-percent", string.format("%.0f", fraction * 100))
end
Flow.percent = percent

local function node(graph, key)
  local n = graph.nodes[key]
  if not n then
    n = { key = key, kind = key:match("^(%a+)/"), prod = 0, cons = 0, loops = {}, contrib = {} }
    graph.nodes[key] = n
  end
  return n
end

local function connect(graph, from, to, amount)
  if amount <= 1e-6 then return end
  local a, b = node(graph, from), node(graph, to)
  if a.kind ~= "recipe" then a.cons = a.cons + amount end
  if b.kind ~= "recipe" then
    b.prod = b.prod + amount
    b.contrib[#b.contrib + 1] = { rate = amount, via = {from} }
  end
  local id = from .. ">" .. to
  local link = graph.links[id]
  if not link then
    link = { from = from, to = to, rate = 0, details = {} }
    graph.links[id] = link
  end
  link.rate = link.rate + amount
end

local function fmt(value)
  return string.format(value >= 100 and "%.0f" or value >= 10 and "%.1f" or "%.2f", value)
end

local function add_fuel(graph, fuels)
  graph.fuel_returns = {}
  for _, key in ipairs(sorted_keys(fuels)) do
    local users, demand = fuels[key], 0
    local recipes = sorted_keys(users)
    for _, name in ipairs(recipes) do demand = demand + users[name] end
    local material = graph.nodes[key]
    local available = material and (material.prod - material.cons) or 0
    local internal = demand > 0 and math.max(0, math.min(1, available / demand)) or 0
    local consumers = {}
    for _, name in ipairs(recipes) do
      local recipe, rate = "recipe/" .. name, users[name]
      if rate * internal > 1e-6 then
        consumers[#consumers + 1] = { key = recipe, rate = rate * internal }
        material.cons = material.cons + rate * internal
        material.loop_out = (material.loop_out or 0) + rate * internal
      end
      if rate * (1 - internal) > 1e-6 then
        local supply = node(graph, key .. "#cell-fuel-input")
        supply.group_key = key
        supply.note = Loc("cells-fuel-external")
        connect(graph, supply.key, recipe, rate * (1 - internal))
      end
    end
    if #consumers > 0 then
      material.note = Loc("cells-fuel-cold-start")
      graph.fuel_returns[#graph.fuel_returns + 1] = { key = key, consumers = consumers }
    end
  end
end

-- Trace the selected outputs upstream through ingredients and internal fuel.
-- A product used inside the cell gets a separate endpoint for its surplus.
local function trace_boundary(graph, ports)
  local pending, keep, upstream = {}, {}, {}
  local function require_node(key)
    if not keep[key] then
      keep[key] = true
      pending[#pending + 1] = key
    end
  end
  local function depends_on(to, from)
    upstream[to] = upstream[to] or {}
    upstream[to][#upstream[to] + 1] = from
  end
  for _, key in ipairs(sorted_keys(ports.outputs)) do
    local material = graph.nodes[key]
    if material and material.prod > 0 then
      require_node(key)
      if material.cons > 0 then
        local output = node(graph, key .. "#cell-output")
        output.group_key, output.cell_output = key, true
        connect(graph, key, output.key, material.prod - material.cons)
        require_node(output.key)
      else
        material.cell_output = true
      end
    end
  end
  -- A chosen input can supplement in-cell production of the same material.
  for _, key in ipairs(sorted_keys(ports.inputs)) do
    local material = graph.nodes[key]
    if material and material.prod > 1e-6 and material.cons - material.prod > 1e-6 then
      local supply = node(graph, key .. "#cell-input")
      supply.group_key = key
      connect(graph, supply.key, key, material.cons - material.prod)
    end
  end
  for id, link in pairs(graph.links) do
    local source = graph.nodes[link.from]
    if source.kind == "recipe" or source.prod > 1e-6 or ports.inputs[source.group_key or source.key] then
      depends_on(link.to, link.from)
    else
      graph.links[id] = nil
    end
  end
  for _, fuel in ipairs(graph.fuel_returns or {}) do
    for _, consumer in ipairs(fuel.consumers) do depends_on(consumer.key, fuel.key) end
  end
  while #pending > 0 do
    for _, key in ipairs(upstream[table.remove(pending)] or {}) do require_node(key) end
  end
  for key in pairs(graph.nodes) do
    if not keep[key] then graph.nodes[key] = nil end
  end
  for id, link in pairs(graph.links) do
    if not (keep[link.from] and keep[link.to]) then graph.links[id] = nil end
  end
end

local function net_flows(rates, fuels)
  local net = {}
  Capacity.flows(rates,
    function(_, key, rate) net[key] = (net[key] or 0) - rate end,
    function(_, key, rate) net[key] = (net[key] or 0) + rate end)
  for key, users in pairs(fuels) do
    for _, rate in pairs(users) do net[key] = (net[key] or 0) - rate end
  end
  return net
end

---@param selected integer? Cell id; nil builds the All view.
---@param opts table? { mode = "measured"|"capacity", period = seconds, surface = index? }
function Flow.build(selected, opts)
  opts = opts or {}
  local measured_mode = opts.mode ~= "capacity"
  local graph = { nodes = {}, links = {}, overlap = false, mode = measured_mode and "measured" or "capacity" }
  local records = Flow.records()
  local sources_cache = {}
  local function rate_sources_for(sidx)
    local key = sidx or 0
    local entry = sources_cache[key]
    if not entry then
      local srcs, start_tick = Sampler.rate_sources(sidx, opts.period)
      entry = { srcs = srcs, start_tick = start_tick }
      sources_cache[key] = entry
    end
    return entry.srcs, entry.start_tick
  end
  -- A subdivision comparison uses one denominator, including its parent.
  -- Sampler rounds this start to its existing history-bin boundary.
  local selected_ids, selected_stage
  if selected then selected_ids, selected_stage = Flow.ids(opts.surface, selected) end
  local parent_id = selected_ids and #selected_ids > 0 and selected or nil
  local comparison_scope = parent_id or (not selected and opts.scope or nil)
  local scope_ids, scope_stage
  if comparison_scope then
    if parent_id then
      scope_ids, scope_stage = selected_ids, selected_stage
    else
      scope_ids, scope_stage = Flow.ids(opts.surface, comparison_scope)
    end
  end
  local since
  if comparison_scope then
    local parent = records[comparison_scope]
    since = parent and parent.since or 0
    for _, id in ipairs(scope_ids) do
      if not parent_id or next((Cells.members(records[id]))) then
        since = math.max(since, records[id].since or 0)
      end
    end
  end
  if selected and not parent_id then
    local record = records[selected]
    if not record then return graph end
    local members = Cells.members(record)
    local capacity, fuels = Capacity.rates(members, nil, record.ports and record.ports.inputs, not measured_mode)
    local rates = capacity
    if measured_mode then
      local seconds, requested
      local srcs, pstart = rate_sources_for(record.surface_index)
      rates, seconds, requested = Flow.measured_rates(record, opts.period, false, since, srcs, pstart)
      graph.seconds, graph.requested = seconds, requested
      graph.utilisation = utilisation(rates, capacity)
      graph.partial = seconds + 1 < requested
    end
    -- Recipe bar tooltips list these rates and the members running each recipe.
    graph.recipe_rates, graph.members = rates, members
    Capacity.flows(rates,
      function(recipe, key, rate) connect(graph, key, "recipe/" .. recipe, rate) end,
      function(recipe, key, rate) connect(graph, "recipe/" .. recipe, key, rate) end)
    if not measured_mode then add_fuel(graph, fuels) end
    if record.ports then
      graph.choose_outputs = not next(record.ports.outputs)
      trace_boundary(graph, record.ports)
    end
    if measured_mode then
      for name, rate in pairs(rates) do
        local n = graph.nodes["recipe/" .. name]
        local full = capacity[name]
        if n then
          n.rate_line = full and full.normal > 1e-9
            and Loc("cells-recipe-utilisation", fmt(rate.normal), percent(rate.normal / full.normal))
            or Loc("cells-recipe-rate", fmt(rate.normal))
        end
      end
    end
    return graph
  end

  -- A machine in multiple cells cannot be assigned to either one from selection
  -- evidence. It stays visible in each individual cell and is omitted here.
  local seen, shared, memberships = {}, {}, {}
  local ids, stage
  if scope_ids then
    ids, stage = scope_ids, scope_stage
  else
    ids, stage = Flow.ids(opts.surface, parent_id or opts.scope)
  end
  if not since then
    since = 0
    for _, id in ipairs(ids) do since = math.max(since, records[id].since or 0) end
  end
  for _, id in ipairs(ids) do
    local members = Cells.members(records[id])
    memberships[id] = members
    for unit in pairs(members) do
      if seen[unit] then shared[unit], graph.overlap = true, true end
      seen[unit] = true
    end
  end
  local parent_rates, parent_capacity, parent_members, parent_fuels
  local child_measured = {}
  if parent_id then
    local parent = records[parent_id]
    parent_members = Cells.members(parent)
    local assigned = {}
    for _, id in ipairs(ids) do
      for unit in pairs(memberships[id]) do
        if not shared[unit] then assigned[unit] = true end
      end
    end
    parent_capacity, parent_fuels = Capacity.rates(parent_members, assigned, parent.ports and parent.ports.inputs, not measured_mode)
    if measured_mode then
      local seconds, requested
      local psrcs, pstart = rate_sources_for(parent.surface_index)
      parent_rates, seconds, requested = Flow.measured_rates(parent, opts.period, false, since, psrcs, pstart)
      graph.seconds, graph.requested = seconds, requested
      graph.partial = seconds + 1 < requested
      for _, id in ipairs(ids) do
        local crec = records[id]
        local csrcs, cpstart = rate_sources_for(crec.surface_index)
        local child_rates, csec, creq = Flow.measured_rates(crec, opts.period, true, since, csrcs, cpstart)
        child_measured[id] = { rates = child_rates, seconds = csec, requested = creq }
        for name, rate in pairs(child_rates) do
          local remainder = parent_rates[name]
          if remainder then
            remainder.normal = math.max(0, remainder.normal - rate.normal)
            remainder.bonus = math.max(0, remainder.bonus - rate.bonus)
          end
        end
      end
    end
    -- Stage the machines left in the parent by their own inputs and outputs.
    -- The saved parent boundary covers the entire line, including its children.
    local remainder = { inputs = {}, outputs = {} }
    for key, amount in pairs(net_flows(parent_capacity, parent_fuels)) do
      if amount < -1e-6 then remainder.inputs[key] = true end
      if amount > 1e-6 then remainder.outputs[key] = true end
    end
    ids[#ids + 1], memberships[parent_id] = parent_id, parent_members
    table.sort(ids)
    stage = Flow.stages(ids, records, { [parent_id] = remainder })
  end
  local entries = {}
  for _, id in ipairs(ids) do
    local record = records[id]
    local surface = game.surfaces[record.surface_index]
    if surface then
      local capacity, fuels
      if id == parent_id then capacity, fuels = parent_capacity, parent_fuels
      else capacity, fuels = Capacity.rates(memberships[id], shared, record.ports and record.ports.inputs, not measured_mode) end
      local rates = capacity
      local seconds, requested
      if measured_mode then
        if id == parent_id then
          rates, seconds, requested = parent_rates, graph.seconds, graph.requested
        elseif child_measured[id] then
          local cached = child_measured[id]
          rates, seconds, requested = cached.rates, cached.seconds, cached.requested
        else
          local srcs, pstart = rate_sources_for(record.surface_index)
          rates, seconds, requested = Flow.measured_rates(record, opts.period, true, since, srcs, pstart)
        end
        graph.requested = requested
        if seconds + 1 < requested then graph.newest = math.min(graph.newest or seconds, seconds) end
      end
      local net = net_flows(rates, fuels)
      local has_production = false
      for _, rate in pairs(rates) do
        if rate.normal + rate.bonus > 1e-6 then has_production = true; break end
      end
      if id ~= parent_id or has_production then
      local cell = "recipe/cell-" .. id
      local n = node(graph, cell)
      n.caption = Loc("cells-node-name", record.name)
      n.cell_name = record.name
      n.sprite = Cells.display_item(record, memberships[id]) or "entity/assembling-machine-1"
      n.context = surface.name
      n.tier, n.is_cell = 2 * stage[id], true
      if measured_mode then
        local used = utilisation(rates, capacity)
        -- The tab already follows the header's surface, so nodes do not repeat it.
        if used then n.rate_line = Loc("cells-node-utilisation", percent(used)) end
        if seconds + 1 < requested then
          n.note = Loc("cells-node-measured-since", Sampler.duration(seconds))
        end
      end
      -- Saved cells chart only their chosen boundary; cells from before it show every net flow.
      local ports, flows = record.ports, {}
      if id == parent_id then ports = nil end
      for _, key in ipairs(sorted_keys(net)) do
        local amount = net[key]
        if math.abs(amount) > 1e-6 and (not ports or ports[amount > 0 and "outputs" or "inputs"][key]) then
          flows[#flows + 1] = { key = key, amount = amount }
        end
      end
      entries[#entries + 1] = { id = id, cell = cell, surface = surface, stage = stage[id], flows = flows }
      end
    end
  end
  Flow.link_stages(graph, entries)
  if parent_id and records[parent_id].ports then
    -- Keep internal transfers while limiting external imports and exports to
    -- the parent's chosen boundary. Separate input/output nodes may represent
    -- the same material when the production order contains a return.
    local materials = {}
    for _, link in pairs(graph.links) do
      local from, to = graph.nodes[link.from], graph.nodes[link.to]
      local material = from.is_cell and to or from
      local key = material.group_key
      if key then
        local bucket = materials[key] or { made = {}, used = {}, production = 0, consumption = 0 }
        materials[key] = bucket
        if from.is_cell then
          bucket.made[#bucket.made + 1] = link
          bucket.production = bucket.production + link.rate
        else
          bucket.used[#bucket.used + 1] = link
          bucket.consumption = bucket.consumption + link.rate
        end
      end
    end
    local ports = records[parent_id].ports
    for key, bucket in pairs(materials) do
      local function trim(links, factor)
        for _, link in ipairs(links) do
          local old = link.rate
          link.rate = old * factor
          local from, to = graph.nodes[link.from], graph.nodes[link.to]
          if not from.is_cell then from.cons = from.cons - (old - link.rate) end
          if not to.is_cell then to.prod = to.prod - (old - link.rate) end
          if link.rate <= 1e-6 then graph.links[link.from .. ">" .. link.to] = nil end
        end
      end
      if not ports.outputs[key] and bucket.production > bucket.consumption then
        trim(bucket.made, bucket.consumption / bucket.production)
      end
      if not ports.inputs[key] and bucket.consumption > bucket.production then
        trim(bucket.used, bucket.production / bucket.consumption)
      end
    end
    for key, n in pairs(graph.nodes) do
      if not n.is_cell and n.prod <= 1e-6 and n.cons <= 1e-6 then graph.nodes[key] = nil end
    end
  end
  return graph
end

-- Material columns sit between cell stages. An item made by earlier cells and
-- used by later ones is a single node joining them; items no cell makes enter
-- just before their first user. Backward loop uses route as thin return lines
-- from the material's output node back to the consuming cell.
function Flow.link_stages(graph, entries)
  local last, materials, order, cell_returns = 1, {}, {}, {}
  for _, entry in ipairs(entries) do
    last = math.max(last, entry.stage)
    for _, flow in ipairs(entry.flows) do
      local where = entry.surface.index .. "|" .. flow.key
      local material = materials[where]
      if not material then
        material = { key = flow.key, surface = entry.surface, makers = {}, users = {} }
        materials[where], order[#order + 1] = material, where
      end
      table.insert(flow.amount > 0 and material.makers or material.users, { entry = entry, rate = math.abs(flow.amount) })
    end
  end
  local function material_node(material, suffix, tier)
    local n = node(graph, material.key .. "#surface-" .. material.surface.index .. suffix)
    n.group_key, n.tier, n.context = material.key, tier, material.surface.name
    return n.key
  end
  for _, where in ipairs(order) do
    local material = materials[where]
    local made_by = 0
    for _, maker in ipairs(material.makers) do made_by = math.max(made_by, maker.entry.stage) end
    local joined, early, back = nil, {}, {}
    if made_by > 0 then
      joined = material_node(material, "-output", 2 * made_by + 1)
      for _, maker in ipairs(material.makers) do connect(graph, maker.entry.cell, joined, maker.rate) end
    end
    for _, user in ipairs(material.users) do
      if joined and user.entry.stage > made_by then
        connect(graph, joined, user.entry.cell, user.rate)
      elseif joined then
        back[#back + 1] = { key = user.entry.cell, rate = user.rate }
      else
        early[#early + 1] = user
      end
    end
    if #back > 0 then
      cell_returns[#cell_returns + 1] = { key = joined, consumers = back }
    end
    local first = math.huge
    for _, user in ipairs(early) do first = math.min(first, user.entry.stage) end
    if #early > 0 then
      local supply = material_node(material, "-input", 2 * first - 1)
      for _, user in ipairs(early) do connect(graph, supply, user.entry.cell, user.rate) end
    end
  end
  if #cell_returns > 0 then graph.cell_returns = cell_returns end
  graph.stages = last
  graph.columns = { Loc("cells-inputs") }
  for s = 1, last do
    graph.columns[2 * s] = last == 1 and Loc("cells-tab") or Loc("cells-stage", s)
    graph.columns[2 * s + 1] = s == last and Loc("cells-outputs") or Loc("cells-between-stages")
  end
end

return Flow
