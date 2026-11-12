-- Native LocalisedStrings stay unresolved until Factorio displays them for each
-- player. Never translate through a shared cache or use translated text as an ID.
local Loc = {}

-- Join presentation fragments without coercing LocalisedStrings to Lua strings.
-- Plain strings remain plain, which also keeps prototype IDs and signatures intact.
local function compose(parts)
  local localised = false
  for _, value in ipairs(parts) do
    if type(value) == "table" then localised = true; break end
  end
  if not localised then return table.concat(parts) end
  while #parts > 20 do
    local groups = {}
    for first = 1, #parts, 20 do
      local group = { "" }
      for i = first, math.min(first + 19, #parts) do group[#group + 1] = parts[i] end
      groups[#groups + 1] = group
    end
    parts = groups
  end
  return { "", table.unpack(parts) }
end

function Loc.join(...)
  return compose({ ... })
end

function Loc.join_list(parts, separator)
  local result = {}
  for i, value in ipairs(parts) do
    if i > 1 then result[#result + 1] = separator or "" end
    result[#result + 1] = value
  end
  return compose(result)
end

return setmetatable(Loc, { __call = function(_, key, ...)
  return { "production-flow." .. key, ... }
end })
