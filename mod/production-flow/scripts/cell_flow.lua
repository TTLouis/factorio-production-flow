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

function Flow.ids()
  return sorted_keys(Flow.records())
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
---@param opts table? { mode = "measured"|"capacity", period = seconds }
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
  graph.columns = { Loc("cells-inputs"), Loc("cells-tab"), Loc("cells-outputs") }
  local seen, shared, memberships = {}, {}, {}
  local ids = sorted_keys(records)
  for _, id in ipairs(ids) do
    local members = Cells.members(records[id])
    memberships[id] = members
    for unit in pairs(members) do
      if seen[unit] then shared[unit], graph.overlap = true, true end
      seen[unit] = true
    end
  end
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
      n.tier, n.is_cell = 2, true
      if measured_mode then
        local used = utilisation(rates, capacity)
        if used then n.rate_line = Loc("cells-node-utilisation", surface.name, percent(used)) end
        if seconds + 1 < requested then
          n.note = Loc("cells-node-measured-since", Sampler.duration(seconds))
        end
      end
      for _, key in ipairs(sorted_keys(net)) do
        local amount = net[key]
        if math.abs(amount) > 1e-6 then
          local side = amount > 0 and "-output" or "-input"
          local material = key .. "#surface-" .. surface.index .. side
          local material_node = node(graph, material)
          material_node.group_key = key
          material_node.tier = amount > 0 and 3 or 1
          material_node.context = surface.name
          if amount > 0 then connect(graph, cell, material, amount)
          else connect(graph, material, cell, -amount) end
        end
      end
    end
  end
  return graph
end

return Flow
