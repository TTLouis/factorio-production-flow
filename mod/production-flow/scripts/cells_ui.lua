local Cells = require("scripts.cells")
local Outlines = require("scripts.cell_outlines")
local Flow = require("scripts.cell_flow")
local Loc = require("scripts.locale")
local SK = require("scripts.sankey_ui")
local Sampler = require("scripts.sampler")
local Su = require("scripts.surfaces")
local RailUI = require("scripts.cell_rail_ui")

local UI = {}
local function roman(depth)
  local values, symbols = { 10, 9, 5, 4, 1 }, { string.char(88), string.char(73, 88), string.char(86), string.char(73, 86), string.char(73) }
  local parts = {}
  for i, value in ipairs(values) do
    while depth >= value do parts[#parts + 1] = symbols[i]; depth = depth - value end
  end
  return table.concat(parts)
end
-- Vanilla tab strip and its top content padding, as on the Balance tab.
local TAB_HEADER = 48
local VIEW_PADDING = 8
local MAP_BAR = 40
UI.ZOOM_MIN, UI.ZOOM_MAX = 0.05, 2

-- Centre and size (tiles) of the area the cells' machines cover.
function UI.area(...)
  local x1, y1, x2, y2
  for _, record in ipairs({ ... }) do
    for unit, p in pairs(record.positions or {}) do
      local entity = record.members[unit]
      if entity and entity.valid then p = entity.position end
      x1, y1 = math.min(x1 or p.x, p.x), math.min(y1 or p.y, p.y)
      x2, y2 = math.max(x2 or p.x, p.x), math.max(y2 or p.y, p.y)
    end
  end
  if not x1 then return end
  return { x = (x1 + x2) / 2, y = (y1 + y2) / 2 }, x2 - x1 + 6, y2 - y1 + 6
end

-- Fitting never zooms in past normal map scale; the slider goes further.
UI.FIT_MAX = 1
-- The fitted view leaves some room around the machines.
UI.FIT_MARGIN = 0.8
-- Each move button shifts the view by this share of the visible map.
UI.PAN_STEP = 1 / 8

local function clamp_zoom(zoom) return math.max(UI.ZOOM_MIN, math.min(UI.ZOOM_MAX, zoom)) end

-- The Map tab's view of the selected cell, or of every listed cell for All.
-- It is fitted to the machines' current positions on each refresh; once the
-- player zooms or moves, their view is kept until Fit or a surface change.
function UI.map_view(state, records, ids)
  local key = state.selected or (state.scope and ("scope-" .. state.scope) or "all")
  local chosen = {}
  if state.selected then chosen[1] = records[state.selected]
  else for _, id in ipairs(ids) do chosen[#chosen + 1] = records[id] end end
  local center, w, h = UI.area(table.unpack(chosen))
  if not center then state.fitted = nil; return end
  local cam_w, cam_h = state.map_w or 600, state.map_h or 400
  local fitted = { key = key, x = center.x, y = center.y, surface = chosen[1].surface_index,
    zoom = clamp_zoom(UI.FIT_MARGIN * math.min(UI.FIT_MAX, cam_w / (w * 32), cam_h / (h * 32))) }
  state.fitted = fitted
  local own = state.maps and state.maps[key]
  if own and own.surface == fitted.surface then return own end
  if own then state.maps[key] = nil end
  return fitted
end

-- The player's own view of the shown cell, started from the fitted one.
function UI.own_view(state)
  local key = state.selected or (state.scope and ("scope-" .. state.scope) or "all")
  state.maps = state.maps or {}
  local fitted = state.fitted
  if not state.maps[key] and fitted and fitted.key == key then
    state.maps[key] = { x = fitted.x, y = fitted.y, surface = fitted.surface, zoom = fitted.zoom }
  end
  return state.maps[key]
end

-- Where the Map tab is looking now.
function UI.current_view(state)
  local key = state.selected or (state.scope and ("scope-" .. state.scope) or "all")
  local fitted = state.fitted
  return state.maps and state.maps[key] or (fitted and fitted.key == key and fitted or nil)
end

-- Ensures a map view and cell outlines exist even when jumping from the Flow sub-tab.
function UI.jump_target(player, state)
  local records = Flow.records()
  local ids
  if state.ids then
    ids = {}
    for _, id in ipairs(state.ids) do
      if records[id] then ids[#ids + 1] = id end
    end
  else
    ids = Flow.ids(state.sidx, state.scope)
  end
  local view = UI.map_view(state, records, ids)
  local shown = state.selected and records[state.selected] and { state.selected } or ids
  if view and #shown > 0 then
    Outlines.show(player, records, shown)
  end
  return view
end

-- Moves the view a small step of the visible map in a direction.
function UI.pan(state, dx, dy)
  local view = UI.own_view(state)
  if not view then return end
  view.x = view.x + dx * (state.map_w or 600) / (32 * view.zoom) * UI.PAN_STEP
  view.y = view.y + dy * (state.map_h or 400) / (32 * view.zoom) * UI.PAN_STEP
end

function UI.zoom(state, zoom)
  local view = UI.own_view(state)
  if view then view.zoom = clamp_zoom(zoom) end
  return view
end

function UI.fit(state)
  if state.maps then state.maps[state.selected or (state.scope and ("scope-" .. state.scope) or "all")] = nil end
end

local function map_button(bar, sprite, tooltip, tags)
  return bar.add { type = "sprite-button", style = "tool_button", sprite = sprite, tooltip = tooltip, tags = tags }
end

-- The selected cell's subdivision and Delete actions in the Flow and Map toolbars.
local function cell_actions(bar, edit_name, delete_name)
  bar.add { type = "sprite-button", name = edit_name .. "_subdivide", style = "tool_button",
    sprite = "utility/add", tooltip = Loc("cells-add-subdivision"), tags = { ssk_ui = "cell_subdivide" } }
  bar.add { type = "sprite-button", name = delete_name, style = "tool_button_red",
    sprite = "utility/trash", tooltip = Loc("cells-delete"), tags = { ssk_ui = "cell_delete" } }
end

local function build_map(map, width, height)
  local bar = map.add { type = "frame", name = "ssk_cell_map_bar", style = "subheader_frame", direction = "horizontal" }
  bar.style.horizontally_stretchable, bar.style.vertical_align = true, "center"
  bar.add { type = "label", name = "ssk_cell_map_heading", style = "subheader_caption_label" }
  bar.add { type = "empty-widget" }.style.horizontally_stretchable = true
  bar.add { type = "label", caption = Loc("machine-status-zoom") }
  local slider = bar.add { type = "slider", name = "ssk_cell_map_zoom", minimum_value = UI.ZOOM_MIN,
    maximum_value = UI.ZOOM_MAX, value = 0.5, value_step = 0.05, tags = { ssk_ui = "cell_map_zoom" } }
  slider.style.width = math.max(80, math.min(160, width - 460))
  for _, move in ipairs({ { "left", -1, 0 }, { "up", 0, -1 }, { "down", 0, 1 }, { "right", 1, 0 } }) do
    map_button(bar, "utility/hint_arrow_" .. move[1], Loc("cells-map-move"),
      { ssk_ui = "cell_map_pan", dx = move[2], dy = move[3] })
  end
  map_button(bar, "utility/center", Loc("cells-map-fit"), { ssk_ui = "cell_map_fit" })
  map_button(bar, "utility/map", Loc("cells-jump"), { ssk_ui = "cell_jump" }).name = "ssk_cell_jump_button"
  cell_actions(bar, "ssk_cell_map_edit", "ssk_cell_map_delete")
  local camera = map.add { type = "camera", name = "ssk_cell_camera", position = { 0, 0 }, surface_index = 1, zoom = 0.5 }
  camera.style.width, camera.style.height = width, height - MAP_BAR
end

-- Measured (default) shows what the cell's machines actually crafted over the
-- selected period; Capacity shows every member running at full speed.
function UI.mode(state) return state.mode == "capacity" and "capacity" or "measured" end

function UI.rail_view(state)
  return state and (state.view == "train_stops" or state.view == "train_history")
end

function UI.fill(player, container, state, width, height, full, only_auto)
  -- Like the other tabs, Cells shows the surface chosen in the window header.
  local records = Flow.records()
  -- A path may become stale when another player edits or deletes a cell.
  local path, parent = {}, nil
  for _, id in ipairs(state.path or {}) do
    local entry = records[id]
    if not entry or entry.parent_id ~= parent or (state.sidx and entry.surface_index ~= state.sidx) then break end
    path[#path + 1], parent = id, id
  end
  state.path, state.scope = path, parent
  local ids = Flow.ids(state.sidx, state.scope)
  local record = state.selected and records[state.selected]
  if not record or (state.sidx and record.surface_index ~= state.sidx)
    or (record.parent_id ~= state.scope and record.id ~= state.scope) then state.selected = nil end
  local stops, rail_groups = RailUI.scope(records, ids, state.selected)
  local has_rail = next(stops) ~= nil
  if not has_rail and UI.rail_view(state) then state.view = nil end
  local side = math.min(236, math.floor(width * 0.32))
  local view_width, view_height = width - side - 8, height - TAB_HEADER
  local content_width, content_height = view_width - 2 * VIEW_PADDING, view_height - 2 * VIEW_PADDING
  local split = container.ssk_cell_split
  if full or not split or split.tags.ssk_cells_view_padding ~= VIEW_PADDING or state.had_rail ~= has_rail then
    state.had_rail, state.listed = has_rail, nil
    container.clear()
    split = container.add { type = "flow", name = "ssk_cell_split", direction = "horizontal",
      tags = { ssk_cells_view_padding = VIEW_PADDING } }
    split.style.horizontal_spacing = 8
    local list = split.add { type = "frame", name = "ssk_cell_sidebar", style = "inside_shallow_frame", direction = "vertical" }
    list.style.width = side
    list.style.height = height
    local bar = list.add { type = "frame", name = "ssk_cell_list_bar", style = "subheader_frame" }
    bar.style.horizontally_stretchable = true
    bar.add { type = "label", style = "subheader_caption_label", caption = Loc("cells-tab") }
    local gap = bar.add { type = "empty-widget" }
    gap.style.horizontally_stretchable = true
    bar.add { type = "sprite-button", name = "ssk_cell_create_help", style = "tool_button",
      sprite = "utility/questionmark", tooltip = Loc("cells-create-help"), tags = { ssk_ui = "cell_create_help" } }
    bar.add { type = "sprite-button", name = "ssk_cell_new_button", style = "tool_button",
      sprite = "utility/add", tooltip = Loc.join(Loc("cells-new"), "\n\n", Loc("cells-first-drag-tip")),
      tags = { ssk_ui = "cell_new" } }
    -- Flow charts the cells; Map shows where they are, like Balance's Flow and History.
    local views = split.add { type = "tabbed-pane", name = "ssk_cell_views", style = "tabbed_pane_with_no_side_padding",
      tags = { ssk_ui = "cell_views" } }
    views.style.top_margin = 0
    -- A fixed width keeps wide cells inside the window; the chart scrolls instead.
    views.style.width = view_width
    local flow_tab = views.add { type = "tab", caption = Loc("help-flow"), tooltip = Loc("cells-flow-tab") }
    local right = views.add { type = "frame", name = "ssk_cell_chart", style = "inside_deep_frame", direction = "vertical" }
    views.add_tab(flow_tab, right)
    local map_tab = views.add { type = "tab", name = "ssk_cell_map_tab", caption = Loc("cells-map"), tooltip = Loc("cells-map-tab") }
    local map = views.add { type = "frame", name = "ssk_cell_map", style = "inside_deep_frame", direction = "vertical" }
    views.add_tab(map_tab, map)
    local panels = {right, map}
    if has_rail then
      for _, spec in ipairs({
        { "ssk_cell_train_stops", Loc("rail-stops") },
        { "ssk_cell_train_history", Loc("rail-history") },
      }) do
        local tab = views.add { type = "tab", caption = spec[2] }
        local panel = views.add { type = "frame", name = spec[1], style = "inside_deep_frame", direction = "vertical" }
        views.add_tab(tab, panel)
        panels[#panels + 1] = panel
      end
    end
    for _, panel in ipairs(panels) do
      panel.style.width, panel.style.height = view_width, view_height
      panel.style.padding = VIEW_PADDING
    end
    state.map_w, state.map_h = content_width, content_height - MAP_BAR
    build_map(map, content_width, content_height)
    local toolbar = right.add { type = "frame", name = "ssk_cell_toolbar", style = "subheader_frame", direction = "vertical" }
    toolbar.style.horizontally_stretchable = true
    local title = toolbar.add { type = "flow", name = "ssk_cell_title", direction = "horizontal" }
    title.style.vertical_align = "center"
    title.add { type = "label", name = "ssk_cell_heading", style = "subheader_caption_label" }
    title.add { type = "empty-widget" }.style.horizontally_stretchable = true
    title.add { type = "switch", name = "ssk_cell_mode", allow_none_state = false,
      left_label_caption = Loc("cells-mode-measured"), right_label_caption = Loc("cells-mode-capacity"),
      left_label_tooltip = Loc("cells-mode-measured-tip"), right_label_tooltip = Loc("cells-mode-capacity-tip"),
      tags = { ssk_ui = "cell_mode" } }
    title.add { type = "empty-widget" }.style.width = 8
    map_button(title, "utility/map", Loc("cells-jump"), { ssk_ui = "cell_jump" }).name = "ssk_cell_flow_jump"
    SK.zoom_buttons(title, true, state.chart.render_zoom or 1)
    title.add { type = "empty-widget" }.style.width = 6
    SK.label_toggle(title, state.chart)
    SK.settings_button(title, state.chart)
    title.add { type = "empty-widget" }.style.width = 8
    cell_actions(title, "ssk_cell_edit_button", "ssk_cell_delete_button")
    right.add { type = "flow", name = "ssk_cell_plot", direction = "vertical" }.style.horizontally_stretchable = true
  end
  local sidebar = split.ssk_cell_sidebar
  local actions = split.ssk_cell_views.ssk_cell_chart.ssk_cell_toolbar.ssk_cell_title
  actions.ssk_cell_edit_button_subdivide.enabled = state.selected ~= nil
  actions.ssk_cell_delete_button.enabled = state.selected ~= nil
  local children = (storage.production_cells and storage.production_cells.children) or {}
  local items, nav, signature, expanded = { (#path > 0 and Loc("cells-return-all") or Loc("cells-all")) }, { { depth = 0, ancestor = #path > 0 } }, {}, false
  for i = 1, #path - 1 do
    items[#items + 1] = records[path[i]].name
    nav[#nav + 1] = { id = path[i], depth = i, ancestor = true }
  end
  for _, id in ipairs(ids) do
    local missing = Cells.missing(records[id])
    items[#items + 1] = missing > 0 and Loc.join("[img=utility/warning_icon] ", records[id].name) or records[id].name
    local has_children = children[id] and #children[id] > 0
    nav[#nav + 1] = { id = id, expandable = has_children }
    expanded = expanded or has_children
    signature[#signature + 1] = id .. (missing > 0 and "!" or "") .. (has_children and "+" or "") .. records[id].name
  end
  local listed = table.concat(signature, ",") .. ":" .. table.concat(path, ",")
  local rows = sidebar.ssk_cell_list
  if full or state.listed ~= listed or not (rows or sidebar.ssk_cell_list_scroll) then
    if rows then rows.destroy() end
    if sidebar.ssk_cell_list_scroll then sidebar.ssk_cell_list_scroll.destroy() end
    local scroll = sidebar.add { type = "scroll-pane", name = "ssk_cell_list_scroll", style = "naked_scroll_pane",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
    scroll.style.horizontally_stretchable, scroll.style.height = true, height - 40
    local line = scroll.add { type = "flow", name = "ssk_cell_list_line", direction = "horizontal" }
    line.style.horizontal_spacing = 0
    line.style.horizontally_stretchable = true
    rows = line.add { type = "list-box", name = "ssk_cell_list", style = "ssk_layered_cell_list", items = items, tags = { ssk_ui = "cell_list" } }
    rows.style.horizontally_stretchable = true
    rows.style.height = math.max(height - 40, #items * 28 + 4)
    local overlay_w = expanded and 56 or 28
    local badges = line.add { type = "flow", name = "ssk_cell_list_actions", direction = "vertical" }
    badges.style.vertical_spacing = 0
    badges.style.left_margin = -overlay_w
    for _, entry in ipairs(nav) do
      if entry.id and not entry.ancestor then
        local row_flow = badges.add { type = "flow", direction = "horizontal" }
        row_flow.style.horizontal_spacing, row_flow.style.vertical_align = 0, "center"
        row_flow.style.width, row_flow.style.height = overlay_w, 28
        if expanded then
          if entry.expandable then
            local badge = row_flow.add { type = "label", style = "clickable_label", caption = roman(#path + 1),
              tooltip = Loc("cells-drill"), tags = { ssk_ui = "cell_drill", cell_id = entry.id } }
            badge.style.width, badge.style.height = 28, 28
            badge.style.horizontal_align, badge.style.vertical_align = "center", "center"
          else
            local spacer = row_flow.add { type = "empty-widget", ignored_by_interaction = true }
            spacer.style.width, spacer.style.height = 28, 28
          end
        end
        local edit_btn = row_flow.add { type = "sprite-button", style = "tool_button", sprite = "utility/rename_icon",
          tooltip = Loc("cells-edit"), tags = { ssk_ui = "cell_edit", cell_id = entry.id } }
        edit_btn.style.width, edit_btn.style.height = 28, 28
      else
        local spacer = badges.add { type = "empty-widget", ignored_by_interaction = true }
        spacer.style.width, spacer.style.height = overlay_w, 28
      end
    end
    state.listed = listed
  elseif not rows then
    rows = sidebar.ssk_cell_list_scroll.ssk_cell_list_line.ssk_cell_list
  end
  local selected_index = 0
  for i, entry in ipairs(nav) do
    if not entry.ancestor and entry.id == state.selected then selected_index = i; break end
  end
  rows.selected_index = selected_index
  state.nav_rows = nav
  state.ids = ids
  local views = split.ssk_cell_views
  local view
  if state.view == "map" then
    view = UI.map_view(state, records, ids)
    views.ssk_cell_map_tab.enabled = view ~= nil
    if not view then state.view = nil end
  else
    views.ssk_cell_map_tab.enabled = #ids > 0
  end
  if view and state.view == "map" then
    Outlines.show(player, records, state.selected and { state.selected } or ids)
  else
    Outlines.clear(player.index, "map")
  end
  views.selected_tab_index = state.view == "map" and 2
    or state.view == "train_stops" and 3 or state.view == "train_history" and 4 or 1
  if view then
    local map = views.ssk_cell_map
    local bar = map.ssk_cell_map_bar
    bar.ssk_cell_map_heading.caption = state.selected and records[state.selected].name or Loc("cells-all")
    bar.ssk_cell_map_zoom.slider_value = view.zoom
    bar.ssk_cell_map_edit_subdivide.enabled = state.selected ~= nil
    bar.ssk_cell_map_delete.enabled = state.selected ~= nil
    local camera = map.ssk_cell_camera
    camera.surface_index, camera.position, camera.zoom = view.surface, { view.x, view.y }, view.zoom
  end
  -- The chart is rebuilt when Flow is shown again.
  if UI.rail_view(state) then
    local panel = state.view == "train_stops" and views.ssk_cell_train_stops or views.ssk_cell_train_history
    state.rail = state.rail or {}
    RailUI.render(player, panel, stops, rail_groups, state, content_width, content_height)
    state.rendered_selection = false
    return
  end
  if state.view == "map" then state.rendered_selection = false; return end
  local mode = UI.mode(state)
  local graph = Flow.build(state.selected, { mode = mode, period = state.period, surface = state.sidx, scope = state.scope })
  graph.chart_zoom = true
  local right = views.ssk_cell_chart
  local bar = right.ssk_cell_toolbar
  bar.ssk_cell_title.ssk_cell_heading.caption = state.selected and records[state.selected].name or Loc("cells-all")
  bar.ssk_cell_title.ssk_cell_mode.switch_state = mode == "capacity" and "right" or "left"
  graph.empty = #ids == 0 and Loc("cells-empty-surface", Su.rich(state.sidx and game.surfaces[state.sidx] or player.surface))
    or graph.choose_outputs and Loc("cells-choose-outputs")
    or mode == "measured" and Loc("cells-flow-no-crafts", Sampler.duration(graph.requested or state.period or Sampler.DEFAULT_PERIOD))
    or Loc("cells-flow-empty")
  local chart = state.chart
  if chart.show_labels == nil then chart.show_labels = true end
  chart.split_raw, chart.is_cell_chart = false, true
  local changed = state.rendered_selection ~= state.selected
  state.rendered_selection = state.selected
  local plot = right.ssk_cell_plot
  SK.fill(player, plot, chart, content_width - 20, math.max(100, content_height - 40),
    full or changed, only_auto, graph)
  bar.ssk_cell_title.ssk_zoom.caption = SK.zoom_caption(chart)
  bar.ssk_cell_title.ssk_show_labels.state = chart.show_labels == true
  bar.ssk_cell_title.ssk_chart_settings.toggled = chart.settings_open == true
  bar.ssk_cell_title.ssk_cell_flow_jump.enabled = state.selected ~= nil
  -- Cap the viewport to the frame so content wider than the chart scrolls.
  if plot.ssk_sp then plot.ssk_sp.style.maximal_width = content_width end
end

return UI
