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

local function recipe_rates(members, shared)
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

function Flow.build(selected)
  local graph = { nodes = {}, links = {}, overlap = false }
  local records = Flow.records()
  if selected then
    local record = records[selected]
    if not record then return graph end
    local members = Cells.members(record)
    recipe_flows(recipe_rates(members),
      function(recipe, key, rate) connect(graph, key, "recipe/" .. recipe, rate) end,
      function(recipe, key, rate) connect(graph, "recipe/" .. recipe, key, rate) end)
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
      local net = {}
      recipe_flows(recipe_rates(memberships[id], shared),
        function(_, key, rate) net[key] = (net[key] or 0) - rate end,
        function(_, key, rate) net[key] = (net[key] or 0) + rate end)
      local cell = "recipe/cell-" .. id
      local n = node(graph, cell)
      n.caption = Loc("cells-node-name", record.name)
      local display_item = Cells.display_item(record, memberships[id])
      n.sprite = display_item and "item/" .. display_item or "entity/assembling-machine-1"
      n.context = surface.name
      n.tier, n.is_cell = 2, true
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
