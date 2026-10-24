-- Top-left toolbar button + main window.
-- Tabs: Balance · Focus · Full Sankey.

local mod_gui = require("mod-gui")
local Sampler = require("scripts.sampler")
local SK = require("scripts.sankey_ui")
local BalanceUI = require("scripts.balance_ui")
local Su = require("scripts.surfaces")
local Help = require("scripts.help_ui")
local MaterialPicker = require("scripts.material_picker")

local UI = {}
local TABS = { "balance", "focus", "sankey" }
local TAB_CAPTIONS = { balance = "Balance", focus = "Focus", sankey = "Full Sankey" }
local WIN = "ssk_main"

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
  -- Adopt the requested default once for existing Live/default users, retaining
  -- explicit longer periods. Later manual choices (including Live) persist.
  if not s.period_default_10m then
    if not s.period or s.period == 0 then s.period = Sampler.DEFAULT_PERIOD end
    s.period_default_10m = true
  end
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
             style = mod_gui.button_style, tooltip = "Production Flow" }
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

function fill.balance(player, c, us, only_auto, keep_balance_rows)
  if not c.ssk_balance_split then
    c.clear()
    local split = c.add { type = "flow", name = "ssk_balance_split", direction = "horizontal" }
    split.style.horizontal_spacing = 12
    split.style.width = us.canvas_w
    local left = split.add { type = "flow", name = "ssk_balance_table", direction = "vertical" }
    local left_w = math.floor(us.canvas_w * 0.44)
    left.style.width, left.style.height = left_w, us.canvas_h + 100
    us.bal_width = left_w - 24
    us.bal_height = us.canvas_h + 100
    -- the chart panel: toolbar strip on top, chart below, in one vanilla inset
    local right = split.add { type = "frame", name = "ssk_balance_focus", style = "inside_deep_frame", direction = "vertical" }
    us.bal_chart_w = us.canvas_w - left_w - 12
    right.style.width, right.style.height = us.bal_chart_w, us.canvas_h + 100
  end
  local split = c.ssk_balance_split
  local first = BalanceUI.fill(player, split.ssk_balance_table, us, scope_caption(player, us), only_auto or keep_balance_rows)
  local fx = SK.balance_state(us)
  if not fx.focus then fx.focus = first end
  fx.sel = fx.focus
  fx.canvas_w, fx.canvas_h = us.bal_chart_w, math.max(100,us.canvas_h+72-SK.toolbar_height(fx))
  if not only_auto or fx.live ~= false then
    SK.fill(player, split.ssk_balance_focus, fx, fx.canvas_w, fx.canvas_h, false, only_auto)
  end
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local function content(player, id)
  local f = player.gui.screen[WIN]
  local inner = f and f.ssk_inner
  local tabs = inner and inner.ssk_tabs
  return tabs and tabs["content_" .. id]
end

local function update_history(player,us)
  local frame=player.gui.screen[WIN]
  local bar=frame and frame.ssk_window_bar
  local label=bar and bar.ssk_history
  if not label then return end
  local _,seconds=Sampler.rates(us.sidx,us.period)
  local target=us.period>0 and us.period or settings.global["ssk-window-seconds"].value
  label.visible=seconds<target
  label.caption=string.format("History collected: %.0f / %d s",seconds,target)
  label.tooltip="The selected period is still filling. Rates use the recorded history available so far, not an assumed full window. Recording continues while the factory runs."
end

-- Focus and Full Sankey draw into one vanilla panel: toolbar strip on top, chart below.
local function chart_panel(c)
  return c.ssk_chart or c.add { type = "frame", name = "ssk_chart", style = "inside_deep_frame", direction = "vertical" }
end

-- full = rebuild the Sankey tab from scratch (otherwise its scroll position is kept)
function UI.refresh(player, only_auto, full, keep_balance_rows)
  local us = ustate(player.index)
  local id = us.tab_id
  local c = content(player, id)
  if not c then return end
  us.sidx = sidx_for(player, us)
  update_history(player,us)
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
  if id ~= "balance" then c.clear() end
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
  MaterialPicker.close(player)
  Help.close(player)
  local f = player.gui.screen[WIN]
  if f then f.destroy() end
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
  tb.add { type = "label", caption = "Production Flow", style = "frame_title", ignored_by_interaction = true }
  local drag = tb.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  local function action_button(sprite, tooltip, tag)
    tb.add { type = "sprite-button", style = "frame_action_button", sprite = sprite,
      tooltip = tooltip, tags = { ssk_ui = tag } }
  end
  tb.style.vertical_align = "center"
  tb.add { type = "label", caption = "Surface:" }
  local sitems, ssel = { "Where I am (" .. Su.rich(player.surface) .. ")" }, 1
  us.surface_names = {}
  for i, x in ipairs(surface_choices(us.surface)) do
    sitems[#sitems + 1] = x.label
    us.surface_names[i + 1] = x.name
    if us.surface == x.name then ssel = i + 1 end
  end
  local surface_picker = tb.add { type = "drop-down", items = sitems, selected_index = ssel, tags = { ssk_ui = "surface" },
           tooltip = "Every tab shows one surface at a time; surfaces are never added together." }
  surface_picker.style.width = math.min(240, math.floor(W * 0.22))
  local pl = tb.add { type = "label", caption = "Period:" }
  pl.style.left_margin = 12
  local psel = 1
  for i, v in ipairs(Sampler.PERIODS) do if us.period == v then psel = i end end
  local items = {}
  for i, cpt in ipairs(Sampler.PERIOD_CAPTIONS) do items[i] = cpt end
  items[1] = string.format("Recent (%d s)", settings.global["ssk-window-seconds"].value)
  tb.add { type = "drop-down", items = items, selected_index = psel, tags = { ssk_ui = "period" },
           tooltip = "How far back rates are averaged. Longer periods smooth out bursts; history builds up from when the mod was added." }
  local history=tb.add{type="label",name="ssk_history"}
  history.style.font="default-small-bold";history.style.font_color={1,0.82,0.35}
  history.style.maximal_width=190
  action_button("utility/questionmark", "Help: controls, calculations, stock, alerts and chart limits", "help")
  action_button("utility/refresh", "Refresh", "refresh")
  action_button("utility/close", "Close", "close")

  local inner = f.add { type = "frame", name = "ssk_inner", style = "inside_deep_frame", direction = "vertical" }
  inner.style.horizontally_stretchable = true
  inner.style.vertically_stretchable = true
  local tabs = inner.add { type = "tabbed-pane", name = "ssk_tabs" }
  tabs.style.horizontally_stretchable = true
  tabs.style.vertically_stretchable = true
  local list = TABS
  local sel = 1
  for i, id in ipairs(list) do if id == us.tab_id then sel = i end end
  us.tab_id = list[sel]
  for _, id in ipairs(list) do
    local tab = tabs.add { type = "tab", caption = TAB_CAPTIONS[id] }
    local c = tabs.add { type = "flow", name = "content_" .. id, direction = "vertical" }
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
  if el.tags and el.tags.ssk_picker == "open" then
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
  local r = SK.on_click(e, (function()
    local u = ustate(e.player_index)
    return chart_state(u)
  end)())
  if r then
    if r ~= "none" then UI.refresh(player, false, false, true) end
    return true
  end
  local a = el.tags and el.tags.ssk_ui
  if not a then return false end
  if a == "close" then UI.close(player)
  elseif a == "help" then Help.open(player)
  elseif a == "help_close" then Help.close(player);player.opened=player.gui.screen[WIN]
  elseif a == "bal_update" then
    local c=content(player,"balance")
    local root=c and c.ssk_balance_split and c.ssk_balance_split.ssk_balance_table.ssk_bal_root
    if root then root.tags={} end
    UI.refresh(player)
  elseif a == "refresh" then UI.refresh(player)
  elseif a == "bal_more" then
    local us = ustate(e.player_index)
    us.bal_limit = (us.bal_limit or 200) + 200
    UI.refresh(player)
  elseif a == "bal_fav" or a == "bal_fav_group" then
    local favs = BalanceUI.favourites(ustate(e.player_index))
    local set, id = a == "bal_fav" and favs.items or favs.groups, el.tags.key or el.tags.gid
    set[id] = not set[id] or nil
    UI.refresh(player)
  elseif a == "focus_item" then
    local us = ustate(e.player_index)
    local fx = us.tab_id == "balance" and SK.balance_state(us) or SK.focus_state(us)
    SK.select_focus(fx, el.tags.key)
    if us.tab_id == "balance" then UI.refresh(player, false, false, true)
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
      if target == us.tab_id then
        SK.select_focus(chart_state(us), key)
        UI.refresh(player, false, false, true)
      end
    end
    return true
  end
  local tags = e.element.tags
  if tags and tags.ssk_ui == "period" then
    ustate(e.player_index).period = Sampler.PERIODS[e.element.selected_index] or Sampler.DEFAULT_PERIOD
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
    else us.bal_sort = e.element.selected_index == 2 and "groups" or "priority" end
    us.bal_limit = nil
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  local u0 = ustate(e.player_index)
  local r = SK.on_selection(e, chart_state(u0))
  if not r then return false end
  UI.refresh(game.get_player(e.player_index), false, false, true)
  return true
end

function UI.on_hover(e, entering)
  return SK.on_hover(e, entering)
end

function UI.on_checked(e)
  if e.element.tags and e.element.tags.ssk_ui == "bal_details" then
    ustate(e.player_index).bal_details = e.element.state
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  local u0 = ustate(e.player_index)
  local r = SK.on_checked(e, chart_state(u0))
  if r then
    if r == "rebuild" then UI.refresh(game.get_player(e.player_index), false, false, true) end
    return true
  end
  return false
end

function UI.on_elem_changed(e)
  local u0 = ustate(e.player_index)
  if u0.tab_id == "focus" or u0.tab_id == "balance" then
    local r = SK.on_elem_changed(e, chart_state(u0))
    if r then
      if r ~= "none" then UI.refresh(game.get_player(e.player_index), false, true, true) end
      return true
    end
  end

  return false
end

function UI.on_tab_changed(e)
  local f = e.element
  if not (f.valid and f.name == "ssk_tabs" and f.parent and f.parent.parent and f.parent.parent.name == WIN) then return false end
  local list = TABS
  local us = ustate(e.player_index)
  us.tab_id = list[f.selected_tab_index] or "balance"
  close_chart_settings(us)
  UI.refresh(game.get_player(e.player_index), false, true)
  return true
end

function UI.on_closed(e)
  if MaterialPicker.on_closed(e) then return true end
  if e.element and e.element.valid and e.element.name=="ssk_help" then
    local player=game.get_player(e.player_index)
    Help.close(player);player.opened=player.gui.screen[WIN]
    return true
  end
  if e.element and e.element.valid and e.element.name == WIN then
    local player=game.get_player(e.player_index)
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

return UI
