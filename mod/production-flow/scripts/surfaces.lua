-- Human names for surfaces: space platforms show the name the player gave the ship,
-- planets their capitalised name. Plain strings (safe for sorting, export and GUI).
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
  if pn then return "Platform: " .. pn end
  local n = sf.name
  return (string.gsub(n, "^%l", string.upper))
end

-- rich-text icon in front of the label (planet icon / platform hub icon)
function Su.rich(sf)
  if not (sf and sf.valid) then return "?" end
  if Su.platform_name(sf) then return "[img=item/space-platform-hub] " .. Su.label(sf) end
  local ok, planet = pcall(function() return sf.planet end)
  if ok and planet then return "[planet=" .. planet.name .. "] " .. Su.label(sf) end
  return Su.label(sf)
end

return Su
