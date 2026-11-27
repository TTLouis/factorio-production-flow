-- Read current drill targets only when a surface rate card needs mining details.
local Mining = {}

local by_material
local DRILL_CACHE_TICKS = 300

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

function Mining.invalidate(sidx)
  local cache = storage and storage.mining_cache
  if not cache then return end
  if not sidx then
    storage.mining_cache = {}
    return
  end
  local prefix = tostring(sidx) .. ":"
  for k in pairs(cache) do
    if k:sub(1, #prefix) == prefix then cache[k] = nil end
  end
end

local function drill_counts(surface, force, fresh)
  local target_force = force or (game.forces and game.forces.player) or "player"
  local force_key = type(target_force) == "string" and target_force or target_force.index
  local cache_key = surface.index .. ":" .. tostring(force_key)
  local cache
  if storage then
    cache = storage.mining_cache
    if not cache then cache = {}; storage.mining_cache = cache end
  end
  local entry = cache and cache[cache_key]
  if entry and entry.surface == surface and game.tick >= entry.tick then
    local age = game.tick - entry.tick
    if (fresh and age == 0) or (not fresh and age < DRILL_CACHE_TICKS) then
      return entry.counts
    end
  end
  local counts = {}
  for _, drill in ipairs(surface.find_entities_filtered{type="mining-drill", force=target_force}) do
    local target = drill.mining_target
    if target and target.valid and target.type == "resource" then
      local types = counts[target.name]
      if not types then types = {}; counts[target.name] = types end
      types[drill.name] = (types[drill.name] or 0) + 1
    end
  end
  if cache then
    for k, v in pairs(cache) do
      if v.surface and v.surface.valid == false then cache[k] = nil end
    end
    cache[cache_key] = { tick = game.tick, surface = surface, counts = counts }
  end
  return counts
end

function Mining.sources_and_uses(sidx, key, force, fresh)
  if not by_material then by_material = index_resources() end
  local made, used = {}, {}
  local definitions = by_material[key]
  local surface = definitions and game.surfaces[sidx]
  if not surface then return made, used end
  local counts = drill_counts(surface, force, fresh)
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
