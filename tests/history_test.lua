local Sm, UI, SK = TREQ("scripts.sampler"), TREQ("scripts.ui"), TREQ("scripts.sankey_ui")
local History = TREQ("scripts.history")
local player = game.players[1]
local old_ui = storage.ui[1]
for _, previous in ipairs({ 0, 3600, 36000 }) do
  storage.ui[1] = { period = previous }
  UI.open(player)
  local us = storage.ui[1]
  assert(us.period == (previous == 0 and 600 or previous), "upgrade default/preserve longer selection")
  assert(SK.focus_state(us).period == us.period and SK.balance_state(us).period == us.period, "all views share period")
  for i, seconds in ipairs({ 60, 600, 3600, 36000, 180000, 900000, 3600000 }) do
    UI.on_selection({ player_index = 1, element = { tags = { ssk_ui = "period" }, selected_index = i } })
    UI.open(player)
    assert(us.period == seconds, "manual period choice must persist")
  end
end
storage.ui[1] = { period = 0, period_default_10m = true }
UI.open(player)
assert(storage.ui[1].period == 60, "an explicit legacy Recent period should migrate to 1m")
storage.ui[1] = old_ui
local saved, tick, setting = storage, game.tick, settings.global["ssk-window-seconds"].value
storage = {}; settings.global["ssk-window-seconds"].value = 60
Sm.init()
for second = 0, 1250 do
  game.tick = second * 60
  Sm.on_stats(game.tick)
  -- One measured production burst, followed by a long idle period.
  local b = storage.bins[second % storage.nbins + 1]
  local count = second == 100 and 600 or 0
  b.rec = { [1] = { smelting = { c = count, p = 0 } } }
  b.stat = { [1] = { ["item/iron-plate"] = { i = count, o = 0 } } }
  local rates, secs = Sm.rates(1, 600)
  assert(secs == math.min(second, 600), "10-minute window lost seconds at boundary " .. second)
  if second >= 600 then
    local expected = second <= 700 and 1 or 0
    assert((rates.recipes.smelting and rates.recipes.smelting.cps or 0) == expected, "recipe cutoff " .. second)
    assert((rates.nodes["item/iron-plate"] and rates.nodes["item/iron-plate"].prod or 0) == expected, "node cutoff " .. second)
    local live, live_secs = Sm.rates(1, 0)
    assert(live_secs == 60 and (live.recipes.smelting and live.recipes.smelting.cps or 0) == 0, "Live window changed")
    local minute, minute_secs = Sm.rates(1, 60)
    assert(minute_secs == 60 and (minute.recipes.smelting and minute.recipes.smelting.cps or 0) == 0)
  end
end
-- Preserve a previous-version ring and prefer its coarse history during warm-up.
storage = { nbins = 60, bins = { [1] = { id = 660, rec = {}, stat = {} } }, last_bin_id = 660,
  rings = { { secs = 60, n = 60, bins = {} } } }
for minute = 1, 10 do storage.rings[1].bins[minute] = { id = minute, secs = 60,
  rec = { [1] = { smelting = { c = 60, p = 0 } } }, stat = {} } end
game.tick = 660 * 60
Sm.init()
assert(storage.bins[660 % storage.nbins + 1].id == 660 and storage.last_bin_id == 660, "upgrade lost fine history")
local rates, secs = Sm.rates(1, 600)
assert(secs > 500 and rates.recipes.smelting.cps == 1, "upgrade lost coarse history")
local rings = storage.rings
settings.global["ssk-window-seconds"].value = 30
Sm.init()
assert(storage.rings == rings and storage.bins[660 % storage.nbins + 1], "Live setting discarded history")

-- Complete all nested rollups at the same boundary without a long simulation.
local material = "item/iron-plate"
local function sample(id, seconds, rate)
  return { id=id, secs=seconds, rec={}, stat={ [1]={ [material]={ i=seconds*rate, o=0 } } } }
end
local function put(ring, id, seconds, rate)
  ring.bins[id % ring.n + 1] = sample(id, seconds, rate)
end
storage = {}
game.tick = 72000 * 60
Sm.init()
local second = 71999
storage.bins[second % storage.nbins + 1] = sample(second, 1, 1)
storage.last_bin_id = second
local child = 1
for i=2,#storage.rings do
  local ring = storage.rings[i]
  put(ring, math.floor(second / ring.secs), ring.secs - child, 1)
  child = ring.secs
end
Sm.on_stats(game.tick)
for i=2,#storage.rings do
  local ring = storage.rings[i]
  local id = math.floor(second / ring.secs)
  local bin = ring.bins[id % ring.n + 1]
  assert(bin.secs == ring.secs and bin.stat[1][material].i == ring.secs, "a completed rollup lost or doubled samples")
end

-- Long windows must include the latest fine samples and each non-overlapping
-- retained tier, even when the longest ring has barely begun filling.
storage = {}
local now = 400 * 3600 + 61
game.tick = now * 60
Sm.init()
rings = storage.rings
put(rings[5], 0, 72000, 2)
put(rings[4], 50, 18000, 3)
put(rings[3], 399, 3600, 4)
for id=now-60,now-1 do storage.bins[id % storage.nbins + 1] = sample(id, 1, 5) end
for _, window in ipairs({ {180000,3660,14700}, {900000,21660,68700}, {3600000,93660,212700} }) do
  local period, seconds, units = window[1], window[2], window[3]
  local model, covered = Sm.rates(1, period)
  assert(covered == seconds and math.abs(model.nodes[material].prod * covered - units) < 1e-6)
  local history = History.build(1, period, material)
  assert(history.seconds == seconds, "History and rate totals disagree on recorded time")
end
storage, game.tick, settings.global["ssk-window-seconds"].value = saved, tick, setting
print("HISTORY TESTS OK: exact short windows, long rollups and coverage, warm-up, upgrade and period choices")
