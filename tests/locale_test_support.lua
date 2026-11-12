-- Test-only English resolver. Runtime code always leaves translation to Factorio.
return function(catalog)
  local resolve
  local function known(value)
    return type(value) ~= "table" or value[1] == "" or value[1] == "?" or catalog[value[1]] ~= nil
  end
  resolve = function(value)
    if type(value) ~= "table" then return tostring(value) end
    local key = value[1]
    assert(#value <= 21, "LocalisedString exceeds Factorio's 20 parameter limit")
    if key == "" then
      local parts = {}
      for i = 2, #value do parts[#parts + 1] = resolve(value[i]) end
      return table.concat(parts)
    end
    if key == "?" then
      for i = 2, #value do if known(value[i]) then return resolve(value[i]) end end
      return "?"
    end
    local template = catalog[key]
    if not template then
      assert(not key:match("^production%-flow%."), "Missing English locale key: " .. key)
      return key -- Synthetic prototypes intentionally have no installed locale.
    end
    local used = {}
    template = template:gsub("__plural_for_parameter__(%d+)__{(.-)}__", function(index, choices)
      index = tonumber(index)
      assert(value[index + 1] ~= nil, "Missing plural parameter: " .. key)
      used[index] = true
      local count, fallback = tonumber(resolve(value[index + 1]))
      for rule, text in choices:gmatch("([^=|]+)=([^|]*)") do
        if rule == tostring(count) then return text end
        if rule == "rest" then fallback = text end
      end
      return assert(fallback, "Missing plural fallback: " .. key)
    end)
    template = template:gsub("__(%d+)__", function(index)
      index = tonumber(index)
      assert(value[index + 1] ~= nil, "Missing locale parameter: " .. key)
      used[index] = true
      return resolve(value[index + 1])
    end)
    for i = 2, #value do assert(used[i - 1], "Unexpected locale parameter: " .. key) end
    return template
  end
  return resolve
end
