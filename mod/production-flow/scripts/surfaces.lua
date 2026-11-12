local Loc = require("scripts.locale")
-- Plain names for sorting/exports; native localized names for the interface.
local Su = {}

function Su.platform_name(sf)
  local ok, name = pcall(function()
    local p = sf.platform
    if p and p.valid then return p.name end
  end)
  if ok and name and name ~= "" then return name end
  return nil
end

function Su.label(sf)
  if not (sf and sf.valid) then return "?" end
  local pn = Su.platform_name(sf)
  if pn then return pn end
  local n = sf.name
  return (string.gsub(n, "^%l", string.upper))
end

function Su.localised(sf)
  if not (sf and sf.valid) then return "?" end
  local pn = Su.platform_name(sf)
  if pn then return Loc("surfaces-platform", pn) end
  local ok, planet = pcall(function() return sf.planet end)
  if ok and planet then
    return { "?", planet.prototype and planet.prototype.localised_name
      or { "space-location-name." .. planet.name }, Su.label(sf) }
  end
  return Su.label(sf)
end

-- rich-text icon in front of the label (planet icon / platform hub icon)
function Su.rich(sf)
  if not (sf and sf.valid) then return "?" end
  if Su.platform_name(sf) then return Loc.join("[img=item/space-platform-hub] ", Su.localised(sf)) end
  local ok, planet = pcall(function() return sf.planet end)
  if ok and planet then return Loc.join("[planet=" .. planet.name .. "] ", Su.localised(sf)) end
  return Su.label(sf)
end

return Su
