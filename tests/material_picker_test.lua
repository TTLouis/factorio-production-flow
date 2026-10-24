local UI, SK = TREQ("scripts.ui"), TREQ("scripts.sankey_ui")
local player, us = game.players[1], storage.ui[1]
local function find(e, predicate)
  if predicate(e) then return e end
  for _, child in ipairs(e.children) do local hit = find(child, predicate); if hit then return hit end end
end
local function action(root, name) return find(root, function(e) return e.tags.ssk_sk == name end) end
local function results(dialog) return find(dialog, function(e) return e.name == "ssk_results" end) end
local originals = { item = {}, fluid = {} }
local fixture_names = { "water", "wood", "hidden-material", "parameter-material", "signal-material", "misc-material" }
for _, kind in ipairs({ "item", "fluid" }) do
  for _, name in ipairs(fixture_names) do
    originals[kind][name] = rawget(prototypes[kind], name)
    rawset(prototypes[kind], name, { name = name, localised_name = name, hidden = name == "hidden-material", parameter = name == "parameter-material",
      group = { name = name == "signal-material" and "signals" or name == "misc-material" and "other"
        or kind == "fluid" and "fluids" or "materials", order = kind, localised_name = kind },
      subgroup = { name = kind .. "-materials", order = "a" }, order = name })
  end
end
local original_locale, original_translate = player.locale, player.request_translations
local requests, next_id = {}, 0
player.locale = "test"
player.request_translations = function(strings)
  local ids = {}
  for i, s in ipairs(strings) do next_id = next_id + 1; ids[i] = next_id; requests[next_id] = s end
  return ids
end
for _, tab in ipairs({ "balance", "focus" }) do
  us.tab_id, us.bal_filter = tab, "all"
  local fx = tab == "balance" and SK.balance_state(us) or SK.focus_state(us)
  fx.focus, fx.focus_hist, fx.focus_forward, fx.live, fx.settings_open = "item/iron-plate", {}, {}, false, true
  UI.open(player)
  local main = player.gui.screen.ssk_main
  local list = find(main, function(e) return e.name == "ssk_bal_root" end)
  local bar = find(main, function(e) return e.name == "ssk_bar" end)
  local chart = bar.parent
  assert(not fx.settings_open and not chart.ssk_settings, "chart settings should start closed when the window opens")
  assert(chart.spec.style == "inside_deep_frame" and chart.ssk_sp.spec.style == "naked_scroll_pane", "toolbar and chart must share one vanilla inset")
  assert(action(bar.children[1], "zoom_in") and action(bar.children[1], "show_labels"), "zoom and labels must remain in the front row")
  local gear = action(main, "chart_settings")
  assert(gear.type == "sprite-button" and gear.sprite == "ssk-gear" and not gear.toggled, "Chart settings must be a vanilla gear toggle")
  local height, chart_height = SK.toolbar_height(fx), chart.ssk_sp.style.height
  UI.on_click { element = gear, player_index = 1 }
  local panel = chart.ssk_settings
  assert(fx.settings_open and panel and action(bar, "chart_settings").toggled, "Chart settings did not open")
  assert(SK.toolbar_height(fx) == height and chart.ssk_sp.style.height == chart_height, "Chart settings must not move the chart")
  assert(panel.style.top_margin + panel.style.height + panel.style.bottom_margin == 0, "Chart settings must take no layout height")
  for _, name in ipairs({ "f_heights", "balance_colors", "f_lines", "live", "reflow", "unpin" }) do
    assert(action(panel, name), "Chart settings lack " .. name)
  end
  assert(action(panel, tab == "balance" and "inputs_more" or "f_steps"), "Chart settings lack the step control")
  if list then assert(list.valid, "Chart settings reset Balance list") end
  UI.on_closed { element = main, player_index = 1 }
  assert(main.valid and not fx.settings_open and not chart.ssk_settings and player.opened == main,
    "Esc must close chart settings before the window")
  UI.on_click { element = action(main, "chart_settings"), player_index = 1 }
  UI.on_click { element = action(chart.ssk_settings, "chart_settings"), player_index = 1 }
  assert(not fx.settings_open and not chart.ssk_settings, "the panel close button did not close chart settings")
  local open = find(main, function(e) return e.tags.ssk_picker == "open" end)
  assert(open and not find(main, function(e) return e.type == "choose-elem-button" end), "split selectors remain")
  assert(UI.on_click { element = open, player_index = 1 })
  local dialog = player.gui.screen.ssk_material_picker
  assert(player.opened == main, "picker must retain the native main-window ownership")
  assert(results(dialog).column_count == 10, "the material grid must have ten columns like the base game selector")
  assert(results(dialog).tags.total == 4 and #results(dialog).tags.keys == 2, "catalog must include items and fluids, excluding hidden materials")
  UI.on_click { element = find(dialog, function(e) return e.tags.ssk_picker == "group" and e.tags.group == "fluids" end), player_index = 1 }
  assert(#results(dialog).tags.keys == 2, "category filter must restrict the visible slots")
  assert(not find(dialog, function(e) return e.tags.ssk_picker == "group"
    and (e.tags.group == "other" or e.tags.group == "signals") end), "signal/miscellaneous categories must be absent")
  for _, query in ipairs({ "parameter", "signal-material", "misc-material" }) do
    dialog.ssk_title.ssk_query.text = query
    UI.on_text_changed { element = dialog.ssk_title.ssk_query, player_index = 1 }
    assert(#results(dialog).tags.keys == 0, "excluded material leaked through search: " .. query)
  end
  UI.refresh(player, true)
  assert(dialog.valid and player.gui.screen.ssk_material_picker == dialog, "live update replaced picker")
  for id, s in pairs(requests) do
    UI.on_string_translated { player_index = 1, id = id, translated = true, result = s == "wood" and "Bois" or s }
  end
  dialog.ssk_title.ssk_query.text = "bois"
  assert(UI.on_text_changed { element = dialog.ssk_title.ssk_query, player_index = 1 })
  assert(#results(dialog).tags.keys == 2, "translated-name search failed")
  dialog.ssk_title.ssk_query.text = "does not exist"
  UI.on_text_changed { element = dialog.ssk_title.ssk_query, player_index = 1 }
  assert(#results(dialog).tags.keys == 0, "no-match state failed")
  local search = find(dialog, function(e) return e.tags.ssk_picker == "search" end)
  UI.on_click { element = search, player_index = 1 }
  assert(dialog.ssk_title.ssk_query.visible == false and dialog.ssk_title.ssk_query.text == ""
    and #results(dialog).tags.keys > 0, "hiding the search field must clear the search")
  UI.on_click { element = search, player_index = 1 }
  assert(dialog.ssk_title.ssk_query.visible, "the search button must show the field again")
  dialog.ssk_title.ssk_query.text = "water"
  UI.on_text_changed { element = dialog.ssk_title.ssk_query, player_index = 1 }
  assert(#results(dialog).tags.keys == 2, "item/fluid names must coexist")
  local chosen = find(dialog, function(e) return e.tags.ssk_picker == "pick" and e.tags.key == "fluid/water" end)
  assert(chosen.type == "sprite-button" and not find(dialog, function(e) return e.type == "list-box" end), "materials must use an icon grid")
  assert(UI.on_click { element = chosen, player_index = 1 })
  assert(fx.focus == "fluid/water" and fx.live == false and not dialog.valid, "typed selection or paused chart failed")
  assert(player.gui.screen.ssk_main == main, "picker selection reopened window")
  if list then assert(find(main, function(e) return e.name == "ssk_bal_root" end) == list, "picker reset Balance list") end
  if tab == "balance" then
    assert(not action(main, "f_history") and not action(main, "f_back") and not action(main, "f_clear_history"),
      "Balance chooses from its list and must not show Focus history")
    fx.focus, fx.focus_hist, fx.focus_forward = "item/iron-plate", {}, {}
  else
  local history = action(main, "f_history")
  history.selected_index = 2
  UI.on_selection { element = history, player_index = 1 }
  assert(fx.focus == "item/iron-plate", "viewed history selection failed")
  UI.on_click { element = action(main, "f_forward"), player_index = 1 }
  assert(fx.focus == "fluid/water", "Forward lost the viewed fluid")
  UI.on_click { element = action(main, "f_trail"), player_index = 1 }
  assert(fx.focus == "item/iron-plate" and #fx.focus_forward == 1, "trail must retain the forward path")
  local bins, focus = storage.bins, fx.focus
  UI.on_click { element = action(main, "f_clear_history"), player_index = 1 }
  assert(#fx.focus_hist == 0 and #fx.focus_forward == 0 and fx.focus == focus and storage.bins == bins, "clear history changed current material/production data")
  assert(not action(main, "f_clear_history").enabled, "empty history clear must be disabled")
  assert(not action(main, "f_history").enabled and not action(main, "f_back").enabled
    and not action(main, "f_forward").enabled, "cleared history still navigates")
  end
  local focus = fx.focus
  SK.select_focus(fx, "fluid/water"); SK.select_focus(fx, "item/wood")
  assert(SK.step_history(fx, -2) and fx.focus == focus and #fx.focus_forward == 2, "multi-step trail failed")
  assert(SK.step_history(fx, 2) and fx.focus == "item/wood", "multi-step forward failed")
  SK.step_history(fx, -1); SK.select_focus(fx, "item/water")
  assert(#fx.focus_forward == 0, "a new branch must discard the abandoned forward path")
  for i = 1, 30 do SK.select_focus(fx, i % 2 == 0 and "item/wood" or "fluid/water") end
  assert(#fx.focus_hist == 6, "view history must keep only the last six materials")
  UI.on_click { element = find(main, function(e) return e.tags.ssk_picker == "open" end), player_index = 1 }
  dialog = player.gui.screen.ssk_material_picker
  assert(UI.on_closed { element = main, player_index = 1 } and player.opened == main and not dialog.valid
    and main.valid, "Escape must close the picker before the main UI")
end
-- Many modded item groups: tabs wrap six per row, then the tab area scrolls and
-- the ten-column grid keeps its height.
local extra = {}
for i = 1, 30 do
  local name = string.format("modded-material-%02d", i)
  extra[#extra + 1] = name
  rawset(prototypes.item, name, { name = name, localised_name = name, order = name,
    group = { name = "modded-group-" .. i, order = string.format("m%02d", i), localised_name = name },
    subgroup = { name = "modded-sub-" .. i, order = "a" } })
end
local MaterialPickerTest = TREQ("scripts.material_picker")
MaterialPickerTest.open(player, "focus", "item/wood")
local dialog = player.gui.screen.ssk_material_picker
local inner = dialog.ssk_material_inner
local tab_count = #inner.ssk_group_scroll.ssk_groups.children
assert(tab_count >= 31 and inner.ssk_group_scroll.ssk_groups.column_count == 6, "every modded group needs a tab, six per row")
assert(inner.ssk_group_scroll.style.height == 4 * 68 and inner.ssk_group_scroll.style.width == 10 * 40 + 24,
  "category tabs must fit the grid and native side margins")
assert(inner.ssk_slot_frame.ssk_slot_scroll.vertical_scroll_policy == "auto",
  "material scrollbars must only occupy space while needed")
assert(results(dialog).column_count == 10 and inner.ssk_slot_frame.ssk_slot_scroll.style.height >= 4 * 40,
  "the grid must stay ten wide and keep at least four rows")
assert(inner.ssk_slot_frame.style.width == 424 and inner.ssk_slot_frame.style.left_padding == 12
  and inner.ssk_slot_frame.style.right_padding == 12, "short categories need both native side margins")
MaterialPickerTest.close(player)
for i = 1, 130 do
  local name = "dense-material-" .. i
  extra[#extra + 1] = name
  rawset(prototypes.item, name, { name = name, localised_name = name, order = name,
    group = prototypes.item.wood.group, subgroup = prototypes.item.wood.subgroup })
end
MaterialPickerTest.open(player, "focus", "item/wood")
inner = player.gui.screen.ssk_material_picker.ssk_material_inner
assert(inner.ssk_slot_frame.style.width == 424 and inner.ssk_group_scroll.style.width == 424
  and inner.ssk_slot_frame.style.left_padding == 12 and inner.ssk_slot_frame.style.right_padding == 0,
  "the scrollbar must replace the right margin without widening the selector")
MaterialPickerTest.close(player)
MaterialPickerTest.open(player, "focus", "item/wood")
assert(player.gui.screen.ssk_material_picker.ssk_material_inner.ssk_slot_frame.ssk_slot_scroll.style.height <= 12 * 40,
  "a tall screen gives the grid up to twelve rows")
MaterialPickerTest.close(player)
for _, name in ipairs(extra) do rawset(prototypes.item, name, nil) end
for kind, names in pairs(originals) do
  for _, name in ipairs(fixture_names) do rawset(prototypes[kind], name, names[name]) end
end
player.locale, player.request_translations = original_locale, original_translate
print("MATERIAL PICKER OK: combined catalog, hidden filtering, translated search, live stability, history and clear")
