local Loc = require("scripts.locale")
-- Top-left toolbar button + main window.
-- Tabs: Balance · Focus · Full Sankey · Transfers.

local mod_gui = require("mod-gui")
local Sampler = require("scripts.sampler")
local SK = require("scripts.sankey_ui")
local BalanceUI = require("scripts.balance_ui")
local Su = require("scripts.surfaces")
local Help = require("scripts.help_ui")
local MaterialPicker = require("scripts.material_picker")
local MachineStatus = require("scripts.machine_status_ui")
local Watch = require("scripts.watch")
local Canvas = require("scripts.canvas")
local HistoryUI = require("scripts.history_ui")
local TransfersUI = require("scripts.transfers_ui")
local Transfers = require("scripts.transfers")

local UI = {}
local TAB_CAPTIONS = { balance = Loc("ui-balance"), focus = Loc("ui-focus"), sankey = Loc("ui-full-sankey"), transfers = Loc("help-transfers") }
local WIN = "ssk_main"

local function visible_tabs()
  local list = { "balance", "focus", "sankey" }
  if Transfers.available() then list[#list + 1] = "transfers" end
  return list
end

local function ustate(pi)
  storage.ui = storage.ui or {}
  local s = storage.ui[pi]
  if not s then
    s = { tab_id = "balance" }
    storage.ui[pi] = s
  end
  if not s.tab_id then s.tab_id = "balance" end
  if not s.readability_defaults then
    s.view, s.tier_mode, s.renderer = "detail", "depth", "poly"
    s.lines, s.layout, s.sel = "curves", "clean", nil
    s.tier_lo, s.tier_hi = nil, nil
    for _, fx in pairs({ s.fx, s.bal_fx }) do fx.renderer = "poly" end
    s.readability_defaults = true
  end
  -- Replace the unpublished grouped default once. Later explicit grouping
  -- choices survive reopening the window and loading the save.
  if not s.plain_names_default then
    s.view, s.collapsed, s.overview_open = "detail", {}, {}
    s.layout_snapshot, s.auto_rank, s.sel = nil, nil, nil
    s.plain_names_default = true
  end
  -- Preserve established periods and map an explicit legacy Recent selection
  -- to the new shortest period. New windows still default to 10 minutes.
  if not s.period_default_10m then
    if not s.period or s.period == 0 then s.period = Sampler.DEFAULT_PERIOD end
    s.period_default_10m = true
  end
  if s.period == 0 then s.period = Sampler.PERIODS[1] end
  if s.period == nil then s.period = Sampler.DEFAULT_PERIOD end
  return s
end

---------------------------------------------------------------------------
-- toolbar button
---------------------------------------------------------------------------
function UI.ensure_button(player)
  local flow = mod_gui.get_button_flow(player)
  if flow.ssk_toggle then flow.ssk_toggle.destroy() end
  flow.add { type = "sprite-button", name = "ssk_toggle", sprite = "ssk-icon",
             style = mod_gui.button_style, tooltip = Loc("ui-production-flow") }
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
-- single-line by default; wrap = true for long free text (needs a maximal_width to wrap at)
local function label(parent, caption, style, wrap)
  local hint = style == "info_label"
  if hint then style = nil end
  local l = parent.add { type = "label", caption = caption, style = style }
  -- same small grey hint text as the Balance and chart toolbars
  if hint then
    l.style.font = "default-small"
    l.style.font_color = { 0.65, 0.65, 0.65 }
  end
  if wrap then
    l.style.single_line = false
    l.style.maximal_width = 1400
  end
  return l
end

-- one surface at a time, never combined: the chosen one, else where the player stands
local function sidx_for(player, us)
  local sf = us.surface and game.surfaces[us.surface]
  return sf and sf.index or player.surface.index
end

local function scope_caption(player, us)
  return Su.rich(game.surfaces[sidx_for(player, us)])
end

-- Surfaces with crafting activity or measured chest stock, busiest machines first.
local function surface_choices(selected)
  local n = {}
  for _, rec in pairs(storage.machines or {}) do n[rec.s] = (n[rec.s] or 0) + 1 end
  for index in pairs(Sampler.stock_surfaces()) do n[index]=n[index] or 0 end
  local chosen=selected and game.surfaces[selected]
  if chosen and chosen.valid and chosen.name~="ssk-canvas" then n[chosen.index]=n[chosen.index] or 0 end
  local list = {}
  for si, c in pairs(n) do
    local sf = game.surfaces[si]
    if sf and sf.name ~= "ssk-canvas" then list[#list + 1] = { name = sf.name, label = Su.rich(sf), n = c } end
  end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  return list
end

---------------------------------------------------------------------------
-- tab fillers
---------------------------------------------------------------------------
local fill = {}
local BALANCE_TAB_HEADER_HEIGHT = 48 -- Vanilla tab strip and its top content padding.

function fill.balance(player, c, us, only_auto, keep_balance_rows)
  local pane_height = us.canvas_h + 100
  local inspector_height = pane_height - BALANCE_TAB_HEADER_HEIGHT
  local split = c.ssk_balance_split
  local modes = split and split.ssk_balance_focus.ssk_balance_inspector_tabs
  if not modes or modes.tags.ssk_balance_material_header ~= "flush" then
    c.clear()
    split = c.add { type = "flow", name = "ssk_balance_split", direction = "horizontal" }
    split.style.horizontal_spacing = 12
    split.style.width = us.canvas_w
    local left = split.add { type = "flow", name = "ssk_balance_table", direction = "vertical" }
    local left_w = math.floor(us.canvas_w * 0.44)
    left.style.width, left.style.height = left_w, pane_height
    us.bal_width = left_w - 24
    us.bal_height = pane_height
    local right = split.add { type = "flow", name = "ssk_balance_focus", direction = "vertical" }
    local right_w = us.canvas_w - left_w - 12
    us.bal_chart_w = right_w - 8
    right.style.width, right.style.height = right_w, pane_height
    modes = right.add { type = "tabbed-pane", name = "ssk_balance_inspector_tabs",
      style = "tabbed_pane_with_no_side_padding", tags = { ssk_balance_material_header = "flush" } }
    modes.style.top_margin = 0
    modes.style.horizontally_stretchable = true
    local flow = modes.add { type = "tab", caption = Loc("help-flow"), tooltip = Loc("ui-show-the-selected-material-s-inputs-and") }
    local flow_panel = modes.add { type = "frame", name = "ssk_balance_flow_panel", style = "inside_deep_frame", direction = "vertical" }
    modes.add_tab(flow, flow_panel)
    local history = modes.add { type = "tab", caption = Loc("help-history"), tooltip = Loc("ui-show-the-selected-material-s-rates-and") }
    local history_panel = modes.add { type = "frame", name = "ssk_history_panel", style = "inside_deep_frame", direction = "vertical" }
    modes.add_tab(history, history_panel)
    for _, panel in ipairs({ flow_panel, history_panel }) do
      panel.style.width, panel.style.height = us.bal_chart_w, inspector_height
      panel.style.left_margin, panel.style.right_margin = 4, 4
      panel.style.padding = 0
    end
    modes.selected_tab_index = us.bal_mode == "history" and 2 or 1
  end
  local first = BalanceUI.fill(player, split.ssk_balance_table, us, scope_caption(player, us), only_auto or keep_balance_rows)
  local fx = SK.balance_state(us)
  if not fx.focus then fx.focus = first end
  fx.sel = fx.focus
  if us.bal_mode == "history" then
    HistoryUI.fill(player, modes.ssk_history_panel, us, fx.focus, us.bal_chart_w, inspector_height, SK.toolbar_height(fx))
    return
  end
  local flow = modes.ssk_balance_flow_panel
  fx.canvas_w, fx.canvas_h = us.bal_chart_w, inspector_height - SK.toolbar_height(fx)
  if not only_auto or fx.live ~= false then
    SK.fill(player, flow, fx, fx.canvas_w, fx.canvas_h, false, only_auto)
  end
  SK.update_balance_actions(flow, us, fx.focus, player.index)
end

function fill.transfers(player, c, us)
  us.transfers = us.transfers or {}
  local seconds = TransfersUI.render(c, player, us.period, us.transfers, us.canvas_w, us.canvas_h + 100)
  if seconds and seconds < us.period then
    local label = player.gui.screen[WIN].ssk_window_bar.ssk_history
    label.visible = true
    label.caption = Loc("ui-recorded", Sampler.duration(seconds), Sampler.duration(us.period))
    label.tooltip = Loc("ui-this-period-includes-time-before-cargo-recording")
  end
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local function content(player, id)
  local f = player.gui.screen[WIN]
  local inner = f and f.ssk_inner
  local tabs = inner and inner.ssk_tabs
  return tabs and tabs[Loc.join("content_", id)]
end

local function update_header(player,us)
  local frame=player.gui.screen[WIN]
  local bar=frame and frame.ssk_window_bar
  if not bar then return end
  local scoped = us.tab_id ~= "transfers"
  bar.ssk_surface_label.visible = scoped
  bar.ssk_surface_picker.visible = scoped
  local label=bar.ssk_history
  if not scoped then label.visible = false; return end
  local seconds=Sampler.coverage(us.sidx,us.period)
  local target=us.period
  label.visible=seconds<target
  label.caption=Loc("ui-recorded", Sampler.duration(seconds), Sampler.duration(target))
  label.tooltip=Loc("ui-the-selected-period-is-still-filling-rates")
end

-- Focus and Full Sankey draw into one vanilla panel: toolbar strip on top, chart below.
local function chart_panel(c)
  return c.ssk_chart or c.add { type = "frame", name = "ssk_chart", style = "inside_deep_frame", direction = "vertical" }
end

local function close_inspectors(player)
  Watch.close(player)
  MachineStatus.close(player)
end

-- full = rebuild the Sankey tab from scratch (otherwise its scroll position is kept)
function UI.refresh(player, only_auto, full, keep_balance_rows)
  local us = ustate(player.index)
  local id = us.tab_id
  local c = content(player, id)
  if not c then return end
  local surface = sidx_for(player, us)
  if us.sidx ~= surface then close_inspectors(player) end
  us.sidx = surface
  update_header(player,us)
  if id == "focus" then
    local fx = SK.focus_state(us)
    fx.sidx = us.sidx
    SK.defaults(fx)
    if only_auto and not fx.live then return end
    SK.fill(player, chart_panel(c), fx, us.canvas_w, math.max(100, us.canvas_h + 70 - SK.toolbar_height(fx)), full, only_auto)
    return
  end
  if id == "sankey" then
    SK.defaults(us)
    if only_auto and not us.live then return end
    SK.fill(player, chart_panel(c), us, us.canvas_w, math.max(100, us.canvas_h + 70 - SK.toolbar_height(us)), full, only_auto)
    return
  end
  fill[id](player, c, us, only_auto, keep_balance_rows)
end

-- Chart settings float over the chart; Esc, tab changes and reopening close them.
local function close_chart_settings(us)
  local open = false
  for _, s in pairs({ us, us.fx, us.bal_fx }) do
    if s.settings_open then s.settings_open, open = nil, true end
  end
  return open
end

function UI.close(player)
  close_inspectors(player)
  MaterialPicker.close(player)
  Help.close(player)
  HistoryUI.clear_hover(player.index)
  local f = player.gui.screen[WIN]
  if f then
    Canvas.clear(player.index)
    f.destroy()
  end
end

function UI.open(player)
  UI.close(player)
  local us = ustate(player.index)
  close_chart_settings(us)
  local res, sc = player.display_resolution, player.display_scale
  local W, H = UI.dimensions(res, sc)

  local f = player.gui.screen.add { type = "frame", name = WIN, direction = "vertical" }
  f.style.width, f.style.height = W, H
  us.canvas_w = W - 64
  us.canvas_h = math.max(100, H - 240)

  local tb = f.add { type = "flow", name="ssk_window_bar", direction = "horizontal" }
  tb.drag_target = f
  tb.add { type = "label", caption = Loc("ui-production-flow"), style = "frame_title", ignored_by_interaction = true }
  local drag = tb.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  local function action_button(sprite, tooltip, tag)
    tb.add { type = "sprite-button", style = "frame_action_button", sprite = sprite,
      tooltip = tooltip, tags = { ssk_ui = tag } }
  end
  tb.style.vertical_align = "center"
  tb.add { type = "label", name = "ssk_surface_label", caption = Loc("ui-surface") }
  local sitems, ssel = { Loc("ui-where-i-am", Su.rich(player.surface)) }, 1
  us.surface_names = {}
  for i, x in ipairs(surface_choices(us.surface)) do
    sitems[#sitems + 1] = x.label
    us.surface_names[i + 1] = x.name
    if us.surface == x.name then ssel = i + 1 end
  end
  local surface_picker = tb.add { type = "drop-down", name = "ssk_surface_picker", items = sitems, selected_index = ssel,
           tags = { ssk_ui = "surface" }, tooltip = Loc("ui-surface-for-balance-focus-and-full-sankey") }
  surface_picker.style.width = math.min(240, math.floor(W * 0.22))
  local pl = tb.add { type = "label", caption = Loc("ui-period") }
  pl.style.left_margin = 12
  local psel = 2
  for i, v in ipairs(Sampler.PERIODS) do if us.period == v then psel = i end end
  tb.add { type = "drop-down", items = Sampler.PERIOD_CAPTIONS, selected_index = psel, tags = { ssk_ui = "period" },
           tooltip = Loc("ui-how-far-back-rates-and-transfers-are") }
  local history=tb.add{type="label",name="ssk_history"}
  history.style.font="default-small-bold";history.style.font_color={1,0.82,0.35}
  history.style.maximal_width=190
  action_button("utility/questionmark", Loc("ui-help-controls-calculations-stock-alerts-and-chart"), "help")
  action_button("utility/refresh", Loc("ui-refresh"), "refresh")
  action_button("utility/close", Loc("help-close"), "close")

  local inner = f.add { type = "frame", name = "ssk_inner", style = "inside_deep_frame", direction = "vertical" }
  inner.style.horizontally_stretchable = true
  inner.style.vertically_stretchable = true
  local list = visible_tabs()
  local tabs = inner.add { type = "tabbed-pane", name = "ssk_tabs", tags = { ssk_tab_ids = list } }
  tabs.style.horizontally_stretchable = true
  tabs.style.vertically_stretchable = true
  local sel = 1
  for i, id in ipairs(list) do if id == us.tab_id then sel = i end end
  us.tab_id = list[sel]
  for _, id in ipairs(list) do
    local tab = tabs.add { type = "tab", caption = TAB_CAPTIONS[id] }
    local c = tabs.add { type = "flow", name = Loc.join("content_", id), direction = "vertical" }
    c.style.horizontally_stretchable = true
    c.style.vertically_stretchable = true
    c.style.padding = 12
    c.style.maximal_width = W - 40
    tabs.add_tab(tab, c)
  end
  tabs.selected_tab_index = sel

  f.auto_center = true
  player.opened = f
  UI.refresh(player, false, true)
end

function UI.dimensions(res, scale)
  local width, height = math.floor(res.width / scale) - 40, math.floor(res.height / scale) - 64
  local W = math.min(1840, width, math.floor(height * 16 / 9))
  return W, math.min(height, math.ceil(W * 9 / 16))
end

local function chart_state(us)
  if us.tab_id == "balance" then return SK.balance_state(us) end
  return us.tab_id == "focus" and SK.focus_state(us) or us
end

local function refresh_material(player, state, previous, full)
  if state.view == "focus" and state.focus ~= previous then close_inspectors(player) end
  UI.refresh(player, false, full, true)
end

function UI.toggle(player)
  if player.gui.screen[WIN] then UI.close(player) else UI.open(player) end
end

function UI.is_open(player) return player.gui.screen[WIN] ~= nil end

---------------------------------------------------------------------------
-- event handlers (return true when handled)
---------------------------------------------------------------------------
function UI.on_click(e)
  local el = e.element
  local player = game.get_player(e.player_index)
  if el.tags and el.tags.ssk_picker == "open" and (el.tags.target == "focus" or el.tags.target == "balance") then
    close_inspectors(player)
    MaterialPicker.open(player, el.tags.target, el.tags.current)
    return true
  elseif el.tags and el.tags.ssk_picker == "group" then
    MaterialPicker.on_group(e)
    return true
  elseif el.tags and el.tags.ssk_picker == "pick" then
    return UI.on_selection(e)
  elseif el.tags and el.tags.ssk_picker == "close" then
    MaterialPicker.close(player)
    return true
  elseif el.tags and el.tags.ssk_picker == "search" then
    MaterialPicker.toggle_search(player)
    return true
  end
  if el.name == "ssk_toggle" then UI.toggle(player); return true end
  if MachineStatus.on_click(player, el, UI.close) then return true end
  local us = ustate(e.player_index)
  if us.tab_id == "transfers" and TransfersUI.on_click(e, us.transfers, UI.close) then
    UI.refresh(player)
    return true
  end
  local chart = chart_state(us)
  local previous = chart.focus
  local r = SK.on_click(e, chart)
  if r then
    if r ~= "none" then refresh_material(player, chart, previous, false) end
    return true
  end
  local a = el.tags and el.tags.ssk_ui
  if not a then return false end
  if a == "close" then UI.close(player)
  elseif a == "help" then close_inspectors(player); Help.open(player)
  elseif a == "help_close" then Help.close(player);player.opened=player.gui.screen[WIN]
  elseif a == "watch" or a == "machine_status" then
    local focus_inspection = us.tab_id == "focus" and a == "machine_status"
    if (us.tab_id ~= "balance" and not focus_inspection) or not chart.focus then return true end
    local surface = sidx_for(player, us)
    MaterialPicker.close(player)
    Help.close(player)
    if a == "watch" then
      MachineStatus.close(player)
      if not Watch.close(player) then Watch.open(player, us, surface, chart.focus) end
    else
      Watch.close(player)
      MachineStatus.open(player, surface, chart.focus)
    end
  elseif a == "watch_close" then Watch.close(player)
  elseif a == "watch_apply" or a == "watch_remove" then
    if us.tab_id == "balance" and Watch.apply(player, us, sidx_for(player, us), chart.focus, a == "watch_remove") then
      UI.refresh(player, true)
    end
  elseif a == "bal_update" then
    local c=content(player,"balance")
    local root=c and c.ssk_balance_split and c.ssk_balance_split.ssk_balance_table.ssk_bal_root
    if root then root.tags={} end
    UI.refresh(player)
  elseif a == "refresh" then UI.refresh(player)
  elseif a == "bal_more" then
    us.bal_limit = (us.bal_limit or 200) + 200
    UI.refresh(player)
  elseif a == "bal_fav" or a == "bal_fav_group" then
    local favs = BalanceUI.favourites(us)
    local set, id = a == "bal_fav" and favs.items or favs.groups, el.tags.key or el.tags.gid
    set[id] = not set[id] or nil
    if not set[id] then
      Watch.pause_unstarred(player.index, us)
      if chart.focus and not Watch.available(player.index, us, chart.focus) then Watch.close(player) end
    end
    UI.refresh(player)
  elseif a == "focus_item" or a == "bal_material" then
    local fx = us.tab_id == "balance" and SK.balance_state(us) or SK.focus_state(us)
    local previous = fx.focus
    SK.select_focus(fx, el.tags.key)
    if us.tab_id == "balance" then refresh_material(player, fx, previous, false)
    else us.tab_id = "focus"; UI.open(player) end
  else
    return false
  end
  return true
end

function UI.on_selection(e)
  local handled, key, target = MaterialPicker.selection(e)
  if handled then
    if key then
      local player = game.get_player(e.player_index)
      local us = ustate(e.player_index)
      if target == us.tab_id and (target == "focus" or target == "balance") then
        local chart = chart_state(us)
        local previous = chart.focus
        SK.select_focus(chart, key)
        refresh_material(player, chart, previous, false)
      end
    end
    return true
  end
  local tags = e.element.tags
  local us = ustate(e.player_index)
  if us.tab_id == "transfers" and TransfersUI.on_selection(e, us.transfers) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if tags and tags.ssk_ui == "period" then
    local period = Sampler.PERIODS[e.element.selected_index] or Sampler.DEFAULT_PERIOD
    if us.period ~= period then Watch.reset_pending(us) end
    us.period = period
    UI.refresh(game.get_player(e.player_index), false, true)
    return true
  end
  if tags and tags.ssk_ui == "surface" then
    local us = ustate(e.player_index)
    us.surface = (us.surface_names or {})[e.element.selected_index]
    UI.refresh(game.get_player(e.player_index), false, true)
    return true
  end
  if tags and tags.ssk_ui == "bal_filter" then
    local us = ustate(e.player_index)
    us.bal_filter = BalanceUI.FILTERS[e.element.selected_index] or "problems"
    us.bal_limit = nil
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if tags and (tags.ssk_ui == "bal_group" or tags.ssk_ui == "bal_sort") then
    local us = ustate(e.player_index)
    if tags.ssk_ui == "bal_group" then us.bal_group = (us.bal_group_ids or {})[e.element.selected_index]
    else us.bal_sort = BalanceUI.SORTS[e.element.selected_index] or "priority" end
    us.bal_limit = nil
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  local chart = chart_state(ustate(e.player_index))
  local previous = chart.focus
  local r = SK.on_selection(e, chart)
  if not r then return false end
  refresh_material(game.get_player(e.player_index), chart, previous, false)
  return true
end

function UI.on_hover(e, entering)
  return HistoryUI.on_hover(e, entering) or SK.on_hover(e, entering)
end

function UI.on_checked(e)
  local u0 = ustate(e.player_index)
  if u0.tab_id == "transfers" and TransfersUI.on_checked(e, u0.transfers) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  local tags = e.element.tags
  local history_option = tags and tags.ssk_ui
  if u0.tab_id == "balance" and u0.bal_mode == "history"
    and (history_option == "history_usage" or history_option == "history_zero") then
    if history_option == "history_usage" then u0.bal_usage_breakdown = e.element.state
    else u0.bal_history_from_zero = e.element.state end
    UI.refresh(game.get_player(e.player_index), false, false, true)
    return true
  end
  if tags and tags.ssk_ui == "bal_details" then
    u0.bal_details = e.element.state
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  local r = SK.on_checked(e, chart_state(u0))
  if r then
    if r == "rebuild" then UI.refresh(game.get_player(e.player_index), false, false, true) end
    return true
  end
  return false
end

function UI.on_elem_changed(e)
  local u0 = ustate(e.player_index)
  if u0.tab_id == "focus" then
    local chart = chart_state(u0)
    local previous = chart.focus
    local r = SK.on_elem_changed(e, chart)
    if r then
      if r ~= "none" then refresh_material(game.get_player(e.player_index), chart, previous, true) end
      return true
    end
  end

  return false
end

function UI.on_tab_changed(e)
  local f = e.element
  if not f.valid then return false end
  local us = ustate(e.player_index)
  local player = game.get_player(e.player_index)
  if f.name == "ssk_balance_inspector_tabs" then
    local c = content(player, "balance")
    local split = c and c.ssk_balance_split
    if us.tab_id ~= "balance" or not split or f ~= split.ssk_balance_focus.ssk_balance_inspector_tabs then return false end
    HistoryUI.clear_hover(e.player_index)
    us.bal_mode = f.selected_tab_index == 2 and "history" or "flow"
    MaterialPicker.close(player)
    close_inspectors(player)
    close_chart_settings(us)
    UI.refresh(player, false, false, true)
    return true
  end
  if us.tab_id == "transfers" and TransfersUI.on_selection(e, us.transfers) then
    UI.refresh(player)
    return true
  end
  if not (f.name == "ssk_tabs" and f.parent and f.parent.parent and f.parent.parent.name == WIN) then return false end
  HistoryUI.clear_hover(e.player_index)
  local ids = f.tags.ssk_tab_ids or {}
  us.tab_id = ids[f.selected_tab_index] or "balance"
  MaterialPicker.close(player)
  Canvas.clear(player.index)
  close_inspectors(player)
  close_chart_settings(us)
  UI.refresh(player, false, true)
  return true
end

function UI.on_closed(e)
  if MaterialPicker.on_closed(e) then return true end
  local player = game.get_player(e.player_index)
  if MachineStatus.on_closed(player, e.element) then return true end
  if e.element and e.element.valid and (e.element.name == Watch.NAME or e.element.name == WIN) and Watch.close(player) then
    player.opened = player.gui.screen[WIN]
    return true
  end
  if e.element and e.element.valid and e.element.name=="ssk_help" then
    Help.close(player);player.opened=player.gui.screen[WIN]
    return true
  end
  if e.element and e.element.valid and e.element.name == WIN then
    if player.gui.screen.ssk_material_picker then
      MaterialPicker.close(player)
      return true
    end
    if player.gui.screen.ssk_help then
      Help.close(player);player.opened=player.gui.screen[WIN]
      return true
    end
    if close_chart_settings(ustate(player.index)) then
      player.opened = player.gui.screen[WIN]
      UI.refresh(player, false, false, true)
      return true
    end
    UI.close(player)
    return true
  end
  return false
end

function UI.on_value_changed(e)
  if e.element and e.element.valid then return MachineStatus.on_value_changed(game.get_player(e.player_index), e.element) end
end

function UI.on_text_changed(e) return MaterialPicker.on_text_changed(e) end
function UI.on_string_translated(e) MaterialPicker.on_translated(e) end

function UI.auto_refresh()
  for _, p in pairs(game.connected_players) do
    if UI.is_open(p) then UI.refresh(p, true) end
  end
end

function UI.on_display_changed(player)
  if UI.is_open(player) then UI.open(player) end
end

function UI.on_surface_changed(player)
  if not UI.is_open(player) then return end
  local us = ustate(player.index)
  if us.sidx ~= sidx_for(player, us) then UI.refresh(player, false, true) end
end

return UI
