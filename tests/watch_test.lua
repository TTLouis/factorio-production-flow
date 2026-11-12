local Watch, UI, SK = TREQ("scripts.watch"), TREQ("scripts.ui"), TREQ("scripts.sankey_ui")
local Groups = TREQ("scripts.groups")
local player = game.players[1]
local key, fluid = "item/iron-plate", "fluid/water"
local group = Groups.of(player.index, key)
local us = { sidx = 1, period = 60, bal_favs = { items = { [fluid] = true }, groups = { [group] = true } } }
local original_tick = game.tick

local frame = Watch.open(player, us, 1, key)
local body = frame.ssk_watch_body
local fields = body.ssk_watch_fields
fields.ssk_watch_made.text = "0"
assert(not Watch.apply(player, us, 1, key) and body.ssk_watch_error.visible, "zero threshold must show an error")
fields.ssk_watch_made.text = "2.5"
fields.ssk_watch_empty.text = "4"
assert(Watch.apply(player, us, 1, key), "watch settings must accept decimals")
assert(not player.gui.screen.ssk_watch and Watch.get(us, 1, key).made == 2.5, "watch should save and close")

local function evaluate(tick, seconds, stock, known, made)
  game.tick = tick
  local nodes = made and { [key] = { prod = made, cons = 0 } } or {}
  local warnings = Watch.evaluate(player, us, seconds, stock, known, nodes)
  return warnings and warnings[key]
end

assert(not evaluate(1000, 59), "warmup must suppress warnings")
assert(not evaluate(1300, 60) and not evaluate(1300, 60), "manual refresh must not duplicate observations")
assert(not evaluate(2500, 60), "a gap must restart a pending breach")
us.period = 120
assert(not evaluate(2800, 120), "changing period must restart a pending breach")
local warning = evaluate(3100, 120)
assert(warning and LOC(warning):find("Made 0") and not LOC(warning):find("Chest stock"), "idle material has measured zero Made but unknown stock")
assert(not evaluate(3400, 119), "unready data must hide a latched warning")
assert(evaluate(3700, 120), "temporary unknown data must preserve the latch")
assert(not evaluate(4000, 120, nil, false, 2.5), "a measured recovery clears the latch")
assert(not evaluate(4300, 120), "a new breach must wait for its second observation")

assert(not evaluate(4600, 120, {}, true, 3), "known zero stock starts a breach")
warning = evaluate(4900, 120, {}, true, 3)
assert(warning and LOC(warning):find("empty in 0 min"), "completed stock sample can measure zero")
assert(not evaluate(5200, 120, { [key] = { count = 200 } }, true, 3), "stock without a drain recovers")
assert(not evaluate(5500, 120, { [key] = { count = 100, per_min = -50 } }, true, 3), "a measured drain starts a breach")
warning = evaluate(5800, 120, { [key] = { count = 100, per_min = -50 } }, true, 3)
assert(warning and LOC(warning):find("empty in 2 min"), "reuse the Balance stock drain estimate")
us.sidx = 2
assert(not evaluate(6100, 120, {}, true, 3), "watches apply only to their configured surface")
us.sidx = 1
us.bal_favs.groups[group] = nil
Watch.pause_unstarred(player.index, us)
assert(not evaluate(6400, 120, {}, true, 3) and Watch.get(us, 1, key), "unstarring a group pauses its saved watches")
us.bal_favs.items[key] = true
assert(Watch.open(player, us, 1, key) and Watch.apply(player, us, 1, key, true), "Remove clears the watch")
assert(not Watch.get(us, 1, key), "removed watch must be absent")
frame = Watch.open(player, us, 1, fluid)
assert(not frame.ssk_watch_body.ssk_watch_fields.ssk_watch_empty.enabled, "fluids must disable the stock threshold")
Watch.close(player)
game.tick = original_tick

local state = storage.ui[player.index]
state.tab_id, state.bal_mode, state.bal_filter = "balance", "flow", "all"
us.bal_favs.items[key], us.bal_favs.groups[group] = nil, true
state.bal_favs = us.bal_favs
SK.balance_state(state).focus = key
UI.open(player)
local main = player.gui.screen.ssk_main
local function find(element, action)
  if element.tags.ssk_ui == action then return element end
  for _, child in ipairs(element.children) do
    local result = find(child, action)
    if result then return result end
  end
end
local function click(action)
  return UI.on_click { element = assert(find(main, action)), player_index = player.index }
end
click("watch")
frame = player.gui.screen.ssk_watch
assert(frame and frame.tags.key == key and player.opened == main, "watch opens over the main window")
assert(UI.on_click { element = { tags = { ssk_ui = "bal_fav_group", gid = group } }, player_index = player.index })
assert(not player.gui.screen.ssk_watch and not find(main, "watch").enabled, "unstarring the only eligible group closes the dialog")
assert(UI.on_click { element = { tags = { ssk_ui = "bal_fav_group", gid = group } }, player_index = player.index })
assert(find(main, "watch").enabled)
click("watch")
frame = player.gui.screen.ssk_watch
UI.refresh(player, true)
assert(player.gui.screen.ssk_watch == frame, "automatic refresh must retain the watch dialog")
UI.on_closed { element = main, player_index = player.index }
assert(not player.gui.screen.ssk_watch and player.gui.screen.ssk_main == main, "Esc closes watch before the main window")
click("watch")
UI.on_click { element = { tags = { ssk_ui = "focus_item", key = fluid } }, player_index = player.index }
assert(not player.gui.screen.ssk_watch, "material change closes the stale watch")

state.tab_id = "focus"
local focus = SK.focus_state(state)
focus.focus = key
UI.open(player)
main = player.gui.screen.ssk_main
assert(find(main, "machine_status").enabled and click("machine_status"))
local machines = assert(player.gui.screen.ssk_machine_status)
assert(machines.tags.material == key and machines.tags.surface == state.sidx)
assert(UI.on_elem_changed { element = { tags = { ssk_sk = "f_item" }, elem_value = "copper-plate" },
  player_index = player.index })
assert(not machines.valid and focus.focus == "item/copper-plate")
print("WATCH OK: individual and group eligibility, thresholds, recovery, and inspector lifecycle")
