local Flow = require("scripts.cell_flow")
local Loc = require("scripts.locale")
local SK = require("scripts.sankey_ui")
local Sampler = require("scripts.sampler")

local UI = {}

-- Measured (default) shows what the cell's machines actually crafted over the
-- selected period; Capacity shows every member running at full speed.
function UI.mode(state) return state.mode == "capacity" and "capacity" or "measured" end

local function scope_caption(state, graph)
  if graph.mode == "capacity" then
    return state.selected and Loc("cells-flow-modeled")
      or Loc(graph.overlap and "cells-flow-overlap" or "cells-flow-shared")
  end
  local period = Sampler.duration(graph.requested or 0)
  if not state.selected then
    return Loc(graph.overlap and "cells-flow-measured-overlap" or "cells-flow-measured-all", period)
  end
  if not graph.utilisation and not next(graph.nodes) then return Loc("cells-flow-no-crafts", period) end
  local used = graph.utilisation and Flow.percent(graph.utilisation) or "—"
  if graph.partial then return Loc("cells-flow-measured-new", Sampler.duration(graph.seconds), used) end
  return Loc("cells-flow-measured", period, used)
end

function UI.fill(player, container, state, width, height, full, only_auto)
  local records, ids = Flow.records(), Flow.ids()
  if state.selected and not records[state.selected] then state.selected = nil end
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
    bar.add { type = "sprite-button", name = "ssk_cell_delete_button", style = "tool_button_red",
      sprite = "utility/trash", tooltip = Loc("cells-delete"), tags = { ssk_ui = "cell_delete" } }
    list.add { type = "list-box", name = "ssk_cell_list", tags = { ssk_ui = "cell_list" } }
    list.ssk_cell_list.style.horizontally_stretchable = true
    list.ssk_cell_list.style.height = height - 40
    local right = split.add { type = "frame", name = "ssk_cell_chart", style = "inside_deep_frame", direction = "vertical" }
    right.style.height = height
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
  local items, selected_index = {Loc("cells-all")}, 1
  for i, id in ipairs(ids) do
    local record = records[id]
    local surface = game.surfaces[record.surface_index]
    items[i + 1] = Loc("cells-list-row", record.name, surface and surface.name or "")
    if state.selected == id then selected_index = i + 1 end
  end
  local sidebar = split.ssk_cell_sidebar
  sidebar.ssk_cell_list_bar.ssk_cell_delete_button.enabled = state.selected ~= nil
  local rows = sidebar.ssk_cell_list
  if full or not state.ids or #state.ids ~= #ids then rows.items = items end
  rows.selected_index = selected_index
  state.ids = ids
  local mode = UI.mode(state)
  local graph = Flow.build(state.selected, { mode = mode, period = state.period })
  local right = split.ssk_cell_chart
  local bar = right.ssk_cell_toolbar
  bar.ssk_cell_title.ssk_cell_heading.caption = state.selected and records[state.selected].name or Loc("cells-all")
  bar.ssk_cell_title.ssk_cell_mode.switch_state = mode == "capacity" and "right" or "left"
  bar.ssk_cell_scope.caption = scope_caption(state, graph)
  graph.empty = #ids == 0 and Loc("cells-empty")
    or mode == "measured" and Loc("cells-flow-no-crafts", Sampler.duration(graph.requested or 0))
    or Loc("cells-flow-empty")
  local chart = state.chart
  chart.show_labels, chart.split_raw = true, false
  local changed = state.rendered_selection ~= state.selected
  state.rendered_selection = state.selected
  SK.fill(player, right.ssk_cell_plot, chart, width - side - 16, math.max(100, height - (width >= 780 and 58 or 88)),
    full or changed, only_auto, graph)
end

return UI
