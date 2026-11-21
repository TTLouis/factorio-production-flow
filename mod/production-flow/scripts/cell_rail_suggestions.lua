local Capacity = require("scripts.cell_capacity")

local Suggestions = {}
local EPSILON = 1e-9

-- Only explicit, valid material tags are meaningful. Other rich text and plain
-- words in station names do not identify a material.
function Suggestions.materials(name)
  local result = {}
  if type(name) ~= "string" then return result end
  for tag in name:gmatch("%[([^%[%]]+)%]") do
    local kind, material = tag:match("^(item)=([^%[%]]+)$")
    if not kind then kind, material = tag:match("^(fluid)=([^%[%]]+)$") end
    if not kind then kind, material = tag:match("^img=(item)/([^%[%]]+)$") end
    if not kind then kind, material = tag:match("^img=(fluid)/([^%[%]]+)$") end
    if kind and prototypes[kind] and prototypes[kind][material] then
      result[kind .. "/" .. material] = true
    end
  end
  return result
end

-- No selected ports feed this calculation: the existing port selections must
-- never make a stop seem to import a material merely because it was selected.
function Suggestions.net(members)
  local rates, fuels = Capacity.rates(members, nil, nil, true)
  local net = {}
  Capacity.flows(rates,
    function(_, key, amount) net[key] = (net[key] or 0) - amount end,
    function(_, key, amount) net[key] = (net[key] or 0) + amount end)
  for key, users in pairs(fuels) do
    for _, amount in pairs(users) do net[key] = (net[key] or 0) - amount end
  end
  return net
end

function Suggestions.role(name, net)
  local incoming, outgoing = false, false
  for key in pairs(Suggestions.materials(name)) do
    local amount = net[key] or 0
    incoming = incoming or amount < -EPSILON
    outgoing = outgoing or amount > EPSILON
  end
  if incoming and outgoing then return "both" end
  if incoming then return "import" end
  if outgoing then return "export" end
end

function Suggestions.ports(name, role, net)
  local ports = { inputs = {}, outputs = {} }
  for key in pairs(Suggestions.materials(name)) do
    local amount = net[key] or 0
    if amount < -EPSILON and (role == "import" or role == "both") then ports.inputs[key] = true end
    if amount > EPSILON and (role == "export" or role == "both") then ports.outputs[key] = true end
    -- A single unambiguous station direction also gives its other named,
    -- balanced materials that direction. Both-sided stops leave them unset.
    if math.abs(amount) <= EPSILON then
      if role == "import" then ports.inputs[key] = true end
      if role == "export" then ports.outputs[key] = true end
    end
  end
  return ports
end

return Suggestions
