local Canvas = require("scripts.canvas")
local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local Sprites = require("shared.sprites")
local Transfers = require("scripts.transfers")
local Tooltip = require("scripts.tooltip")

local UI = {}
local FILTERS = { { "from", "Load from" }, { "to", "Unload to" }, { "material", "Material" } }
local LOADED = { r = 0.28, g = 0.59, b = 0.73, a = 1 }
local UNLOADED = { r = 0.80, g = 0.53, b = 0.29, a = 1 }
local MADE = { r = 0.55, g = 0.82, b = 0.65, a = 1 }
local GRID = { r = 0.25, g = 0.25, b = 0.26, a = 1 }
local AXIS = { r = 0.49, g = 0.48, b = 0.46, a = 1 }
local TICK = { r = 0.75, g = 0.74, b = 0.71, a = 1 }
local HIGHLIGHT = { r = 0.28, g = 0.24, b = 0.18, a = 1 }
local CARD_ROW, CARD_HEADER, CARD_GAP = 25, 34, 12
local DIRECTIONS = { "loaded", "unloaded" }
local LAYOUT_VERSION = 4
local TAB_HEADER_HEIGHT, PRODUCTION_NOTE_HEIGHT = 36, 36

local function label(parent, name, caption, style, width)
  local el = parent.add { type = "label", name = name, caption = caption, style = style }
  if width then el.style.width, el.style.single_line = width, true end
  return el
end

local function plain(el)
  if defines.rich_text_setting then el.style.rich_text_setting = defines.rich_text_setting.disabled end
  return el
end

local function row(parent, name)
  local flow = parent.add { type = "flow", name = name, direction = "horizontal" }
  flow.style.vertical_align = "center"
  return flow
end

local function spacer(parent)
  parent.add { type = "empty-widget" }.style.horizontally_stretchable = true
end

local function sprite(parent, path, size)
  local el = parent.add { type = "sprite", resize_to_sprite = false, ignored_by_interaction = true }
  el.visible = path ~= nil and helpers.is_valid_sprite_path(path)
  if el.visible then el.sprite = path end
  el.style.width, el.style.height = size, size
  return el
end

local function action(parent, name, icon, tooltip, tags)
  return parent.add { type = "sprite-button", name = name, sprite = "utility/" .. icon,
    style = "tool_button", tooltip = tooltip, tags = tags }
end

local function strip(parent, name, height)
  local el = parent.add { type = "frame", name = name, style = "subheader_frame", direction = "horizontal" }
  el.style.height, el.style.padding = height, 0
  el.style.left_padding, el.style.right_padding = 8, 8
  el.style.horizontally_stretchable = true
  el.style.vertical_align = "center"
  return el
end

local function number(n)
  return (string.format("%.0f", n):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse())
end

local function mass(data)
  local grams = data.weight or 0
  if data.unknown_weight and grams == 0 then return "Unknown" end
  local unit, value = "g", number(grams)
  if grams >= 1000000 then
    unit, value = "t", string.format("%.2f", grams / 1000000)
  elseif grams >= 1000 then
    unit, value = "kg", string.format("%.1f", grams / 1000)
  end
  return (data.unknown_weight and "≥" or "") .. value .. " " .. unit
end

local function clock(tick, seconds)
  local elapsed = math.floor(math.max(tick, 0) / 60)
  local h, m, s = math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60, elapsed % 60
  if seconds then return string.format("%02d:%02d:%02d", h, m, s) end
  return string.format("%02d:%02d", h, m)
end

local function range(from, to)
  local seconds = to - from < 3600
  return clock(from, seconds) .. " – " .. clock(to, seconds)
end

local function item_name(name, with_icon)
  local prototype = prototypes.item[name]
  if not prototype then return (name:gsub("-", " ")) end
  if with_icon then return { "", Graph.rt("item/" .. name), " ", prototype.localised_name } end
  return prototype.localised_name
end

local function manifest_tooltip(header, detail, items, seconds)
  local parts = { header, "\n", detail }
  if seconds and seconds > 0 and #items > 0 then parts[#parts + 1] = "\nAverage rate over recorded time" end
  for _, item in ipairs(items) do
    local entry = { "", "\n", item_name(item.name, true), "  ", number(item.count) }
    if seconds and seconds > 0 then entry[#entry + 1] = string.format("  ·  %.5g items/s", item.count / seconds) end
    parts[#parts + 1] = entry
  end
  return Tooltip.lines(parts)
end

local function endpoint_name(endpoint)
  local name, icon = Transfers.describe(endpoint)
  return endpoint.surface.valid and name or name .. " (removed)", icon
end

local function choices_for(endpoints)
  local list, counts = {}, {}
  for id, endpoint in pairs(endpoints) do
    local name = endpoint_name(endpoint)
    list[#list + 1] = { key = id, name = name }
    counts[name] = (counts[name] or 0) + 1
  end
  table.sort(list, function(a, b)
    if a.name ~= b.name then
      if a.name:lower() == b.name:lower() then return a.name < b.name end
      return a.name:lower() < b.name:lower()
    end
    return a.key < b.key
  end)
  for _, choice in ipairs(list) do
    if counts[choice.name] > 1 then choice.name = choice.name .. " (" .. choice.key .. ")" end
    choice.caption = choice.name
  end
  return list
end

local function material_choices(materials)
  local names, list = {}, {}
  for name in pairs(materials) do names[#names + 1] = name end
  table.sort(names)
  for i, name in ipairs(names) do list[i] = { key = name, name = name, caption = item_name(name, true) } end
  return list
end

local function same_choices(el, keys, names)
  local tags = el.tags
  if not tags.keys or #tags.keys ~= #keys then return false end
  for i, key in ipairs(keys) do
    if key ~= tags.keys[i] or names[i] ~= tags.names[i] then return false end
  end
  return true
end

local function update_filter(el, field, choices, state)
  local keys, names = { 0 }, { field == "material" and "All materials" or "All surfaces" }
  local items, selected = { names[1] }, 1
  local value = state[field]
  for _, choice in ipairs(choices) do
    keys[#keys + 1], names[#names + 1], items[#items + 1] = choice.key, choice.name, choice.caption
    if choice.key == value then
      selected = #keys
      state[field .. "_label"] = choice.name
    end
  end
  if value and selected == 1 then
    local name = state[field .. "_label"] or tostring(value)
    keys[#keys + 1], names[#names + 1] = value, name
    items[#items + 1] = field == "material" and item_name(value, true) or name
    selected = #keys
  end
  if not same_choices(el, keys, names) then
    el.items = items
    el.tags = { transfer_filter = field, keys = keys, names = names }
  end
  if el.selected_index ~= selected then el.selected_index = selected end
end

local function update_platforms(el, platforms, selected)
  local keys, names, items, index = {}, {}, {}, 0
  for i, p in ipairs(platforms) do
    keys[i], names[i] = p.id, p.name
    items[i] = p.icon and ("[img=" .. p.icon .. "] " .. p.name) or p.name
    if selected and selected.id == p.id then index = i end
  end
  if not same_choices(el, keys, names) then
    el.items = items
    el.tags = { transfer_platforms = true, keys = keys, names = names }
  end
  if el.selected_index ~= index then el.selected_index = index end
end

local function scroll(parent, name, width, height)
  local pane = parent.add { type = "scroll-pane", name = name, style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
  pane.style.width, pane.style.height = width, height
  return pane
end

local function build(content, width, height)
  local panel = content.add { type = "frame", name = "ssk_transfers", style = "inside_deep_frame",
    direction = "vertical", tags = { transfers_layout = LAYOUT_VERSION } }
  panel.style.width, panel.style.height = width, height
  panel.style.padding = 4
  local filters = strip(panel, "filters", 40)
  local compact = width < 700
  local filter_w = math.min(196, math.floor((width - (compact and 200 or 276)) / 3))
  for _, filter in ipairs(FILTERS) do
    local field, title = filter[1], filter[2]
    local cell = row(filters, field)
    cell.style.horizontal_spacing, cell.style.right_margin = 4, 4
    label(cell, nil, compact and (field == "from" and "From" or field == "to" and "To" or title) or title,
      "subheader_semibold_label")
    local dropdown = cell.add { type = "drop-down", name = "ssk_transfer_" .. field, items = { "" },
      selected_index = 1, tooltip = "Filter by " .. title:lower() .. "." }
    dropdown.style.width = filter_w
  end

  local split = row(panel, "split")
  split.style.vertical_align, split.style.horizontal_spacing = "top", 8
  split.style.top_margin = 8
  local sidebar_w = math.max(116, math.min(236, math.floor(width * 0.17)))
  local details_w = width - sidebar_w - 16
  local body_h = height - 56
  local sidebar = split.add { type = "frame", name = "sidebar", style = "inside_deep_frame", direction = "vertical" }
  sidebar.style.width, sidebar.style.height = sidebar_w, body_h
  sidebar.style.padding = 0
  local side_header = strip(sidebar, "heading", 38)
  label(side_header, nil, "Platforms", "subheader_caption_label")
  spacer(side_header)
  label(side_header, "count", "", "subheader_semibold_label")
  local platforms = sidebar.add { type = "list-box", name = "ssk_transfer_platforms",
    style = "wide_list_box_in_shallow_frame_under_subheader", items = {},
    tags = { transfer_platforms = true }, tooltip = "Select a space platform." }
  platforms.style.width, platforms.style.height = sidebar_w - 4, body_h - 42

  local right = split.add { type = "frame", name = "details", style = "inside_deep_frame", direction = "vertical" }
  right.style.width, right.style.height = details_w, body_h
  right.style.padding = 4
  local heading = strip(right, "heading", 38)
  local icon = heading.add { type = "sprite", name = "icon", resize_to_sprite = false }
  icon.style.width, icon.style.height = 26, 26
  label(heading, "platform", "", "subheader_caption_label", math.max(70, details_w - 224))
  spacer(heading)
  label(heading, "material", "", "subheader_semibold_label", math.min(142, math.floor(details_w / 4)))
    .style.horizontal_align = "right"

  local tab_row = row(right, "tab_row")
  tab_row.style.vertical_align, tab_row.style.horizontal_spacing = "top", 0
  local tabs = tab_row.add { type = "tabbed-pane", name = "ssk_transfer_tabs",
    style = "tabbed_pane_with_no_side_padding", tags = { transfer_tabs = true } }
  tabs.style.width = details_w - 8
  tabs.style.top_margin = 4
  -- The native pane adds a tab strip and an inset around its content.
  local tab_w, tab_h = details_w - 16, body_h - 104
  for _, title in ipairs({ "Flow", "History" }) do
    local tab = tabs.add { type = "tab", caption = title }
    local body = tabs.add { type = "flow", name = "ssk_transfer_" .. title:lower(), direction = "vertical",
      tags = { transfer_width = tab_w, transfer_height = tab_h } }
    body.style.width, body.style.height = tab_w, tab_h
    body.style.vertical_spacing = 4
    tabs.add_tab(tab, body)
  end
  tabs.selected_tab_index = 1

  -- Keep the native tabs and place the Flow controls over the unused space to their right.
  local options_w = math.min(416, tab_w - 184)
  local options = tab_row.add { type = "flow", name = "production", direction = "vertical" }
  options.style.width, options.style.vertical_spacing = options_w, 0
  options.style.left_margin, options.style.right_margin = -(options_w + 12), 12
  options.style.top_margin = 4
  local toggle_row = row(options, "toggle")
  toggle_row.style.height = TAB_HEADER_HEIGHT
  toggle_row.add { type = "checkbox", name = "ssk_transfer_show_all_production", caption = "Show all onboard production",
    state = false, tags = { transfer_show_all_production = true } }
  local hint = label(options, "note", "When off, Made aboard shows items made and unloaded in this period.", "grey_label")
  hint.style.top_margin, hint.style.maximal_width, hint.style.single_line = 8, options_w, false
  hint.tooltip = "Made aboard counts how much the platform produced. Unloaded counts how much it delivered."
  return panel
end

-- Match the existing Sankey camera and keep native controls aligned with its coordinates.
local function place(el, x, y, width, height)
  local style = el.style
  style.width, style.height = width, height
  style.left_margin, style.top_margin, style.bottom_margin = x, y, -(y + height)
  return el
end

local function camera(parent, player, painter, width, height)
  local el = parent.ssk_transfer_camera
  local spec = Canvas.camera_spec(player, painter)
  if el then
    el.position = spec.position
  else
    spec.name, spec.ignored_by_interaction = "ssk_transfer_camera", true
    el = parent.add(spec)
  end
  return place(el, 0, 0, width, height)
end

local function canvas_label(parent, caption, style, x, y, width, alignment)
  local wrapper = parent.add { type = "flow", direction = "horizontal" }
  place(wrapper, x, y, width, 24)
  local el = label(wrapper, nil, caption, style, width)
  el.style.horizontal_align = alignment or "left"
  el.ignored_by_interaction = true
  return el
end

local function card_height(items)
  return CARD_HEADER + CARD_ROW * math.min(5, #items) + (#items > 5 and 22 or 0) + 6
end

local function ranking(parent, name, icon, data, x, y, width, colour)
  local tip = manifest_tooltip(name, "Cargo mass: " .. mass(data), data.items)
  local wrapper = parent.add { type = "flow", direction = "horizontal" }
  place(wrapper, x, y, width, card_height(data.items))
  local card = wrapper.add { type = "frame", name = "ssk_transfer_surface_card", style = "inside_deep_frame",
    direction = "vertical", tooltip = tip, tags = { transfer_surface = name, transfer_rank_count = math.min(5, #data.items) } }
  card.style.width, card.style.padding = width, 2
  local header = strip(card, "heading", CARD_HEADER)
  if icon then sprite(header, icon, 23) end
  local header_w = width - (icon and 132 or 104)
  plain(label(header, "surface_name", name, "subheader_caption_label", header_w)).tooltip = tip
  spacer(header)
  local weight = label(header, "weight", mass(data), "subheader_semibold_label", 72)
  weight.style.horizontal_align, weight.tooltip = "right", tip

  for i = 1, math.min(5, #data.items) do
    local item = data.items[i]
    local line = row(card, "rank_" .. i)
    line.tags = { transfer_rank = item.name, count = item.count }
    line.style.height, line.style.horizontal_spacing = CARD_ROW, 4
    line.style.left_padding, line.style.right_padding = 6, 6
    line.tooltip = tip
    sprite(line, "item/" .. item.name, 19)
    local bar_w = width >= 180 and math.min(48, math.floor(width / 6)) or 0
    local name_w = width - bar_w - (bar_w > 0 and 95 or 92)
    label(line, nil, item_name(item.name), nil, name_w).tooltip = tip
    if bar_w > 0 then
      local bar = row(line)
      bar.style.width = bar_w
      local size = math.max(1, math.floor(bar_w * item.count / data.items[1].count + 0.5))
      local image = sprite(bar, Sprites.bar(colour), size)
      image.style.height, image.style.stretch_image_to_widget_size = 4, true
    end
    local count = label(line, nil, number(item.count), "bold_label", 48)
    count.style.horizontal_align, count.tooltip = "right", tip
  end
  if #data.items > 5 then
    local foot = label(card, nil, "+" .. (#data.items - 5) .. " more · Hover for all items", "grey_label", width - 8)
    foot.style.left_margin, foot.tooltip = 4, tip
  end
end

local function ribbon_shape(x0, y0, x1, y1, width, linear)
  return { kind = "curve", x = x0, w = x1 - x0, h = math.abs(y1 - y0) + width,
    ya = y0 - width / 2, yb = y1 - width / 2, t0 = width, t1 = width, linear = linear }
end

local function draw_ribbon(painter, x0, y0, x1, y1, data, highest, color)
  local width = math.min(30, (data.weight or 0) * 30 / highest)
  if width < 1 then
    painter.line(x0, y0, x1, y1, color, 2, true)
    return ribbon_shape(x0, y0, x1, y1, 2, true)
  end
  painter.curve(x0, x1, y0 - width / 2, y1 - width / 2, width, color)
  painter.polygon({ { x1 - 6, y1 - 4 }, { x1 - 6, y1 + 4 }, { x1, y1 } }, TICK)
  return ribbon_shape(x0, y0, x1, y1, width)
end

local function flow_signature(result)
  local parts = { result.platform.id, result.platform.name, result.made.seconds or 0 }
  local function manifest(data)
    parts[#parts + 1] = mass(data)
    for _, item in ipairs(data.items) do
      parts[#parts + 1], parts[#parts + 2] = item.name, item.count
    end
  end
  for _, routes in ipairs({ result.loading, result.unloading }) do
    parts[#parts + 1] = #routes
    for _, route in ipairs(routes) do
      parts[#parts + 1], parts[#parts + 2] = route.endpoint.id, endpoint_name(route.endpoint)
      manifest(route)
    end
  end
  manifest(result.made)
  return table.concat(parts, "\n")
end

local function flow_layout(routes)
  local layout, y = {}, 34
  for _, route in ipairs(routes) do
    local h = card_height(route.items)
    layout[#layout + 1] = { route = route, y = y, center = y + h / 2 }
    y = y + h + CARD_GAP
  end
  return layout, y
end

local function flow_graph(player, parent, result, width, viewport)
  local left, left_end = flow_layout(result.loading)
  local right, right_end = flow_layout(result.unloading)
  local made = #result.made.items > 0
  local empty_y = 36
  local made_y = #left == 0 and empty_y + 30 or left_end
  if made then left_end = made_y + card_height(result.made.items) + CARD_GAP end
  local height = math.max(viewport - 4, left_end, right_end, 240)
  local card_w = math.min(254, math.floor(width * 0.28))
  local center_w = math.min(192, math.floor(width * 0.26))
  local x_left, x_right, x_center = 4, width - card_w - 4, math.floor((width - center_w) / 2)
  local center_y = math.max(82, math.min(height - 125, math.floor((viewport - 40) / 2)))
  local highest = 1
  for _, list in ipairs({ left, right }) do
    for _, cell in ipairs(list) do highest = math.max(highest, cell.route.weight or 0) end
  end
  local signature = flow_signature(result)
  local update = parent.tags.transfer_graph ~= signature
  if update then parent.clear() end
  parent.style.width, parent.style.height = width, height
  local painter = Canvas.begin(player, width, height)
  camera(parent, player, painter, width, height)
  local platform_name = result.platform.name
  local function route_hover(shape, caption, route, direction, index)
    local tip = manifest_tooltip(caption, "Cargo mass: " .. mass(route), route.items, result.covered_seconds)
    Tooltip.ribbon(parent, { shape }, tip, { transfer_ribbon = direction },
      "ssk_transfer_ribbon_" .. direction .. "_" .. index .. "_")
  end
  for i, cell in ipairs(left) do
    local offset = (i / (#left + 1) - 0.5) * 34
    local shape = draw_ribbon(painter, x_left + card_w, cell.center, x_center, center_y + 52 + offset, cell.route, highest, LOADED)
    route_hover(shape, endpoint_name(cell.route.endpoint) .. " → " .. platform_name, cell.route, "loaded", i)
  end
  for i, cell in ipairs(right) do
    local offset = (i / (#right + 1) - 0.5) * 34
    local shape = draw_ribbon(painter, x_center + center_w, center_y + 52 + offset, x_right, cell.center, cell.route, highest, UNLOADED)
    route_hover(shape, platform_name .. " → " .. endpoint_name(cell.route.endpoint), cell.route, "unloaded", i)
  end
  if made then
    local x, y = x_left + card_w, made_y + card_height(result.made.items) / 2
    painter.line(x, y, x_center, center_y + 94, MADE, 2, true)
    local shape = ribbon_shape(x, y, x_center, center_y + 94, 2, true)
    local tip = manifest_tooltip("Made aboard " .. platform_name, "Recorded platform production", result.made.items, result.made.seconds)
    Tooltip.ribbon(parent, { shape }, tip, { transfer_ribbon = "made" }, "ssk_transfer_ribbon_made_")
  end
  if not update then return end
  parent.tags = { transfer_graph = signature }
  canvas_label(parent, "Loading surfaces", "heading_2_label", x_left, 2, card_w)
  canvas_label(parent, "Selected platform", "heading_2_label", x_center, 2, center_w, "center")
  canvas_label(parent, "Unloading surfaces", "heading_2_label", x_right, 2, card_w)
  if #left == 0 then canvas_label(parent, "No matching loads", "grey_label", x_left, empty_y, card_w) end
  if #right == 0 then canvas_label(parent, "No matching unloads", "grey_label", x_right, empty_y, card_w) end
  for _, entry in ipairs({ { left, x_left, 7 }, { right, x_right, 5 } }) do
    for _, cell in ipairs(entry[1]) do
      local name, icon = endpoint_name(cell.route.endpoint)
      ranking(parent, name, icon, cell.route, entry[2], cell.y, card_w, entry[3])
    end
  end
  if made then ranking(parent, "Made aboard", nil, result.made, x_left, made_y, card_w, 15) end

  local wrapper = parent.add { type = "flow", direction = "horizontal" }
  place(wrapper, x_center, center_y, center_w, 124)
  local platform = wrapper.add { type = "frame", name = "ssk_transfer_platform_node", style = "inside_deep_frame",
    direction = "vertical" }
  platform.style.width, platform.style.padding = center_w, 2
  local header = strip(platform, "heading", 34)
  sprite(header, result.platform.icon, 23)
  label(header, nil, result.platform.name, "subheader_semibold_label", center_w - 44).tooltip = result.platform.name
  for _, stat in ipairs({ { "Loaded", result.loaded, 7 }, { "Unloaded", result.unloaded, 5 },
      { "Made", result.made, 15 } }) do
    local line = row(platform)
    line.style.height, line.style.left_padding, line.style.right_padding = 25, 8, 8
    sprite(line, Sprites.bar(stat[3]), 7)
    label(line, nil, stat[1])
    spacer(line)
    local unavailable = stat[1] == "Made" and result.made.seconds == 0
    local weight = label(line, nil, unavailable and "—" or mass(stat[2]), "bold_label")
    if unavailable then weight.tooltip = "No production history is available for this platform and period." end
  end
end

local function render_flow(player, body, result, note)
  local width, height = body.tags.transfer_width, body.tags.transfer_height
  local graph_height = height - 30 - PRODUCTION_NOTE_HEIGHT
  if not body.graph then
    local pane = scroll(body, "graph", width, graph_height)
    pane.style.top_margin = PRODUCTION_NOTE_HEIGHT
    pane.add { type = "flow", name = "canvas", direction = "vertical" }.style.vertical_spacing = 0
    local legend = row(body, "legend")
    legend.style.width, legend.style.height = width, 26
    legend.style.left_padding, legend.style.right_padding = 8, 8
    for _, key in ipairs({ { "Loaded", 7 }, { "Unloaded", 5 }, { "Made aboard", 15 } }) do
      sprite(legend, Sprites.bar(key[2]), 8)
      label(legend, nil, key[1], "grey_label").style.right_margin = 8
    end
    spacer(legend)
    label(legend, "note", "", "grey_label", math.max(40, width - 300)).style.horizontal_align = "right"
  end
  body.legend.note.caption = note or "Ribbon width shows known cargo mass."
  body.legend.note.tooltip = note or "Mass uses each item's Space Age rocket weight. Made aboard is sampled platform production."
  flow_graph(player, body.graph.canvas, result, width - 24, graph_height)
end

local function bucket_value(data, material)
  return material and data.count or data.pods
end

local function bucket_tooltip(bucket, direction, material, start_tick, end_tick, recorded_from)
  local cargo = bucket[direction]
  local title = (direction == "loaded" and "Loaded onto platform" or "Unloaded to surface")
    .. " · " .. range(start_tick, end_tick)
  local detail = number(cargo.pods) .. (cargo.pods == 1 and " pod" or " pods")
  if material then detail = detail .. " · " .. number(cargo.count) .. " selected items" end
  if cargo.pods > 0 then detail = detail .. " · " .. mass(cargo) end
  local seconds = math.max(0, end_tick - math.max(start_tick, recorded_from)) / 60
  return manifest_tooltip(title, detail, cargo.items, seconds)
end

local function nice_step(value)
  if value <= 2 then return 1 end
  local power = 10 ^ math.floor(math.log(value / 2, 10))
  for _, factor in ipairs({ 1, 2, 5, 10 }) do
    if value <= 2 * factor * power then return factor * power end
  end
end

local function timeline(player, chart, result, width, height, material)
  local painter = Canvas.begin(player, width, height)
  camera(chart, player, painter, width, height)
  local left, right, top, bottom = width < 650 and 115 or 156, width - 24, 10, height - 29
  local mid = math.floor((top + bottom) / 2)
  local peak = 1
  for _, bucket in ipairs(result.buckets) do
    for _, direction in ipairs(DIRECTIONS) do peak = math.max(peak, bucket_value(bucket[direction], material)) end
  end
  local step = nice_step(peak)
  local edge = math.ceil(peak / step) * step
  local scale = (mid - top - 4) / edge
  local domain = math.max(1, result.to_tick - result.from_tick)
  local recorded_from = result.to_tick - result.covered_seconds * 60
  local function x(tick) return left + (right - left) * (tick - result.from_tick) / domain end

  local selected = result.bucket
  for _, bucket in ipairs(result.buckets) do
    if bucket.start_tick == selected then
      local a, b = x(math.max(bucket.start_tick, result.from_tick)), x(math.min(bucket.end_tick, result.to_tick))
      painter.rect(a, top, b - a, bottom - top, HIGHLIGHT)
    end
  end
  for value = 0, edge, step do
    local high, low = mid - value * scale, mid + value * scale
    painter.line(left, high, right, high, value == 0 and AXIS or GRID, 1)
    painter.text(left - 9, high, number(value), TICK, "right")
    if value > 0 then
      painter.line(left, low, right, low, GRID, 1)
      painter.text(left - 9, low, number(value), TICK, "right")
    end
  end
  local spacing = width >= 740 and 5 or 3
  for i = 0, spacing do
    local tick = result.from_tick + domain * i / spacing
    painter.text(x(tick), bottom + 13, clock(tick, domain < 5 * 60 * 60), TICK, "center")
  end
  local middle_top = math.floor((top + mid) / 2)
  local middle_bottom = math.floor((mid + bottom) / 2)
  for _, lane in ipairs({ { middle_top, LOADED, "Loaded onto", "the platform" },
      { middle_bottom, UNLOADED, "Unloaded to", "a surface" } }) do
    painter.rect(8, lane[1] - 8, 8, 8, lane[2])
    painter.text(22, lane[1] - 4, lane[3], TICK, "left")
    painter.text(22, lane[1] + 12, lane[4], TICK, "left")
  end

  for i, bucket in ipairs(result.buckets) do
    local start_tick, end_tick = math.max(bucket.start_tick, result.from_tick), math.min(bucket.end_tick, result.to_tick)
    local a, b = math.floor(x(start_tick)), math.ceil(x(end_tick))
    local band = math.max(1, b - a)
    local gap = math.floor(band * 0.14)
    for j, direction in ipairs(DIRECTIONS) do
      local up, amount = j == 1, bucket_value(bucket[direction], material)
      local magnitude = math.max(1, amount * scale)
      local color = up and LOADED or UNLOADED
      if amount > 0 then
        painter.rect(a + gap, up and mid - magnitude or mid + 1, band - 2 * gap, magnitude, color)
        if selected == bucket.start_tick and band >= 23 then
          painter.text(a + band / 2, up and mid - 9 or mid + 10, number(amount), TICK, "center")
        end
      end

      local name = "ssk_transfer_bucket_" .. direction .. "_" .. i
      local hit = chart[name] or chart.add { type = "sprite", name = name, sprite = "ssk-node-hit",
        resize_to_sprite = false }
      hit.tooltip = bucket_tooltip(bucket, direction, material, start_tick, end_tick, recorded_from)
      hit.tags = { transfer_bucket = bucket.start_tick, transfer_direction = direction }
      place(hit, a, up and top or mid, band, up and mid - top or bottom - mid)
      hit.visible = true
    end
  end
  for i = #result.buckets + 1, chart.tags.bucket_count or 0 do
    for _, direction in ipairs(DIRECTIONS) do chart["ssk_transfer_bucket_" .. direction .. "_" .. i].visible = false end
  end
  chart.tags = { bucket_count = math.max(#result.buckets, chart.tags.bucket_count or 0) }
end

local function log_widths(width)
  local arrival = width < 600 and 80 or 110
  local direction = width < 600 and 76 or 104
  local surface = math.min(170, math.floor(width * 0.20))
  local weight = width < 600 and 76 or 100
  return { arrival, direction, surface, width - arrival - direction - surface - weight - 52, weight }
end

local function log_row(parent)
  local line = row(parent)
  line.style.height, line.style.horizontal_spacing = 4 + 24, 4
  line.style.left_padding, line.style.right_padding = 4, 4
  return line
end

local function detail_row(parent, items, width)
  local columns = math.max(1, math.min(4, math.floor((width - 38) / 155)))
  local grid = parent.add { type = "table", name = "ssk_transfer_manifest",
    column_count = columns }
  grid.style.left_margin, grid.style.right_margin = 34, 4
  local cell_w = math.floor((width - 48) / columns) - 5
  for _, item in ipairs(items) do
    local cell = grid.add { type = "frame", style = "inside_shallow_frame", direction = "horizontal",
      tags = { transfer_item = item.name, count = item.count } }
    cell.style.width, cell.style.height, cell.style.padding = cell_w, 27, 2
    cell.style.vertical_align = "center"
    sprite(cell, "item/" .. item.name, 18)
    local count = number(item.count)
    local cap = label(cell, nil, item_name(item.name), nil, math.max(24, cell_w - 48 - #count * 6))
    cap.tooltip = item_name(item.name, true)
    spacer(cell)
    label(cell, nil, count, "bold_label")
  end
end

local function render_log(body, result, state, width)
  local header, pane = body.delivered, body.log_scroll
  local selected
  for _, bucket in ipairs(result.buckets) do
    if bucket.start_tick == result.bucket then selected = bucket; break end
  end
  local interval = selected and range(math.max(selected.start_tick, result.from_tick),
    math.min(selected.end_tick, result.to_tick)) or "Selected period"
  header.range.caption = interval .. "  ·  " .. number(result.arrival_count)
    .. (result.arrival_count == 1 and " confirmed pod" or " confirmed pods")
  header.range.tooltip = "Arrival time is shown as elapsed simulation time."
  header.reset_bucket.visible = selected ~= nil
  header.previous.visible, header.next.visible, header.pages.visible = result.pages > 1, result.pages > 1, result.pages > 1
  header.previous.enabled, header.next.enabled = result.page > 1, result.page < result.pages
  header.pages.caption = result.page .. " / " .. result.pages
  local keys = {}
  for i, pod in ipairs(result.arrivals) do keys[i] = tostring(pod.id) end
  local signature = (state.expanded and tostring(state.expanded) or "-") .. ":" .. table.concat(keys, ",")
  if pane.tags.log == signature then return end
  pane.tags = { log = signature }
  pane.clear()
  if #result.arrivals == 0 then
    label(pane, nil, "No confirmed deliveries in this range.", "grey_label").style.left_margin = 8
    return
  end
  local columns = log_widths(width - 24)
  for i, pod in ipairs(result.arrivals) do
    local line = log_row(pane)
    local expanded = state.expanded == pod.id
    local expand = action(line, "ssk_transfer_delivery_" .. i, expanded and "collapse" or "expand",
      expanded and "Collapse cargo manifest" or "Expand cargo manifest", { transfer_delivery = pod.id })
    expand.style.width, expand.style.height = 24, 24
    expand.toggled = expanded
    label(line, nil, clock(pod.tick, true), nil, columns[1])
    local direction = row(line)
    direction.style.width = columns[2]
    local loaded = pod.direction == "loaded"
    sprite(direction, Sprites.bar(loaded and 7 or 5), 8)
    label(direction, nil, loaded and "Loaded" or "Unloaded", "bold_label")
    local endpoint = row(line)
    endpoint.style.width = columns[3]
    local name, icon = endpoint_name(pod.endpoint)
    sprite(endpoint, icon, 18)
    plain(label(endpoint, nil, name, nil, columns[3] - 22)).tooltip = name
    local cargo = row(line)
    cargo.style.width = columns[4]
    cargo.tooltip = manifest_tooltip(name, mass(pod), pod.items)
    local shown = math.min(#pod.items, math.max(0, math.min(5, math.floor((columns[4] - 32) / 23))))
    for j = 1, shown do sprite(cargo, "item/" .. pod.items[j].name, 19) end
    if shown < #pod.items then label(cargo, nil, "+" .. (#pod.items - shown), "grey_label") end
    local weight = label(line, nil, mass(pod), "caption_label", columns[5])
    weight.style.horizontal_align = "right"
    weight.tooltip = "Full cargo pod mass."
    if expanded then detail_row(pane, pod.items, width - 24) end
  end
end

local function render_history(player, body, result, state, note)
  local width, height = body.tags.transfer_width, body.tags.transfer_height
  local chart_height = math.max(116, math.min(228, math.floor(height * 0.43)))
  if not body.chart then
    local heading = strip(body, "timeline_heading", 38)
    label(heading, nil, "Cargo timeline", "subheader_caption_label")
    label(heading, "units", "", "grey_label")
    spacer(heading)
    label(heading, "counts", "", "subheader_semibold_label")
    local chart = body.add { type = "flow", name = "chart", direction = "vertical" }
    chart.style.width, chart.style.height, chart.style.vertical_spacing = width, chart_height, 0
    local delivered = strip(body, "delivered", 38)
    label(delivered, nil, "Delivered cargo", "subheader_caption_label")
    spacer(delivered)
    label(delivered, "range", "", "subheader_semibold_label")
    action(delivered, "reset_bucket", "reset", "Clear selected time bucket", { transfer_reset_bucket = true })
    action(delivered, "previous", "left_arrow", "Previous page", { transfer_page = -1 })
    label(delivered, "pages", "", "grey_label")
    action(delivered, "next", "right_arrow", "Next page", { transfer_page = 1 })
    local headers = log_row(body)
    local gutter = headers.add { type = "empty-widget" }
    gutter.style.width = 24
    local columns = log_widths(width - 24)
    for i, title in ipairs({ "Arrival", "Direction", "Surface", "Cargo", "Mass" }) do
      local cell = label(headers, nil, title, "caption_label", columns[i])
      if i == 5 then cell.style.horizontal_align = "right" end
    end
    scroll(body, "log_scroll", width, math.max(70, height - chart_height - 126))
  end
  local seconds = result.bucket_ticks / 60
  local period = Sampler.duration(seconds)
  local heading = body.timeline_heading
  heading.units.caption = (state.material and "Selected items" or "Confirmed pods") .. " / " .. period
  heading.units.tooltip = note or "Select a time bucket to filter delivered cargo. Hover either lane for its complete manifest."
  heading.counts.caption = "Loaded " .. number(bucket_value(result.loaded, state.material))
    .. "  ·  Unloaded " .. number(bucket_value(result.unloaded, state.material))
  timeline(player, body.chart, result, width, chart_height, state.material)
  render_log(body, result, state, width)
end

local function reset_log(state)
  state.bucket, state.page, state.expanded = nil, nil, nil
end

function UI.render(content, player, period, state, width, height)
  local force = player.force
  if state.force ~= force then
    state.force, state.platform = force, nil
    for _, filter in ipairs(FILTERS) do
      local field = filter[1]
      state[field], state[field .. "_label"] = nil, nil
    end
    reset_log(state)
  end
  if state.period ~= period then
    state.period = period
    reset_log(state)
  end
  state.view = state.view or "flow"
  local panel = content.ssk_transfers
  if panel and panel.tags.transfers_layout ~= LAYOUT_VERSION then panel.destroy(); panel = nil end
  panel = panel or build(content, width, height)

  local seconds = period > 0 and period or settings.global["ssk-window-seconds"].value
  local available = Transfers.available()
  local result = available and Transfers.platform_view(force, game.tick, seconds, state)
    or { platforms = {}, materials = {}, sources = {}, destinations = {} }
  local filters = panel.filters
  update_filter(filters.from.ssk_transfer_from, "from", choices_for(result.sources), state)
  update_filter(filters.to.ssk_transfer_to, "to", choices_for(result.destinations), state)
  update_filter(filters.material.ssk_transfer_material, "material", material_choices(result.materials), state)
  local sidebar, details = panel.split.sidebar, panel.split.details
  update_platforms(sidebar.ssk_transfer_platforms, result.platforms, result.platform)
  sidebar.heading.count.caption = tostring(#result.platforms)
  local tab_row, heading = details.tab_row, details.heading
  local tabs, options = tab_row.ssk_transfer_tabs, tab_row.production
  tabs.selected_tab_index = state.view == "history" and 2 or 1
  options.visible = result.platform ~= nil and state.view == "flow"
  options.toggle.ssk_transfer_show_all_production.state = state.show_all_production == true
  local body = state.view == "history" and tabs.ssk_transfer_history or tabs.ssk_transfer_flow
  heading.platform.caption = result.platform and result.platform.name or "Transfers"
  heading.platform.tooltip = result.platform and result.platform.name or nil
  heading.material.caption = state.material and item_name(state.material, true) or "All materials"
  local icon = result.platform and result.platform.icon
  heading.icon.visible = icon ~= nil and helpers.is_valid_sprite_path(icon)
  if heading.icon.visible then heading.icon.sprite = icon end

  if not result.platform then
    state.platform = nil
    Canvas.clear(player.index)
    if not body.empty then
      body.clear()
      label(body, "empty", "", "grey_label").style.left_margin = 8
    end
    body.empty.caption = available and "No space platforms on this force." or "Transfers are available with Space Age enabled."
    return result.covered_seconds
  end
  state.platform = result.platform.id
  if body.empty then body.empty.destroy() end
  local note = result.truncated and "Some deliveries are outside the retained history." or nil
  if state.view == "history" then
    state.bucket, state.page = result.bucket, result.page
    render_history(player, body, result, state, note)
  else
    render_flow(player, body, result, note)
  end
  return result.covered_seconds
end

function UI.on_selection(event, state)
  local el = event.element
  if not (state and el and el.valid) then return false end
  local tags = el.tags
  if tags.transfer_tabs then
    state.view = el.selected_tab_index == 2 and "history" or "flow"
    return true
  end
  if tags.transfer_platforms then
    state.platform = tags.keys and tags.keys[el.selected_index]
    reset_log(state)
    return true
  end
  local field = tags.transfer_filter
  if not field then return false end
  local key = tags.keys[el.selected_index]
  state[field] = key ~= 0 and key or nil
  state[field .. "_label"] = key ~= 0 and tags.names[el.selected_index] or nil
  reset_log(state)
  return true
end

function UI.on_checked(event, state)
  local el = event.element
  if not (state and el and el.valid and el.tags.transfer_show_all_production) then return false end
  state.show_all_production = el.state
  return true
end

function UI.on_click(event, state)
  local el = event.element
  if not (state and el and el.valid) then return false end
  local tags = el.tags
  if tags.transfer_reset_bucket then
    reset_log(state)
  elseif tags.transfer_bucket ~= nil then
    local was_selected = state.bucket == tags.transfer_bucket
    reset_log(state)
    if not was_selected then state.bucket = tags.transfer_bucket end
  elseif tags.transfer_delivery then
    if state.expanded == tags.transfer_delivery then state.expanded = nil else state.expanded = tags.transfer_delivery end
  elseif tags.transfer_page then
    state.page = (state.page or 1) + tags.transfer_page
    state.expanded = nil
  else
    return false
  end
  return true
end

return UI
