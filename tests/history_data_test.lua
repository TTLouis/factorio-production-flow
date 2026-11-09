local H = require("scripts.history")
local material = "item/iron-plate"
local other = H.OTHER

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
near(next_point.uses[d], 10); near(next_point.uses[a], 0)
near(third.uses[other], 0); near(fourth.uses[other], 20)
assert(idle.made == 0 and idle.used == 0 and gap.made == nil and gap.used == nil)
assert(H.build(2, 10, material).usage_keys[1] == x)
for _, point in ipairs(h.points) do
  if point.uses then
    local sum = 0
    for _, key in ipairs(h.usage_keys) do sum = sum + point.uses[key] end
    near(sum, point.used)
  end
end

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
near(stock_at(h, 30).count, 100); near(stock_at(h, 630).count, 130); near(stock_at(h, 690).count, 0)
assert(not stock_at(h, 300).measured)
near(stock_at(h, 300).count, 185.5)
near(stock_at(h, 600).count, 130.5)
assert(h.stock[#h.stock].tick == 690, "no extrapolation or partial scans")
near(stock_at(H.build(2, 12, material), 300).count, 790)
near(stock_at(H.build(nil, 12, material), 300).count, 975.5)
assert(not H.build(1, 12, "fluid/water").stock_supported and #H.build(1, 12, "fluid/water").stock == 0)
assert(#H.build(999, 12, material).stock == 0)

local clipped = H.build(1, 10, material)
assert(not stock_at(clipped, 30) and stock_at(clipped, 300))
near(stock_at(clipped, 300).count, 185.5)
storage.bins[4] = nil
h = H.build(1, 12, material)
assert(stock_at(h, 30) and stock_at(h, 630) and not stock_at(h, 300), "no estimates over a rate gap")
assert(stock_at(h, 660) and stock_at(h, 660).count >= 0, "later interval can still be estimated")
fine(4, stats(20, 0), stats(500, 0))
table.insert(storage.stock, 2, { tick = 390, s = { [2] = { [material] = 800 } } })
h = H.build(1, 12, material)
assert(stock_at(h, 30) and stock_at(h, 630) and not stock_at(h, 300), "no estimates over a missing surface scan")
assert(not stock_at(h, 390), "unscanned surface must not appear as an empty chest scan")
assert(not stock_at(H.build(nil, 12, material), 300), "aggregate scope changed between scans")

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
