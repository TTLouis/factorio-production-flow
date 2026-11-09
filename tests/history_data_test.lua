local H = require("scripts.history")
local material = "item/iron-plate"
local other = H.OTHER
prototypes = { get_entity_filtered = function() return {
  lab = { lab_inputs = { "modded-science", { name = "automation-science-pack" } } },
} end }

local function near(actual, expected)
  assert(actual and math.abs(actual - expected) < 1e-8, tostring(actual) .. " ~= " .. expected)
end

local function reset(tick)
  storage = { bins = {}, rings = {}, stock = {}, stock_basis = "physical-chests-v1" }
  settings = { global = { ["ssk-window-seconds"] = { value = 60 } } }
  game = { tick = tick }
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
near(stock_at(h, 300).count, 185.5)
near(stock_at(h, 600).count, 130.5)
assert(h.stock[#h.stock].live and h.stock[#h.stock].tick == 720, "stop at the latest complete sampler bin")
near(h.stock[#h.stock].count, 0)
near(stock_at(H.build(2, 12, material), 300).count, 790)
near(stock_at(H.build(nil, 12, material), 300).count, 975.5)
assert(not H.build(1, 12, "fluid/water").stock_supported and #H.build(1, 12, "fluid/water").stock == 0)
assert(#H.build(999, 12, material).stock == 0)

local clipped = H.build(1, 10, material)
assert(not stock_at(clipped, 30) and stock_at(clipped, 300))
assert(clipped.stock[1].tick == clipped.start_tick and not clipped.stock[1].measured,
  "a complete scan interval should fill the visible time axis from its left edge")
near(stock_at(clipped, 300).count, 185.5)
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
assert(last.live and not last.measured and last.tick == 360)
near(last.count, 29)
near(stock_at(h, last_scan.tick).count, 20)
near(stock_at(H.build(nil, 20, material), 360).count, 80)
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

reset(6 * 60)
for sec = 0, 5 do fine(sec, stats(sec < 3 and 0 or 100, sec < 3 and 100 or 0)) end
scan(0, 1)
scan(360, 1)
h = H.build(1, 6, material)
near(stock_at(h, 180).count, 0)
near(stock_at(h, 360).count, 1)
storage.stock_basis = "legacy-logistic-network"
assert(#H.build(1, 6, material).stock == 0)
print("MATERIAL HISTORY OK: bounded aligned rates, gaps, ranked usage, measured and estimated stock, surface scopes")
