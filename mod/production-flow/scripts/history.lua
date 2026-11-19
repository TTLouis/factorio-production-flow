-- History reads completed sampler bins and chest scans without changing them.
local Sampler = require("scripts.sampler")
local Graph = require("scripts.graph")
local Transport = require("scripts.transport_flows")

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
  if source.stock_rate then return source.stock_rate * (source.last - source.first) end
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

local function scoped_stock_sources(sources, scope, key)
  if not scope then return sources end
  local result = {}
  for _, source in ipairs(sources) do
    if source.known then
      local intervals = { { first = source.first, last = source.last, rate = 0 } }
      for index in pairs(scope) do
        local materials = source.bin.stat[index]
        local runs = source.bin.coverage and source.bin.coverage[index]
        if not materials or source.bin.coverage and not runs then intervals = {}; break end
        local duration = source.duration or (source.last - source.first)
        if runs then
          duration = 0
          for i = 1, #runs, 2 do duration = duration + (runs[i + 1] - runs[i]) * TICKS_PER_SECOND end
        end
        local measured = materials[key]
        local rate = measured and (measured.i - measured.o) / duration or 0
        local covered = {}
        for _, interval in ipairs(intervals) do
          if runs then
            for i = 1, #runs, 2 do
              local first = math.max(interval.first, runs[i] * TICKS_PER_SECOND)
              local last = math.min(interval.last, runs[i + 1] * TICKS_PER_SECOND)
              if last > first then covered[#covered + 1] = { first = first, last = last, rate = interval.rate + rate } end
            end
          else
            covered[#covered + 1] = { first = interval.first, last = interval.last, rate = interval.rate + rate }
          end
        end
        intervals = covered
      end
      -- Aggregate coverage means any surface was sampled. Stock requires every
      -- surface in its physical baseline, with each total divided by its own
      -- observed duration. Intersect those runs instead of bridging their gaps.
      for _, interval in ipairs(intervals) do
        result[#result + 1] = { first = interval.first, last = interval.last, known = true, stock_rate = interval.rate }
      end
    end
  end
  return result
end

local function add_stock_estimates(result, sources, from, to, old, new, scope, key)
  sources = scoped_stock_sources(sources, scope, key)
  local live = new == nil
  local tick, net, point_index = from, 0, 1
  local estimates, last_rate, last_rate_end = {}, nil, nil
  local crossings={}
  for _,event in ipairs(result.stock_events or {}) do
    if event.tick>from and event.tick<=to and (not scope or scope[event.surface_index]) then crossings[#crossings+1]=event end
  end
  local shipment_index, shipment_total, crossing_index = 1, 0, 1
  local function shipment_net(at)
    while crossings[shipment_index] and crossings[shipment_index].tick <= at do
      shipment_total = shipment_total + crossings[shipment_index].delta
      shipment_index = shipment_index + 1
    end
    return shipment_total
  end
  local completed = math.floor(result.end_tick / TICKS_PER_SECOND) * TICKS_PER_SECOND
  local function advance(stop, net_per_tick, extrapolated)
    while crossings[crossing_index] and crossings[crossing_index].tick <= stop do
      local event = crossings[crossing_index]
      if event.tick>tick and event.tick<=stop then
        estimates[#estimates+1]={tick=event.tick,net=net+(event.tick-tick)*net_per_tick,
          extrapolated=extrapolated,boundary=true,event=event}
      end
      crossing_index = crossing_index + 1
    end
    local start = result.start_tick
    if start > from and start > tick and start <= stop and start < to then
      estimates[#estimates + 1] = { tick = start, net = net + (start - tick) * net_per_tick,
        extrapolated = extrapolated }
    end
    while result.points[point_index] and result.points[point_index].end_tick <= stop do
      local at = result.points[point_index].end_tick
      if at > from and at < to and at > tick then
        estimates[#estimates + 1] = { tick = at, net = net + (at - tick) * net_per_tick,
          extrapolated = extrapolated }
      end
      point_index = point_index + 1
    end
    net = net + (stop - tick) * net_per_tick
    tick = stop
  end
  for _, source in ipairs(sources) do
    if source.last == completed and source.last <= from then
      -- A scan on or after the latest completed boundary can still use that
      -- immediately preceding observation for the remaining fractional second.
      local change = stock_net(source, scope, key)
      last_rate = change and change / (source.duration or (source.last - source.first)) or nil
      last_rate_end = source.last
    elseif source.last > tick then
      if source.first > tick then break end
      local change = stock_net(source, scope, key)
      if change == nil then break end
      local stop = math.min(source.last, to)
      local net_per_tick = change / (source.duration or (source.last - source.first))
      advance(stop, net_per_tick)
      last_rate, last_rate_end = net_per_tick, stop
      if tick == to then break end
    end
  end
  -- Completed-bin statistics never include the accumulating second. Forecast
  -- only its short tail, after a contiguous run reaches the current completed
  -- boundary. Older missing history or missing surface coverage stays a gap.
  local extrapolated = last_rate ~= nil and last_rate_end == completed and tick >= completed and to > tick
    and to - completed < TICKS_PER_SECOND and to <= result.end_tick
  if extrapolated then advance(to, last_rate, true) end
  if live then
    -- The final point follows the current time only when the short forecast
    -- above is supported; otherwise it stops at the last covered observation.
    local last = estimates[#estimates]
    if tick >= result.start_tick and tick > from and (not last or last.tick < tick) then
      estimates[#estimates + 1] = { tick = tick, net = net, extrapolated = extrapolated or nil }
    end
  elseif tick ~= to then
    return nil
  end
  table.sort(estimates,function(a,b) return a.tick<b.tick end)
  local unique={}
  for _,point in ipairs(estimates) do
    local previous=unique[#unique]
    if previous and previous.tick==point.tick then
      previous.boundary=previous.boundary or point.boundary;previous.event=previous.event or point.event
    else unique[#unique+1]=point end
  end
  for _, point in ipairs(unique) do if live or point.tick<to then
    result.stock[#result.stock + 1] = { tick = point.tick, measured = false, live = live or nil, joined = true,
      boundary=point.boundary,transport=point.event,extrapolated = point.extrapolated,
      count = math.max(0, old + point.net + shipment_net(point.tick)) }
  end end
  return true
end

local function stock_events(result,scans,sidx,key,first,last)
  if not result.stock_supported then return {} end
  local force=game.forces and game.forces.player
  if not (force and force.valid and game.surfaces) then return {} end
  local scopes={}
  if sidx then scopes[sidx]=true else for _,scan in ipairs(scans) do for index in pairs(scan.s) do scopes[index]=true end end end
  local events,receipts={},{}
  for index in pairs(scopes) do
    local surface=game.surfaces[index]
    if surface and surface.valid then
      local observed,metadata=Transport.events(force,surface,last,(last-first)/60,{material=key:sub(6)})
      if metadata and metadata.provider then result.import_receipts=result.import_receipts or {} end
      for _,event in ipairs(observed or {}) do
        if event.material==key then
          -- Receipt markers are observations, independent of whether this
          -- engine version includes cargo in production statistics. Combine
          -- qualities arriving on the same tick without changing accounting.
          if event.kind=="received" and event.delta>0 and event.tick>=result.start_tick and event.tick<=last then
            local receipt=receipts[event.tick]
            if not receipt then
              receipt={tick=event.tick,count=0};receipts[event.tick]=receipt
              result.import_receipts=result.import_receipts or {}
              result.import_receipts[#result.import_receipts+1]=receipt
            end
            receipt.count=receipt.count+event.delta
          end
          if event.stats_included==false then events[#events+1]=event
          elseif event.stats_included==nil then result.stock_transport_incomplete=true end
        end
      end
      if metadata and metadata.provider then
        local coverage, seconds = metadata.coverage or {}, metadata.period_seconds or (last-first)/60
        if metadata.truncated or metadata.received_partial or not metadata.coverage_known
          or (coverage.sent or 0) < seconds or (coverage.received or 0) < seconds then
          result.stock_transport_incomplete=true
        end
      end
    end
  end
  if result.import_receipts then table.sort(result.import_receipts,function(a,b)return a.tick<b.tick end) end
  table.sort(events,function(a,b) if a.tick~=b.tick then return a.tick<b.tick end;return a.key<b.key end)
  return events
end

local function stock_points(result, sources, scans, sidx, key)
  local previous, old
  for _, scan in ipairs(scans) do
    if scan.tick > result.end_tick then break end
    local count = stock_count(scan, sidx, key)
    if scan.tick >= result.start_tick then
      local joined
      if count ~= nil and old ~= nil and scan.tick > previous.tick and (sidx or same_stock_scope(previous, scan)) then
        joined = add_stock_estimates(result, sources, previous.tick, scan.tick, old, count, not sidx and previous.s or nil, key)
      end
      if count ~= nil then
        result.stock[#result.stock + 1] = { tick = scan.tick, count = count, measured = true, joined = joined, boundary=true }
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
  local scans = result.stock_supported and storage.stock_basis == "physical-storage-v2" and storage.stock or {}
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
  result.stock_events=stock_events(result,scans,sidx,key,start_tick,now)
  stock_points(result, sources, scans, sidx, key)
  return result
end

return H
