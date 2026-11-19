local H = require("scripts.history")
local Transport = require("scripts.transport_flows")
local original_events = Transport.events
local crossings, crossing_metadata = {}, {}
Transport.events = function(force, surface, last, seconds, filters)
  assert(force == game.forces.player and surface == game.surfaces[surface.index])
  local result = {}
  for _, event in ipairs(crossings) do
    if event.surface_index == surface.index and event.tick >= last - seconds * 60 and event.tick <= last
      and (not filters.material or event.material == "item/" .. filters.material) then result[#result + 1] = event end
  end
  return result, crossing_metadata
end
local material = "item/iron-plate"
local other = H.OTHER
prototypes = { get_entity_filtered = function() return {
  lab = { lab_inputs = { "modded-science", { name = "automation-science-pack" } } },
} end }

local function near(actual, expected)
  assert(actual and math.abs(actual - expected) < 1e-8, tostring(actual) .. " ~= " .. expected)
end

local function reset(tick)
  storage = { bins = {}, rings = {}, stock = {}, stock_basis = "physical-storage-v2" }
  settings = { global = { ["ssk-window-seconds"] = { value = 60 } } }
  game = { tick = tick, forces = { player = { index = 1, valid = true } }, surfaces = {
    { index = 1, valid = true }, { index = 2, valid = true }, { index = 3, valid = true } } }
  crossings, crossing_metadata = {}, {}
end

local function stats(made, used)
  return { [material] = { i = made, o = used } }
end

local function fine(second, first, second_surface, samples)
  storage.bins[second] = { id = second, stat = { first, second_surface }, rec = samples or {} }
end

local function scan(tick, first, second)
  local function inventory(count)
    if count == nil then return nil end
    return count == 0 and {} or { [material] = count }
  end
  storage.stock[#storage.stock + 1] = { tick = tick, s = {
    inventory(first), inventory(second),
  } }
end

local function stock_at(history, tick)
  for _, point in ipairs(history.stock) do
    if point.tick == tick then return point end
  end
end

local function totals(history)
  local made, used = 0, 0
  for _, point in ipairs(history.points) do
    if point.made then
      made = made + point.made * point.seconds
      used = used + point.used * point.seconds
    end
  end
  return made, used
end

-- Overlapping resolutions, a partial coarse bin, a measured idle surface, and
-- a missing fine stats sample are all different cases.
reset(150 * 60 + 30)
for sec = 50, 139 do fine(sec, stats(20, 4), stats(500, 0)) end
fine(125, nil, stats(500, 0))
fine(150, stats(1e6, 1e6)) -- Still accumulating.
storage.rings[1] = { secs = 60, bins = {
  { id = 0, secs = 60, stat = { stats(600, 0) }, rec = {} },
  { id = 1, secs = 60, stat = { stats(9999, 9999) }, rec = {} },
  { id = 2, secs = 30, stat = { stats(9999, 9999) }, rec = {} },
} }
local h = H.build(1, 600, material)
assert(h.end_tick == game.tick and h.start_tick == game.tick - 600 * 60)
assert(#h.points <= 61 and h.points[1].made == nil and h.points[#h.points].made == nil)
near(h.seconds, 139)
local made, used = totals(h)
near(made, 600 + 79 * 20)
near(used, 79 * 4)
local found_partial
for _, point in ipairs(h.points) do
  if point.partial then found_partial = true; near(point.seconds, 9) end
end
assert(found_partial, "a missing sample inside a bucket is distinguishable from a known zero")
local second_surface = H.build(2, 600, material)
near(second_surface.seconds, 90)
near(totals(second_surface), 45000)
assert(H.build(999, 600, material).seconds == 0)

-- Keep the finest coverage when the rolling start falls inside a coarse bin.
-- Fractional chart edges must neither lose nor duplicate the measured duration.
reset(130 * 60 + 30)
for sec = 70, 129 do fine(sec, stats(3, 1)) end
storage.rings[1] = { secs = 60, bins = {
  { id = 1, secs = 60, stat = { stats(6000, 0) }, rec = {} },
} }
h = H.build(1, 0, material)
near(h.seconds, 59.5)
near(totals(h), 178.5)

-- A completed 10-minute source replaces an incomplete minute prefix without
-- being counted alongside it. A fully covered next minute still stays fine.
reset(660 * 60)
for sec = 600, 659 do fine(sec, stats(2, 1)) end
storage.rings = {
  { secs = 60, bins = { { id = 0, secs = 60, stat = { stats(500, 0) }, rec = {} } } },
  { secs = 600, bins = { { id = 0, secs = 600, stat = { stats(600, 300) }, rec = {} } } },
}
h = H.build(1, 36000, material)
near(h.seconds, 660)
near(totals(h), 720)

reset(10 * 60)
local a, b, c, d, x = "item/gear", "fluid/oil", "item/circuit", "item/belt", "item/unused"
local function input(key, amount) return { key = key, amount = amount } end
local function recipe(ingredients, ...)
  return { ingredients = ingredients, products = { ... } }
end
local single = { input(material, 1) }
local catalyst = "item/catalyst"
storage.graph = { nodes = { [material] = { consumers = { "a", "a", "a2", "b", "c", "d", "multi", "return_all", "x" } } },
  recipes = {
    a = recipe({ input(material, 4), input(material, 1), input(catalyst, 3) },
      input(a, 1), input(material, 2), input(catalyst, 3)),
    a2 = recipe(single, input(a, 2)), b = recipe(single, input(b, 1)), c = recipe(single, input(c, 1)),
    d = recipe(single, input(d, 1)), multi = recipe(single, input(a, 1), input(b, 1)),
    return_all = recipe(single, input(material, 1), input(x, 1)), x = recipe(single, input(x, 1)),
  } }
local function crafts(c, p) return { c = c, p = p or 0 } end
fine(0, stats(2, 12), stats(0, 100), {
  { a = crafts(4, 4), a2 = crafts(2), b = crafts(7), c = crafts(4), d = crafts(1), multi = crafts(3), return_all = crafts(99) },
  { x = crafts(100) },
})
fine(1, stats(6, 100), {}, { { b = crafts(2), c = crafts(1), d = crafts(10) } })
fine(2, stats(1, 0), {}, { { x = crafts(1000) } })
fine(3, stats(0, 20), {}, { { untracked = crafts(50) } })
fine(4, {}, {})
h = H.build(1, 10, material)
assert(table.concat(h.usage_keys, ",") == table.concat({ d, b, a, other }, ","))
local first, next_point, third, fourth, idle, gap = table.unpack(h.points, 1, 6)
near(first.made, 2); near(first.used, 12); near(first.net, -10)
near(first.uses[a], 8 * 12 / 23); near(first.uses[b], 7 * 12 / 23); near(first.uses[d], 12 / 23)
near(first.uses[other], 7 * 12 / 23)
near(first.usage_detail[c], 4 * 12 / 23)
near(first.usage_detail[other], 3 * 12 / 23)
near(h.usage_totals[c], 4 * 12 / 23 + 1)
near(next_point.uses[d], 10); near(next_point.uses[a], 0)
near(third.uses[other], 0); near(fourth.uses[other], 20)
assert(idle.made == 0 and idle.used == 0 and gap.made == nil and gap.used == nil)
assert(H.build(2, 10, material).usage_keys[1] == x)
for _, point in ipairs(h.points) do
  if point.uses then
    local sum = 0
    for _, key in ipairs(h.usage_keys) do sum = sum + point.uses[key] end
    near(sum, point.used)
    local detailed = 0
    for _, rate in pairs(point.usage_detail) do detailed = detailed + rate end
    near(detailed, point.used)
  end
end

-- A productivity payout can occur while a regular craft is still in progress.
-- It must not receive any of the material consumption in that time bucket.
reset(60)
storage.graph = { nodes = { [material] = { consumers = { "a", "b" } } }, recipes = {
  a = recipe(single, input(a, 1)), b = recipe(single, input(b, 1)),
} }
fine(0, stats(0, 2), nil, { { a = { c = 1, n = 0 }, b = { c = 2, n = 1 } } })
h = H.build(1, 1, material)
assert(h.usage_totals[a] == nil)
near(h.usage_totals[b], 1)
near(h.usage_totals[other], 1)

-- Science consumption left after recipes is estimated lab use. Keep ambiguous
-- recipe outputs separate, and recognise modded lab inputs from prototypes.
reset(60)
local science = "item/modded-science"
local science_input = { input(science, 1) }
storage.graph = { nodes = { [science] = { consumers = { "a", "multi" } } }, recipes = {
  a = recipe(science_input, input(a, 1)), multi = recipe(science_input, input(a, 1), input(b, 1)),
} }
fine(0, { [science] = { i = 3, o = 9 } }, { [science] = { i = 0, o = 5 } }, { { a = crafts(2), multi = crafts(1) } })
h = H.build(1, 1, science)
near(h.points[1].used, 9)
near(h.usage_totals[H.LABS], 6)
near(h.usage_totals[a], 2)
near(h.usage_totals[other], 1)
local labs_only = H.build(2, 3600, science)
assert(#labs_only.usage_keys == 1 and labs_only.usage_keys[1] == H.LABS)
near(labs_only.rolling_points[#labs_only.rolling_points].uses[H.LABS], 5)

-- Rolling windows are trailing, duration-weighted, and independent of the
-- raw buckets used for totals. An incomplete newest bucket only adds its own time.
reset(2700 * 60)
storage.graph = { nodes = { [material] = { consumers = { "a" } } }, recipes = { a = recipe(single, input(a, 1)) } }
storage.rings[1] = { secs = 600, bins = {} }
for id = 0, 3 do
  local made_rate, used_rate = 10 * (id + 1), 8 * (id + 1)
  storage.rings[1].bins[id] = { id = id, secs = 600, stat = { stats(made_rate * 600, used_rate * 600) },
    rec = { { a = crafts(used_rate * 300) } } }
end
for sec = 2400, 2699 do fine(sec, stats(50, 40), nil, { { a = crafts(20) } }) end
h = H.build(1, 36000, material)
near(h.rolling_seconds, 1800)
local newest = h.rolling_points[#h.rolling_points]
near(newest.average_start_tick, 900 * 60)
near(newest.end_tick, 2700 * 60)
near(newest.made, 35); near(newest.used, 28); near(newest.net, 7)
near(newest.usage_detail[a], 14); near(newest.uses[a], 14); near(newest.uses[other], 14)
near(h.points[#h.points].made, 50); near(h.seconds, 2700)
local raw_made, raw_used = totals(h)
near(raw_made, 75000); near(raw_used, 60000); near(h.usage_totals[a], 30000)
assert(H.build(1, 600, material).rolling_points == nil)
for _, window in ipairs({ {3600, 180}, {180000, 9000}, {900000, 45000}, {3600000, 180000} }) do
  near(H.build(1, window[1], material).rolling_seconds, window[2])
end
storage.rings[1].bins[2] = nil
h = H.build(1, 36000, material)
newest = h.rolling_points[#h.rolling_points]
near(newest.average_start_tick, 1800 * 60)
near(newest.made, (600 * 40 + 300 * 50) / 900)
storage.bins[2600] = nil
h = H.build(1, 36000, material)
assert(h.rolling_points[#h.rolling_points].partial, "A gap within a bucket stays a gap in the rolling chart")

-- Earlier samples warm the plotted average without changing visible period totals.
reset(7200 * 60 + 30)
storage.graph = { nodes = { [material] = { consumers = { "a", "b" } } }, recipes = {
  a = recipe(single, input(a, 1)), b = recipe(single, input(b, 1)),
} }
for sec = 3420, 3599 do fine(sec, stats(0, 3), nil, { { b = crafts(3) } }) end
for sec = 3600, 3659 do fine(sec, stats(90, 9), nil, { { a = crafts(9) } }) end
h = H.build(1, 3600, material)
local leading = h.rolling_points[1]
near(leading.start_tick, h.start_tick)
near(leading.average_start_tick, 3480 * 60)
near(leading.made, 30); near(leading.used, 5)
near(leading.uses[a], 3); near(leading.uses[other], 2)
near(leading.usage_detail[b], 2)
assert(#h.rolling_points == #h.points and #h.usage_keys == 2 and h.usage_keys[1] == a and h.usage_keys[2] == other)
assert(h.usage_totals[b] == nil, "Earlier usage must not affect the visible rankings or totals")
near(h.seconds, 59.5); near(h.usage_totals[a], 59.5 * 9)
storage.bins[3599] = nil
h = H.build(1, 3600, material)
near(h.rolling_points[1].average_start_tick, 3600 * 60)
near(h.rolling_points[1].made, 90)

reset(7190 * 60)
storage.rings[1] = { secs = 60, bins = {
  { id = 59, secs = 60, stat = { stats(900, 0) }, rec = {} },
} }
for sec = 3590, 3599 do fine(sec, stats(90, 0)) end
h = H.build(1, 3600, material)
near(h.points[1].seconds, 10)
near(h.points[1].made, 90)
near(h.seconds, 10)
near(h.rolling_points[1].average_start_tick, 3540 * 60)
near(h.rolling_points[1].made, 15)

reset(12 * 60 + 20)
for sec = 0, 11 do
  fine(sec, stats(sec < 5 and 20 or 0, sec >= 5 and sec < 10 and 10 or 0), stats(500, 0))
end
scan(30, 100, 700)
scan(630, 130, 900)
scan(690, 0, 1000)
storage.chest_stock = { batch = { s = { { [material] = 1e6 } } } }
h = H.build(1, 12, material)
assert(stock_at(h, 30).measured and stock_at(h, 630).measured and stock_at(h, 690).measured)
assert(not stock_at(h, 30).joined and stock_at(h, 630).joined and stock_at(h, 690).joined)
near(stock_at(h, 30).count, 100); near(stock_at(h, 630).count, 130); near(stock_at(h, 690).count, 0)
assert(not stock_at(h, 300).measured)
near(stock_at(h, 300).count, 190)
near(stock_at(h, 600).count, 140)
assert(h.stock[#h.stock].live and h.stock[#h.stock].extrapolated and h.stock[#h.stock].tick == game.tick,
  "a supported fractional-second tail reaches the current time")
near(h.stock[#h.stock].count, 0)
near(stock_at(H.build(2, 12, material), 300).count, 2950)
near(stock_at(H.build(nil, 12, material), 300).count, 3140)
assert(not H.build(1, 12, "fluid/water").stock_supported and #H.build(1, 12, "fluid/water").stock == 0)
assert(#H.build(999, 12, material).stock == 0)

local clipped = H.build(1, 10, material)
assert(not stock_at(clipped, 30) and stock_at(clipped, 300))
assert(clipped.stock[1].tick == clipped.start_tick and not clipped.stock[1].measured,
  "a complete scan interval should fill the visible time axis from its left edge")
near(stock_at(clipped, 300).count, 190)
storage.bins[4] = nil
h = H.build(1, 12, material)
assert(stock_at(h, 30) and stock_at(h, 630) and not stock_at(h, 300), "no estimates over a rate gap")
assert(not stock_at(h, 630).joined, "a measured scan following a gap must start a new run")
assert(stock_at(h, 660) and stock_at(h, 660).count >= 0, "later interval can still be estimated")
fine(4, stats(20, 0), stats(500, 0))
table.insert(storage.stock, 2, { tick = 390, s = { [2] = { [material] = 800 } } })
h = H.build(1, 12, material)
assert(stock_at(h, 30) and stock_at(h, 630) and not stock_at(h, 300), "no estimates over a missing surface scan")
assert(not stock_at(h, 390), "unscanned surface must not appear as an empty chest scan")
assert(not stock_at(H.build(nil, 12, material), 300), "aggregate scope changed between scans")

reset(6 * 60 + 15)
for sec = 0, 5 do fine(sec, stats(4, 1), stats(9, 2)) end
scan(3 * 60, 20, 30)
local last_scan = storage.stock[1]
h = H.build(1, 20, material)
local last = h.stock[#h.stock]
assert(last.live and last.extrapolated and not last.measured and last.tick == game.tick)
near(last.count, 29.75)
near(stock_at(h, last_scan.tick).count, 20)
near(stock_at(H.build(nil, 20, material), 360).count, 80)
near(stock_at(H.build(nil, 20, material), game.tick).count, 82.5)
near(h.seconds, 6)
made, used = totals(h); near(made, 24); near(used, 6)
fine(6, stats(1e6, 0), stats(1e6, 0)) -- The current accumulating bin is not a measurement.
game.tick = 6 * 60 + 30
h = H.build(1, 20, material)
near(h.stock[#h.stock].count, 30.5)
assert(h.stock[#h.stock].tick == game.tick and h.stock[#h.stock].extrapolated)
near(h.seconds, 6)
made, used = totals(h); near(made, 24); near(used, 6)
game.tick = 9 * 60
for sec = 6, 8 do fine(sec, stats(4, 1), stats(9, 2)); storage.bins[sec].stat[3] = stats(100, 0) end
h = H.build(1, 20, material)
near(h.stock[#h.stock].count, 38)
assert(h.stock[#h.stock].tick == game.tick and storage.stock[1] == last_scan and #storage.stock == 1)
near(stock_at(H.build(nil, 20, material), game.tick).count, 110)
local tail = H.build(1, 2, material)
assert(tail.stock[1].tick == tail.start_tick and tail.stock[1].live,
  "a scan before the visible range must still anchor live estimates")
storage.bins[7] = nil
h = H.build(1, 20, material)
last = h.stock[#h.stock]
assert(last.live and last.tick == 420, "stop at gaps even when there are later rates")
near(last.count, 32)

-- Extrapolation is limited to the current incomplete second. It cannot make
-- stale or retained suffix history contiguous with a scan across missing data.
reset(6 * 60 + 15)
scan(3 * 60, 20, 30)
assert(#H.build(1, 20, material).stock == 1, "a scan alone cannot forecast stock")
for sec = 0, 5 do fine(sec, stats(4, 1), stats(9, 2)) end
storage.bins[4] = nil
h = H.build(1, 20, material)
assert(h.stock[#h.stock].tick == 240 and not h.stock[#h.stock].extrapolated,
  "later current rates cannot bridge a genuine gap")
storage.bins[4] = nil; storage.bins[3] = nil
h = H.build(1, 20, material)
assert(#h.stock == 1, "a retained suffix cannot bridge discarded history after a scan")
fine(3, stats(4, 1), stats(9, 2)); fine(4, stats(4, 1), stats(9, 2))
storage.bins[5].stat[1] = nil
h = H.build(1, 20, material)
assert(h.stock[#h.stock].tick == 300 and not h.stock[#h.stock].extrapolated,
  "another surface's newest coverage does not extend the selected scope")
local scoped = H.build(2, 20, material)
assert(scoped.stock[#scoped.stock].tick == game.tick and scoped.stock[#scoped.stock].extrapolated)
near(scoped.stock[#scoped.stock].count, 52.75)
local combined = H.build(nil, 20, material)
assert(combined.stock[#combined.stock].tick == 300,
  "aggregate estimates require the latest scan's whole surface scope")
fine(5, stats(4, 1), stats(9, 2))
game.tick = 7 * 60
h = H.build(1, 20, material)
assert(h.stock[#h.stock].tick == 360 and not h.stock[#h.stock].extrapolated,
  "a missing complete second is stale history, not a fractional tail")

-- A measurement on the completed boundary can anchor a current forecast. A
-- measurement inside the current second also closes interpolation without
-- discarding the whole preceding interval; that actual scan remains unchanged.
reset(6 * 60 + 15)
for sec = 0, 5 do fine(sec, stats(4, 1), stats(9, 2)) end
scan(360, 20, 30)
h = H.build(1, 20, material)
assert(h.stock[#h.stock].tick == game.tick and h.stock[#h.stock].extrapolated)
near(h.stock[#h.stock].count, 20.75)
storage.stock = {}
scan(6 * 60 + 5, 20, 30)
h = H.build(1, 20, material)
assert(h.stock[#h.stock].tick == game.tick and h.stock[#h.stock].extrapolated,
  "a scan inside the current second can anchor its remaining fractional tail")
near(h.stock[#h.stock].count, 20.5)
storage.stock = {}
scan(180, 20, 30); scan(game.tick, 60, 80)
local newest_scan = storage.stock[2]
h = H.build(1, 20, material)
assert(stock_at(h, 360) and stock_at(h, game.tick).joined,
  "a fractional newest measured scan retains its preceding estimated interval")
near(stock_at(h, 360).count, 29)
assert(stock_at(h, game.tick).measured and not stock_at(h, game.tick).extrapolated)
near(stock_at(h, game.tick).count, 60)
assert(storage.stock[2] == newest_scan and newest_scan.s[1][material] == 60)
made, used = totals(h); near(made, 24); near(used, 6)

reset(6 * 60 + 45)
for sec = 0, 5 do fine(sec, stats(0, 8)) end
scan(360, 2)
h = H.build(1, 20, material)
assert(h.stock[#h.stock].extrapolated and h.stock[#h.stock].tick == game.tick)
near(h.stock[#h.stock].count, 0)

reset(6 * 60)
for sec = 0, 5 do fine(sec, stats(sec < 3 and 0 or 100, sec < 3 and 100 or 0)) end
scan(0, 1)
scan(360, 1)
h = H.build(1, 6, material)
near(stock_at(h, 180).count, 0)
near(stock_at(h, 360).count, 1)
storage.stock_basis = "legacy-logistic-network"
assert(#H.build(1, 6, material).stock == 0)

-- Physical crossings change the estimate on their observed boundary, never
-- before it. Later scans reset the baseline without spreading their residual
-- backwards through the earlier production/transport history.
local function event(tick, delta, surface, included, name)
  return {key=tostring(#crossings+1),tick=tick,delta=delta,surface_index=surface or 1,
    material=name or material,stats_included=included,kind=delta<0 and "sent" or "received",provider="sa"}
end
reset(600)
for sec=0,9 do fine(sec,stats(2,1),stats(0,0)) end
scan(0,100,50)
crossings[1]=event(150,-10,1,false)
crossings[2]=event(330,20,1,false)
h=H.build(1,10,material)
near(stock_at(h,120).count,102)
near(stock_at(h,150).count,92.5)
near(stock_at(h,180).count,93)
near(stock_at(h,330).count,115.5)
near(stock_at(h,600).count,120)
assert(stock_at(h,150).boundary and stock_at(h,150).transport==crossings[1])
assert(stock_at(h,330).boundary and stock_at(h,330).transport==crossings[2])
made,used=totals(h);near(made,20);near(used,10)
scan(480,80,50)
crossings[3]=event(480,5,1,false)
h=H.build(1,10,material)
near(stock_at(h,330).count,115.5)
near(stock_at(h,480).count,80)
near(stock_at(h,600).count,82)
assert(stock_at(h,480).measured and stock_at(h,480).boundary,
  "a measured scan resets the estimate and owns same-tick transport")

reset(600)
for sec=0,9 do fine(sec,stats(2,1),stats(0,0)) end
scan(0,100,50)
crossings[1]=event(150,-10,1,true)
h=H.build(1,10,material)
near(stock_at(h,600).count,110)
assert(not stock_at(h,150),"a crossing already included in statistics cannot be added again")
crossings[1]=event(150,20,1,nil)
h=H.build(1,10,material)
near(stock_at(h,600).count,110)
assert(h.stock_transport_incomplete and not stock_at(h,150),
  "unverified statistics accounting is disclosed, never guessed")
crossings={};crossing_metadata={provider="sa",received_partial=true}
h=H.build(1,10,material)
near(stock_at(h,600).count,110)
assert(h.stock_transport_incomplete and #h.stock_events==0,
  "an unknown cargo receipt cannot create a positive stock event")
crossing_metadata={provider="sa",coverage_known=true,period_seconds=10,coverage={sent=10,received=5}}
h=H.build(1,10,material)
assert(h.stock_transport_incomplete,"lost receipt coverage must mark the estimate incomplete")
crossing_metadata.coverage.received=10
h=H.build(1,10,material)
assert(not h.stock_transport_incomplete,"complete independent SA boundaries permit a complete estimate")

reset(600)
for sec=0,9 do fine(sec,stats(2,1),stats(0,0)) end
scan(0,100,50)
crossings[1]=event(150,-10,1,false)
crossings[2]=event(150,10,2,false)
crossings[3]=event(180,1000,3,false)
h=H.build(nil,10,material)
near(stock_at(h,150).count,152.5)
near(stock_at(h,600).count,160)
assert(#h.stock_events==2,"aggregate scope cannot include an unscanned surface")
scan(300,100,nil)
crossings={event(400,-10,1,false),event(400,10,2,false)}
h=H.build(nil,10,material)
near(stock_at(h,400).count,100+100/60-10)
near(stock_at(h,600).count,95)
assert(stock_at(h,300).measured and not stock_at(h,300).joined,
  "a changed aggregate scan scope establishes a new baseline")

-- A coarse source still yields every requested chart point around shipment
-- boundaries. Aggregate interpolation uses only surfaces in the anchored scan,
-- including the historical interval before a later measured reset.
reset(600)
storage.rings={{secs=60,bins={{id=0,secs=10,first=0,last=10,
  stat={stats(20,10),stats(0,0),stats(1000,0)},rec={},
  coverage={[0]={0,10},[1]={0,10},[2]={0,10},[3]={0,10}}}}}}
scan(0,100,50);scan(600,200,50)
crossings[1]=event(150,-10,1,false)
crossings[2]=event(330,20,1,false)
h=H.build(nil,10,material)
near(stock_at(h,60).count,151)
near(stock_at(h,120).count,152)
near(stock_at(h,150).count,142.5)
near(stock_at(h,180).count,143)
near(stock_at(h,300).count,145)
near(stock_at(h,330).count,165.5)
near(stock_at(h,540).count,169)
near(stock_at(h,600).count,250)
assert(stock_at(h,600).measured and stock_at(h,600).boundary)

-- Any-surface coarse coverage cannot stand in for the full physical scan scope.
-- Each surface's net total also has its own observed duration in that bin.
reset(600)
storage.rings={{secs=60,bins={{id=0,secs=10,first=0,last=10,
  stat={stats(10,0),stats(20,0)},rec={},
  coverage={[0]={0,10},[1]={0,5},[2]={0,10}}}}}}
scan(0,100,50)
h=H.build(nil,10,material)
near(stock_at(h,300).count,170)
assert(h.stock[#h.stock].tick==300 and not stock_at(h,360),
  "aggregate stock stops when one anchored surface loses coarse coverage")
near(stock_at(H.build(1,10,material),300).count,110)
near(stock_at(H.build(2,10,material),600).count,70)

-- An internal hole remains a gap even if another surface covers the whole bin.
storage.rings[1].bins[1].coverage[1]={0,3,5,10}
h=H.build(nil,10,material)
assert(h.stock[#h.stock].tick==180 and not stock_at(h,240),
  "aggregate stock cannot bridge a hole hidden by any-surface coverage")
near(stock_at(h,180).count,150+10*3/8+20*3/10)
scan(300,100,50)
h=H.build(nil,10,material)
assert(stock_at(h,300).measured and not stock_at(h,300).joined)
near(stock_at(h,600).count,150+10*5/8+20*5/10)

-- A dense observed ledger retains every actual boundary and exact running
-- total, including simultaneous events, without changing production totals.
reset(600)
for sec=0,9 do fine(sec,stats(2,1)) end
scan(0,10000)
for i=1,4096 do crossings[i]=event(math.ceil(i/8),-1,1,false) end
h=H.build(1,10,material)
near(stock_at(h,1).count,10000+1/60-8)
near(stock_at(h,512).count,10000+512/60-4096)
near(stock_at(h,600).count,5914)
made,used=totals(h);near(made,20);near(used,10)

-- Balance's receipt overlay is observation-only. Qualities at one arrival
-- share a marker; lookback/export/foreign/material events cannot leak into it.
reset(600)
for sec=0,9 do fine(sec,stats(2,1)) end
scan(0,100)
crossings={event(150,100,1,false),event(330,20,1,true),event(330,7,1,nil),
  event(450,-3,1,false),event(360,99,2,false),event(370,55,1,false,"item/copper-plate"),event(700,50,1,false)}
h=H.build(1,5,material)
assert(#h.import_receipts==1 and h.import_receipts[1].tick==330 and h.import_receipts[1].count==27,
  "receipt markers must use visible local arrivals and sum their qualities")
near(stock_at(h,600).count,207)
made,used=totals(h);near(made,10);near(used,5)
assert(#h.stock_events==2,"receipt overlay changed independent stock accounting")
storage.stock={}
h=H.build(1,5,material)
assert(#h.stock==0 and #h.import_receipts==1,"receipts must remain visible before the first stock scan")
assert(not H.build(1,5,"fluid/water").import_receipts,"item receipts leaked into fluid history")
crossings={};crossing_metadata={provider="sa",received_partial=true}
h=H.build(1,5,material)
assert(#h.import_receipts==0,"unknown cargo receipts must never invent an import marker")

Transport.events=original_events
print("MATERIAL HISTORY OK: bounded aligned rates, gaps, ranked usage, measured and estimated stock, surface scopes")
