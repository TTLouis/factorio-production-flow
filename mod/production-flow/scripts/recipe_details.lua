-- Recipe details for Sankey bar tooltips: a recipe's per-craft and current
-- rates with the machines running it, and the recipes that make and use a
-- material. Rates come from the view; machines from the sampler's registry or,
-- for a production cell, from the cell's members.
local Loc = require("scripts.locale")
local Sampler = require("scripts.sampler")
local Tooltip = require("scripts.tooltip")

local RD = {}

local LIST_LIMIT = 3
local MACHINE_LIMIT = 6

-- context = { rates = {[recipe] = {normal = crafts/s, bonus = productivity crafts/s}},
--             sidx = surface index, members = {[unit] = entity} or nil,
--             capacity = true when rates are full-speed figures }
-- Model rates ({cps, normal_cps}) are converted once per view.
function RD.from_model(recipes)
  local rates = {}
  for name, rate in pairs(recipes or {}) do
    local normal = rate.normal_cps or 0
    rates[name] = { normal = normal, bonus = math.max(0, (rate.cps or 0) - normal) }
  end
  return rates
end

local function short(x)
  local text = string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", "")
  return text
end

local function rich(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  return "[" .. kind .. "=" .. name .. "]"
end

local function rate_of(rate, part, input)
  if input then return rate.normal * part.amount end
  return rate.normal * part.amount + rate.bonus * (part.prod or part.amount)
end

-- "[a] x + [b] y → [c] z" with per-craft amounts (rate nil) or rates.
local function recipe_line(recipe, rate, fmt)
  local parts = {}
  local function side(list, input)
    for i, part in ipairs(list) do
      if i > 1 then parts[#parts + 1] = " + " end
      parts[#parts + 1] = rich(part.key) .. " "
      parts[#parts + 1] = rate and Loc("recipe-details-rate", fmt(rate_of(rate, part, input))) or short(part.amount)
    end
  end
  side(recipe.ingredients, true)
  parts[#parts + 1] = " → "
  side(recipe.products, false)
  return Tooltip.lines(parts)
end

-- Machines running each recipe, counted once per tick and surface (or cell) as
-- counts[recipe][entity][quality][speed]. The surface count reads the
-- sampler's registry; a machine's name and quality never change, so they are
-- kept on its record after the first read and later redraws make no entity calls.
local cache = { tick = -1 }
local function count(counts, recipe, name, quality, speed)
  local by_name = counts[recipe]
  if not by_name then by_name = {}; counts[recipe] = by_name end
  local by_quality = by_name[name]
  if not by_quality then by_quality = {}; by_name[name] = by_quality end
  local by_speed = by_quality[quality]
  if not by_speed then by_speed = {}; by_quality[quality] = by_speed end
  local rounded = math.floor(speed * 1000 + 0.5) / 1000
  by_speed[rounded] = (by_speed[rounded] or 0) + 1
end

function RD.machine_counts(context)
  local key = context.members or context.sidx
  if cache.tick ~= game.tick or cache.key ~= key then
    local counts = {}
    if context.members then
      for _, entity in pairs(context.members) do
        if entity.valid then
          local name = Sampler.current_recipe(entity)
          if name then count(counts, name, entity.name, entity.quality and entity.quality.name or "normal", entity.crafting_speed) end
        end
      end
    else
      for _, rec in pairs(storage.machines or {}) do
        if rec.s == context.sidx and rec.r and rec.spd then
          if not rec.n and rec.e.valid then rec.n, rec.q = rec.e.name, rec.e.quality and rec.e.quality.name or "normal" end
          if rec.n then count(counts, rec.r, rec.n, rec.q, rec.spd) end
        end
      end
    end
    cache = { tick = game.tick, key = key, counts = counts, groups = {} }
  end
  return cache.counts
end

local function machines_for(context, recipe)
  local counts = RD.machine_counts(context)
  local groups = cache.groups[recipe]
  if groups then return groups end
  groups = {}
  for name, by_quality in pairs(counts[recipe] or {}) do
    local prototype = prototypes.entity[name]
    for quality, by_speed in pairs(by_quality) do
      local base = prototype and prototype.get_crafting_speed(quality) or 0
      for speed, n in pairs(by_speed) do
        groups[#groups + 1] = { name = name, quality = quality, speed = speed, count = n,
          bonus = base > 0 and speed / base - 1 or 0 }
      end
    end
  end
  table.sort(groups, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.name ~= b.name then return a.name < b.name end
    if a.quality ~= b.quality then return a.quality < b.quality end
    return a.speed > b.speed
  end)
  cache.groups[recipe] = groups
  return groups
end

local function machine_line(group)
  local icon = "[entity=" .. group.name .. (group.quality ~= "normal" and ",quality=" .. group.quality or "") .. "]"
  local count = string.format("%d", group.count)
  if math.abs(group.bonus) >= 0.005 then
    local bonus = string.format("%+.0f%%", group.bonus * 100)
    return Loc("recipe-details-machine-bonus", icon, count, short(group.speed), bonus)
  end
  return Loc("recipe-details-machine", icon, count, short(group.speed))
end

-- Lines for a recipe bar.
function RD.recipe(context, name, fmt)
  local recipe = storage.graph and storage.graph.recipes[name]
  if not (context and recipe) then return nil end
  local lines = { Loc("recipe-details-per-craft", short(recipe.energy), recipe_line(recipe, nil, fmt)) }
  local rate = context.rates and context.rates[name]
  if rate and rate.normal + rate.bonus > 1e-9 then
    local line = recipe_line(recipe, rate, fmt)
    lines[#lines + 1] = context.capacity and Loc("recipe-details-capacity", line) or Loc("recipe-details-measured", line)
  end
  local groups = machines_for(context, name)
  if #groups > 0 then
    lines[#lines + 1] = Loc("recipe-details-machines")
    for i, group in ipairs(groups) do
      if i > MACHINE_LIMIT then
        lines[#lines + 1] = Loc("recipe-details-more", string.format("%d", #groups - MACHINE_LIMIT))
        break
      end
      lines[#lines + 1] = machine_line(group)
    end
  end
  return Loc.join_list(lines, "\n")
end

-- Lines for an item or fluid bar: the running recipes that make and use it.
function RD.material(context, key, fmt, limit, recipe_icons)
  local graph = storage.graph
  local node = graph and graph.nodes[key]
  if not (context and context.rates and node) then return nil end
  local lines = {}
  limit = limit or LIST_LIMIT
  local function list(names, heading, input)
    local found, seen = {}, {}
    for _, name in ipairs(names) do
      local recipe, rate = graph.recipes[name], context.rates[name]
      if recipe and rate and not seen[name] then
        seen[name] = true
        local amount = 0
        for _, part in ipairs(input and recipe.ingredients or recipe.products) do
          if part.key == key then amount = amount + rate_of(rate, part, input) end
        end
        if amount > 1e-9 then found[#found + 1] = { name = name, recipe = recipe, rate = rate, amount = amount } end
      end
    end
    if #found == 0 then return end
    table.sort(found, function(a, b)
      if a.amount ~= b.amount then return a.amount > b.amount end
      return a.name < b.name
    end)
    lines[#lines + 1] = heading
    for i, entry in ipairs(found) do
      if i > limit then
        lines[#lines + 1] = Loc("recipe-details-more", string.format("%d", #found - limit))
        break
      end
      local icon = recipe_icons and recipe_icons("recipe/" .. entry.name)
      local recipe_icon = "[recipe=" .. entry.name .. "]"
      if icon then recipe_icon = Loc.join(icon, " ", recipe_icon) end
      lines[#lines + 1] = Loc.join(recipe_icon, "  ", recipe_line(entry.recipe, entry.rate, fmt))
    end
  end
  list(node.producers, Loc("recipe-details-made-by"), false)
  list(node.consumers, Loc("recipe-details-used-by"), true)
  if #lines == 0 then return nil end
  return Loc.join_list(lines, "\n")
end

return RD
