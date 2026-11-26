local Loc = require("scripts.locale")
local Cells = require("scripts.cells")
local CellsUI = require("scripts.cells_ui")
local RailUI = require("scripts.cell_rail_ui")
local CellOutlines = require("scripts.cell_outlines")
-- Top-left toolbar button + main window.
-- Tabs: Balance · Focus · Cells · Full Sankey · Transfers.

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
local SERockets = require("scripts.se_rockets")
local SELogisticsUI = require("scripts.se_logistics_ui")
local TransportHistoryUI = require("scripts.transport_history_ui")
local TransferPanels = require("scripts.se_transfer_panels")

local UI = {}
local TAB_CAPTIONS = { balance = Loc("ui-balance"), focus = Loc("ui-focus"), cells = Loc("cells-tab"), sankey = Loc("ui-full-sankey"), transfers = Loc("help-transfers") }
local WIN = "ssk_main"
local THUMBS = {x="ssk_scroll_thumb_x", y="ssk_scroll_thumb_y"}
local sync_scroll_thumbs

local function clear_scroll_thumbs(player)
  for _,name in pairs(THUMBS) do
    local thumb = player.gui.screen[name]
    if thumb then thumb.destroy() end
  end
end
-- The native window uses 12 px per side around the tab pane, and each tab keeps
-- 12 px between its panels and the pane's border on every side (TAB_PAD_X here,
-- TAB_PAD_Y above and below), so lists and charts never touch the outer border.
local TAB_PAD_X = 12
local WINDOW_SIDE_CHROME = 24 + 2 * TAB_PAD_X
-- At 16:9 this leaves room for the fixed headers and shipment table columns.
local MIN_WINDOW_WIDTH = 880
-- Compact Transfers can scroll, but still needs room for its tabs and viewport.
local MIN_SAFE_WINDOW_WIDTH = 396

local function visible_tabs()
  local list = { "balance", "focus", "cells", "sankey" }
  if Transfers.available() or SERockets.available() then list[#list + 1] = "transfers" end
  return list
end

local function release_chart_zoom(player)
  local guards = storage.chart_wheel_zoom
  local guard = guards and guards[player.index]
  if not guard then return end
  player.set_zoom_limits(guard.controller, guard.limits)
  guards[player.index] = nil
  if not next(guards) then storage.chart_wheel_zoom = nil end
end

function UI.release_chart_zoom(tick)
  local guards = storage.chart_wheel_zoom
  if not guards then return end
  for index, guard in pairs(guards) do
    if guard.tick < tick then
      local player = game.get_player(index)
      if player then release_chart_zoom(player) else guards[index] = nil end
    end
  end
  if not next(guards) then storage.chart_wheel_zoom = nil end
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
    s.view, s.tier_mode = "detail", "depth"
    s.lines, s.layout, s.sel = "curves", "clean", nil
    s.tier_lo, s.tier_hi = nil, nil
    s.readability_defaults = true
  end
  -- Older saves selected the experimental world camera. Charts use native GUI
  -- sprites so the game world's colour lookup cannot alter the chart palette.
  if not s.gui_chart_defaults then
    s.renderer = "sprites"
    if s.fx then s.fx.renderer = "sprites" end
    if s.bal_fx then s.bal_fx.renderer = "sprites" end
    s.gui_chart_defaults = true
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
  local supported=player.force==game.forces.player
  flow.add { type = "sprite-button", name = "ssk_toggle", sprite = "ssk-icon",enabled=supported,
             style = mod_gui.button_style, tooltip = supported and Loc("ui-production-flow") or Loc("ui-player-force-only") }
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
local function surface_choices(selected, force)
  local n = {}
  for _, rec in pairs(storage.machines or {}) do n[rec.s] = (n[rec.s] or 0) + 1 end
  for index in pairs(Sampler.stock_surfaces()) do n[index]=n[index] or 0 end
  if SERockets.available() then
    for index in pairs(SERockets.surfaces(force)) do n[index]=n[index] or 0 end
  end
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
-- Every tab fills the same box: 12 px of tab padding on all four sides, so each
-- tab leaves the same margin inside the window's border.
local TAB_PAD_Y = 12
local function tab_pane_height(us) return us.canvas_h + 100 end

function fill.balance(player, c, us, only_auto, keep_balance_rows, refresh_graph)
  local pane_height = tab_pane_height(us)
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
    us.bal_chart_w = right_w
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
      panel.style.padding = 0
    end
    modes.selected_tab_index = us.bal_mode == "history" and 2 or 1
  end
  local first = BalanceUI.fill(player, split.ssk_balance_table, us, scope_caption(player, us), only_auto or keep_balance_rows or refresh_graph)
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
    SK.fill(player, flow, fx, fx.canvas_w, fx.canvas_h, false, only_auto, nil, refresh_graph)
  end
  SK.update_balance_actions(flow, us, fx.focus, player.index)
end

function fill.transfers(player, c, us)
  -- Transfers uses the same tab padding as Balance, so its nested tabs line up
  -- with Balance's Flow / History tabs and it leaves the same bottom strip.
  c.style.top_padding, c.style.bottom_padding = TAB_PAD_Y, TAB_PAD_Y
  local _, window_height = UI.dimensions(player.display_resolution, player.display_scale)
  local height = math.min(tab_pane_height(us), window_height - 96)
  if us.transport_history then
    TransportHistoryUI.render(c,player,us,us.canvas_w,height)
    return
  end
  if SERockets.available() and not Transfers.available() then
    us.se_logistics=us.se_logistics or {}
    SELogisticsUI.render(c,player,game.surfaces[us.sidx],us.period,us.se_logistics,us.canvas_w,height)
    return
  end
  us.transfers = us.transfers or {}
  local parent, width, platform_height = c, us.canvas_w, tab_pane_height(us)
  if width < 850 then
    if not c.viewport then
      c.clear()
      TransferPanels.viewport(c, width, height, "platforms")
    end
    parent = c.viewport.body
    local size = parent.tags
    width, platform_height = size.width, size.height
  end
  local seconds = TransfersUI.render(parent, player, us.period, us.transfers, width, platform_height)
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
  local scoped = us.tab_id ~= "transfers" or us.transport_history~=nil or (SERockets.available() and not Transfers.available())
  local rail_view = us.tab_id == "cells" and CellsUI.rail_view(us.cells)
  local periodic = us.tab_id ~= "cells" or rail_view or CellsUI.mode(us.cells or {}) == "measured"
  bar.ssk_period_label.visible = true
  bar.ssk_period_picker.visible = true
  bar.ssk_surface_label.visible = scoped
  bar.ssk_surface_picker.visible = scoped
  local label=bar.ssk_history
  if not scoped then label.visible = false; return end
  if us.tab_id=="transfers" or rail_view or not periodic then label.visible=false;return end
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
function UI.refresh(player, only_auto, full, keep_balance_rows, refresh_graph)
  local us = ustate(player.index)
  local id = us.tab_id
  if id ~= "sankey" then clear_scroll_thumbs(player) end
  if id ~= "cells" then CellOutlines.clear(player.index, "map") end
  local c = content(player, id)
  if not c then return end
  local surface = sidx_for(player, us)
  if us.sidx ~= surface then close_inspectors(player) end
  us.sidx = surface
  update_header(player,us)
  if id == "cells" then
    us.cells = us.cells or {}
    us.cells.chart = us.cells.chart or {}
    if only_auto and not CellsUI.rail_view(us.cells)
      and (CellsUI.mode(us.cells) ~= "measured" or (us.cells.view ~= "map"
        and (us.cells.chart.live == false or us.cells.chart.oversized))) then return end
    us.cells.period, us.cells.sidx = us.period, us.sidx
    CellsUI.fill(player, c, us.cells, us.canvas_w, tab_pane_height(us), full, only_auto)
    return
  end
  if id == "focus" then
    local fx = SK.focus_state(us)
    fx.sidx = us.sidx
    SK.defaults(fx)
    if only_auto and not fx.live then return end
    SK.fill(player, chart_panel(c), fx, us.canvas_w, math.max(100, tab_pane_height(us) - SK.toolbar_height(fx)), full, only_auto, nil, refresh_graph)
    return
  end
  if id == "sankey" then
    SK.defaults(us)
    if only_auto and not us.live then return end
    SK.fill(player, chart_panel(c), us, us.canvas_w, math.max(100, tab_pane_height(us) - SK.toolbar_height(us)), full, only_auto, nil, refresh_graph)
    sync_scroll_thumbs(player)
    return
  end
  fill[id](player, c, us, only_auto, keep_balance_rows, refresh_graph)
end

-- Chart settings float over the chart; Esc, tab changes and reopening close them.
local function close_chart_settings(us)
  local open = false
  for _, s in pairs({ us, us.fx, us.bal_fx, us.cells and us.cells.chart }) do
    if s.settings_open then s.settings_open, open = nil, true end
  end
  return open
end

function UI.close(player)
  release_chart_zoom(player)
  clear_scroll_thumbs(player)
  CellOutlines.on_window_closed(player.index)
  close_inspectors(player)
  MaterialPicker.close(player)
  Help.close(player)
  HistoryUI.clear_hover(player.index)
  SK.clear_hover(player.index)
  local f = player.gui.screen[WIN]
  if f then
    Canvas.clear(player.index)
    f.destroy()
  end
end

function UI.sanitize_saved_states()
  for _,us in pairs(storage.ui or {}) do
    MaterialPicker.sanitize_state(us)
    for _,field in ipairs({"fx","bal_fx"}) do
      if type(us[field])=="table" then MaterialPicker.sanitize_state(us[field]) end
    end
  end
end

function UI.on_player_removed(index)
  if storage.chart_wheel_zoom then storage.chart_wheel_zoom[index] = nil end
  CellOutlines.clear(index)
  HistoryUI.clear_hover(index)
  SK.clear_hover(index)
  if storage.canvas and storage.canvas[index] then Canvas.clear(index) end
  for _,field in ipairs({"ui","pgroups","canvas","material_picker"}) do
    if storage[field] then storage[field][index]=nil end
  end
  if storage.sk_render then
    storage.sk_render[index]=nil
    storage.sk_render[Loc.join(index,":focus")]=nil
  end
end

function UI.open(player)
  Cells.cancel(player)
  UI.close(player)
  if player.force~=game.forces.player then player.print(Loc("ui-player-force-only"));return end
  local res, sc = player.display_resolution, player.display_scale
  local W, H = UI.dimensions(res, sc)
  local compact_window = player.mod_settings["ssk-allow-small-window"]
  if W < MIN_SAFE_WINDOW_WIDTH or (W < MIN_WINDOW_WIDTH and not (compact_window and compact_window.value)) then
    player.print(Loc("ui-window-too-small"))
    return
  end

  local us = ustate(player.index)
  close_chart_settings(us)
  local f = player.gui.screen.add { type = "frame", name = WIN, direction = "vertical" }
  f.style.width, f.style.height = W, H
  us.canvas_w = W - WINDOW_SIDE_CHROME
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
  -- Vanilla title bars (frame_header_flow) space their controls 8 px apart.
  tb.style.horizontal_spacing = 8
  tb.add { type = "label", name = "ssk_surface_label", caption = Loc("ui-surface") }
  local sitems, ssel = { Loc("ui-where-i-am", Su.rich(player.surface)) }, 1
  us.surface_names = {}
  for i, x in ipairs(surface_choices(us.surface,player.force)) do
    sitems[#sitems + 1] = x.label
    us.surface_names[i + 1] = x.name
    if us.surface == x.name then ssel = i + 1 end
  end
  local surface_picker = tb.add { type = "drop-down", name = "ssk_surface_picker", items = sitems, selected_index = ssel,
           tags = { ssk_ui = "surface" }, tooltip = SERockets.available() and Loc("se-surface-help") or Loc("ui-surface-for-balance-focus-cells-and-full-sankey") }
  surface_picker.style.width = math.min(240, math.floor(W * 0.22))
  local pl = tb.add { type = "label", name = "ssk_period_label", caption = Loc("ui-period") }
  -- 16 px between each label + drop-down pair and the next group.
  pl.style.left_margin = 8
  local psel = 2
  for i, v in ipairs(Sampler.PERIODS) do if us.period == v then psel = i end end
  tb.add { type = "drop-down", name = "ssk_period_picker", items = Sampler.PERIOD_CAPTIONS, selected_index = psel, tags = { ssk_ui = "period" },
           tooltip = Loc("ui-how-far-back-rates-and-transfers-are") }
  local history=tb.add{type="label",name="ssk_history"}
  history.style.font="default-small-bold";history.style.font_color={1,0.82,0.35}
  history.style.maximal_width=190
  history.style.left_margin,history.style.right_margin=8,8
  action_button("utility/list_view", Loc("cells-title"), "cells")
  action_button("utility/questionmark", Loc("ui-help-controls-calculations-stock-alerts-and-chart"), "help")
  action_button("utility/refresh", Loc("ui-refresh"), "refresh")
  action_button("utility/close", Loc("help-close"), "close")

  local inner = f.add { type = "frame", name = "ssk_inner", style = "inside_deep_frame", direction = "vertical" }
  inner.style.horizontally_stretchable = true
  inner.style.vertically_stretchable = true
  local list = visible_tabs()
  local tabs = inner.add { type = "tabbed-pane", name = "ssk_tabs", style = "tabbed_pane_with_no_side_padding",
    tags = { ssk_tab_ids = list } }
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
    c.style.padding = 0
    c.style.top_padding, c.style.bottom_padding = 12, 12
    c.style.left_padding, c.style.right_padding = TAB_PAD_X, TAB_PAD_X
    c.style.maximal_width = us.canvas_w + 2 * TAB_PAD_X
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
  if us.tab_id == "cells" then return us.cells and us.cells.chart or us end
  return us.tab_id == "focus" and SK.focus_state(us) or us
end

local function refresh_material(player, state, previous, full, refresh_graph)
  if state.view == "focus" and state.focus ~= previous then close_inspectors(player) end
  UI.refresh(player, false, full, true, refresh_graph)
end

function UI.toggle(player)
  if player.gui.screen[WIN] then UI.close(player) else UI.open(player) end
end

function UI.is_open(player) return player.gui.screen[WIN] ~= nil end

function UI.on_sankey_viewport_setting_changed(player)
  if UI.is_open(player) and ustate(player.index).tab_id == "sankey" then
    UI.refresh(player, false, true)
  end
end

local function scroll_chart(player)
  if not (player and UI.is_open(player)) then return end
  local us = ustate(player.index)
  local tab = us.tab_id == "sankey" and content(player, "sankey")
  local chart = tab and tab.ssk_chart
  local viewport = chart and chart.ssk_body and chart.ssk_body.ssk_viewport
  if viewport and us.chart_viewport then return chart, us, us.chart_viewport end
end

sync_scroll_thumbs = function(player)
  local chart, us, viewport = scroll_chart(player)
  if not chart then
    clear_scroll_thumbs(player)
    return
  end
  local frame = player.gui.screen[WIN]
  local scale = player.display_scale
  local function px(size) return math.floor(size * scale) end
  local location = frame.location
  if not location then
    local res = player.display_resolution
    local w,h = UI.dimensions(res,scale)
    location = {x=math.floor((res.width-px(w))/2), y=math.floor((res.height-px(h))/2)}
  end
  -- Match the Full Sankey panel inside the window and tab chrome. The tracks
  -- start below the toolbar and the optional chart size notice.
  local left = location.x + px(WINDOW_SIDE_CHROME / 2)
  local top = location.y + px(112) + px(SK.toolbar_height(us))
  if chart.ssk_size_notice.visible then top = top + px(chart.ssk_size_notice.style.minimal_height) end
  for axis,name in pairs(THUMBS) do
    local horizontal = axis == "x"
    local travel = horizontal and viewport.travel_x or viewport.travel_y
    local maximum = horizontal and viewport.max_x or viewport.max_y
    local thumb = player.gui.screen[name]
    if travel > 0 and maximum > 0 then
      if not thumb then
        -- Factorio moves its drag target immediately. Give each scrollbar a
        -- transparent screen frame so it can never move the Production Flow window.
        thumb = player.gui.screen.add{type="frame", name=name, style="invisible_frame"}
        local grip = thumb.add{type="label", name="grip", tags={ssk_scroll_thumb=axis}}
        grip.drag_target = thumb
      end
      local grip = thumb.grip.style
      grip.width, grip.height = horizontal and viewport.thumb_w or 12, horizontal and 12 or viewport.thumb_h
      local x = left + px(horizontal and viewport.thumb_x or viewport.w)
      local y = top + px(horizontal and viewport.h or viewport.thumb_y)
      thumb.tags = {ssk_scroll_thumb=axis, x=x, y=y}
      thumb.location = {x=x,y=y}
      if player.opened == frame then thumb.bring_to_front() end
    elseif thumb then
      thumb.destroy()
    end
  end
end

local function pan_chart(player, chart, us, x, y)
  if not SK.pan_to(player, chart, us, x, y) then return false end
  sync_scroll_thumbs(player)
  return true
end

function UI.on_chart_location_changed(e)
  local element = e.element
  if not (element and element.valid) then return end
  local player = game.get_player(e.player_index)
  if element.name == WIN then
    sync_scroll_thumbs(player)
    return
  end
  local origin = element.tags
  local axis = origin.ssk_scroll_thumb
  if not axis or element.name ~= THUMBS[axis] or not element.location then return end
  local chart, us, viewport = scroll_chart(player)
  if not chart then return end
  local movement = element.location[axis] - origin[axis]
  local horizontal = axis == "x"
  local travel = horizontal and viewport.travel_x or viewport.travel_y
  local maximum = horizontal and viewport.max_x or viewport.max_y
  local delta = travel > 0 and movement * maximum / (travel * player.display_scale) or 0
  pan_chart(player, chart, us, viewport.x + (horizontal and delta or 0), viewport.y + (horizontal and 0 or delta))
end

function UI.on_chart_wheel(e, dx, dy)
  local player = game.get_player(e.player_index)
  local chart, us, viewport = scroll_chart(player)
  if not player then return end
  local target = chart and chart.ssk_body.ssk_viewport
  local ancestor = target and e.element
  while ancestor and ancestor.valid and ancestor ~= target and not ancestor.tags.ssk_scroll_thumb do
    ancestor = ancestor.parent
  end
  if not (ancestor and ancestor.valid) then
    release_chart_zoom(player)
    return
  end

  -- Non-consuming custom wheel inputs arrive before the game's zoom action.
  -- Hold the current zoom until that action has passed, without blocking wheel
  -- bindings elsewhere or changing the chart's clipping and drag surfaces.
  local index, controller = player.index, player.controller_type
  local guards = storage.chart_wheel_zoom
  local guard = guards and guards[index]
  if guard and guard.controller ~= controller then
    release_chart_zoom(player)
    guard = nil
  end
  if not guard then
    local zoom, limits = player.zoom, player.zoom_limits
    guard = {controller=controller, limits=limits}
    storage.chart_wheel_zoom = storage.chart_wheel_zoom or {}
    storage.chart_wheel_zoom[index] = guard
    player.zoom_limits = {closest={zoom=zoom}, furthest={zoom=zoom}, furthest_game_view=limits.furthest_game_view}
  end
  guard.tick = game.tick
  pan_chart(player, chart, us, viewport.x + dx, viewport.y + dy)
end

function UI.on_chart_page(e, direction)
  local player = game.get_player(e.player_index)
  local chart, us, viewport = scroll_chart(player)
  if not chart or player.opened ~= player.gui.screen[WIN] then return end
  local el = e.element
  if el and el.valid and (el.type == "textfield" or el.type == "text-box") then return end
  pan_chart(player, chart, us, viewport.x + direction*viewport.w, viewport.y)
end

---------------------------------------------------------------------------
-- event handlers (return true when handled)
---------------------------------------------------------------------------
local function finish_cell_delete(player, confirm)
  local pending = Cells.finish_delete(player, confirm)
  if not pending then return end
  if pending.from_tab then UI.open(player) else Cells.open(player) end
end

-- Opens the Cells tab on a saved cell, switching the header's surface to the
-- cell's surface the way choosing it from the surface picker would.
local function show_cell(player, id)
  local cells = storage.production_cells
  local record = cells and cells.records[id]
  local surface = record and game.surfaces[record.surface_index]
  if not surface or player.force ~= game.forces.player then return end
  local us = ustate(player.index)
  if sidx_for(player, us) ~= surface.index then
    us.surface = surface ~= player.surface and surface.name or nil
  end
  us.tab_id = "cells"
  us.cells = us.cells or {}
  us.cells.selected, us.cells.chart = id, {}
  Cells.close(player)
  UI.open(player)
end

-- Closes the window and opens remote view where the Map tab is looking.
local function jump_to_map(player, state)
  if player.force ~= game.forces.player then return end
  local view = CellsUI.jump_target(player, state)
  if not view then return end
  -- The map's outlines stay visible in remote view until the player leaves it.
  CellOutlines.hold(player.index)
  UI.close(player)
  local ok = pcall(player.set_controller, { type = defines.controllers.remote,
    surface = view.surface, position = { view.x, view.y } })
  if ok then return end
  CellOutlines.clear(player.index, "map")
  local record = state.selected and storage.production_cells.records[state.selected]
  for _, entity in pairs(record and record.members or {}) do
    if entity.valid then player.centered_on = entity; return end
  end
end

function UI.on_click(e)
  local el = e.element
  local player = game.get_player(e.player_index)
  local page = el.tags.ssk_scroll_page
  if page then
    local chart, us, viewport = scroll_chart(player)
    if not chart then return end
    local axis = el.tags.ssk_scroll_axis
    return pan_chart(player, chart, us, viewport.x + (axis=="x" and page*viewport.w or 0),
      viewport.y + (axis=="y" and page*viewport.h or 0))
  end
  if el.tags and el.tags.ssk_picker == "open" and el.tags.target == "cell" then
    Cells.open_display_picker(player)
    return true
  elseif el.tags and el.tags.ssk_picker == "open" and (el.tags.target == "focus" or el.tags.target == "balance") then
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
  if el.tags.ssk_cell_delete_answer then
    finish_cell_delete(player, el.tags.ssk_cell_delete_answer == "delete")
    return true
  elseif el.tags.ssk_cell_delete_request then
    Cells.prompt_delete(player, el.tags.ssk_cell_delete_request, false, Cells.close)
    return true
  end
  if el.tags.ssk_cell == "show" then show_cell(player, el.tags.cell_id); return true end
  if Cells.on_click(player, el) then return true end
  if MachineStatus.on_click(player, el, UI.close) then return true end
  local us = ustate(e.player_index)
  if us.tab_id == "cells" and CellsUI.rail_view(us.cells) and RailUI.on_click(el.tags, us.cells) then
    UI.refresh(player)
    return true
  end
  if el.tags and el.tags.ssk_ui=="transport_history" then
    if TransportHistoryUI.open(player,us,el.tags) then UI.open(player) end
    return true
  end
  if us.tab_id=="transfers" and us.transport_history then
    local handled=TransportHistoryUI.on_click(e,us,UI.close)
    if handled then
      if handled=="reopen" then UI.open(player)
      elseif UI.is_open(player) then UI.refresh(player) end
      return true
    end
  end
  if us.tab_id=="transfers" and SERockets.available() and SELogisticsUI.on_click(e,us.se_logistics or {},UI.close) then
    if UI.is_open(player) then UI.refresh(player) end
    return true
  end
  if us.tab_id == "transfers" and TransfersUI.on_click(e, us.transfers, UI.close) then
    UI.refresh(player)
    return true
  end
  local chart = chart_state(us)
  local previous = chart.focus
  local r = SK.on_click(e, chart)
  if r then
    if r ~= "none" then
      local action = el.tags.ssk_sk
      local graph_only = action == "zoom_in" or action == "zoom_out" or action == "zoom_fit"
        or action == "center_selection" or action == "reflow"
      refresh_material(player, chart, previous, false, graph_only)
    end
    return true
  end
  local a = el.tags and el.tags.ssk_ui
  if not a then return false end
  if a == "close" then UI.close(player)
  elseif a == "cells" then UI.close(player); Cells.open(player)
  elseif a == "cell_new" and us.tab_id == "cells" then
    UI.close(player)
    Cells.on_click(player, { tags = { ssk_cell = "select" } })
  elseif a == "cell_select" and us.tab_id == "cells" then
    local state = us.cells
    local id = el.tags.cell_id ~= 0 and el.tags.cell_id or nil
    if el.tags.ancestor then
      while #state.path > el.tags.depth do table.remove(state.path) end
      state.scope = state.path[#state.path]
    end
    state.selected, state.chart = id, {}
    state.rail = { axis = state.rail and state.rail.axis }
    UI.refresh(player)
  elseif a == "cell_drill" and us.tab_id == "cells" then
    local state = us.cells
    state.path = state.path or {}
    state.path[#state.path + 1] = el.tags.cell_id
    state.scope, state.selected, state.chart = el.tags.cell_id, nil, {}
    state.rail = { axis = state.rail and state.rail.axis }
    UI.refresh(player)
  elseif a == "cell_subdivide" and us.tab_id == "cells" and us.cells.selected then
    local id = us.cells.selected
    UI.close(player)
    Cells.start_child(player, id)
  elseif a == "cell_edit" and us.tab_id == "cells" and (el.tags.cell_id or us.cells.selected) then
    local id = el.tags.cell_id or us.cells.selected
    UI.close(player)
    Cells.on_click(player, { tags = { ssk_cell = "edit", cell_id = id } })
  elseif a == "cell_jump" and us.tab_id == "cells" then
    jump_to_map(player, us.cells)
  elseif a == "rail_train_jump" and us.tab_id == "cells" then
    local train = el.tags.train_id and game.train_manager and game.train_manager.get_train_by_id(el.tags.train_id)
    local carriages = train and train.valid and train.carriages
    local anchor = carriages and carriages[math.ceil(#carriages / 2)]
    if anchor and anchor.valid and anchor.surface then
      UI.close(player)
      player.set_controller { type = defines.controllers.remote, position = anchor.position, surface = anchor.surface }
      player.centered_on = anchor
    end
  elseif a == "cell_map_pan" and us.tab_id == "cells" then
    CellsUI.pan(us.cells, el.tags.dx, el.tags.dy)
    UI.refresh(player)
  elseif a == "cell_map_fit" and us.tab_id == "cells" then
    CellsUI.fit(us.cells)
    UI.refresh(player)
  elseif a == "cell_delete" and us.tab_id == "cells" and us.cells.selected then
    Cells.prompt_delete(player, us.cells.selected, true, UI.close)
  elseif a == "help" or (a == "cell_create_help" and us.tab_id == "cells") then
    close_inspectors(player)
    Help.open(player, a == "cell_create_help" and "cells" or nil)
  elseif a == "help_close" then Help.close(player);player.opened=player.gui.screen[WIN]
  elseif a == "watch" or a == "machine_status" then
    local material = chart.focus
    if a == "machine_status" and us.tab_id == "sankey" then
      material = el.tags.key
    elseif us.tab_id ~= "balance" and not (us.tab_id == "focus" and a == "machine_status") then
      return true
    end
    if not material then return true end
    local surface = sidx_for(player, us)
    MaterialPicker.close(player)
    Help.close(player)
    if a == "watch" then
      MachineStatus.close(player)
      if not Watch.close(player) then Watch.open(player, us, surface, material) end
    else
      Watch.close(player)
      MachineStatus.open(player, surface, material)
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
  elseif a == "refresh" then
    if us.tab_id=="transfers" and us.se_logistics then us.se_logistics.rescan_endpoints=true end
    UI.refresh(player, false, false, false, true)
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
  elseif a == "sankey_material_tab" and us.tab_id == "sankey" then
    local key, target = el.tags.key, el.tags.target
    if type(key) ~= "string" then return true end
    local kind, name = key:match("^(%a+)/(.+)$")
    if (kind ~= "item" and kind ~= "fluid") or not prototypes[kind][name] then return true end
    if target ~= "focus" and target ~= "balance" then return true end
    local fx = target == "balance" and SK.balance_state(us) or SK.focus_state(us)
    if SK.select_focus(fx, key) then fx.pinned = nil end
    if target == "balance" then us.bal_mode = "flow" end
    us.tab_id = target
    UI.open(player)
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
  local tags = e.element and e.element.valid and e.element.tags
  if tags and tags.ssk_cell_list_surface then
    Cells.on_list_surface(game.get_player(e.player_index), e.element)
    return
  end
  if tags and tags.ssk_rail_role then
    Cells.on_rail_role(game.get_player(e.player_index), e.element)
    return true
  end
  local handled, key, target = MaterialPicker.selection(e)
  if handled then
    if key then
      local player = game.get_player(e.player_index)
      local us = ustate(e.player_index)
      if target == "cell" then
        Cells.pick_display_item(player, key)
      elseif target == "cell-inputs" or target == "cell-outputs" then
        Cells.pick_port(player, target:sub(6), key)
      elseif target == us.tab_id and (target == "focus" or target == "balance") then
        local chart = chart_state(us)
        local previous = chart.focus
        if target == "focus" then
          chart.focus, chart.sel, chart.pinned = key, nil, nil
          chart.focus_hist, chart.focus_forward = {}, {}
        else
          SK.select_focus(chart, key)
        end
        refresh_material(player, chart, previous, false)
      end
    end
    return true
  end
  local tags = e.element.tags
  local us = ustate(e.player_index)
  if us.tab_id=="transfers" and us.transport_history then
    local handled=TransportHistoryUI.on_selection(e,us)
    if handled then
      local player=game.get_player(e.player_index)
      if handled=="reopen" then UI.open(player) else UI.refresh(player) end
      return true
    end
  end
  if us.tab_id=="transfers" and SERockets.available() and SELogisticsUI.on_selection(e,us.se_logistics or {}) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if us.tab_id == "transfers" and TransfersUI.on_selection(e, us.transfers) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if tags and tags.ssk_ui == "cell_list" and us.tab_id == "cells" then
    local state = us.cells
    local entry = state.nav_rows and state.nav_rows[e.element.selected_index]
    if not entry then return true end
    if entry.ancestor then
      while #state.path > entry.depth do table.remove(state.path) end
      state.scope = state.path[#state.path]
    end
    state.selected = entry.id
    us.cells.chart = {}
    us.cells.rail = { axis = us.cells.rail and us.cells.rail.axis }
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if tags and tags.ssk_rail_select and us.tab_id == "cells" and CellsUI.rail_view(us.cells)
    and RailUI.on_selection(e.element, us.cells) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if tags and tags.ssk_ui == "period" then
    local period = Sampler.PERIODS[e.element.selected_index] or Sampler.DEFAULT_PERIOD
    if us.period ~= period then
      Watch.reset_pending(us)
      if us.cells and us.cells.rail then RailUI.reset_history(us.cells.rail) end
    end
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
  local element = e.element
  local axis = element.valid and element.tags.ssk_scroll_visual
  if axis then
    -- Clicking the main window can cover sibling frames. Expose the grip when
    -- the pointer next reaches the visible thumb, even without a title-bar drag.
    if entering then
      local player = game.get_player(e.player_index)
      local thumb = player.gui.screen[THUMBS[axis]]
      if thumb and player.opened == player.gui.screen[WIN] then thumb.bring_to_front() end
    end
    return true
  end
  return RailUI.on_hover(e.element, entering) or HistoryUI.on_hover(e, entering) or SK.on_hover(e, entering)
end

function UI.on_checked(e)
  local u0 = ustate(e.player_index)
  if u0.tab_id=="transfers" and SERockets.available() and SELogisticsUI.on_checked(e,u0.se_logistics or {}) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
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

function UI.on_switch(e)
  local us=ustate(e.player_index)
  local el=e.element
  if us.tab_id == "cells" and el and el.valid and CellsUI.rail_view(us.cells) and RailUI.on_switch(el, us.cells) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if us.tab_id=="cells" and el and el.valid and el.tags and el.tags.ssk_ui=="cell_mode" then
    us.cells=us.cells or {}
    us.cells.mode=el.switch_state=="right" and "capacity" or "measured"
    us.cells.chart={}
    UI.refresh(game.get_player(e.player_index),false,true)
    return true
  end
  if us.tab_id~="transfers" then return false end
  local handled
  if us.transport_history then
    handled=TransferPanels.on_switch(e,us.transport_history)
  elseif SERockets.available() and not Transfers.available() then
    local state=us.se_logistics
    handled=state and state.view=="history" and TransferPanels.on_switch(e,state)
  else
    handled=TransfersUI.on_switch(e,us.transfers)
  end
  if handled then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  if us.tab_id=="transfers" and SERockets.available() and SELogisticsUI.on_switch(e,us.se_logistics or {}) then
    UI.refresh(game.get_player(e.player_index))
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
  if us.tab_id=="transfers" and us.transport_history then
    local handled=TransportHistoryUI.on_selection(e,us)
    if handled then
      if handled=="reopen" then UI.open(player) else UI.refresh(player) end
      return true
    end
  end
  if us.tab_id=="transfers" and SERockets.available() and SELogisticsUI.on_selection(e,us.se_logistics or {}) then
    UI.refresh(player)
    return true
  end
  if f.name == "ssk_cell_views" and us.tab_id == "cells" then
    local index = f.selected_tab_index
    close_chart_settings(us)
    us.cells.view = index == 2 and "map" or index == 3 and "train_stops" or index == 4 and "train_history" or nil
    UI.refresh(player)
    return true
  end
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
  if e.element and e.element.valid and e.element.name == Cells.DELETE_NAME then
    finish_cell_delete(player, false)
    return true
  end
  if e.element and e.element.valid and e.element.name == Cells.NAME then
    if player.gui.screen.ssk_material_picker then
      MaterialPicker.close(player)
      player.opened = e.element
    else
      Cells.cancel(player)
    end
    return true
  end
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
  local el = e.element
  if not (el and el.valid) then return end
  local player = game.get_player(e.player_index)
  if el.tags.ssk_ui == "cell_map_zoom" then
    local state = ustate(e.player_index).cells
    local view = state and CellsUI.zoom(state, el.slider_value)
    if view then
      el.parent.parent.ssk_cell_camera.zoom = view.zoom
    end
    return true
  elseif el.tags.ssk_ui == "rail_preview_zoom" then
    local state = ustate(e.player_index).cells
    if state and state.rail then
      local zoom = math.max(0.05, math.min(2, el.slider_value))
      state.rail.preview_zoom = zoom
      local camera = el.parent.parent.ssk_rail_camera
      if camera and camera.valid then camera.zoom = zoom end
    end
    return true
  end
  return MachineStatus.on_value_changed(player, el)
end

function UI.on_text_changed(e)
  local us=ustate(e.player_index)
  if us.tab_id=="transfers" and TransportHistoryUI.on_text_changed(e,us) then
    UI.refresh(game.get_player(e.player_index));return true
  end
  if us.tab_id=="transfers" and SERockets.available() and SELogisticsUI.on_text_changed(e,us.se_logistics or {}) then
    UI.refresh(game.get_player(e.player_index))
    return true
  end
  return MaterialPicker.on_text_changed(e)
end
function UI.on_string_translated(e)
  MaterialPicker.on_translated(e)
  local us=ustate(e.player_index)
  if TransportHistoryUI.on_translated(e,us) and us.tab_id=="transfers" then
    UI.refresh(game.get_player(e.player_index));return
  end
  if us.se_logistics and SELogisticsUI.on_translated(e,us.se_logistics) and us.tab_id=="transfers" and us.se_logistics.view=="items" then
    UI.refresh(game.get_player(e.player_index))
  end
end

function UI.auto_refresh(phase, slots)
  for _, p in pairs(game.connected_players) do
    if (not phase or p.index % slots == phase % slots) and UI.is_open(p) then UI.refresh(p, true) end
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

function UI.on_force_changed(player)
  UI.ensure_button(player)
  if player.force~=game.forces.player then UI.close(player)
  elseif UI.is_open(player) then UI.open(player) end
end

return UI
