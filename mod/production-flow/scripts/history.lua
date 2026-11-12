-- History reads completed sampler bins and chest scans without changing them.
local Sampler = require("scripts.sampler")
local Graph = require("scripts.graph")

local H = { OTHER = "other", LABS = "labs" }
local TICKS_PER_SECOND = 60
local MAX_BUCKETS = 60
local ROLLING_MIN_PERIOD = 3600
local ROLLING_BUCKETS = 3

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
      local crafts = Sampler.normal_crafts(sample)
      if crafts > 0 then
        estimates[recipe.key] = (estimates[recipe.key] or 0) + crafts * recipe.amount
      end
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

local function rate_points(result, sources, lab_input, rate_start_tick)
  local width = result.bucket_seconds * TICKS_PER_SECOND
  local first, index = rate_start_tick, 1
  local totals, points, duration = {}, {}, 0
  while first < result.end_tick do
    local visible = first >= result.start_tick
    local boundary = visible and result.end_tick or result.start_tick
    local last = math.min(boundary, (math.floor(first / width) + 1) * width)
    local made, used, seconds, seen_first, seen_last = 0, 0, 0, nil, nil
    local estimates = {}
    while sources[index] and sources[index].first < last do
      local source = sources[index]
      local left, right = math.max(first, source.first), math.min(last, source.last)
      if source.known and right > left then
        local fraction = (right - left) / (source.duration or (source.last - source.first))
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
      if lab_input and used - estimated_total > 1e-9 then
        estimates[H.LABS] = used - estimated_total
      end
      point.made, point.used, point.net = made / seconds, used / seconds, (made - used) / seconds
      point.uses = {}
      for key, amount in pairs(estimates) do
        if key ~= H.OTHER and scale > 0 then
          local adjusted = amount * scale
          if visible then totals[key] = (totals[key] or 0) + adjusted end
          point.uses[key] = adjusted / seconds
        end
      end
    end
    points[#points + 1] = point
    if visible then duration = duration + seconds end
    first = last
  end
  return points, totals, duration
end

local function ranked_uses(totals)
  local keys = {}
  for key in pairs(totals) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if a == H.LABS or b == H.LABS then return a == H.LABS and b ~= H.LABS end
    if totals[a] == totals[b] then return a < b end
    return totals[a] > totals[b]
  end)
  return { table.unpack(keys, 1, math.min(3, #keys)) }
end

local function group_uses(points, keys, totals)
  local has_other = false
  for _, point in ipairs(points) do
    if point.uses then
      local unattributed = point.used
      for _, rate in pairs(point.uses) do unattributed = unattributed - rate end
      point.usage_detail = point.uses
      if unattributed > 1e-9 then
        point.usage_detail[H.OTHER] = unattributed
        if totals then totals[H.OTHER] = (totals[H.OTHER] or 0) + unattributed * point.seconds end
      end
      local bands, left = {}, point.used
      for _, key in ipairs(keys) do
        local rate = math.min(left, point.uses[key] or 0)
        bands[key], left = rate, left - rate
      end
      if left > 1e-9 then has_other = true end
      bands[H.OTHER] = left
      point.uses = bands
    end
  end
  return has_other
end

local function add_weighted_rates(target, rates, weight)
  for key, rate in pairs(rates) do target[key] = (target[key] or 0) + rate * weight end
end

-- Keep the non-overlapping buckets for period totals and stock. Only the
-- plotted rates use overlapping trailing windows, bounded by recorded runs.
local function rolling_points(points, window_ticks)
  local rolling, first = {}, 1
  for i, point in ipairs(points) do
    if point.made == nil or point.partial then
      rolling[i], first = point, i + 1
    else
      if i > 1 and points[i - 1].end_tick ~= point.start_tick then first = i end
      local end_tick = point.end_tick
      local start_tick = math.max(points[first].start_tick, end_tick - window_ticks)
      while points[first].end_tick <= start_tick do first = first + 1 end
      local duration = end_tick - start_tick
      local average = { start_tick = point.start_tick, end_tick = end_tick,
        average_start_tick = start_tick, made = 0, used = 0, uses = {}, usage_detail = {} }
      for j = first, i do
        local sample = points[j]
        local weight = (sample.end_tick - math.max(start_tick, sample.start_tick)) / duration
        average.made = average.made + sample.made * weight
        average.used = average.used + sample.used * weight
        add_weighted_rates(average.uses, sample.uses, weight)
        add_weighted_rates(average.usage_detail, sample.usage_detail, weight)
      end
      average.net = average.made - average.used
      rolling[i] = average
    end
  end
  return rolling
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

local function stock_net(source, scope, key)
  if not source.known then return nil end
  if not scope then return source.made - source.used end
  local net = 0
  for index in pairs(scope) do
    local materials = source.bin.stat[index]
    if not materials then return nil end
    local measured = materials[key]
    if measured then net = net + measured.i - measured.o end
  end
  return net
end

local function add_stock_estimates(result, sources, from, to, old, new, scope, key)
  local live = new == nil
  local tick, net, point_index = from, 0, 1
  local estimates = {}
  for _, source in ipairs(sources) do
    if source.last > tick then
      if source.first > tick then break end
      local change = stock_net(source, scope, key)
      if change == nil then break end
      local stop = math.min(source.last, to)
      local net_per_tick = change / (source.duration or (source.last - source.first))
      local start = result.start_tick
      if start > from and start > tick and start <= stop and start < to then
        estimates[#estimates + 1] = { tick = start, net = net + (start - tick) * net_per_tick }
      end
      while result.points[point_index] and result.points[point_index].end_tick <= stop do
        local at = result.points[point_index].end_tick
        if at > from and at < to and (not estimates[#estimates] or at > estimates[#estimates].tick) then
          estimates[#estimates + 1] = { tick = at, net = net + (at - tick) * net_per_tick }
        end
        point_index = point_index + 1
      end
      net = net + (stop - tick) * net_per_tick
      tick = stop
      if tick == to then break end
    end
  end
  if live then
    -- Finish at the latest covered sample, even inside the current plot bucket.
    local last = estimates[#estimates]
    if tick >= result.start_tick and tick > from and (not last or last.tick < tick) then
      estimates[#estimates + 1] = { tick = tick, net = net }
    end
  elseif tick ~= to then
    return nil
  end
  local residual = live and 0 or new - old - net
  for _, point in ipairs(estimates) do
    local fraction = (point.tick - from) / (to - from)
    result.stock[#result.stock + 1] = { tick = point.tick, measured = false, live = live or nil, joined = true,
      count = math.max(0, old + point.net + residual * fraction) }
  end
  return true
end

local function stock_points(result, sources, scans, sidx, key)
  local previous, old
  for _, scan in ipairs(scans) do
    if scan.tick > result.end_tick then break end
    local count = stock_count(scan, sidx, key)
    if scan.tick >= result.start_tick then
      local joined
      if count ~= nil and old ~= nil and scan.tick > previous.tick and (sidx or same_stock_scope(previous, scan)) then
        joined = add_stock_estimates(result, sources, previous.tick, scan.tick, old, count)
      end
      if count ~= nil then
        result.stock[#result.stock + 1] = { tick = scan.tick, count = count, measured = true, joined = joined }
      end
    end
    previous, old = scan, count
  end
  if previous and old ~= nil and previous.tick < result.end_tick then
    local scope = not sidx and previous.s or nil
    add_stock_estimates(result, sources, previous.tick, result.end_tick, old, nil, scope, key)
  end
end

---Return bounded rate buckets and chest stock for one material. Times use game
---ticks; made, used, net and usage bands are rates per second. A missing rate is
---a gap. Stock comes from scans or rate-based estimates, including after the latest scan.
function H.build(sidx, period, key)
  local requested = period and period > 0 and period or settings.global["ssk-window-seconds"].value
  local now = game.tick
  local result = { start_tick = now - requested * TICKS_PER_SECOND, end_tick = now, seconds = 0,
    bucket_seconds = math.ceil(requested / MAX_BUCKETS), points = {}, usage_keys = {}, stock = {},
    stock_supported = key:sub(1, 5) == "item/" }
  local scans = result.stock_supported and storage.stock_basis == "physical-chests-v1" and storage.stock or {}
  local rate_start_tick = result.start_tick
  if requested >= ROLLING_MIN_PERIOD then
    result.rolling_seconds = result.bucket_seconds * ROLLING_BUCKETS
    rate_start_tick = rate_start_tick - result.rolling_seconds * TICKS_PER_SECOND
  end
  local start_tick = result.start_tick
  -- A scan just before the visible range can still anchor estimates in it.
  for i = #scans, 1, -1 do
    if scans[i].tick < result.start_tick then
      start_tick = scans[i].tick
      break
    end
  end
  local sources = Sampler.history_sources(sidx, start_tick, now, true)
  local recipes = candidate_recipes(key)
  local separate_lookback = rate_start_tick < start_tick
  local recipe_start = separate_lookback and result.start_tick or rate_start_tick
  for _, source in ipairs(sources) do
    if source.known then
      material_totals(source, sidx, key, source.last > recipe_start and recipes or nil)
    end
  end
  local lab_inputs = result.stock_supported and Graph.lab_inputs()
  local lab_input = lab_inputs and lab_inputs[key]
  result.points, result.usage_totals, result.seconds = rate_points(result, sources, lab_input, result.start_tick)
  result.usage_keys = ranked_uses(result.usage_totals)
  local has_other = group_uses(result.points, result.usage_keys, result.usage_totals)
  if result.rolling_seconds then
    local lookback = separate_lookback and Sampler.history_sources(sidx, rate_start_tick, now, true) or sources
    local points = result.points
    if lookback[1] and lookback[1].first < result.start_tick then
      -- The visible totals retain their fine cutoff. Build each rolling point
      -- from one set of sources so a coarse bin and its finer suffix cannot overlap.
      if separate_lookback then
        for _, source in ipairs(lookback) do
          if source.known then material_totals(source, sidx, key, recipes) end
        end
      end
      points = rate_points(result, lookback, lab_input, rate_start_tick)
      group_uses(points, result.usage_keys)
    end
    local rolling = rolling_points(points, result.rolling_seconds * TICKS_PER_SECOND)
    result.rolling_points = {}
    for i = #points - #result.points + 1, #points do
      local point = rolling[i]
      result.rolling_points[#result.rolling_points + 1] = point
      has_other = has_other or point.uses and (point.uses[H.OTHER] or 0) > 1e-9
    end
  end
  if has_other then result.usage_keys[#result.usage_keys + 1] = H.OTHER end
  stock_points(result, sources, scans, sidx, key)
  return result
end

return H
