local Budget = { nodes = 150, links = 300 }

function Budget.bypassed()
  local option = settings and settings.global and settings.global["ssk-bypass-sankey-size-limit"]
  return option and option.value == true
end

local function keys(map)
  local list = {}
  for key in pairs(map) do list[#list + 1] = key end
  table.sort(list)
  return list
end

local function order(a, b)
  if a.priority ~= b.priority then return a.priority > b.priority end
  if a.weight ~= b.weight then return a.weight > b.weight end
  return a.id < b.id
end

local function factor(node, fluid_scale)
  return (node.kind == "fluid" or node.flow_kind == "fluid") and fluid_scale or 1
end

-- Work on the display graph. Preserve exact rates for all surviving edges.
function Budget.apply(nodes, links, returns, chart, remap, fluid_scale, automatic)
  local count, link_count = 0, 0
  for _ in pairs(nodes) do count = count + 1 end
  for _ in pairs(links) do link_count = link_count + 1 end
  for _, route in ipairs(returns) do link_count = link_count + #route.sources + #route.targets - 1 end
  local limit = {
    nodes = count, links = link_count, bypass = not automatic and Budget.bypassed(),
    oversized = count > Budget.nodes or link_count > Budget.links,
  }
  if not limit.oversized or limit.bypass then return limit, returns end

  local retained, protected, hot = {}, {}, {}
  local candidates, ranked_nodes = {}, {}
  for _, key in pairs({ chart.sel, chart.pinned, chart.focus }) do
    local base = key:gsub("#.*$", "")
    local node = nodes[key] or nodes[remap[key] or remap[base] or base]
    if node then protected[node.key] = true end
  end
  for id, link in pairs(links) do
    local a, b = nodes[link.from], nodes[link.to]
    local material = a.kind == "recipe" and b or a
    candidates[#candidates + 1] = {
      id = "link/" .. id, link = id, ends = { a.key, b.key }, cost = 1,
      weight = link.rate * factor(material, fluid_scale),
    }
  end
  for index, route in ipairs(returns) do
    local ends, weight = {}, 0
    for _, source in ipairs(route.sources) do ends[#ends + 1] = source.key end
    for _, target in ipairs(route.targets) do
      ends[#ends + 1] = target.node.key
      weight = weight + target.rate * factor(target.node, fluid_scale)
    end
    candidates[#candidates + 1] = {
      id = "return/" .. index, route = index, ends = ends, cost = #ends - 1, weight = weight,
    }
  end
  for _, entry in ipairs(candidates) do
    for _, key in ipairs(entry.ends) do
      if protected[key] then
        for _, neighbor in ipairs(entry.ends) do hot[neighbor] = true end
        break
      end
    end
  end
  for _, entry in ipairs(candidates) do
    entry.priority = 0
    for _, key in ipairs(entry.ends) do
      entry.priority = math.max(entry.priority, protected[key] and 2 or hot[key] and 1 or 0)
    end
  end
  table.sort(candidates, order)
  local weights, seen = {}, {}
  for index, entry in ipairs(candidates) do
    for _, key in ipairs(entry.ends) do
      if seen[key] ~= index then
        weights[key] = (weights[key] or 0) + entry.weight
        seen[key] = index
      end
    end
  end
  for key, n in pairs(nodes) do
    ranked_nodes[#ranked_nodes + 1] = {
      id = key, priority = protected[key] and 2 or hot[key] and 1 or 0,
      weight = math.max(weights[key] or 0, ((n.prod or 0) + (n.cons or 0)) * factor(n, fluid_scale)),
    }
  end
  table.sort(ranked_nodes, order)
  count = math.min(#ranked_nodes, Budget.nodes)
  for index = 1, count do retained[ranked_nodes[index].id] = true end

  link_count = 0
  local kept_links, kept_routes = {}, {}
  for _, entry in ipairs(candidates) do
    local fits = link_count + entry.cost <= Budget.links
    if fits then
      for _, key in ipairs(entry.ends) do
        if not retained[key] then fits = false; break end
      end
    end
    if fits then
      link_count = link_count + entry.cost
      if entry.link then kept_links[entry.link] = true else kept_routes[entry.route] = true end
    end
  end
  for key in pairs(nodes) do if not retained[key] then nodes[key] = nil end end
  for id in pairs(links) do if not kept_links[id] then links[id] = nil end end
  local visible = {}
  for index, route in ipairs(returns) do
    if kept_routes[index] then visible[#visible + 1] = route end
  end
  limit.nodes, limit.links = count, link_count
  return limit, visible
end

-- The renderer splits raw inputs across lanes after selecting the chart.
function Budget.reserve_copies(limit, extra)
  local count = limit.nodes + extra
  if count > Budget.nodes then
    limit.oversized = true
    if not limit.bypass then return false end
  end
  limit.nodes = count
  return true
end

-- Length-prefix strings and keep numeric precision. The fingerprint is saved
-- with the chart so a joining peer makes the same refresh decision as the host.
local function append(parts, value, skip)
  local kind = type(value)
  if kind == "table" then
    parts[#parts + 1] = "{"
    local numbers, strings = {}, {}
    for key in pairs(value) do
      if not (skip and skip[key]) then
        if type(key) == "number" then numbers[#numbers + 1] = key
        elseif type(key) == "string" then strings[#strings + 1] = key end
      end
    end
    table.sort(numbers)
    table.sort(strings)
    for _, list in ipairs({ numbers, strings }) do
      for _, key in ipairs(list) do append(parts, key); append(parts, value[key]) end
    end
    parts[#parts + 1] = "}"
  elseif kind == "string" then
    parts[#parts + 1] = #value .. ":" .. value
  elseif kind == "number" then
    parts[#parts + 1] = string.format("%.17g;", value)
  else
    parts[#parts + 1] = kind == "boolean" and tostring(value) or "-"
  end
end

local NODE_REFS = { ins = true, outs = true, contrib = true }
local LINK_REFS = { a = true, b = true }

function Budget.fingerprint(layout, chart, inputs)
  local parts = {}
  append(parts, inputs)
  for _, key in ipairs(keys(chart.nodes)) do append(parts, chart.nodes[key], NODE_REFS) end
  for _, link in ipairs(chart.links) do append(parts, link, LINK_REFS) end
  for _, route in ipairs(chart.returns) do
    append(parts, { route.recipe, route.rate, route.fuel, route.catalyst })
    for _, source in ipairs(route.sources) do append(parts, source.key) end
    parts[#parts + 1] = ">"
    for _, target in ipairs(route.targets) do append(parts, { target.node.key, target.rate, target.w }) end
    parts[#parts + 1] = "!"
  end
  return layout .. table.concat(parts)
end

return Budget
