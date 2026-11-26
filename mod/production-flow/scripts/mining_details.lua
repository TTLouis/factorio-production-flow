-- Read current drill targets only when a surface rate card needs mining details.
local Mining = {}

local by_material
local sample_tick, surface_counts

local function index_resources()
  local materials = {}
  local function add(key, resource)
    local definitions = materials[key]
    if not definitions then
      definitions = {}
      materials[key] = definitions
    end
    definitions[resource.name] = resource
  end
  for name, prototype in pairs(prototypes.get_entity_filtered{{filter="type", type="resource"}}) do
    local mineable = prototype.mineable_properties
    if mineable and mineable.minable and mineable.products and #mineable.products > 0 then
      local resource = {name=name, caption=prototype.localised_name, products={}}
      for _, product in ipairs(mineable.products) do
        local key = product.type .. "/" .. product.name
        resource.products[key] = true
        add(key, resource)
      end
      if mineable.required_fluid and (mineable.fluid_amount or 0) > 0 then
        resource.input = "fluid/" .. mineable.required_fluid
        add(resource.input, resource)
      end
    end
  end
  return materials
end

local function drill_counts(surface)
  if sample_tick ~= game.tick then
    sample_tick, surface_counts = game.tick, {}
  end
  local counts = surface_counts[surface.index]
  if counts then return counts end
  counts = {}
  for _, drill in ipairs(surface.find_entities_filtered{type="mining-drill", force="player"}) do
    local target = drill.mining_target
    if target and target.valid and target.type == "resource" then
      local types = counts[target.name]
      if not types then types = {}; counts[target.name] = types end
      types[drill.name] = (types[drill.name] or 0) + 1
    end
  end
  surface_counts[surface.index] = counts
  return counts
end

function Mining.sources_and_uses(sidx, key)
  if not by_material then by_material = index_resources() end
  local made, used = {}, {}
  local definitions = by_material[key]
  local surface = definitions and game.surfaces[sidx]
  if not surface then return made, used end
  local counts = drill_counts(surface)
  for name, resource in pairs(definitions) do
    local row = {resource=resource, drills=counts[name]}
    if resource.products[key] then made[#made + 1] = row end
    if resource.input == key and row.drills then used[#used + 1] = row end
  end
  local function by_name(a, b) return a.resource.name < b.resource.name end
  table.sort(made, by_name)
  table.sort(used, by_name)
  return made, used
end

return Mining
