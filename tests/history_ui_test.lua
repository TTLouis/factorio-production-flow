local UI = TREQ("scripts.ui")
local SK = TREQ("scripts.sankey_ui")
local History = TREQ("scripts.history")
local player, us = game.players[1], storage.ui[1]
local saved_mode, saved_view, saved_period, saved_filter = us.bal_mode, us.bal_history_view, us.period, us.bal_filter
local previous_build = History.build
local function find(element, predicate)
  if predicate(element) then return element end
  for _, child in ipairs(element.children) do
    local hit = find(child, predicate)
    if hit then return hit end
  end
end
local function named(element, name)
  return assert(find(element, function(e) return e.name == name end), name)
end
local function event(element)
  return { element = element, player_index = player.index }
end
local function objects()
  return storage.canvas[player.index].objs
end

us.tab_id, us.bal_mode, us.bal_history_view, us.bal_filter, us.period = "balance", "flow", "all", "all", 600
local fx = SK.balance_state(us)
local saved_focus = fx.focus
fx.focus = "item/iron-plate"
local request, data_state
History.build = function(surface, period, key)
  request = { surface, period, key }
  local fluid = key:sub(1, 6) == "fluid/"
  local uses = { ["item/steel-plate"] = 6, other = 2 }
  if data_state then
    return { start_tick = 0, end_tick = 6000, seconds = data_state == "idle" and 100 or 0,
      bucket_seconds = 15, points = {}, usage_keys = {}, stock = {}, stock_supported = not fluid }
  end
  return {
    start_tick = 0, end_tick = 6000, seconds = 35, bucket_seconds = 15,
    points = {
      { start_tick = 3000, end_tick = 3900, seconds = 15, made = 10, used = 8, net = 2, uses = uses },
      { start_tick = 3900, end_tick = 4800, seconds = 5, made = 10, used = 8, net = 2, uses = uses, partial = true },
      { start_tick = 4800, end_tick = 5700, seconds = 15, made = 2, used = 8, net = -6, uses = uses },
    },
    usage_keys = { "item/steel-plate", History.OTHER },
    stock_supported = not fluid,
    stock = not fluid and {
      { tick = 3000, count = 30, measured = true },
      { tick = 3900, count = 20, measured = false },
      { tick = 5700, count = 17, measured = true },
    } or {},
  }
end

UI.open(player)
local root = player.gui.screen.ssk_main
local table_root = named(root, "ssk_bal_root")
local items = named(table_root, "ssk_bal_items")
assert(UI.on_click(event(named(root, "ssk_bal_history"))))
assert(us.bal_mode == "history" and request[1] == us.sidx and request[2] == 600 and request[3] == fx.focus)
assert(named(root, "ssk_bal_root") == table_root and named(root, "ssk_bal_items") == items)
local controls = named(root, "ssk_history_controls")
local camera, stock_camera = named(root, "ssk_history_camera"), named(root, "ssk_history_stock_camera")
assert(camera.style.width == stock_camera.style.width and camera.position[1] == stock_camera.position[1],
  "rate and stock charts must align")
local polygons, dashed = 0, 0
for _, o in ipairs(objects()) do
  if o.k == "poly" then polygons = polygons + 1 end
  if o.k == "line" and o.a.gap_length > 0 then dashed = dashed + 1 end
end
assert(polygons == 2 and dashed == 2, "Used bands and dashed total must leave a gap in unrecorded time")
assert(named(root, "ssk_history_use_1").rate.caption == "6/s" and named(root, "ssk_history_use_2").rate.caption == "2/s")
local old = objects()
UI.refresh(player, true)
assert(named(root, "ssk_history_controls") == controls and named(root, "ssk_history_camera") == camera)
assert(named(root, "ssk_bal_items") == items and not old[1].valid, "replace render objects while retaining GUI and scroll state")

assert(UI.on_checked(event(named(root, "ssk_history_net"))))
assert(us.bal_history_view == "net" and named(root, "ssk_history_net").state and not named(root, "ssk_history_all").state)
assert(not named(root, "ssk_history_uses").visible and named(root, "ssk_history_controls") == controls)
for _, o in ipairs(objects()) do
  assert(o.k ~= "poly", "Net must not draw Used product bands")
end
local material_cell = assert(find(table_root, function(e)
  return e.tags.ssk_ui == "bal_material" and e.tags.key ~= fx.focus
end))
assert(UI.on_click(event(material_cell)))
assert(fx.focus == material_cell.tags.key and request[3] == fx.focus and material_cell.valid)
assert(named(root, "ssk_history_controls") == controls and named(root, "ssk_bal_items") == items)

data_state = "warmup"
UI.refresh(player, true)
local rate_state = named(root, "ssk_history_rate_state")
assert(rate_state.visible and rate_state.caption:find("Collecting", 1, true) and not camera.parent.visible)
data_state = "idle"
UI.refresh(player, true)
assert(rate_state.visible and rate_state.caption:find("No recorded", 1, true))
data_state = nil

assert(UI.on_click(event({ tags = { ssk_ui = "focus_item", key = "fluid/water" } })))
assert(not stock_camera.parent.visible and named(root, "ssk_history_stock_state").caption:find("Fluid tanks", 1, true))
assert(UI.on_click(event(named(root, "ssk_bal_flow"))))
assert(not named(root, "ssk_history_panel").visible and named(root, "ssk_balance_flow_panel").visible)
assert(fx.focus == "fluid/water" and named(root, "ssk_bal_items") == items)
assert(UI.on_click(event(named(root, "ssk_bal_history"))))
assert(named(root, "ssk_history_controls") == controls and us.bal_history_view == "net")
old = objects()
local tabs = root.ssk_inner.ssk_tabs
tabs.selected_tab_index = 4
assert(UI.on_tab_changed(event(tabs)))
assert(us.tab_id == "transfers" and not root.ssk_window_bar.ssk_surface_picker.visible)
assert(not old[1].valid and #objects() == 0, "leaving History clears its render objects")
tabs.selected_tab_index = 1
assert(UI.on_tab_changed(event(tabs)))
assert(us.tab_id == "balance" and root.ssk_window_bar.ssk_surface_picker.visible)
assert(named(root, "ssk_bal_items") == items and named(root, "ssk_history_controls") == controls)
old = objects()
UI.close(player)
assert(not old[1].valid and #objects() == 0, "closing History clears its render objects")
History.build = previous_build
us.bal_mode, us.bal_history_view, us.period, us.bal_filter, fx.focus = saved_mode, saved_view, saved_period, saved_filter, saved_focus
UI.open(player)
print("BALANCE HISTORY UI OK: retained list, controls, aligned axes, measured and estimated rendering, and cleanup")
