-- Runs with mock2's real UI and registered lifecycle handlers.
return function(handlers)
  local UI = TREQ("scripts.ui")
  local Transfers = TREQ("scripts.transfers")
  local player, us = game.players[1], storage.ui[1]
  local mods, events = script.active_mods, defines.events
  local selected, saved_ledger, options = us.tab_id, storage.transfers, us.transfers
  local record = {tick=game.tick-60}
  local ledger = {pending={}, pending_count=0, endpoints={}, serial=0,
    history={record}, first=1, count=1, dropped={}, recording_start=game.tick-120}
  storage.transfers = ledger
  local function pane() return player.gui.screen.ssk_main.ssk_inner.ssk_tabs end
  local function check(expected)
    local tabs = pane()
    assert(#tabs.children == #expected * 2, "Wrong number of visible tabs")
    for i, id in ipairs(expected) do
      assert(tabs.tags.ssk_tab_ids[i] == id and tabs["content_" .. id], "Wrong tab ID mapping")
      tabs.selected_tab_index = i
      assert(UI.on_tab_changed{element=tabs, player_index=player.index})
      assert(us.tab_id == id, "Tab event selected the wrong view")
      UI.close(player)
      UI.open(player)
      tabs = pane()
      assert(us.tab_id == id and tabs.selected_tab_index == i, "Reopening lost the stable tab ID")
    end
  end
  local base = {"balance", "focus", "sankey"}
  local space = {"balance", "focus", "sankey", "transfers"}
  UI.open(player)
  check(space)
  assert(Transfers.available(), "Space Age fixture must have cargo events")
  assert(storage.transfers == ledger, "Visibility changed cargo history")

  -- All event names still exist in base; DLC presence is a separate requirement.
  script.active_mods = {base=mods.base}
  us.tab_id = "transfers"
  handlers.cc()
  assert(us.tab_id == "balance" and pane().selected_tab_index == 1 and not pane().content_transfers)
  assert(player.gui.screen.ssk_main.ssk_window_bar.ssk_surface_picker.visible)
  check(base)

  script.active_mods = mods
  for _, missing in ipairs({"on_cargo_pod_finished_ascending", "on_cargo_pod_finished_descending", "on_cargo_pod_delivered_cargo"}) do
    defines.events = {
      on_cargo_pod_finished_ascending=1, on_cargo_pod_finished_descending=2, on_cargo_pod_delivered_cargo=3,
    }
    defines.events[missing] = nil
    us.tab_id = "transfers"
    UI.open(player)
    assert(not Transfers.available() and us.tab_id == "balance" and not pane().content_transfers, missing)
    check(base)
  end
  defines.events = events
  -- Re-enabling restores the tab, without switching an existing Focus selection.
  us.tab_id = "focus"
  handlers.cc()
  assert(us.tab_id == "focus" and pane().selected_tab_index == 2 and pane().content_transfers)

  -- A disconnected player's saved GUI is rebuilt when they join after a config change.
  us.tab_id = "transfers"
  UI.open(player)
  script.active_mods = {base=mods.base}
  local connected = game.connected_players
  game.connected_players = {}
  handlers.cc()
  game.connected_players = connected
  handlers.on_player_joined_game{player_index=player.index}
  assert(us.tab_id == "balance" and not pane().content_transfers)
  script.active_mods = mods
  UI.open(player)
  check(space)
  handlers.on_player_joined_game{player_index=player.index}
  assert(us.tab_id == "transfers" and pane().selected_tab_index == 4)
  assert(storage.transfers == ledger and ledger.count == 1 and ledger.history[1] == record
    and us.transfers == options, "Tab visibility discarded transfer history or settings")
  storage.transfers = saved_ledger
  us.tab_id = selected
  UI.open(player)
  print("TAB VISIBILITY PASS: base, Space Age, each missing cargo event, stable IDs, reopening, configuration and joining")
end
