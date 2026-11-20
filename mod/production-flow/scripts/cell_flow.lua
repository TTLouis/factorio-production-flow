local Cells = require("scripts.cells")
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

-- A cell's boundary: its locked items, or for cells saved before the lock,
-- what its machines' recipes suggest.
local function boundary(record)
  if record.ports then return record.ports end
  local suggested, ports = Cells.suggest_ports(Cells.members(record)), { inputs = {}, outputs = {} }
  for side, keys in pairs(suggested) do
    for _, key in ipairs(keys) do ports[side][key] = true end
  end
  return ports
end

-- Production order. A cell is in stage 1 unless another cell on its surface
-- makes one of its inputs; then it comes one stage after the latest such cell.
-- Smelting therefore precedes casting, which precedes the cells using the
-- castings. Cells feeding each other in a loop are ordered by creation: the
-- oldest waiting cell is placed first.
function Flow.stages(ids, records)
  local makers, ports = {}, {}
  for _, id in ipairs(ids) do
    local record = records[id]
    ports[id] = boundary(record)
    for key in pairs(ports[id].outputs) do
      local where = record.surface_index .. "|" .. key
      makers[where] = makers[where] or {}
      table.insert(makers[where], id)
    end
  end
  local feeds = {}
  for _, id in ipairs(ids) do
    feeds[id] = {}
    for key in pairs(ports[id].inputs) do
      for _, maker in ipairs(makers[records[id].surface_index .. "|" .. key] or {}) do
        if maker ~= id then feeds[id][maker] = true end
      end
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
      for _, id in ipairs(ids) do
        if not stage[id] then
          local at = 1
          for maker in pairs(feeds[id]) do
            if stage[maker] then at = math.max(at, stage[maker] + 1) end
          end
          stage[id], waiting = at, waiting - 1
          break
        end
      end
    end
  end
  return stage
end

---@param surface_index integer? Only cells on this surface.
---@return integer[] ids In production order, then by creation.
---@return table<integer, integer> stage
function Flow.ids(surface_index)
  local records, ids = Flow.records(), {}
  for _, id in ipairs(sorted_keys(records)) do
    if not surface_index or records[id].surface_index == surface_index then ids[#ids + 1] = id end
  end
  local stage = Flow.stages(ids, records)
  table.sort(ids, function(a, b)
    if stage[a] ~= stage[b] then return stage[a] < stage[b] end
    return a < b
  end)
  return ids, stage
end

-- Capacity: every member running its configured recipe at full speed.
-- rates[recipe] = { normal = crafts/s, bonus = productivity crafts/s }
local function capacity_rates(members, shared)
  local rates, recipes = {}, storage.graph.recipes
  for _, id in ipairs(sorted_keys(members)) do
    if not (shared and shared[id]) then
      local entity = members[id]
      local name, force_recipe = Sampler.current_recipe(entity)
      local recipe = recipes[name]
      if recipe and recipe.energy > 0 then
        local normal = entity.crafting_speed / recipe.energy
        local extra = normal * Sampler.craft_productivity(entity, name, force_recipe, recipe)
        local rate = rates[name] or { normal = 0, bonus = 0 }
        rate.normal, rate.bonus = rate.normal + normal, rate.bonus + extra
        rates[name] = rate
      end
    end
  end
  return rates
end

-- Measured: crafts the sampler attributed to the cell over the period.
local function measured_rates(record, period, exclusive)
  local recipes, seconds, requested = Sampler.cell_rates(record.id, record.surface_index, period, record.since, exclusive)
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

local function recipe_flows(rates, consume, produce)
  for _, name in ipairs(sorted_keys(rates)) do
    local rate, recipe = rates[name], storage.graph.recipes[name]
    for _, input in ipairs(recipe.ingredients) do
      consume(name, input.key, rate.normal * input.amount)
    end
    for _, output in ipairs(recipe.products) do
      produce(name, output.key, rate.normal * output.amount + rate.bonus * output.prod)
    end
  end
end

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

---@param selected integer? Cell id; nil builds the All view.
---@param opts table? { mode = "measured"|"capacity", period = seconds, surface = index? }
function Flow.build(selected, opts)
  opts = opts or {}
  local measured_mode = opts.mode ~= "capacity"
  local graph = { nodes = {}, links = {}, overlap = false, mode = measured_mode and "measured" or "capacity" }
  local records = Flow.records()
  if selected then
    local record = records[selected]
    if not record then return graph end
    local members = Cells.members(record)
    local capacity = capacity_rates(members)
    local rates = capacity
    if measured_mode then
      local seconds, requested
      rates, seconds, requested = measured_rates(record, opts.period)
      graph.seconds, graph.requested = seconds, requested
      graph.utilisation = utilisation(rates, capacity)
      graph.partial = seconds + 1 < requested
    end
    recipe_flows(rates,
      function(recipe, key, rate) connect(graph, key, "recipe/" .. recipe, rate) end,
      function(recipe, key, rate) connect(graph, "recipe/" .. recipe, key, rate) end)
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
  local ids, stage = Flow.ids(opts.surface)
  for _, id in ipairs(ids) do
    local members = Cells.members(records[id])
    memberships[id] = members
    for unit in pairs(members) do
      if seen[unit] then shared[unit], graph.overlap = true, true end
      seen[unit] = true
    end
  end
  local entries = {}
  for _, id in ipairs(ids) do
    local record = records[id]
    local surface = game.surfaces[record.surface_index]
    if surface then
      local capacity = capacity_rates(memberships[id], shared)
      local rates = capacity
      local seconds, requested
      if measured_mode then
        rates, seconds, requested = measured_rates(record, opts.period, true)
        graph.requested = requested
        if seconds + 1 < requested then graph.newest = math.min(graph.newest or seconds, seconds) end
      end
      local net = {}
      recipe_flows(rates,
        function(_, key, rate) net[key] = (net[key] or 0) - rate end,
        function(_, key, rate) net[key] = (net[key] or 0) + rate end)
      local cell = "recipe/cell-" .. id
      local n = node(graph, cell)
      n.caption = Loc("cells-node-name", record.name)
      local display_item = Cells.display_item(record, memberships[id])
      n.sprite = display_item and "item/" .. display_item or "entity/assembling-machine-1"
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
      -- Saved cells lock their boundary; cells from before the lock show every net flow.
      local ports, flows = record.ports, {}
      for _, key in ipairs(sorted_keys(net)) do
        local amount = net[key]
        if math.abs(amount) > 1e-6 and (not ports or ports[amount > 0 and "outputs" or "inputs"][key]) then
          flows[#flows + 1] = { key = key, amount = amount }
        end
      end
      entries[#entries + 1] = { id = id, cell = cell, surface = surface, stage = stage[id], flows = flows }
    end
  end
  Flow.link_stages(graph, entries)
  return graph
end

-- Material columns sit between cell stages. An item made by earlier cells and
-- used by later ones is a single node joining them; items no cell makes enter
-- just before their first user. A loop's backward use gets its own input node.
function Flow.link_stages(graph, entries)
  local last, materials, order = 1, {}, {}
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
    local joined, early = nil, {}
    if made_by > 0 then
      joined = material_node(material, "-output", 2 * made_by + 1)
      for _, maker in ipairs(material.makers) do connect(graph, maker.entry.cell, joined, maker.rate) end
    end
    for _, user in ipairs(material.users) do
      if joined and user.entry.stage > made_by then
        connect(graph, joined, user.entry.cell, user.rate)
      else
        early[#early + 1] = user
      end
    end
    local first = math.huge
    for _, user in ipairs(early) do first = math.min(first, user.entry.stage) end
    if #early > 0 then
      local supply = material_node(material, "-input", 2 * first - 1)
      for _, user in ipairs(early) do connect(graph, supply, user.entry.cell, user.rate) end
    end
  end
  graph.stages = last
  graph.columns = { Loc("cells-inputs") }
  for s = 1, last do
    graph.columns[2 * s] = last == 1 and Loc("cells-tab") or Loc("cells-stage", s)
    graph.columns[2 * s + 1] = s == last and Loc("cells-outputs") or Loc("cells-between-stages")
  end
end

return Flow
