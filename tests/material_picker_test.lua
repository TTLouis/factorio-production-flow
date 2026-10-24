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
  fx.focus, fx.focus_hist, fx.focus_forward, fx.live, fx.options_open = "item/iron-plate", {}, {}, false, false
  UI.open(player)
  local main = player.gui.screen.ssk_main
  local list = find(main, function(e) return e.name == "ssk_bal_root" end)
  local bar = find(main, function(e) return e.name == "ssk_bar" end)
  assert(not bar.ssk_options.visible, "less-used controls should start collapsed")
  assert(action(bar.children[1], "zoom_in") and action(bar.children[1], "show_labels"), "zoom and labels must remain in the front row")
  assert(action(main, "f_options").type == "sprite-button" and not action(main, "f_options").toggled,
    "Options must be a vanilla icon toggle")
  local height = SK.toolbar_height(fx)
  UI.on_click { element = action(main, "f_options"), player_index = 1 }
  assert(fx.options_open and bar.ssk_options.visible and SK.toolbar_height(fx) > height, "Options did not open")
  if list then assert(list.valid, "Options reset Balance list") end
  UI.on_click { element = action(main, "f_options"), player_index = 1 }
  assert(not fx.options_open and not bar.ssk_options.visible and SK.toolbar_height(fx) == height, "Options did not release chart space")
  local open = find(main, function(e) return e.tags.ssk_picker == "open" end)
  assert(open and not find(main, function(e) return e.type == "choose-elem-button" end), "split selectors remain")
  assert(UI.on_click { element = open, player_index = 1 })
  local dialog = player.gui.screen.ssk_material_picker
  assert(player.opened == main, "picker must retain the native main-window ownership")
  assert(results(dialog).tags.total == 4 and #results(dialog).tags.keys == 2, "catalog must include items and fluids, excluding hidden materials")
  UI.on_click { element = find(dialog, function(e) return e.tags.ssk_picker == "group" and e.tags.group == "fluids" end), player_index = 1 }
  assert(#results(dialog).tags.keys == 2, "category filter must restrict the visible slots")
  assert(not find(dialog, function(e) return e.tags.ssk_picker == "group"
    and (e.tags.group == "other" or e.tags.group == "signals") end), "signal/miscellaneous categories must be absent")
  for _, query in ipairs({ "parameter", "signal-material", "misc-material" }) do
    dialog.ssk_query.text = query
    UI.on_text_changed { element = dialog.ssk_query, player_index = 1 }
    assert(#results(dialog).tags.keys == 0, "excluded material leaked through search: " .. query)
  end
  UI.refresh(player, true)
  assert(dialog.valid and player.gui.screen.ssk_material_picker == dialog, "live update replaced picker")
  for id, s in pairs(requests) do
    UI.on_string_translated { player_index = 1, id = id, translated = true, result = s == "wood" and "Bois" or s }
  end
  dialog.ssk_query.text = "bois"
  assert(UI.on_text_changed { element = dialog.ssk_query, player_index = 1 })
  assert(#results(dialog).tags.keys == 2, "translated-name search failed")
  dialog.ssk_query.text = "does not exist"
  UI.on_text_changed { element = dialog.ssk_query, player_index = 1 }
  assert(#results(dialog).tags.keys == 0, "no-match state failed")
  dialog.ssk_query.text = "water"
  UI.on_text_changed { element = dialog.ssk_query, player_index = 1 }
  assert(#results(dialog).tags.keys == 2, "item/fluid names must coexist")
  local chosen = find(dialog, function(e) return e.tags.ssk_picker == "pick" and e.tags.key == "fluid/water" end)
  assert(chosen.type == "sprite-button" and not find(dialog, function(e) return e.type == "list-box" end), "materials must use an icon grid")
  assert(UI.on_click { element = chosen, player_index = 1 })
  assert(fx.focus == "fluid/water" and fx.live == false and not dialog.valid, "typed selection or paused chart failed")
  assert(player.gui.screen.ssk_main == main, "picker selection reopened window")
  if list then assert(find(main, function(e) return e.name == "ssk_bal_root" end) == list, "picker reset Balance list") end
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
  SK.select_focus(fx, "fluid/water"); SK.select_focus(fx, "item/wood")
  assert(SK.step_history(fx, -2) and fx.focus == focus and #fx.focus_forward == 2, "multi-step trail failed")
  assert(SK.step_history(fx, 2) and fx.focus == "item/wood", "multi-step forward failed")
  SK.step_history(fx, -1); SK.select_focus(fx, "item/water")
  assert(#fx.focus_forward == 0, "a new branch must discard the abandoned forward path")
  for i = 1, 30 do SK.select_focus(fx, i % 2 == 0 and "item/wood" or "fluid/water") end
  assert(#fx.focus_hist == 20, "view history must remain bounded")
  UI.on_click { element = find(main, function(e) return e.tags.ssk_picker == "open" end), player_index = 1 }
  dialog = player.gui.screen.ssk_material_picker
  assert(UI.on_closed { element = main, player_index = 1 } and player.opened == main and not dialog.valid
    and main.valid, "Escape must close the picker before the main UI")
end
for kind, names in pairs(originals) do
  for _, name in ipairs(fixture_names) do rawset(prototypes[kind], name, names[name]) end
end
player.locale, player.request_translations = original_locale, original_translate
print("MATERIAL PICKER OK: combined catalog, hidden filtering, translated search, live stability, history and clear")
