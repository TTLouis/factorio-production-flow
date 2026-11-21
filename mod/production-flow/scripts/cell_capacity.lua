local Sampler = require("scripts.sampler")
local Selection = require("shared.cell_selection")

local Capacity = {}

function Capacity.index()
  local filters, burners = {}, {}
  for _, kind in ipairs(Selection.types) do
    filters[#filters + 1] = { filter = "type", type = kind, mode = "or" }
  end
  for name, entity in pairs(prototypes.get_entity_filtered(filters)) do
    local burner = entity.burner_prototype
    if burner then
      burners[name] = { fuel_categories = burner.fuel_categories, effectivity = burner.effectivity }
    end
  end
  storage.cell_burner_prototypes = burners
  return burners
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function fuel_for(machine, burner, candidates)
  local live = machine.burner
  local burning = live and live.currently_burning
  if burning then return burning.name end
  local fuel
  for key in pairs(candidates) do
    local item = key:sub(1, 5) == "item/" and prototypes.item[key:sub(6)]
    for _, category in ipairs(item and item.fuel_categories or {}) do
      if burner.fuel_categories[category] then
        if fuel and fuel.name ~= item.name then return nil end
        fuel = item
      end
    end
  end
  return fuel
end

-- Full-speed crafts and estimated burner demand, grouped by fuel and recipe.
-- A stopped burner uses an unambiguous fuel from the cell's products or inputs.
function Capacity.rates(members, shared, inputs, estimate_fuel)
  local rates, fuels, burners = {}, {}, {}
  local recipes = storage.graph and storage.graph.recipes
  if not recipes then return rates, fuels end
  local index = estimate_fuel and (storage.cell_burner_prototypes or Capacity.index())

  for _, unit in ipairs(sorted_keys(members)) do
    if not (shared and shared[unit]) then
      local machine = members[unit]
      local name, force_recipe = Sampler.current_recipe(machine)
      local recipe = recipes[name]
      if recipe and recipe.energy > 0 then
        local normal = machine.crafting_speed / recipe.energy
        local bonus = Sampler.craft_productivity(machine, name, force_recipe, recipe)
        local rate = rates[name] or { normal = 0, bonus = 0 }
        rate.normal, rate.bonus = rate.normal + normal, rate.bonus + normal * bonus
        rates[name] = rate

        local burner = index and index[machine.name]
        if burner then burners[#burners + 1] = { machine = machine, burner = burner, recipe = name } end
      end
    end
  end

  if #burners == 0 then return rates, fuels end
  local candidates = {}
  for key in pairs(inputs or {}) do candidates[key] = true end
  for name, rate in pairs(rates) do
    for _, product in ipairs(recipes[name].products) do
      if rate.normal * product.amount + rate.bonus * product.prod > 0 then candidates[product.key] = true end
    end
  end
  for _, entry in ipairs(burners) do
    local machine, burner = entry.machine, entry.burner
    local fuel = fuel_for(machine, burner, candidates)
    if fuel and fuel.fuel_value > 0 and burner.effectivity > 0 then
      local energy = machine.prototype.get_max_energy_usage(machine.quality) * 60
      local usage = energy * math.max(0.2, 1 + (machine.consumption_bonus or 0))
      local key = "item/" .. fuel.name
      local users = fuels[key] or {}
      users[entry.recipe] = (users[entry.recipe] or 0) + usage / (fuel.fuel_value * burner.effectivity)
      fuels[key] = users
    end
  end
  return rates, fuels
end

function Capacity.flows(rates, consume, produce)
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

return Capacity
