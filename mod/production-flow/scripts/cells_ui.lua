local Cells = require("scripts.cells")
local Flow = require("scripts.cell_flow")
local Loc = require("scripts.locale")
local SK = require("scripts.sankey_ui")
local Sampler = require("scripts.sampler")
local Su = require("scripts.surfaces")

local UI = {}
-- Vanilla tab strip and its top content padding, as on the Balance tab.
local TAB_HEADER = 48
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

local function clamp_zoom(zoom) return math.max(UI.ZOOM_MIN, math.min(UI.ZOOM_MAX, zoom)) end

-- The Map tab's view of the selected cell, or of every listed cell for All.
-- It is fitted to the machines' current positions on each refresh; once the
-- player zooms or moves, their view is kept until Fit or a surface change.
function UI.map_view(state, records, ids)
  local key = state.selected or "all"
  local chosen = {}
  if state.selected then chosen[1] = records[state.selected]
  else for _, id in ipairs(ids) do chosen[#chosen + 1] = records[id] end end
  local center, w, h = UI.area(table.unpack(chosen))
  if not center then state.fitted = nil; return end
  local cam_w, cam_h = state.map_w or 600, state.map_h or 400
  local fitted = { key = key, x = center.x, y = center.y, surface = chosen[1].surface_index,
    zoom = clamp_zoom(math.min(UI.FIT_MAX, cam_w / (w * 32), cam_h / (h * 32))) }
  state.fitted = fitted
  local own = state.maps and state.maps[key]
  if own and own.surface == fitted.surface then return own end
  if own then state.maps[key] = nil end
  return fitted
end

-- The player's own view of the shown cell, started from the fitted one.
function UI.own_view(state)
  local key = state.selected or "all"
  state.maps = state.maps or {}
  local fitted = state.fitted
  if not state.maps[key] and fitted and fitted.key == key then
    state.maps[key] = { x = fitted.x, y = fitted.y, surface = fitted.surface, zoom = fitted.zoom }
  end
  return state.maps[key]
end

-- Where the Map tab is looking now.
function UI.current_view(state)
  local key = state.selected or "all"
  local fitted = state.fitted
  return state.maps and state.maps[key] or (fitted and fitted.key == key and fitted or nil)
end

-- Moves the view a quarter of the visible map in a direction.
function UI.pan(state, dx, dy)
  local view = UI.own_view(state)
  if not view then return end
  view.x = view.x + dx * (state.map_w or 600) / (32 * view.zoom) / 4
  view.y = view.y + dy * (state.map_h or 400) / (32 * view.zoom) / 4
end

function UI.zoom(state, zoom)
  local view = UI.own_view(state)
  if view then view.zoom = clamp_zoom(zoom) end
  return view
end

function UI.fit(state)
  if state.maps then state.maps[state.selected or "all"] = nil end
end

local function map_button(bar, sprite, tooltip, tags)
  return bar.add { type = "sprite-button", style = "tool_button", sprite = sprite, tooltip = tooltip, tags = tags }
end

local function build_map(map, width, height)
  local bar = map.add { type = "frame", name = "ssk_cell_map_bar", style = "subheader_frame", direction = "horizontal" }
  bar.style.horizontally_stretchable, bar.style.vertical_align = true, "center"
  bar.add { type = "label", name = "ssk_cell_map_heading", style = "subheader_caption_label" }
  bar.add { type = "empty-widget" }.style.horizontally_stretchable = true
  bar.add { type = "label", caption = Loc("machine-status-zoom") }
  local slider = bar.add { type = "slider", name = "ssk_cell_map_zoom", minimum_value = UI.ZOOM_MIN,
    maximum_value = UI.ZOOM_MAX, value = 0.5, value_step = 0.05, tags = { ssk_ui = "cell_map_zoom" } }
  slider.style.width = math.max(80, math.min(160, width - 420))
  for _, move in ipairs({ { "left", -1, 0 }, { "up", 0, -1 }, { "down", 0, 1 }, { "right", 1, 0 } }) do
    map_button(bar, "utility/hint_arrow_" .. move[1], Loc("cells-map-move"),
      { ssk_ui = "cell_map_pan", dx = move[2], dy = move[3] })
  end
  map_button(bar, "utility/center", Loc("cells-map-fit"), { ssk_ui = "cell_map_fit" })
  map_button(bar, "utility/go_to_arrow", Loc("cells-jump"), { ssk_ui = "cell_jump" }).name = "ssk_cell_jump_button"
  map_button(bar, "utility/rename_icon", Loc("cells-edit"), { ssk_ui = "cell_edit" }).name = "ssk_cell_map_edit"
  local camera = map.add { type = "camera", name = "ssk_cell_camera", position = { 0, 0 }, surface_index = 1, zoom = 0.5 }
  camera.style.width, camera.style.height = width, height - MAP_BAR
end

-- Measured (default) shows what the cell's machines actually crafted over the
-- selected period; Capacity shows every member running at full speed.
function UI.mode(state) return state.mode == "capacity" and "capacity" or "measured" end

local function scope_caption(state, graph)
  if graph.mode == "capacity" then
    return state.selected and Loc("cells-flow-modeled")
      or Loc(graph.overlap and "cells-flow-overlap" or "cells-flow-shared")
  end
  -- With no cells measured, the caption still names the period the header selects.
  local period = Sampler.duration(graph.requested or state.period or Sampler.DEFAULT_PERIOD)
  if not state.selected then
    local caption = Loc(graph.overlap and "cells-flow-measured-overlap" or "cells-flow-measured-all", period)
    -- Cells created during the period have less data than the period asks for.
    if graph.newest then return Loc.join(caption, " ", Loc("cells-flow-newest", Sampler.duration(graph.newest))) end
    return caption
  end
  if not graph.utilisation and not next(graph.nodes) then return Loc("cells-flow-no-crafts", period) end
  local used = graph.utilisation and Flow.percent(graph.utilisation) or "—"
  if graph.partial then return Loc("cells-flow-measured-new", Sampler.duration(graph.seconds), used) end
  return Loc("cells-flow-measured", period, used)
end

function UI.fill(player, container, state, width, height, full, only_auto)
  -- Like the other tabs, Cells shows the surface chosen in the window header.
  local records, ids = Flow.records(), Flow.ids(state.sidx)
  local record = state.selected and records[state.selected]
  if not record or (state.sidx and record.surface_index ~= state.sidx) then state.selected = nil end
  local side = math.min(236, math.floor(width * 0.32))
  local split = container.ssk_cell_split
  if full or not split then
    container.clear()
    split = container.add { type = "flow", name = "ssk_cell_split", direction = "horizontal" }
    split.style.horizontal_spacing = 8
    local list = split.add { type = "frame", name = "ssk_cell_sidebar", style = "inside_shallow_frame", direction = "vertical" }
    list.style.width = side
    list.style.height = height
    local bar = list.add { type = "frame", name = "ssk_cell_list_bar", style = "subheader_frame" }
    bar.style.horizontally_stretchable = true
    bar.add { type = "label", style = "subheader_caption_label", caption = Loc("cells-tab") }
    local gap = bar.add { type = "empty-widget" }
    gap.style.horizontally_stretchable = true
    bar.add { type = "sprite-button", name = "ssk_cell_new_button", style = "tool_button",
      sprite = "utility/add", tooltip = Loc("cells-new"), tags = { ssk_ui = "cell_new" } }
    bar.add { type = "sprite-button", name = "ssk_cell_edit_button", style = "tool_button",
      sprite = "utility/rename_icon", tooltip = Loc("cells-edit"), tags = { ssk_ui = "cell_edit" } }
    bar.add { type = "sprite-button", name = "ssk_cell_delete_button", style = "tool_button_red",
      sprite = "utility/trash", tooltip = Loc("cells-delete"), tags = { ssk_ui = "cell_delete" } }
    list.add { type = "list-box", name = "ssk_cell_list", tags = { ssk_ui = "cell_list" } }
    list.ssk_cell_list.style.horizontally_stretchable = true
    list.ssk_cell_list.style.height = height - 40
    -- Flow charts the cells; Map shows where they are, like Balance's Flow and History.
    local views = split.add { type = "tabbed-pane", name = "ssk_cell_views", style = "tabbed_pane_with_no_side_padding",
      tags = { ssk_ui = "cell_views" } }
    views.style.top_margin = 0
    -- A fixed width keeps wide cells inside the window; the chart scrolls instead.
    views.style.width = width - side - 8
    local flow_tab = views.add { type = "tab", caption = Loc("help-flow"), tooltip = Loc("cells-flow-tab") }
    local right = views.add { type = "frame", name = "ssk_cell_chart", style = "inside_deep_frame", direction = "vertical" }
    views.add_tab(flow_tab, right)
    local map_tab = views.add { type = "tab", name = "ssk_cell_map_tab", caption = Loc("cells-map"), tooltip = Loc("cells-map-tab") }
    local map = views.add { type = "frame", name = "ssk_cell_map", style = "inside_deep_frame", direction = "vertical" }
    views.add_tab(map_tab, map)
    for _, panel in ipairs({ right, map }) do
      panel.style.width, panel.style.height = width - side - 8, height - TAB_HEADER
      panel.style.padding = 0
    end
    state.map_w, state.map_h = width - side - 8, height - TAB_HEADER - MAP_BAR
    build_map(map, width - side - 8, height - TAB_HEADER)
    local toolbar = right.add { type = "frame", name = "ssk_cell_toolbar", style = "subheader_frame", direction = "vertical" }
    toolbar.style.horizontally_stretchable = true
    -- subheader_frame is one line tall; let it grow for the wrapped scope text so
    -- the text never overlaps the chart's column headings.
    toolbar.style.minimal_height = 36
    toolbar.style.maximal_height = 96
    toolbar.style.bottom_padding = 4
    local title = toolbar.add { type = "flow", name = "ssk_cell_title", direction = "horizontal" }
    title.style.vertical_align = "center"
    title.add { type = "label", name = "ssk_cell_heading", style = "subheader_caption_label" }
    title.add { type = "empty-widget" }.style.horizontally_stretchable = true
    title.add { type = "switch", name = "ssk_cell_mode", allow_none_state = false,
      left_label_caption = Loc("cells-mode-measured"), right_label_caption = Loc("cells-mode-capacity"),
      left_label_tooltip = Loc("cells-mode-measured-tip"), right_label_tooltip = Loc("cells-mode-capacity-tip"),
      tags = { ssk_ui = "cell_mode" } }
    title.add { type = "empty-widget" }.style.width = 8
    local hint = toolbar.add { type = "label", name = "ssk_cell_scope", style = "grey_label" }
    hint.style.single_line = false
    hint.style.maximal_width = math.max(160, width - side - 28)
    right.add { type = "flow", name = "ssk_cell_plot", direction = "vertical" }
  end
  local items, selected_index, signature = {Loc("cells-all")}, 1, {}
  for i, id in ipairs(ids) do
    -- Cells with members removed from the map carry the saved-cells list's warning.
    local missing = Cells.missing(records[id])
    items[i + 1] = missing > 0 and Loc.join("[img=utility/warning_icon] ", records[id].name) or records[id].name
    signature[i] = id .. (missing > 0 and "!" or "")
    if state.selected == id then selected_index = i + 1 end
  end
  local sidebar = split.ssk_cell_sidebar
  local list_bar = sidebar.ssk_cell_list_bar
  list_bar.ssk_cell_edit_button.enabled = state.selected ~= nil
  list_bar.ssk_cell_delete_button.enabled = state.selected ~= nil
  local rows = sidebar.ssk_cell_list
  local listed = table.concat(signature, ",")
  if full or state.listed ~= listed then rows.items = items end
  state.listed = listed
  rows.selected_index = selected_index
  state.ids = ids
  local views = split.ssk_cell_views
  local view = UI.map_view(state, records, ids)
  views.ssk_cell_map_tab.enabled = view ~= nil
  if not view then state.view = nil end
  views.selected_tab_index = state.view == "map" and 2 or 1
  if view then
    local map = views.ssk_cell_map
    local bar = map.ssk_cell_map_bar
    bar.ssk_cell_map_heading.caption = state.selected and records[state.selected].name or Loc("cells-all")
    bar.ssk_cell_map_zoom.slider_value = view.zoom
    bar.ssk_cell_map_edit.enabled = state.selected ~= nil
    local camera = map.ssk_cell_camera
    camera.surface_index, camera.position, camera.zoom = view.surface, { view.x, view.y }, view.zoom
  end
  -- The chart is rebuilt when Flow is shown again.
  if state.view == "map" then state.rendered_selection = false; return end
  local mode = UI.mode(state)
  local graph = Flow.build(state.selected, { mode = mode, period = state.period, surface = state.sidx })
  local right = views.ssk_cell_chart
  local bar = right.ssk_cell_toolbar
  bar.ssk_cell_title.ssk_cell_heading.caption = state.selected and records[state.selected].name or Loc("cells-all")
  bar.ssk_cell_title.ssk_cell_mode.switch_state = mode == "capacity" and "right" or "left"
  bar.ssk_cell_scope.caption = scope_caption(state, graph)
  graph.empty = #ids == 0 and Loc("cells-empty-surface", Su.rich(state.sidx and game.surfaces[state.sidx] or player.surface))
    or mode == "measured" and Loc("cells-flow-no-crafts", Sampler.duration(graph.requested or state.period or Sampler.DEFAULT_PERIOD))
    or Loc("cells-flow-empty")
  local chart = state.chart
  chart.show_labels, chart.split_raw = true, false
  local changed = state.rendered_selection ~= state.selected
  state.rendered_selection = state.selected
  local plot = right.ssk_cell_plot
  SK.fill(player, plot, chart, width - side - 28, math.max(100, height - TAB_HEADER - (width >= 780 and 58 or 88)),
    full or changed, only_auto, graph)
  -- Cap the viewport to the frame so content wider than the chart scrolls.
  if plot.ssk_sp then plot.ssk_sp.style.maximal_width = width - side - 16 end
end

return UI
