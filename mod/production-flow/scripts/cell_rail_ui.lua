local Loc = require("scripts.locale")
local Rail = require("scripts.cell_rail")
local History = require("scripts.cell_rail_history")
local Layout = require("scripts.transfer_history_layout")
local Sampler = require("scripts.sampler")

local UI = {}
local role_names = { import = Loc("rail-import"), export = Loc("rail-export"), both = Loc("rail-both") }
local STOP_ROW_CONTENT_HEIGHT = 44
local STOP_ROW_PADDING = 4
local STOP_ROW_HEIGHT = STOP_ROW_CONTENT_HEIGHT + 2 * STOP_ROW_PADDING
local DETAIL_ROW_HEIGHT = 28
local SECTION_GAP = 8

function UI.scope(records, ids, selected)
  local stops, groups, children, visited = {}, {}, {}, {}
  for id, record in pairs(records) do
    if record.parent_id then
      children[record.parent_id] = children[record.parent_id] or {}
      table.insert(children[record.parent_id], id)
    end
  end
  for _, list in pairs(children) do table.sort(list) end
  local function visit(id)
    if visited[id] then return end
    visited[id] = true
    local record = records[id]
    if record and next(record.stops or {}) then
      groups[#groups + 1] = record
      for unit, stop in pairs(record.stops) do stops[unit] = stop end
    end
    for _, child in ipairs(children[id] or {}) do visit(child) end
  end
  for _, id in ipairs(selected and {selected} or ids) do visit(id) end
  return stops, groups
end

function UI.ordered(stops)
  local units = {}
  for unit in pairs(stops) do units[#units + 1] = unit end
  table.sort(units, function(a, b)
    local x, y = Rail.name(stops[a]), Rail.name(stops[b])
    if x ~= y then return x < y end
    return a < b
  end)
  return units
end

local function title(parent, caption, name, tooltip)
  local bar = parent.add { type = "frame", name = name, style = "shallow_frame", direction = "horizontal" }
  bar.style.height, bar.style.padding = Layout.STRIP_HEIGHT, { 0, 12 }
  bar.style.horizontally_stretchable, bar.style.vertical_align = true, "center"
  local label = bar.add { type = "label", style = "subheader_caption_label", caption = caption, tooltip = tooltip }
  label.style.single_line = true
  return label, bar
end

local function headed_caption(entry)
  local count = #entry.headed
  if entry.limit == nil then return tostring(count) end
  local stopped = entry.stopped and 1 or 0
  return tostring(count) .. "/" .. tostring(math.max(0, entry.limit - stopped))
end

local function stopped_caption(entry)
  local stopped = entry.stopped and 1 or 0
  if entry.limit == nil then return tostring(stopped) end
  return tostring(stopped) .. "/" .. tostring(math.min(entry.limit, 1))
end

local function wrapped_label(parent, caption, width, style)
  local label = parent.add { type = "label", style = style or "label", caption = caption }
  label.style.single_line, label.style.maximal_width = false, width
  return label
end

local function scroll(parent, height)
  local pane = parent.add { type = "scroll-pane", style = "naked_scroll_pane", direction = "vertical",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
  pane.style.horizontally_stretchable, pane.style.height = true, height
  return pane
end

local function frame(parent, width)
  local box = parent.add { type = "frame", style = "inside_deep_frame", direction = "vertical" }
  box.style.width, box.style.padding = width, 0
  return box
end

local function section_flow(parent, name, spacing)
  local flow = parent.add { type = "flow", name = name, direction = "vertical" }
  flow.style.vertical_spacing = spacing or 0
  return flow
end

local function section_body(parent, width, caption, tooltip)
  local body = frame(parent, width)
  body.name = "ssk_rail_section_body"
  title(body, caption, "ssk_rail_section_title", tooltip)
  return body
end

local function stop_name(stop, surface, caption)
  return Rail.live_stop(stop, surface) and caption or Loc("rail-missing-stop", caption)
end

local function stock_note(snapshot)
  if snapshot.count == 0 and snapshot.missing == 0 then return Loc("rail-no-buffers") end
  if snapshot.count == 0 then return Loc("rail-missing-buffers", snapshot.missing) end
  return Loc("rail-buffer-empty")
end

local function stop_row(parent, unit, stop, entry, stock, state, width, owner)
  local row = parent.add { type = "frame", style = "inside_deep_frame", direction = "vertical" }
  row.style.horizontally_stretchable, row.style.padding = true, 4
  local caption = stop_name(stop, state.sidx, stock.caption)
  local button = row.add { type = "button", style = "list_box_item", caption = caption,
    tooltip = stop_name(stop, state.sidx, stock.tooltip), tags = { ssk_rail = owner and "jump" or "stop", unit = unit, cell = owner } }
  button.style.width = math.max(70, width - 14)
  button.toggled = not owner and state.rail.stop == unit
  wrapped_label(row, Loc("rail-stop-counts", entry.scheduled, headed_caption(entry), stopped_caption(entry)), width - 16, "grey_label")
  local shown = math.min(3, #stock.items)
  if shown == 0 then wrapped_label(row, stock_note(stock), width - 16, "grey_label") end
  for i = 1, shown do wrapped_label(row, History.material(stock.items[i]), width - 16) end
  if #stock.items > shown then wrapped_label(row, Loc("rail-more-materials", #stock.items - shown), width - 16, "grey_label") end
  if stock.count > 0 and stock.missing > 0 then
    wrapped_label(row, Loc("rail-missing-buffers", stock.missing), width - 16, "grey_label")
  end
end

local function grid(parent, name, columns)
  local result = parent.add { type = "table", name = name, column_count = columns }
  result.style.horizontal_spacing, result.style.vertical_spacing, result.style.cell_padding = 0, 0, 0
  return result
end

local function column_label(parent, caption, width, align, tooltip)
  local label = parent.add { type = "label", style = "semibold_label", caption = caption, tooltip = tooltip }
  label.style.width, label.style.horizontal_align, label.style.single_line = width, align, true
  if align ~= "center" then label.style.padding = { 0, 8 } end
  return label
end

local function compact_stock(stock)
  local item = stock.items[1]
  if not item then return stock_note(stock) end
  local caption = Loc.join(History.material_name(item, true), " ", History.material_count(item))
  if #stock.items > 1 then caption = Loc.join(caption, "  +", tostring(#stock.items - 1)) end
  return caption
end

local function stop_label_style(label, palette, width, height, align)
  label.style = palette
  label.style.width, label.style.height, label.style.single_line = width, height, true
  label.style.horizontal_align, label.style.vertical_align = align, "center"
  if align == "left" then label.style.padding = { 0, 8 } end
end

local function paint_stop_row(button, entering)
  local text = button.parent.ssk_rail_stop_text
  local tags = text.tags
  local hovered = entering == true or (entering == nil and tags.hovered == true)
  local dark = hovered or button.toggled
  if tags.dark ~= dark then
    local palette = dark and "black_label" or "label"
    for _, label in ipairs(text.ssk_rail_stop_station.children) do
      stop_label_style(label, palette, tags.station_width, STOP_ROW_CONTENT_HEIGHT / 2, "left")
    end
    for i = 2, 4 do
      stop_label_style(text.children[i], palette, tags.count_width, STOP_ROW_CONTENT_HEIGHT, "center")
    end
  end
  if tags.dark ~= dark or tags.hovered ~= hovered then
    tags.dark, tags.hovered = dark, hovered
    text.tags = tags
  end
end

local function add_stop_entry(parent, unit, width, station_width, count_width)
  local row = parent.add { type = "flow", direction = "vertical" }
  row.style.vertical_spacing = 0
  local button = row.add { type = "button", name = "ssk_rail_stop_button", style = "list_box_item",
    raise_hover_events = true, tags = { ssk_rail = "stop", unit = unit } }
  button.style.width, button.style.height, button.style.margin = width, STOP_ROW_HEIGHT, 0
  -- Use one native row background and let the text pass clicks through to it.
  local text = row.add { type = "flow", name = "ssk_rail_stop_text", direction = "horizontal",
    ignored_by_interaction = true, tags = { station_width = station_width, count_width = count_width } }
  text.style.height, text.style.top_margin, text.style.horizontal_spacing = STOP_ROW_HEIGHT, -STOP_ROW_HEIGHT, 0
  text.style.top_padding, text.style.bottom_padding = STOP_ROW_PADDING, STOP_ROW_PADDING
  local station = text.add { type = "flow", name = "ssk_rail_stop_station", direction = "vertical" }
  station.style.vertical_spacing = 0
  station.add { type = "label", name = "ssk_rail_stop_name" }
  station.add { type = "label", name = "ssk_rail_stop_stock" }
  text.add { type = "label", name = "ssk_rail_stop_scheduled" }
  text.add { type = "label", name = "ssk_rail_stop_headed" }
  text.add { type = "label", name = "ssk_rail_stop_stopped" }
  paint_stop_row(button)
end

local function cell_stop_list(parent, role, stops, units, live, stocks, state, width, height)
  local listed = {}
  for _, unit in ipairs(units) do
    local stop = stops[unit]
    if stop.role == role or stop.role == "both" then
      listed[#listed + 1] = unit
    end
  end
  local rows_height = height - Layout.STRIP_HEIGHT - Layout.ROW_HEIGHT - 4
  local overflow = #listed * STOP_ROW_HEIGHT > rows_height
  local table_width = width - 4 - (overflow and Layout.SCROLL_GUTTER or 0)
  local count_width = math.max(46, math.floor(table_width * 0.16))
  local station_width = table_width - 3 * count_width
  local signature = table.concat(listed, ",")
  local body = parent.ssk_rail_section_body
  local list = body and body.ssk_rail_stop_rows
  local rows = list and list.ssk_rail_stop_entries
  local tags = parent.tags
  if not body or tags.units ~= signature or tags.row_height ~= STOP_ROW_HEIGHT or (#listed > 0 and not rows) then
    parent.clear()
    parent.tags = { units = signature, row_height = STOP_ROW_HEIGHT }
    body = section_body(parent, width, role_names[role])
    local headings = Layout.columns(body, "ssk_rail_stop_headings", width - 4)
    local headers = grid(headings, nil, 4)
    column_label(headers, Loc("rail-stop"), station_width, "left")
    column_label(headers, Loc("rail-scheduled-heading"), count_width, "center", Loc("rail-scheduled-tip"))
    column_label(headers, Loc("rail-headed-heading"), count_width, "center", Loc("rail-headed-tip"))
    column_label(headers, Loc("rail-stopped-heading"), count_width, "center", Loc("rail-stopped-tip"))
    list = scroll(body, rows_height)
    list.name = "ssk_rail_stop_rows"
    list.vertical_scroll_policy = overflow and "auto" or "dont-show-but-allow-scrolling"
    if #listed == 0 then
      local empty = wrapped_label(list, Loc("rail-no-stops"), width - 24, "grey_label")
      empty.style.padding = { 4, 8 }
    else
      rows = list.add { type = "flow", name = "ssk_rail_stop_entries", direction = "vertical" }
      rows.style.vertical_spacing = 0
      for _, unit in ipairs(listed) do add_stop_entry(rows, unit, table_width, station_width, count_width) end
    end
  end
  if #listed == 0 then return end
  local children = rows.children
  for i, unit in ipairs(listed) do
    local entry, stock = live[unit], stocks[unit]
    local name = stop_name(stops[unit], state.sidx, stock.caption)
    local summary = {stop_name(stops[unit], state.sidx, stock.tooltip)}
    for j = 1, math.min(3, #stock.items) do summary[#summary + 1] = History.material(stock.items[j]) end
    if #stock.items == 0 then summary[#summary + 1] = stock_note(stock) end
    if #stock.items > 3 then summary[#summary + 1] = Loc("rail-more-materials", #stock.items - 3) end
    local row = children[i]
    local button, text = row.ssk_rail_stop_button, row.ssk_rail_stop_text
    local station = text.ssk_rail_stop_station
    station.ssk_rail_stop_name.caption, station.ssk_rail_stop_stock.caption = name, compact_stock(stock)
    text.ssk_rail_stop_scheduled.caption = tostring(entry.scheduled)
    text.ssk_rail_stop_headed.caption = headed_caption(entry)
    text.ssk_rail_stop_stopped.caption = stopped_caption(entry)
    button.tooltip, button.toggled = Loc.join_list(summary, "\n"), state.rail.stop == unit
    paint_stop_row(button)
  end
end

local function overview_column(parent, role, record, units, live, stocks, state, width)
  local column = frame(parent, width)
  title(column, role_names[role])
  if #units == 0 then
    local empty = wrapped_label(column, Loc("rail-no-stops"), width - 16, "grey_label")
    empty.style.padding = { 4, 8 }
  end
  for _, unit in ipairs(units) do
    stop_row(column, unit, record.stops[unit], live[unit], stocks[unit], state, width, record.id)
  end
end

local function all_view(parent, groups, live, stocks, state, width, height)
  local pane = scroll(parent, height)
  local cards = pane.add { type = "flow", direction = "vertical" }
  cards.style.vertical_spacing = 12
  local group_width = width - Layout.SCROLL_GUTTER
  local content_width = group_width - 16
  local half = math.floor((content_width - 8) / 2)
  for _, record in ipairs(groups) do
    local group = cards.add { type = "frame", direction = "vertical" }
    group.style.width, group.style.padding = group_width, 8
    local body = group.add { type = "flow", direction = "vertical" }
    body.style.vertical_spacing = 8
    wrapped_label(body, record.name, content_width, "heading_2_label")
    local pair = body.add { type = "flow", direction = "horizontal" }
    pair.style.horizontal_spacing = 8
    local by_role = { import = {}, export = {}, both = {} }
    for _, unit in ipairs(UI.ordered(record.stops)) do
      local units = by_role[record.stops[unit].role]
      units[#units + 1] = unit
    end
    for _, role in ipairs({ "import", "export" }) do
      overview_column(pair, role, record, by_role[role], live, stocks, state, half)
    end
    if #by_role.both > 0 then
      overview_column(body, "both", record, by_role.both, live, stocks, state, content_width)
    end
  end
end

local function update_buffer(parent, stock, width, height)
  local missing = stock.count > 0 and stock.missing > 0
  local count = #stock.items
  local rows = math.max(1, count) + (missing and 1 or 0)
  local overflow = rows * DETAIL_ROW_HEIGHT > height
  local content_width = width - 4 - (overflow and Layout.SCROLL_GUTTER or 0)
  parent.style.height = height
  parent.vertical_scroll_policy = overflow and "auto" or "dont-show-but-allow-scrolling"
  local tags = parent.tags
  if tags.items ~= count or tags.missing ~= missing or tags.width ~= content_width then
    parent.clear()
    parent.tags = { items = count, missing = missing, width = content_width }
    if count > 0 then
      local table_rows = grid(parent, "ssk_rail_stock_items", 2)
      local amount_width = math.min(100, math.floor(content_width / 3))
      for _ = 1, count do
        local material = column_label(table_rows, "", content_width - amount_width, "left")
        local amount = column_label(table_rows, "", amount_width, "right")
        material.style.height, amount.style.height = DETAIL_ROW_HEIGHT, DETAIL_ROW_HEIGHT
      end
    end
    if count == 0 or missing then
      local note = parent.add { type = "label", name = "ssk_rail_stock_note", style = "grey_label" }
      note.style.height, note.style.left_padding = DETAIL_ROW_HEIGHT, 8
    end
  end
  local table_rows = parent.ssk_rail_stock_items
  if table_rows then
    local cells = table_rows.children
    for i, item in ipairs(stock.items) do
      local name = History.material_name(item)
      local label = cells[2 * i - 1]
      label.caption, label.tooltip = name, name
      cells[2 * i].caption = History.material_count(item)
    end
  end
  if parent.ssk_rail_stock_note then
    parent.ssk_rail_stock_note.caption = missing and Loc("rail-missing-buffers", stock.missing) or stock_note(stock)
  end
end

local function update_train_list(list, trains, stopped, selected, height, empty)
  local ids, items, index = {}, {}, 0
  for i, train in ipairs(trains) do
    ids[i] = train.id
    if selected == train then index = i end
    if stopped == nil then
      items[i] = Loc("rail-visit-train", train.id)
    elseif stopped == train then
      items[i] = Loc("rail-train-stopped", train.id)
    else
      items[i] = Loc("rail-train-headed", train.id)
    end
  end
  if #items == 0 then items[1] = empty end
  local signature = table.concat(ids, ",") .. ":" .. (stopped and stopped.id or "")
  if list.tags.signature ~= signature then
    list.items = items
    list.tags = { ssk_rail_select = "train", ids = ids, signature = signature }
  end
  list.enabled = #ids > 0
  if list.selected_index ~= index then list.selected_index = index end
  list.style.height = height
end

local function details(parent, unit, caption, nearby, stopped, scheduled, selected, stock, width, height)
  local sections = parent.ssk_rail_detail_sections
  if parent.tags.stop ~= unit or not sections then
    parent.clear()
    parent.tags = { stop = unit }
    sections = section_flow(parent, "ssk_rail_detail_sections", SECTION_GAP)
    local buffers = section_flow(sections, "ssk_rail_buffer_section")
    local buffer_body = section_body(buffers, width, caption)
    buffer_body.ssk_rail_section_title.children[1].style.maximal_width = width - 28
    title(buffer_body, Loc("rail-buffer-stock"), "ssk_rail_buffer_title")
    scroll(buffer_body, 0).name = "ssk_rail_stock"
    local local_trains = section_flow(sections, "ssk_rail_local_section")
    local local_body = section_body(local_trains, width, Loc("rail-trains-here"))
    local_body.add { type = "list-box", name = "ssk_rail_local_trains" }.style.horizontally_stretchable = true
    local scheduled_trains = section_flow(sections, "ssk_rail_scheduled_section")
    local scheduled_body = section_body(scheduled_trains, width, Loc("rail-scheduled-trains"), Loc("rail-scheduled-tip"))
    scheduled_body.add { type = "list-box", name = "ssk_rail_scheduled_trains" }.style.horizontally_stretchable = true
  end
  local buffer_body = sections.ssk_rail_buffer_section.ssk_rail_section_body
  local heading = buffer_body.ssk_rail_section_title.children[1]
  heading.caption, heading.tooltip = caption, caption
  local buffer_title = buffer_body.ssk_rail_buffer_title.children[1]
  buffer_title.caption = stock.count > 0 and Loc.join(Loc("rail-buffer-stock"), " (", tostring(stock.count), ")")
    or Loc("rail-buffer-stock")
  buffer_title.tooltip = Loc("rail-buffer-count", stock.count)
  local available = height - 4 * Layout.STRIP_HEIGHT - 2 * SECTION_GAP - 4
  local buffer_height = math.floor(available / 3)
  local live_height = math.floor((available - buffer_height) / 2)
  local scheduled_height = available - buffer_height - live_height
  update_buffer(buffer_body.ssk_rail_stock, stock, width, buffer_height)
  local local_trains = sections.ssk_rail_local_section.ssk_rail_section_body.ssk_rail_local_trains
  local scheduled_trains = sections.ssk_rail_scheduled_section.ssk_rail_section_body.ssk_rail_scheduled_trains
  update_train_list(local_trains, nearby, stopped or false, selected, live_height, Loc("rail-no-train"))
  update_train_list(scheduled_trains, scheduled, nil, selected, scheduled_height, Loc("rail-no-scheduled-trains"))
end

local PREVIEW_ZOOM_MIN, PREVIEW_ZOOM_MAX = 0.05, 2

local function clamp_preview_zoom(zoom)
  return math.max(PREVIEW_ZOOM_MIN, math.min(PREVIEW_ZOOM_MAX, zoom))
end

local function preview(parent, train, has_scheduled, rail, width, height)
  local train_id = train and train.id or 0
  local tags = parent.tags
  if tags.train == train_id and tags.has_scheduled == has_scheduled then
    local camera = parent.ssk_rail_camera
    if camera and rail.preview_zoom then camera.zoom = clamp_preview_zoom(rail.preview_zoom) end
    return
  end
  parent.clear()
  parent.tags = { train = train_id, has_scheduled = has_scheduled }
  local _, bar = title(parent, train and Loc.join(Loc("rail-preview"), " · ", Loc("rail-visit-train", train_id)) or Loc("rail-preview"))
  if not train then
    local note = has_scheduled and Loc("rail-pick-preview-train") or Loc("rail-no-train")
    wrapped_label(parent, note, width - 18, "grey_label").style.padding = { 4, 8 }
    return
  end
  local carriages = train.carriages
  local anchor = carriages[math.ceil(#carriages / 2)]
  if not anchor or not anchor.valid then return end
  local default_zoom = math.max(0.12, math.min(0.8, (width - 20) / (#carriages * 7 * 32 + 64)))
  local zoom = clamp_preview_zoom(rail.preview_zoom or default_zoom)
  bar.add { type = "empty-widget" }.style.horizontally_stretchable = true
  bar.add { type = "label", caption = Loc("machine-status-zoom") }
  local slider = bar.add { type = "slider", name = "ssk_rail_preview_zoom", minimum_value = PREVIEW_ZOOM_MIN,
    maximum_value = PREVIEW_ZOOM_MAX, value = zoom, value_step = 0.05, tags = { ssk_ui = "rail_preview_zoom" } }
  slider.style.width = math.max(60, math.min(120, width - 310))
  slider.style.left_margin, slider.style.right_margin = 6, 6
  bar.add { type = "sprite-button", name = "ssk_rail_jump_button", style = "tool_button",
    sprite = "utility/map", tooltip = Loc("rail-jump-train"),
    tags = { ssk_ui = "rail_train_jump", train_id = train_id } }
  local camera = parent.add { type = "camera", name = "ssk_rail_camera", surface_index = anchor.surface.index,
    position = anchor.position, zoom = zoom }
  camera.entity = anchor
  camera.style.width, camera.style.height = width - 4, math.max(90, height - Layout.STRIP_HEIGHT - 4)
end

function UI.render(player, parent, stops, groups, state, width, height)
  local rail = state.rail
  if state.view == "train_history" then
    parent.clear()
    History.render(player, parent, stops, UI.ordered(stops), rail, state.period or Sampler.DEFAULT_PERIOD, width, height)
    return
  end
  local units = state.selected and UI.ordered(stops)
  if units and not stops[rail.stop] then rail.stop, rail.train = units[1], nil end
  local live, stocks = Rail.traffic(stops, state.sidx, player.force, units and rail.stop), {}
  local names = History.stop_captions(stops)
  for unit, stop in pairs(stops) do
    local items, count, missing = Rail.stock(stop, state.sidx)
    stocks[unit] = { items = items, count = count, missing = missing, caption = Rail.name(stop), tooltip = names[unit] }
  end
  if not units then
    parent.clear()
    all_view(parent, groups, live, stocks, state, width, height)
    return
  end
  local columns_width = width - 2 * SECTION_GAP
  local quarter = math.floor(columns_width / 4)
  local rest = columns_width - 2 * quarter
  height = height - 4
  local row = parent.ssk_rail_stop_view
  local tags = row and row.tags or {}
  local detail_column = row and row.ssk_rail_details
  if tags.cell ~= state.selected or tags.width ~= width or tags.height ~= height
    or not detail_column or detail_column.type ~= "flow" then
    parent.clear()
    row = parent.add { type = "flow", name = "ssk_rail_stop_view", direction = "horizontal",
      tags = { cell = state.selected, width = width, height = height } }
    row.style.horizontal_spacing = SECTION_GAP
    local left = section_flow(row, "ssk_rail_roles", SECTION_GAP)
    section_flow(left, "ssk_rail_imports")
    section_flow(left, "ssk_rail_exports")
    section_flow(row, "ssk_rail_details")
    frame(row, rest).name = "ssk_rail_preview"
  end
  local top = math.floor((height - SECTION_GAP) / 2)
  cell_stop_list(row.ssk_rail_roles.ssk_rail_imports, "import", stops, units, live, stocks, state, quarter, top)
  cell_stop_list(row.ssk_rail_roles.ssk_rail_exports, "export", stops, units, live, stocks, state, quarter, height - top - SECTION_GAP)
  local unit = rail.stop
  local entry, stock = live[unit], stocks[unit]
  local nearby = {}
  if entry.stopped then nearby[1] = entry.stopped end
  for _, train in ipairs(entry.headed) do nearby[#nearby + 1] = train end
  local scheduled = entry.scheduled_trains or {}
  local selected
  if rail.train then
    for _, train in ipairs(nearby) do if train.id == rail.train then selected = train; break end end
    if not selected then
      for _, train in ipairs(scheduled) do if train.id == rail.train then selected = train; break end end
    end
    if not selected then rail.train = nil end
  end
  selected = selected or nearby[1]
  local caption = stop_name(stops[unit], state.sidx, stock.caption)
  details(row.ssk_rail_details, unit, caption, nearby, entry.stopped, scheduled, selected, stock, quarter, height)
  preview(row.ssk_rail_preview, selected, #scheduled > 0, rail, rest, height)
end

function UI.on_click(tags, state)
  if not tags.ssk_rail then return false end
  local rail = state.rail
  if tags.ssk_rail == "jump" then
    local records = storage.production_cells and storage.production_cells.records or {}
    local record, reverse, seen = records[tags.cell], {}, {}
    local parent = record and record.parent_id
    while parent and records[parent] and not seen[parent] do
      seen[parent] = true
      reverse[#reverse + 1] = parent
      parent = records[parent].parent_id
    end
    state.path = {}
    for i = #reverse, 1, -1 do state.path[#state.path + 1] = reverse[i] end
    state.scope = state.path[#state.path]
    state.view, state.selected, rail.stop, rail.train = "train_stops", tags.cell, tags.unit, nil
  elseif tags.ssk_rail == "stop" then
    if rail.stop ~= tags.unit then rail.stop, rail.train = tags.unit, nil end
  else
    return History.on_click(tags, rail)
  end
  return true
end

function UI.on_selection(el, state)
  local kind, ids = el.tags.ssk_rail_select, el.tags.ids
  if kind == "train" then state.rail.train = ids[el.selected_index]; return true end
  if kind == "history" then
    state.rail.filter = ids[el.selected_index]
    History.reset(state.rail)
    return true
  end
  return false
end

function UI.on_hover(element, entering)
  if not element or not element.valid or element.name ~= "ssk_rail_stop_button" then return false end
  paint_stop_row(element, entering)
  return true
end

function UI.on_switch(el, state)
  return state.view == "train_history" and History.on_switch(el, state.rail)
end

UI.reset_history = History.reset

return UI
