local Sm, UI, SK = TREQ("scripts.sampler"), TREQ("scripts.ui"), TREQ("scripts.sankey_ui")
local player = game.players[1]
local old_ui = storage.ui[1]
for _, previous in ipairs({ 0, 3600, 36000 }) do
  storage.ui[1] = { period = previous }
  UI.open(player)
  local us = storage.ui[1]
  assert(us.period == (previous == 0 and 600 or previous), "upgrade default/preserve longer selection")
  assert(SK.focus_state(us).period == us.period and SK.balance_state(us).period == us.period, "all views share period")
  UI.on_selection({ player_index = 1, element = { tags = { ssk_ui = "period" }, selected_index = 1 } })
  UI.open(player)
  assert(us.period == 0, "manual Live choice must persist")
end
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
storage, game.tick, settings.global["ssk-window-seconds"].value = saved, tick, setting
print("HISTORY TESTS OK: exact rolling 600 seconds, burst retention/expiry, warm-up, upgrade, defaults and manual choices")
