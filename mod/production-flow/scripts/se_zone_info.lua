-- Space Exploration zone properties for the Transfers Flow zone panel.
-- Reuses what SE's own Universe Explorer shows (zone type, parent, primary
-- resource, environment tags, threat, robot interference, solar, hazards,
-- day/night and radius) through SE's public remote interface and SE's own
-- locale. Every call is optional: without SE, or for a surface that is not a
-- zone, rows() returns nil and Flow shows no zone panel.
local Info = {}
local SE = "space-exploration"

local function call(fn, args)
  local api = remote and remote.interfaces and remote.interfaces[SE]
  if not (api and api[fn]) then return nil end
  local ok, value = pcall(remote.call, SE, fn, args)
  if ok then return value end
end

local function se(key, ...) return { "space-exploration." .. key, ... } end

local TYPES = { planet = true, moon = true, star = true, ["asteroid-field"] = true,
  ["asteroid-belt"] = true, anomaly = true, spaceship = true }

local function icon(zone)
  local path = zone and zone.index and call("get_zone_icon", { zone_index = zone.index })
  if type(path) ~= "string" then return "" end
  if helpers and helpers.is_valid_sprite_path and not helpers.is_valid_sprite_path(path) then return "" end
  return "[img=" .. path .. "] "
end

local function parent_of(zone)
  return zone.parent_index and call("get_zone_from_zone_index", { zone_index = zone.parent_index }) or nil
end

local function type_title(zone, parent)
  if zone.type == "orbit" then
    return se("something_orbit", parent and TYPES[parent.type] and se(parent.type) or "?")
  end
  return TYPES[zone.type] and se(zone.type) or tostring(zone.type)
end

local function solid(zone) return zone.type == "planet" or zone.type == "moon" end
local function percent(value) return string.format("%.0f%%", value * 100) end

-- Comma-separated localised list, kept flat (a localised string takes at most
-- 20 parameters, so very long lists are cut rather than nested).
local function list(parts, prefix)
  local out = { "", prefix or "" }
  for i, part in ipairs(parts) do
    if #out >= 19 then break end
    if i > 1 then out[#out + 1] = ", " end
    out[#out + 1] = part
  end
  return out
end

local function environment(zone)
  if zone.is_homeworld then return se("climate_homeworld") end
  if type(zone.tags) ~= "table" then return nil end
  local tags = {}
  for _, tag in pairs(zone.tags) do
    if type(tag) == "string" and not tag:find("enemy", 1, true) then tags[#tags + 1] = tag end
  end
  if #tags == 0 then return nil end
  table.sort(tags)
  local parts = {}
  for i, tag in ipairs(tags) do parts[i] = se("climate_" .. tag) end
  return list(parts)
end

-- Rows of {name, label, value, tooltip}, in SE's order; the first is the type.
function Info.rows(surface)
  if not (surface and surface.valid) then return nil end
  local zone = call("get_zone_from_surface_index", { surface_index = surface.index })
  if type(zone) ~= "table" or type(zone.type) ~= "string" then return nil end
  local rows = {}
  local function add(name, label, value, tooltip)
    if value ~= nil then rows[#rows + 1] = { name = name, label = label, value = value, tooltip = tooltip } end
  end
  local parent = parent_of(zone)
  add("type", se("zone-tooltip-type"), { "", icon(zone), type_title(zone, parent) })
  -- One row per enclosing body up to its star (SE has no galaxy level), each
  -- labelled with SE's type name: a moon shows its planet and star, an orbit
  -- starts from the body it circles.
  local seen, ancestor = { [zone.index or 0] = true }, parent
  while ancestor and type(ancestor) == "table" and not seen[ancestor.index or 0] do
    seen[ancestor.index or 0] = true
    local kind = TYPES[ancestor.type] and ancestor.type or "parent"
    add("parent_" .. kind, kind == "parent" and se("zone-tooltip-parent") or { "", se(kind), ":" },
      { "", icon(ancestor), tostring(ancestor.name) })
    if ancestor.type == "star" then break end
    ancestor = parent_of(ancestor)
  end
  local resource = zone.type ~= "orbit" and zone.primary_resource
  if type(resource) == "string" then
    local known = prototypes and prototypes.entity and prototypes.entity[resource]
    add("resource", { "", se("zonelist-heading-primary-resource"), ":" },
      known and { "", "[img=entity/" .. resource .. "] ", known.localised_name } or resource)
  end
  add("environment", se("zone-tooltip-climate"), environment(zone))
  if zone.type ~= "spaceship" then
    local threat = call("threat_for_surface", { surface_index = surface.index })
    if type(threat) == "number" then add("threat", se("zone-tooltip-threat"), percent(threat)) end
    local attrition = call("robot_attrition_for_surface", { surface_index = surface.index })
    if type(attrition) == "number" then
      local kind = zone.type == "anomaly" and "spacial-distortion" or solid(zone) and "wind" or "radiation"
      add("attrition", se("zone-tooltip-bot-attrition", se("attrition-type-" .. kind)), string.format("%.2f", attrition))
    end
  end
  local solar = call("solar_for_surface", { surface_index = surface.index })
  if type(solar) == "number" then add("solar", se("zone-tooltip-solar"), percent(solar)) end
  local hazards = zone.type ~= "spaceship" and call("hazards_for_surface", { surface_index = surface.index })
  if type(hazards) == "table" and next(hazards) then
    local names, tips = {}, {}
    for _, hazard in pairs(hazards) do
      if type(hazard) == "string" then
        names[#names + 1] = se("zone-hazard-" .. hazard)
        tips[#tips + 1] = se("zone-hazard-tooltip-" .. hazard)
      end
    end
    if #names > 0 then
      add("hazards", se("zone-tooltip-hazards"), list(names, "[img=utility/warning_icon] "), list(tips))
    end
  end
  if solid(zone) and type(zone.ticks_per_day) == "number" then
    add("daynight", se("zone-tooltip-daynight"), { "time-symbol-minutes", string.format("%.2f", zone.ticks_per_day / 3600) },
      se("tick-time-unit", zone.ticks_per_day))
  end
  if type(zone.radius) == "number" then add("radius", se("zone-tooltip-radius"), string.format("%.0f", zone.radius)) end
  return rows
end

-- The surface's richest resources, ranked like SE's Universe Explorer
-- (frequency × size × richness from the surface's map generation controls).
-- Each entry: {name, caption, frequency, size, richness}, values as fractions.
-- Like SE, orbits and spaceships list no resources.
function Info.resources(surface, limit)
  if not (surface and surface.valid) then return {} end
  local zone = call("get_zone_from_surface_index", { surface_index = surface.index })
  if type(zone) ~= "table" or zone.type == "orbit" or zone.type == "spaceship" then return {} end
  local ok, mapgen = pcall(function() return surface.map_gen_settings end)
  local controls = ok and mapgen and mapgen.autoplace_controls
  if type(controls) ~= "table" then return {} end
  local catalog = prototypes and prototypes.autoplace_control
  local entities = prototypes and prototypes.entity
  local out = {}
  for name, control in pairs(controls) do
    local proto = catalog and catalog[name]
    if proto and proto.category == "resource" and type(control) == "table" then
      local f, s, r = control.frequency or 1, control.size or 1, control.richness or 1
      if f * s * r > 0 then
        local entity = entities and entities[name]
        out[#out + 1] = { name = name, score = f * s * r, frequency = f, size = s, richness = r,
          caption = entity and { "", "[img=entity/" .. name .. "] ", entity.localised_name } or proto.localised_name or name }
      end
    end
  end
  table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
  for i = #out, (limit or 5) + 1, -1 do out[i] = nil end
  return out
end

function Info.percent(value) return percent(value) end

return Info
