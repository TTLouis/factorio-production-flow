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
    start_tick = 0, end_tick = 6000, seconds = 50, bucket_seconds = 15,
    points = {
      { start_tick = 3000, end_tick = 3900, seconds = 15, made = 10, used = 8, net = 2, uses = uses },
      { start_tick = 3900, end_tick = 4800, seconds = 15, made = 2, used = 4, net = -2,
        uses = { ["item/steel-plate"] = 3, other = 1 } },
      { start_tick = 4800, end_tick = 5100, seconds = 5, made = 10, used = 8, net = 2, uses = uses, partial = true },
      { start_tick = 5100, end_tick = 6000, seconds = 15, made = 2, used = 8, net = -6, uses = uses },
    },
    usage_keys = { "item/steel-plate", History.OTHER },
    stock_supported = not fluid,
    stock = not fluid and {
      { tick = 3000, count = 30, measured = true },
      { tick = 3900, count = 20, measured = false, joined = true },
      { tick = 4800, count = 17, measured = true, joined = true },
      { tick = 5700, count = 15, measured = true },
    } or {},
  }
end

UI.open(player)
local root = player.gui.screen.ssk_main
local table_root = named(root, "ssk_bal_root")
local items = named(table_root, "ssk_bal_items")
local inspector_tabs = named(root, "ssk_balance_inspector_tabs")
assert(inspector_tabs.type == "tabbed-pane")
local function select_inspector(index)
  inspector_tabs.selected_tab_index = index
  assert(UI.on_tab_changed(event(inspector_tabs)))
end
select_inspector(2)
assert(us.bal_mode == "history" and request[1] == us.sidx and request[2] == 600 and request[3] == fx.focus)
assert(named(root, "ssk_bal_root") == table_root and named(root, "ssk_bal_items") == items)
local controls = named(root, "ssk_history_controls")
local camera, stock_camera = named(root, "ssk_history_camera"), named(root, "ssk_history_stock_camera")
local net_camera = named(root, "ssk_history_net_camera")
local history_panel = inspector_tabs.ssk_history_panel
local history_scroll = history_panel.ssk_history_scroll
assert(history_panel.style.height == inspector_tabs.ssk_balance_flow_panel.style.height,
  "both inspector tabs must have the same panel height")
assert(history_scroll.style.width + 2 * history_panel.style.padding == history_panel.style.width
  and history_scroll.style.height + history_panel.ssk_history_toolbar.style.height + 2 * history_panel.style.padding
    == history_panel.style.height, "History must inset its content equally on every side")
assert(camera.style.width + 2 * history_scroll.ssk_history_body.style.left_margin == history_scroll.style.width,
  "History plots must leave equal gutters on both sides")
assert(camera.style.width == stock_camera.style.width and camera.style.width == net_camera.style.width
  and camera.position[1] == stock_camera.position[1] and camera.position[1] == net_camera.position[1],
  "rate, stock and net charts must align")
local sections = camera.parent.parent.children
assert(sections[1].name == "ssk_history_rate_title" and sections[#sections].name == "ssk_history_stock_note"
  and camera.position[2] < net_camera.position[2] and net_camera.position[2] < stock_camera.position[2],
  "History must show Rate history, Net rate, then Chest stock")
local compact_fraction = (stock_camera.style.height + net_camera.style.height + 84) / us.bal_height
assert(math.abs(compact_fraction - 1 / 3) < 0.02, "stock and net should share a third of the inspector")
assert(named(root, "ssk_history_products").column_count == 4, "consumption entries must fit on one row")
local rate_targets = camera.parent.ssk_history_tooltips.children
local net_targets = net_camera.parent.ssk_history_tooltips.children
local stock_targets = stock_camera.parent.ssk_history_tooltips.children
assert(#rate_targets == 3 and #net_targets == 3, "partial or unrecorded rates have no tooltip")
assert(rate_targets[1].tooltip == "50s ago to 35s ago\nMade  10 items/s\nUsed  8 items/s\nNet  2 items/s")
assert(net_targets[2].tooltip == rate_targets[2].tooltip and net_targets[2].tooltip:find("Net  -2 items/s", 1, true))
assert(stock_targets[1].tooltip == "50s ago\nMeasured stock  30 items"
  and stock_targets[2].tooltip == "35s ago\nEstimated stock  20 items")
local polygons, rising_or_falling = 0, 0
local stock = {}
for _, o in ipairs(objects()) do
  if o.k == "poly" then polygons = polygons + 1 end
  if o.k == "line" and o.a.gap_length > 0 then
    local dx = o.a.to[1] - o.a.from[1]
    assert(dx > 0, "rate traces must not use vertical steps")
    if o.a.to[2] ~= o.a.from[2] then rising_or_falling = rising_or_falling + 1 end
  end
  if o.k == "rect" and (o.a.color[1] == 181 / 255 or o.a.color[1] == 67 / 255) then stock[#stock + 1] = o.a end
end
assert(polygons == 4 and rising_or_falling >= 4, "Used needs separate filled paths across gaps and smoothed transitions")
assert(#stock == 4 and stock[1].right_bottom[1] == stock[2].left_top[1]
  and stock[2].right_bottom[1] == stock[3].left_top[1]
  and stock[3].right_bottom[1] < stock[4].left_top[1], "stock bars share edges only where a rate estimate is available")
assert(named(root, "ssk_history_use_1").rate.caption == "5.1/s" and named(root, "ssk_history_use_2").rate.caption == "1.7/s")
local old = objects()
UI.refresh(player, true)
assert(named(root, "ssk_history_controls") == controls and named(root, "ssk_history_camera") == camera)
assert(camera.parent.ssk_history_tooltips.children[1] == rate_targets[1], "refresh must retain hover targets")
assert(named(root, "ssk_bal_items") == items and not old[1].valid, "replace render objects while retaining GUI and scroll state")

local all_height = camera.style.height
assert(UI.on_checked(event(named(root, "ssk_history_net"))))
assert(us.bal_history_view == "net" and named(root, "ssk_history_net").state and not named(root, "ssk_history_all").state)
assert(not named(root, "ssk_history_uses").visible and named(root, "ssk_history_controls") == controls)
assert(camera.style.height == all_height + 46 and rate_targets[1].style.height == camera.style.height - 33,
  "hiding the usage legend should free room for the rate chart and resize its hover targets")
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
select_inspector(1)
assert(us.bal_mode == "flow" and named(inspector_tabs, "ssk_balance_flow_panel").ssk_sp)
assert(fx.focus == "fluid/water" and named(root, "ssk_bal_items") == items)
select_inspector(2)
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
