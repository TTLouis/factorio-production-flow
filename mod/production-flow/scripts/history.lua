-- History reads completed sampler bins and chest scans without changing them.
local Sampler = require("scripts.sampler")

local H = { OTHER = "other" }
local TICKS_PER_SECOND = 60
local MAX_BUCKETS = 60

local function source_bins(bins, size, sidx, start_tick, end_tick)
  local sources = {}
  local width = size * TICKS_PER_SECOND
  for _, bin in pairs(bins) do
    local first = bin.id * width
    local last = first + width
    if first < end_tick and last <= end_tick and last > start_tick and (size == 1 or bin.secs == size) then
      local known = (sidx and bin.stat[sidx] ~= nil) or (not sidx and next(bin.stat) ~= nil)
      sources[#sources + 1] = { first = first, last = last, bin = bin, known = known }
    end
  end
  table.sort(sources, function(a, b) return a.first < b.first end)
  return sources
end

-- The resolutions nest on the same absolute time grid. Use the finer bins if
-- they cover the interval, or if they record a gap the coarse total cannot locate.
local function merge_sources(fine, coarse, start_tick)
  local result, index = {}, 1
  for _, wide in ipairs(coarse) do
    while fine[index] and fine[index].first < wide.first do
      result[#result + 1] = fine[index]
      index = index + 1
    end
    local first, covered, known, missing = index, 0, false, false
    while fine[index] and fine[index].first < wide.last do
      local narrow = fine[index]
      covered = covered + narrow.last - math.max(narrow.first, start_tick)
      known = known or narrow.known
      missing = missing or not narrow.known
      index = index + 1
    end
    local duration = wide.last - math.max(wide.first, start_tick)
    if covered == duration or (wide.known and missing) or (not wide.known and known) then
      for i = first, index - 1 do result[#result + 1] = fine[i] end
    else
      result[#result + 1] = wide
    end
  end
  for i = index, #fine do result[#result + 1] = fine[i] end
  return result
end

local function candidate_recipes(key)
  local graph = storage.graph
  local node = graph and graph.nodes[key]
  local result = {}
  for _, name in ipairs(node and node.consumers or {}) do
    if not result[name] then
      local recipe = graph.recipes[name]
      local inputs, outputs = {}, {}
      for _, input in ipairs(recipe.ingredients) do
        inputs[input.key] = (inputs[input.key] or 0) + input.amount
      end
      for _, product in ipairs(recipe.products) do
        outputs[product.key] = (outputs[product.key] or 0) + product.amount
      end
      -- Returned inputs are catalysts. Credit a recipe to a single net output
      -- when possible, and keep ambiguous co-products together in Other uses.
      local amount = (inputs[key] or 0) - (outputs[key] or 0)
      if amount > 0 then
        local output
        for product, produced in pairs(outputs) do
          if product ~= key and produced > (inputs[product] or 0) then
            if output then output = H.OTHER; break end
            output = product
          end
        end
        result[name] = { key = output or H.OTHER, amount = amount }
      end
    end
  end
  return result
end

local function add_estimates(estimates, samples, recipes)
  if not samples or not recipes then return end
  for name, recipe in pairs(recipes) do
    local sample = samples[name]
    if sample and sample.c > 0 then
      local crafts = sample.c
      if Sampler.PF_INCLUDES_BONUS then crafts = crafts / (1 + sample.p / crafts) end
      estimates[recipe.key] = (estimates[recipe.key] or 0) + crafts * recipe.amount
    end
  end
end

local function material_totals(source, sidx, key, recipes)
  local made, used, estimates = 0, 0, {}
  local stats, crafts = source.bin.stat, source.bin.rec
  if sidx then
    local measured = stats[sidx][key]
    if measured then made, used = measured.i, measured.o end
    add_estimates(estimates, crafts[sidx], recipes)
  else
    for index, materials in pairs(stats) do
      local measured = materials[key]
      if measured then made, used = made + measured.i, used + measured.o end
      add_estimates(estimates, crafts[index], recipes)
    end
  end
  source.made, source.used, source.estimates = made, used, estimates
end

local function rate_points(result, sources)
  local width = result.bucket_seconds * TICKS_PER_SECOND
  local first, index = result.start_tick, 1
  local totals = {}
  while first < result.end_tick do
    local last = math.min(result.end_tick, (math.floor(first / width) + 1) * width)
    local made, used, seconds, seen_first, seen_last = 0, 0, 0, nil, nil
    local estimates = {}
    while sources[index] and sources[index].first < last do
      local source = sources[index]
      local left, right = math.max(first, source.first), math.min(last, source.last)
      if source.known and right > left then
        local fraction = (right - left) / (source.last - source.first)
        made = made + source.made * fraction
        used = used + source.used * fraction
        seconds = seconds + (right - left) / TICKS_PER_SECOND
        seen_first, seen_last = seen_first or left, right
        for key, amount in pairs(source.estimates) do
          estimates[key] = (estimates[key] or 0) + amount * fraction
        end
      end
      if source.last > last then break end
      index = index + 1
    end
    local point = { start_tick = seen_first or first, end_tick = seen_last or last, seconds = seconds }
    if seconds > 0 then
      point.partial = seconds * TICKS_PER_SECOND < point.end_tick - point.start_tick - 1e-6 or nil
      local estimated_total = 0
      for _, amount in pairs(estimates) do estimated_total = estimated_total + amount end
      local scale = estimated_total > used and used / estimated_total or 1
      point.made, point.used, point.net = made / seconds, used / seconds, (made - used) / seconds
      point.uses = {}
      for key, amount in pairs(estimates) do
        if key ~= H.OTHER and scale > 0 then
          local adjusted = amount * scale
          totals[key] = (totals[key] or 0) + adjusted
          point.uses[key] = adjusted / seconds
        end
      end
      result.seconds = result.seconds + seconds
    end
    result.points[#result.points + 1] = point
    first = last
  end
  return totals
end

local function group_uses(result, totals)
  local keys = {}
  for key in pairs(totals) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if totals[a] == totals[b] then return a < b end
    return totals[a] > totals[b]
  end)
  for i = 1, math.min(3, #keys) do result.usage_keys[i] = keys[i] end
  local has_other = false
  for _, point in ipairs(result.points) do
    if point.uses then
      local bands, left = {}, point.used
      for _, key in ipairs(result.usage_keys) do
        local rate = math.min(left, point.uses[key] or 0)
        bands[key], left = rate, left - rate
      end
      if left > 0 then has_other = true end
      bands[H.OTHER] = left
      point.uses = bands
    end
  end
  if has_other then result.usage_keys[#result.usage_keys + 1] = H.OTHER end
end

local function stock_count(snap, sidx, key)
  if sidx then
    local surface = snap.s[sidx]
    return surface and (surface[key] or 0)
  end
  if not next(snap.s) then return nil end
  local count = 0
  for _, surface in pairs(snap.s) do count = count + (surface[key] or 0) end
  return count
end

local function same_stock_scope(left, right)
  for index in pairs(left.s) do if not right.s[index] then return false end end
  for index in pairs(right.s) do if not left.s[index] then return false end end
  return true
end

local function add_stock_estimates(result, sources, left, right, old, new)
  local from, to = left.tick, right.tick
  local tick, net, point_index = from, 0, 1
  local estimates = {}
  for _, source in ipairs(sources) do
    if source.last > tick then
      if not source.known or source.first > tick then return end
      local stop = math.min(source.last, to)
      local net_per_tick = (source.made - source.used) / (source.last - source.first)
      while result.points[point_index] and result.points[point_index].end_tick <= stop do
        local at = result.points[point_index].end_tick
        if at > from and at < to then
          estimates[#estimates + 1] = { tick = at, net = net + (at - tick) * net_per_tick }
        end
        point_index = point_index + 1
      end
      net = net + (stop - tick) * net_per_tick
      tick = stop
      if tick == to then break end
    end
  end
  if tick ~= to then return end
  local residual = new - old - net
  for _, point in ipairs(estimates) do
    local fraction = (point.tick - from) / (to - from)
    result.stock[#result.stock + 1] = { tick = point.tick, measured = false,
      count = math.max(0, old + point.net + residual * fraction) }
  end
end

local function stock_points(result, sources, scans, sidx, key)
  local previous, old
  for _, scan in ipairs(scans) do
    if scan.tick > result.end_tick then break end
    local count = stock_count(scan, sidx, key)
    if scan.tick >= result.start_tick then
      if count ~= nil and old ~= nil and scan.tick > previous.tick and (sidx or same_stock_scope(previous, scan)) then
        add_stock_estimates(result, sources, previous, scan, old, count)
      end
      if count ~= nil then
        result.stock[#result.stock + 1] = { tick = scan.tick, count = count, measured = true }
      end
    end
    previous, old = scan, count
  end
end

---Return bounded rate buckets and chest stock for one material. Times use game
---ticks; made, used, net and usage bands are rates per second. A missing rate is
---a gap. A stock entry has its exact scan tick or an interior estimate tick.
function H.build(sidx, period, key)
  local requested = period and period > 0 and period or settings.global["ssk-window-seconds"].value
  local now = game.tick
  local result = { start_tick = now - requested * TICKS_PER_SECOND, end_tick = now, seconds = 0,
    bucket_seconds = math.ceil(requested / MAX_BUCKETS), points = {}, usage_keys = {}, stock = {},
    stock_supported = key:sub(1, 5) == "item/" }
  local scans = result.stock_supported and storage.stock_basis == "physical-chests-v1" and storage.stock or {}
  local start_tick = result.start_tick
  -- A scan just before the visible range can still anchor estimates in it.
  for i = #scans - 1, 1, -1 do
    if scans[i].tick < result.start_tick then
      if scans[i + 1].tick <= now and scans[i + 1].tick > result.start_tick then start_tick = scans[i].tick end
      break
    end
  end
  local sources = source_bins(storage.bins or {}, 1, sidx, start_tick, now)
  for _, ring in ipairs(storage.rings or {}) do
    sources = merge_sources(sources, source_bins(ring.bins, ring.secs, sidx, start_tick, now), start_tick)
  end
  local recipes = candidate_recipes(key)
  for _, source in ipairs(sources) do
    if source.known then
      material_totals(source, sidx, key, source.last > result.start_tick and recipes or nil)
    end
  end
  group_uses(result, rate_points(result, sources))
  stock_points(result, sources, scans, sidx, key)
  return result
end

return H
