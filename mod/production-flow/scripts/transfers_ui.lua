local Loc = require("scripts.locale")
local Canvas = require("scripts.canvas")
local Graph = require("scripts.graph")
local GuiPlot = require("scripts.gui_plot")
local Sampler = require("scripts.sampler")
local Transfers = require("scripts.transfers")
local Tooltip = require("scripts.tooltip")
local Surfaces = require("scripts.surfaces")
local Exchanges = require("scripts.transfer_exchanges")
local Axis = require("scripts.transfer_history_axis")
local HistoryLayout = require("scripts.transfer_history_layout")
local Manifest = require("scripts.transfer_manifest_ui")

local UI = {}
local Shades = require("shared.ribbon_shades")
local LOADED, UNLOADED, MADE = Shades.color("in", 1), Shades.color("out", 1), Shades.color("made")
local GRID = { r = 0.25, g = 0.25, b = 0.26, a = 1 }
local AXIS = { r = 0.49, g = 0.48, b = 0.46, a = 1 }
local TICK = { r = 0.75, g = 0.74, b = 0.71, a = 1 }
local HIGHLIGHT = { r = 0.28, g = 0.24, b = 0.18, a = 1 }
local CARD_ROW, CARD_HEADER, CARD_GAP = 30, 34, 12
local DIRECTIONS = { "loaded", "unloaded" }
local LAYOUT_VERSION = 24 -- above 0.2.10's 23: upgrades rebuild the platform node
local SPLIT_GAP, PANEL_INSET = 12, 8
local LIST_HEADER_HEIGHT, TAB_HEIGHT, TAB_CHROME = 36, 36, 48
-- Platform node: 2 px padding, 34 px strip, four 25 px stat rows.
local GRAPH_TOP, PLATFORM_HEIGHT, STAT_ROW = 34, 138, 25
-- The Made ribbon meets the middle of the second stat row (Made aboard).
local MADE_PORT = 2 + 34 + 25 + 12
local SCROLLBAR_WIDTH = 12
-- Platform list: 28 px rows (a 24 px star with 2 px around it) flush with the
-- panel, and a scrollbar lane plus 8 px gutter only when it scrolls.
local PLATFORM_ROW, FAVOURITE_WIDTH, LIST_PAD, LIST_GUTTER = 28, 24, 12, 8

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
  return parent.add { type = "sprite-button", name = name, sprite = Loc.join("utility/", icon),
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
  if data.unknown_weight and grams == 0 then return Loc("transfers-unknown") end
  local unit, value = Loc("transfers-g"), number(grams)
  if grams >= 1000000 then
    unit, value = Loc("transfers-t"), string.format("%.2f", grams / 1000000)
  elseif grams >= 1000 then
    unit, value = Loc("transfers-kg"), string.format("%.1f", grams / 1000)
  end
  return Loc.join((data.unknown_weight and "≥" or ""), value, " ", unit)
end

local function clock(tick, seconds)
  local elapsed = math.floor(math.max(tick, 0) / 60)
  local h, m, s = math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60, elapsed % 60
  if seconds then return string.format("%02d:%02d:%02d", h, m, s) end
  return string.format("%02d:%02d", h, m)
end

local function range(from, to)
  local seconds = to - from < 3600
  return Loc.join(clock(from, seconds), " – ", clock(to, seconds))
end

local function item_name(name, with_icon)
  local prototype = prototypes.item[name]
  if not prototype then return (name:gsub("-", " ")) end
  if with_icon then return { "", Graph.rt(Loc.join("item/", name)), " ", prototype.localised_name } end
  return prototype.localised_name
end

local function manifest_tooltip(header, detail, items, seconds)
  local parts = { header, "\n", detail }
  if seconds and seconds > 0 and #items > 0 then parts[#parts + 1] = Loc("transfers-average-rate-over-recorded-time") end
  for _, item in ipairs(items) do
    local entry = { "", "\n", item_name(item.name, true), "  ", number(item.count) }
    if seconds and seconds > 0 then entry[#entry + 1] = Loc.join("  ", Loc("transfers-items-s", string.format("%.5g", item.count / seconds))) end
    parts[#parts + 1] = entry
  end
  return Tooltip.lines(parts)
end

local function endpoint_name(endpoint)
  local name, icon = Transfers.describe(endpoint)
  if endpoint.surface.valid then
    name = Surfaces.platform_name(endpoint.surface) or Surfaces.localised(endpoint.surface)
  elseif icon and icon:match("^space%-location/") then
    name = { "?", { "space-location-name." .. icon:sub(16) }, name }
  end
  return endpoint.surface.valid and name or Loc("removed-surface", name), icon
end

local function platform_hub(force, id)
  if not id then return end
  for _, platform in pairs(force.platforms or {}) do
    if platform.valid and platform.index == id then
      local hub = platform.hub
      if hub and hub.valid and hub.force == force then return hub end
      return
    end
  end
end

local function platform_caption(platform)
  -- Keep rich-text names, and give icon-only names a readable identifier.
  if platform.name:gsub("%[[^%]]+%]", ""):match("^%s*$") then
    return Loc.join(platform.name, " #", platform.id)
  end
  return platform.name
end

local function add_platform_row(list, platform, width, favourite)
  local star = list.add { type = "sprite-button", name = Loc.join("favourite_", platform.id), style = "tool_button",
    sprite = favourite and "ssk-star" or "ssk-star-off", toggled = favourite,
    tags = { transfer_favourite = platform.id },
    tooltip = favourite and Loc("transfers-remove-this-platform-from-favourites") or Loc("transfers-add-this-platform-to-favourites-at-the") }
  star.style.width, star.style.height = FAVOURITE_WIDTH, FAVOURITE_WIDTH
  local inset = (PLATFORM_ROW - FAVOURITE_WIDTH) / 2
  star.style.left_margin, star.style.right_margin = inset, inset
  star.style.top_margin, star.style.bottom_margin = inset, inset
  -- A vanilla list-box row: the whole row is the click target, and the selected
  -- platform is drawn with the list box's selected highlight (toggled).
  local name = platform_caption(platform)
  local pick = list.add { type = "button", name = Loc.join("platform_", platform.id),
    style = "list_box_item", caption = name, tooltip = name, tags = { transfer_platform = platform.id } }
  pick.style.width, pick.style.height = width - PLATFORM_ROW, PLATFORM_ROW
end

local function update_platforms(list, platforms, selected, favourites)
  local parts, pinned, others = {}, {}, {}
  for _, platform in ipairs(platforms) do
    local favourite = favourites and favourites[platform.id]
    local group = favourite and pinned or others
    group[#group + 1] = platform
    parts[#parts + 1] = Loc.join(platform.id, ":", favourite and "1:" or "0:", platform.name)
  end
  local scroll = list.parent
  local scrolls = #platforms * PLATFORM_ROW > list.tags.viewport_height
  local width = list.tags.full_width - (scrolls and SCROLLBAR_WIDTH + LIST_GUTTER or 0)
  local policy = scrolls and "auto-and-reserve-space" or "dont-show-but-allow-scrolling"
  if scroll.vertical_scroll_policy ~= policy then scroll.vertical_scroll_policy = policy end

  local signature = Loc.join_list(parts, "\n") .. ":" .. width
  if list.tags.signature ~= signature then
    list.clear()
    local tags = list.tags
    tags.row_width, tags.signature = width, signature
    list.tags = tags
    for _, platform in ipairs(pinned) do add_platform_row(list, platform, width, true) end
    for _, platform in ipairs(others) do add_platform_row(list, platform, width, false) end
  end
  for _, platform in ipairs(platforms) do
    local pick = list[Loc.join("platform_", platform.id)]
    local active = selected ~= nil and selected.id == platform.id
    if pick.toggled ~= active then pick.toggled = active end
  end
end

local function scroll(parent, name, width, height)
  local pane = parent.add { type = "scroll-pane", name = name, style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
  pane.style.width, pane.style.height = width, height
  return pane
end

local function build(content, width, height)
  local panel = content.add { type = "flow", name = "ssk_transfers",
    direction = "vertical", tags = { transfers_layout = LAYOUT_VERSION } }
  panel.style.width, panel.style.height = width, height
  local split = row(panel, "split")
  split.style.vertical_align, split.style.horizontal_spacing = "top", SPLIT_GAP
  local sidebar_w = math.max(160, math.min(264, math.floor(width * 0.18)))
  local details_w = width - sidebar_w - SPLIT_GAP
  local sidebar = split.add { type = "frame", name = "sidebar", style = "inside_deep_frame", direction = "vertical" }
  sidebar.style.width, sidebar.style.height, sidebar.style.padding = sidebar_w, height, 0
  -- A one-line title strip, then the rows straight on the panel, edge to edge and
  -- down to its foot, with the scrollbar against the panel's right border.
  local side_header = sidebar.add { type = "frame", name = "heading", style = "subheader_frame",
    direction = "horizontal" }
  side_header.style.width, side_header.style.height = sidebar_w, LIST_HEADER_HEIGHT
  side_header.style.left_padding, side_header.style.right_padding = LIST_PAD, LIST_PAD
  side_header.style.top_padding, side_header.style.bottom_padding = 4, 4
  side_header.style.vertical_align = "center"
  label(side_header, nil, Loc("transfers-platforms"), "subheader_caption_label")
  spacer(side_header)
  label(side_header, "count", "", "subheader_semibold_label")

  local list_w = sidebar_w
  local list_h = math.max(PLATFORM_ROW, height - LIST_HEADER_HEIGHT)
  local platform_scroll = scroll(sidebar, "platform_scroll", list_w, list_h)
  platform_scroll.vertical_scroll_policy = "dont-show-but-allow-scrolling"
  local platforms = platform_scroll.add { type = "table", name = "ssk_transfer_platforms", column_count = 2,
    style = "table", tags = { full_width = list_w, viewport_height = list_h } }
  platforms.style.horizontal_spacing, platforms.style.vertical_spacing = 0, 0
  platforms.style.top_cell_padding, platforms.style.bottom_cell_padding = 0, 0
  platforms.style.left_cell_padding, platforms.style.right_cell_padding = 0, 0

  local tab_row = row(split, "tab_row")
  tab_row.style.vertical_align, tab_row.style.horizontal_spacing = "top", 0
  local tabs = tab_row.add { type = "tabbed-pane", name = "ssk_transfer_tabs",
    style = "tabbed_pane_with_no_side_padding", tags = { transfer_tabs = true } }
  tabs.style.width, tabs.style.top_margin = details_w, 0
  local tab_h = height - TAB_CHROME
  for _, view in ipairs({ { "flow", Loc("help-flow") }, { "history", Loc("help-history") } }) do
    local tab = tabs.add { type = "tab", caption = view[2] }
    local body = tabs.add { type = "frame", name = "ssk_transfer_" .. view[1], direction = "vertical",
      style = "inside_deep_frame" }
    body.style.width, body.style.height, body.style.padding = details_w, tab_h, PANEL_INSET
    local tab_content = body.add { type = "flow", name = "content", direction = "vertical",
      tags = { transfer_width = details_w - 2 * PANEL_INSET, transfer_height = tab_h - 2 * PANEL_INSET } }
    tab_content.style.vertical_spacing = 4
    tabs.add_tab(tab, body)
  end
  tabs.selected_tab_index = 1

  -- The native tab strip leaves room for the controls and right-aligned title.
  local header_w = details_w - 196
  local heading = row(tab_row, "heading")
  heading.style.width, heading.style.height = header_w, TAB_HEIGHT
  heading.style.left_margin, heading.style.right_margin = -(header_w + 12), 12
  heading.style.horizontal_spacing = 8
  spacer(heading)
  local compact = header_w < 400
  heading.add { type = "checkbox", name = "ssk_transfer_show_all_production",
    caption = compact and Loc("transfers-all-production") or Loc("transfers-show-all-onboard-production"),
    state = false, tags = { transfer_show_all_production = true },
    tooltip = Loc("transfers-when-off-made-aboard-shows-only-items") }
  local icon = heading.add { type = "sprite", name = "icon", resize_to_sprite = false }
  icon.style.width, icon.style.height = 24, 24
  icon.style.left_margin = 4
  local caption = label(heading, "platform", "", "subheader_caption_label")
  caption.style.maximal_width = math.min(320, math.max(32, header_w - (compact and 156 or 240) - 36))
  caption.style.single_line = true
  heading.add { type = "sprite-button", name = "ssk_transfer_jump", style = "tool_button",
    sprite = "utility/map", tooltip = Loc("transfers-jump-to-this-platform-in-remote-view") }
  return panel
end

-- Keep native controls aligned with plot coordinates.
local function position_reset_name(el)
  if el.name and el.name~="" then return "ssk_transfer_position_reset_"..el.name end
  local tags=el.tags
  if not tags.transfer_position_reset then
    tags.transfer_position_reset="ssk_transfer_position_reset_anon_"..(#el.parent.children+1)
    el.tags=tags
  end
  return tags.transfer_position_reset
end

local function place(el, x, y, width, height)
  local style = el.style
  style.width, style.height = width, height
  style.left_margin, style.top_margin, style.bottom_margin = x, y, -height
  local parent,name=el.parent,position_reset_name(el)
  local reset=parent[name]
  if not reset then
    reset=parent.add { type="empty-widget",name=name,index=el.get_index_in_parent()+1,
      ignored_by_interaction=true }
  end
  reset.style.width,reset.style.height=0,0
  reset.style.left_margin,reset.style.bottom_margin=0,0
  reset.style.top_margin=-y
  reset.visible=el.visible~=false
  return el
end

local function overlay_visible(el,visible)
  el.visible=visible
  local reset=el.parent[position_reset_name(el)]
  if reset then reset.visible=visible end
end

local function plot(parent, player, width, height)
  Canvas.clear(player.index)
  if parent.ssk_transfer_plot then parent.ssk_transfer_plot.destroy() end
  local painter=GuiPlot.begin(parent,width,height,"ssk_transfer_plot")
  painter.root.style.bottom_margin=-height
  return painter
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

-- A surface card: name, mass and pod count in the strip, then up to five items.
-- Each row carries a count ("×406") and a bar under the name, scaled to the
-- card's largest item, so items compare at a glance. A 3 px stripe in the
-- ribbon colour marks the edge where the ribbon attaches (side "left"/"right").
local function ranking(parent, name, icon, data, x, y, width, colour, side)
  local tip = manifest_tooltip(name, Loc("transfers-cargo-mass", mass(data)), data.items)
  local height = card_height(data.items)
  local wrapper = parent.add { type = "flow", direction = "horizontal" }
  place(wrapper, x, y, width, height)
  local card = wrapper.add { type = "frame", name = "ssk_transfer_surface_card", style = "inside_deep_frame",
    direction = "vertical", tooltip = tip, tags = { transfer_surface = name, transfer_rank_count = math.min(5, #data.items) } }
  card.style.width, card.style.padding = width, 2
  local header = strip(card, "heading", CARD_HEADER)
  -- Keep the header text clear of the ribbon-colour stripe on the ribbon side.
  header.style.left_padding = side == "left" and 11 or 8
  header.style.right_padding = side == "right" and 11 or 8
  local pods = (data.pods or 0) > 0 and data.pods or nil
  if icon then sprite(header, icon, 23) end
  local name_label = plain(label(header, "surface_name", name, "subheader_caption_label"))
  name_label.style.maximal_width, name_label.tooltip = width - 4 - 19 - (icon and 27 or 0) - 84 - (pods and 64 or 0), tip
  spacer(header)
  label(header, "weight", mass(data), "subheader_semibold_label").tooltip = tip
  if pods then
    local count = label(header, "pods", Loc("cargo-pod-count", pods, number(pods)), "grey_label")
    count.style.left_margin, count.tooltip = 8, tip
  end

  local rows = card.add { type = "table", name = "rows", column_count = 1, style = "ssk_balance_grid",
    draw_horizontal_lines = true }
  rows.style.horizontal_spacing, rows.style.vertical_spacing = 0, 0
  rows.style.top_cell_padding, rows.style.bottom_cell_padding = 0, 0
  rows.style.left_cell_padding, rows.style.right_cell_padding = 0, 0
  local name_w = width - 4 - 12 - 19 - 52 - 12
  for i = 1, math.min(5, #data.items) do
    local item = data.items[i]
    local line = row(rows, Loc.join("rank_", i))
    line.tags = { transfer_rank = item.name, count = item.count }
    line.style.width, line.style.height, line.style.horizontal_spacing = width - 4, CARD_ROW, 6
    line.style.left_padding, line.style.right_padding = 6, 6
    line.tooltip = tip
    sprite(line, Loc.join("item/", item.name), 19)
    local text = line.add { type = "flow", direction = "vertical" }
    text.style.vertical_spacing, text.style.width = 2, name_w
    label(text, nil, item_name(item.name), nil, name_w).tooltip = tip
    local size = math.max(1, math.floor(name_w * item.count / data.items[1].count + 0.5))
    local bar = sprite(text, colour, size)
    bar.style.height, bar.style.stretch_image_to_widget_size = 3, true
    local count = label(line, nil, Loc.join("×", number(item.count)), "bold_label", 52)
    count.style.horizontal_align, count.tooltip = "right", tip
  end
  if #data.items > 5 then
    local foot = label(card, nil, Loc("transfers-more-hover-for-all-items", (#data.items - 5)), "grey_label", width - 8)
    foot.style.left_margin, foot.tooltip = 6, tip
  end
  local edge = parent.add { type = "flow", direction = "horizontal" }
  place(edge, side == "left" and x or x + width - 3, y, 3, height)
  local stripe = sprite(edge, colour, 3)
  stripe.style.height, stripe.style.stretch_image_to_widget_size = height, true
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
  painter.polygon({ { x1 - 6, y1 - 4 }, { x1 - 6, y1 + 4 }, { x1, y1 }, { x1, y1 } }, TICK)
  return ribbon_shape(x0, y0, x1, y1, width)
end

local function flow_signature(result, width, viewport)
  local parts = { result.platform.id, result.platform.name, result.platform.location or "", result.made.seconds or 0, width or 0, viewport or 0 }
  local function manifest(data)
    -- Cache identities depend on raw data, never a per-player LocalisedString.
    parts[#parts + 1] = data.weight or 0
    parts[#parts + 1] = tostring(data.unknown_weight == true)
    for _, item in ipairs(data.items) do
      parts[#parts + 1], parts[#parts + 2] = item.name, item.count
    end
  end
  for _, routes in ipairs({ result.loading, result.unloading }) do
    parts[#parts + 1] = #routes
    for _, route in ipairs(routes) do
      parts[#parts + 1], parts[#parts + 2] = route.endpoint.id, Transfers.describe(route.endpoint)
      parts[#parts + 1] = tostring(route.endpoint.surface.valid)
      manifest(route)
    end
  end
  manifest(result.made)
  return table.concat(parts, "\n")
end

local function flow_layout(routes)
  local layout, y = {}, 0
  for _, route in ipairs(routes) do
    local h = card_height(route.items)
    layout[#layout + 1] = { route = route, y = y, center = y + h / 2 }
    y = y + h + CARD_GAP
  end
  return layout, math.max(0, y - CARD_GAP)
end

local function flow_graph(player, parent, result, width, viewport)
  local left, left_height = flow_layout(result.loading)
  local right, right_height = flow_layout(result.unloading)
  local made = #result.made.items > 0
  local made_height = made and card_height(result.made.items) or 0
  local empty_y = GRAPH_TOP + 2
  local lower_left = left_height / 2
  if made then lower_left = #left > 0 and lower_left + CARD_GAP + made_height or made_height / 2 end
  local half = math.ceil(math.max(lower_left, right_height / 2, PLATFORM_HEIGHT / 2))
  local height = math.max(viewport - 4, GRAPH_TOP + 2 * half + 4, made_height + empty_y + 34, 240)
  if height > viewport then width = width - SCROLLBAR_WIDTH end
  local middle = math.floor((GRAPH_TOP + height - 4) / 2)
  local left_top, right_top = middle - left_height / 2, middle - right_height / 2
  local made_y = #left == 0 and math.max(empty_y + 30, middle - made_height / 2)
    or left_top + left_height + CARD_GAP
  local card_w = math.min(254, math.floor(width * 0.28))
  local center_w = math.min(192, math.floor(width * 0.26))
  local x_left, x_right, x_center = 4, width - card_w - 4, math.floor((width - center_w) / 2)
  local center_y = middle - PLATFORM_HEIGHT / 2
  local highest = 1
  for _, list in ipairs({ left, right }) do
    for _, cell in ipairs(list) do highest = math.max(highest, cell.route.weight or 0) end
  end
  local signature = flow_signature(result, width, viewport)
  local update = parent.tags.transfer_graph ~= signature
  if not update then return end
  parent.clear()
  parent.style.width, parent.style.height = width, height
  local painter = plot(parent, player, width, height)
  local platform_name = result.platform.name
  local function route_hover(shape, caption, route, direction, index)
    local tip = manifest_tooltip(caption, Loc("transfers-cargo-mass", mass(route)), route.items, result.covered_seconds)
    Tooltip.ribbon(parent, { shape }, tip, { transfer_ribbon = direction },
      Loc.join("ssk_transfer_ribbon_", direction, "_", index, "_"))
  end
  for i, cell in ipairs(left) do
    local offset = (i / (#left + 1) - 0.5) * 34
    local shape = draw_ribbon(painter, x_left + card_w, left_top + cell.center, x_center, middle + offset, cell.route, highest, Shades.color("in", i))
    route_hover(shape, Loc.join(endpoint_name(cell.route.endpoint), " → ", platform_name), cell.route, "loaded", i)
  end
  for i, cell in ipairs(right) do
    local offset = (i / (#right + 1) - 0.5) * 34
    local shape = draw_ribbon(painter, x_center + center_w, middle + offset, x_right, right_top + cell.center, cell.route, highest, Shades.color("out", i))
    route_hover(shape, Loc.join(platform_name, " → ", endpoint_name(cell.route.endpoint)), cell.route, "unloaded", i)
  end
  if made then
    local x, y = x_left + card_w, made_y + made_height / 2
    painter.line(x, y, x_center, center_y + MADE_PORT, MADE, 2, true)
    local shape = ribbon_shape(x, y, x_center, center_y + MADE_PORT, 2, true)
    local tip = manifest_tooltip(Loc("transfers-made-aboard", platform_name), Loc("transfers-recorded-platform-production"), result.made.items, result.made.seconds)
    Tooltip.ribbon(parent, { shape }, tip, { transfer_ribbon = "made" }, "ssk_transfer_ribbon_made_")
  end
  parent.tags = { transfer_graph = signature }
  canvas_label(parent, Loc("transfers-loading-surfaces"), "heading_2_label", x_left, 2, card_w)
  canvas_label(parent, Loc("transfers-selected-platform"), "heading_2_label", x_center, 2, center_w, "center")
  canvas_label(parent, Loc("transfers-unloading-surfaces"), "heading_2_label", x_right, 2, card_w)
  if #left == 0 then canvas_label(parent, Loc("transfers-no-recorded-loads"), "grey_label", x_left, empty_y, card_w) end
  if #right == 0 then canvas_label(parent, Loc("transfers-no-recorded-unloads"), "grey_label", x_right, empty_y, card_w) end
  -- Each card's stripe and item bars take its own ribbon's shade.
  for _, entry in ipairs({ { left, x_left, "in", left_top, "right" }, { right, x_right, "out", right_top, "left" } }) do
    for i, cell in ipairs(entry[1]) do
      local name, icon = endpoint_name(cell.route.endpoint)
      ranking(parent, name, icon, cell.route, entry[2], math.floor(entry[4] + cell.y + 0.5), card_w, Shades.sprite(entry[3], i), entry[5])
    end
  end
  if made then ranking(parent, Loc("transfers-made-aboard-2"), nil, result.made, x_left, math.floor(made_y + 0.5), card_w, Shades.sprite("made"), "right") end

  local wrapper = parent.add { type = "flow", direction = "horizontal" }
  place(wrapper, x_center, center_y, center_w, PLATFORM_HEIGHT)
  local platform = wrapper.add { type = "frame", name = "ssk_transfer_platform_node", style = "inside_deep_frame",
    direction = "vertical" }
  platform.style.width, platform.style.height, platform.style.padding = center_w, PLATFORM_HEIGHT, 2
  -- Name and where the platform is in the strip; stats in flow order (in, made,
  -- out), then the net mass kept aboard. A zero shows as a grey dash.
  local header = strip(platform, "heading", 34)
  local where = result.platform.location
  local place_name = where and prototypes.space_location and prototypes.space_location[where]
    and prototypes.space_location[where].localised_name or where or Loc("transfers-in-transit")
  local caption = platform_caption(result.platform)
  label(header, "platform_name", caption, "subheader_semibold_label", center_w - 96).tooltip = caption
  spacer(header)
  local location = label(header, "platform_location", place_name, "grey_label", 72)
  location.style.horizontal_align, location.tooltip = "right", place_name
  local stats = platform.add { type = "table", name = "stats", column_count = 1, style = "ssk_balance_grid",
    draw_horizontal_lines = true }
  stats.style.horizontal_spacing, stats.style.vertical_spacing = 0, 0
  stats.style.top_cell_padding, stats.style.bottom_cell_padding = 0, 0
  stats.style.left_cell_padding, stats.style.right_cell_padding = 0, 0
  local no_history = result.made.seconds == 0
  local unknown = no_history or result.loaded.unknown_weight or result.unloaded.unknown_weight or result.made.unknown_weight
  local kept = (result.loaded.weight or 0) + (result.made.weight or 0) - (result.unloaded.weight or 0)
  for _, stat in ipairs({ { "loaded", Loc("transfers-loaded"), result.loaded, Shades.sprite("in") },
      { "made", Loc("transfers-made-aboard-2"), result.made, Shades.sprite("made") },
      { "unloaded", Loc("transfers-unloaded"), result.unloaded, Shades.sprite("out") }, { "kept", Loc("transfers-kept-aboard") } }) do
    local line = row(stats, stat[1])
    line.style.width, line.style.height = center_w - 4, STAT_ROW
    line.style.left_padding, line.style.right_padding, line.style.horizontal_spacing = 8, 8, 6
    if stat[4] then sprite(line, stat[4], 7) else line.add { type = "empty-widget" }.style.width = 7 end
    local data, value, tip = stat[3], nil, nil
    if stat[1] == "kept" then
      value = unknown and Loc("transfers-unknown") or Loc.join(kept > 0 and "+" or kept < 0 and "−" or "", mass({ weight = math.abs(kept) }))
      tip = Loc("transfers-kept-aboard-help")
    elseif stat[1] == "made" and no_history then
      value, tip = "—", Loc("transfers-no-production-history-is-available-for-this")
    elseif (data.weight or 0) == 0 and not data.unknown_weight then
      value = "—"
    else
      value = mass(data)
    end
    local muted = value == "—"
    label(line, "stat_caption", stat[2], muted and "grey_label" or nil).tooltip = tip
    spacer(line)
    local weight = label(line, "stat_value", value, muted and "grey_label" or "bold_label")
    weight.tooltip = tip
  end
end

local function render_flow(player, body, result, note)
  local width, height = body.tags.transfer_width, body.tags.transfer_height
  local graph_height = height - 30
  if not body.graph then
    local pane = scroll(body, "graph", width, graph_height)
    pane.vertical_scroll_policy = "auto"
    local canvas = pane.add { type = "flow", name = "canvas", direction = "vertical" }
    canvas.style.vertical_spacing = 0
    local legend = row(body, "legend")
    legend.style.width, legend.style.height = width, 26
    legend.style.left_padding, legend.style.right_padding = 8, 8
    for _, key in ipairs({ { Loc("transfers-loaded"), "in" }, { Loc("transfers-unloaded"), "out" }, { Loc("transfers-made-aboard-2"), "made" } }) do
      sprite(legend, Shades.sprite(key[2]), 8)
      label(legend, nil, key[1], "grey_label").style.right_margin = 8
    end
    spacer(legend)
    label(legend, "note", "", "grey_label", math.max(40, width - 300)).style.horizontal_align = "right"
  end
  body.legend.note.caption = note or Loc("transfers-ribbon-width-shows-known-cargo-mass")
  body.legend.note.tooltip = note or Loc("transfers-mass-uses-each-item-s-space-age")
  flow_graph(player, body.graph.canvas, result, width, graph_height)
end

local function bucket_tooltip(bucket, direction, start_tick, end_tick, recorded_from)
  local cargo = bucket[direction]
  local title = Loc.join((direction == "loaded" and Loc("transfers-loaded-onto-platform") or Loc("transfers-unloaded-to-surface")), " · ", range(start_tick, end_tick))
  local detail = Loc("cargo-pod-count", cargo.pods, number(cargo.pods))
  if cargo.pods > 0 then detail = Loc.join(detail, " · ", mass(cargo)) end
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

local function timeline(player, chart, result, width, height,state)
  local painter = plot(chart, player, width, height)
  local left, right, top, bottom = width < 650 and 115 or 156, width - 24, 10, height - 29
  local mid = math.floor((top + bottom) / 2)
  local events=state.axis=="events"
  local buckets=result.buckets
  local event_start=1
  if events then
    local _,_,first,last=Exchanges.page(result.exchanges,right-left,state.event_page)
    event_start=first;buckets={}
    for i=first,last do buckets[#buckets+1]=result.exchanges[i] end
  end
  local peak = 1
  for _, bucket in ipairs(buckets) do
    for _, direction in ipairs(DIRECTIONS) do peak = math.max(peak, bucket[direction].pods) end
  end
  local step = nice_step(peak)
  local edge = math.ceil(peak / step) * step
  local scale = (mid - top - 4) / edge
  local domain = math.max(1, result.to_tick - result.from_tick)
  local recorded_from = result.to_tick - result.covered_seconds * 60
  local function x(tick) return left + (right - left) * (tick - result.from_tick) / domain end

  local function band(bucket,i)
    if events then return right-(#buckets-i+1)*Exchanges.SLOT,right-(#buckets-i)*Exchanges.SLOT end
    return x(math.max(bucket.start_tick,result.from_tick)),x(math.min(bucket.end_tick,result.to_tick))
  end
  local selected = events and result.exchange or result.bucket
  for i, bucket in ipairs(buckets) do
    if (events and bucket.key or bucket.start_tick) == selected then
      local a,b=band(bucket,i)
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
  for i = 0, events and -1 or spacing do
    local tick = result.from_tick + domain * i / spacing
    painter.text(x(tick), bottom + 13, clock(tick, domain < 5 * 60 * 60), TICK, "center")
  end
  local middle_top = math.floor((top + mid) / 2)
  local middle_bottom = math.floor((mid + bottom) / 2)
  for _, lane in ipairs({ { middle_top, LOADED, Loc("transfers-loaded-onto"), Loc("transfers-the-platform") },
      { middle_bottom, UNLOADED, Loc("transfers-unloaded-to"), Loc("transfers-a-surface") } }) do
    painter.rect(8, lane[1] - 8, 8, 8, lane[2])
    painter.text(22, lane[1] - 4, lane[3], TICK, "left")
    painter.text(22, lane[1] + 12, lane[4], TICK, "left")
  end

  for i, bucket in ipairs(buckets) do
    local start_tick, end_tick = math.max(bucket.start_tick, result.from_tick), math.min(bucket.end_tick, result.to_tick)
    local a,b=band(bucket,i);a,b=math.floor(a),math.ceil(b)
    local band = math.max(1, b - a)
    local gap = math.floor(band * 0.14)
    for j, direction in ipairs(DIRECTIONS) do
      local up, amount = j == 1, bucket[direction].pods
      local magnitude = math.max(1, amount * scale)
      local color = up and LOADED or UNLOADED
      if amount > 0 then
        painter.rect(a + gap, up and mid - magnitude or mid + 1, band - 2 * gap, magnitude, color)
        if selected == (events and bucket.key or bucket.start_tick) and band >= 23 then
          painter.text(a + band / 2, up and mid - 9 or mid + 10, number(amount), TICK, "center")
        end
      end

      local name = Loc.join("ssk_transfer_bucket_", direction, "_", i)
      local hit = chart[name] or chart.add { type = "sprite", name = name, sprite = "ssk-node-hit",
        resize_to_sprite = false }
      hit.tooltip = bucket_tooltip(bucket, direction, start_tick, end_tick, recorded_from)
      hit.tags = events and {transfer_exchange=bucket.key,transfer_direction=direction}
        or { transfer_bucket = bucket.start_tick, transfer_direction = direction }
      place(hit, a, up and top or mid, band, up and mid - top or bottom - mid)
      overlay_visible(hit,true)
    end
    if events and (i-1)%3==0 then painter.text((a+b)/2,bottom+13,"#"..(event_start+i-1),TICK,"center") end
  end
  for i = #buckets + 1, chart.tags.bucket_count or 0 do
    for _, direction in ipairs(DIRECTIONS) do overlay_visible(chart[Loc.join("ssk_transfer_bucket_", direction, "_", i)],false) end
  end
  chart.tags = { bucket_count = math.max(#buckets, chart.tags.bucket_count or 0) }
end

local LOG_ROW_PADDING = 4
local LOG_COLUMN_GAP = 12
local LOG_EXPAND_WIDTH = 24

local function log_widths(width)
  local arrival = width < 600 and 80 or 110
  local direction = width < 600 and 76 or 104
  local surface = math.min(170, math.floor(width * 0.20))
  local weight = width < 600 and 76 or 100
  local row_chrome = LOG_EXPAND_WIDTH + 2 * LOG_ROW_PADDING + 5 * LOG_COLUMN_GAP
  local cargo = width - row_chrome - arrival - direction - surface - weight
  return { arrival, direction, surface, cargo, weight }
end

local function log_row(parent)
  local line = row(parent)
  line.style.height, line.style.horizontal_spacing = 4 + LOG_EXPAND_WIDTH, LOG_COLUMN_GAP
  line.style.left_padding, line.style.right_padding = LOG_ROW_PADDING, LOG_ROW_PADDING
  return line
end

local function detail_row(parent, items, width)
  local detail = parent.add { type = "frame", style = "inside_shallow_frame", direction = "vertical" }
  detail.style.width, detail.style.padding = width, 8
  Manifest.section(detail, "delivered_contents", Loc("se-ui-received-manifest"), items, width - 16, number,
    "ssk_transfer_manifest")
end

local function render_log(body, result, state, width)
  local header, pane = body.delivered, body.log_scroll
  local selected
  for _, bucket in ipairs(result.buckets) do
    if bucket.start_tick == result.bucket then selected = bucket; break end
  end
  local interval = result.exchange and Loc("transfer-exchange-selected")
    or selected and range(math.max(selected.start_tick, result.from_tick),
    math.min(selected.end_tick, result.to_tick)) or Loc("transfers-selected-period")
  header.range.caption = Loc("confirmed-pod-count", interval, result.arrival_count, number(result.arrival_count))
  header.range.tooltip = Loc("transfers-arrival-time-is-shown-as-elapsed-simulation")
  header.reset_bucket.visible = selected ~= nil or result.exchange ~= nil
  header.previous.visible, header.next.visible, header.pages.visible = result.pages > 1, result.pages > 1, result.pages > 1
  header.previous.enabled, header.next.enabled = result.page > 1, result.page < result.pages
  header.pages.caption = Loc.join(result.page, " / ", result.pages)
  local keys = {}
  for i, pod in ipairs(result.arrivals) do keys[i] = tostring(pod.id) end
  local signature = Loc.join((state.expanded and tostring(state.expanded) or "-"), ":", Loc.join_list(keys, ","))
  if pane.tags.log == signature then return end
  pane.tags = { log = signature }
  pane.clear()
  if #result.arrivals == 0 then
    label(pane, nil, Loc("transfers-no-confirmed-deliveries-in-this-range"), "grey_label").style.left_margin = 8
    return
  end
  local columns = log_widths(width - 24)
  for i, pod in ipairs(result.arrivals) do
    local line = log_row(pane)
    local expanded = state.expanded == pod.id
    local expand = action(line, Loc.join("ssk_transfer_delivery_", i), expanded and "collapse" or "expand",
      expanded and Loc("transfers-collapse-cargo-manifest") or Loc("transfers-expand-cargo-manifest"), { transfer_delivery = pod.id })
    expand.style.width, expand.style.height = LOG_EXPAND_WIDTH, LOG_EXPAND_WIDTH
    expand.toggled = expanded
    label(line, nil, clock(pod.tick, true), nil, columns[1])
    local direction = row(line)
    direction.style.width = columns[2]
    local loaded = pod.direction == "loaded"
    sprite(direction, Shades.sprite(loaded and "in" or "out"), 8)
    label(direction, nil, loaded and Loc("transfers-loaded") or Loc("transfers-unloaded"), "bold_label")
    local endpoint = row(line)
    endpoint.style.width = columns[3]
    local name, icon = endpoint_name(pod.endpoint)
    sprite(endpoint, icon, 18)
    plain(label(endpoint, nil, name, nil, columns[3] - 22)).tooltip = name
    local cargo = row(line)
    cargo.style.width = columns[4]
    cargo.tooltip = manifest_tooltip(name, mass(pod), pod.items)
    Manifest.preview(cargo, pod.items, columns[4])
    local weight = label(line, nil, mass(pod), "caption_label", columns[5])
    weight.style.horizontal_align = "right"
    weight.tooltip = Loc("transfers-full-cargo-pod-mass")
    if expanded then detail_row(pane, pod.items, width - 24) end
  end
end

local function render_history(player, body, result, state, note)
  local width, height = body.tags.transfer_width, body.tags.transfer_height
  local chart_height = HistoryLayout.plot_height(height)
  if not body.chart then
    local heading = HistoryLayout.strip(body, "timeline_heading")
    label(heading, nil, Loc("transfers-cargo-timeline"), "subheader_caption_label")
    label(heading, "units", "", "grey_label")
    spacer(heading)
    action(heading,"previous_exchanges","left_arrow",Loc("transfer-exchanges-previous"),{transfer_exchange_page=-1})
    label(heading,"exchange_pages","","grey_label")
    action(heading,"next_exchanges","right_arrow",Loc("transfer-exchanges-next"),{transfer_exchange_page=1})
    Axis.add(heading, state.axis, Loc("transfer-axis-help"))
    label(heading, "counts", "", "subheader_semibold_label")
    local chart = body.add { type = "flow", name = "chart", direction = "vertical" }
    chart.style.width, chart.style.height, chart.style.vertical_spacing = width, chart_height, 0
    local delivered = HistoryLayout.strip(body, "delivered")
    label(delivered, nil, Loc("transfers-delivered-cargo"), "subheader_caption_label")
    spacer(delivered)
    label(delivered, "range", "", "subheader_semibold_label")
    action(delivered, "reset_bucket", "reset", Loc("transfers-clear-selected-time-bucket"), { transfer_reset_bucket = true })
    action(delivered, "previous", "left_arrow", Loc("transfers-previous-page"), { transfer_page = -1 })
    label(delivered, "pages", "", "grey_label")
    action(delivered, "next", "right_arrow", Loc("transfers-next-page"), { transfer_page = 1 })
    local headers = log_row(HistoryLayout.columns(body, "log_headers", width - HistoryLayout.SCROLL_GUTTER))
    local gutter = headers.add { type = "empty-widget" }
    gutter.style.width = LOG_EXPAND_WIDTH
    local columns = log_widths(width - 24)
    for i, title in ipairs({ Loc("transfers-arrival"), Loc("transfers-direction"), Loc("transfers-surface"), Loc("transfers-cargo"), Loc("transfers-mass") }) do
      local cell = label(headers, nil, title, "caption_label", columns[i])
      if i == 5 then cell.style.horizontal_align = "right" end
    end
    scroll(body, "log_scroll", width, HistoryLayout.log_height(height, chart_height, 0))
  end
  local seconds = result.bucket_ticks / 60
  local period = Sampler.duration(seconds)
  local heading = body.timeline_heading
  local events=state.axis=="events"
  local left=width<650 and 115 or 156
  local page,pages=Exchanges.page(result.exchanges,width-24-left,state.event_page)
  state._event_pages=pages
  if events then state.event_page=page end
  heading.axis.switch_state=events and "right" or "left"
  heading.previous_exchanges.visible,heading.next_exchanges.visible,heading.exchange_pages.visible=events,events,events
  heading.previous_exchanges.enabled,heading.next_exchanges.enabled=page>1,page<pages
  heading.exchange_pages.caption=Loc("se-ui-page",page,pages)
  heading.units.caption = Loc("transfers-confirmed-pods-2", period)
  heading.units.visible=not events
  heading.units.tooltip = note or Loc("transfers-select-a-time-bucket-to-filter-delivered")
  heading.counts.caption = Loc("transfers-loaded-unloaded", number(result.loaded.pods), number(result.unloaded.pods))
  timeline(player, body.chart, result, width, chart_height,state)
  render_log(body, result, state, width)
  body.delivered.reset_bucket.tooltip=Loc(result.exchange and "transfer-exchange-clear" or "transfers-clear-selected-time-bucket")
end

local function reset_log(state)
  state.bucket, state.page, state.expanded,state.exchange = nil, nil, nil,nil
end

function UI.render(content, player, period, state, width, height)
  local force = player.force
  if state.force ~= force then
    state.force, state.platform = force, nil
    reset_log(state)
  end
  if state.from or state.to or state.material then
    state.from, state.to, state.material = nil, nil, nil
    state.from_label, state.to_label, state.material_label = nil, nil, nil
    reset_log(state)
  end
  if state.period ~= period then
    state.period = period
    reset_log(state)
    state.event_page=nil
  end
  state.view = state.view or "flow"
  local panel = content.ssk_transfers
  if panel and panel.tags.transfers_layout ~= LAYOUT_VERSION then panel.destroy(); panel = nil end
  panel = panel or build(content, width, height)

  local seconds = period > 0 and period or settings.global["ssk-window-seconds"].value
  local available = Transfers.available()
  local result = available and Transfers.platform_view(force, game.tick, seconds, state)
    or { platforms = {} }
  local sidebar, tab_row = panel.split.sidebar, panel.split.tab_row
  local platforms = sidebar.platform_scroll.ssk_transfer_platforms
  update_platforms(platforms, result.platforms, result.platform, state.favourites)
  sidebar.heading.count.caption = tostring(#result.platforms)
  local tabs, heading = tab_row.ssk_transfer_tabs, tab_row.heading
  local jump = heading.ssk_transfer_jump
  jump.visible = result.platform ~= nil
  jump.enabled = result.platform ~= nil and platform_hub(force, result.platform.id) ~= nil
  jump.tags = result.platform and { transfer_jump = result.platform.id } or {}
  local production = heading.ssk_transfer_show_all_production
  tabs.selected_tab_index = state.view == "history" and 2 or 1
  production.visible = result.platform ~= nil and state.view == "flow"
  production.state = state.show_all_production == true
  local body = (state.view == "history" and tabs.ssk_transfer_history or tabs.ssk_transfer_flow).content
  heading.platform.caption = result.platform and platform_caption(result.platform) or Loc("help-transfers")
  heading.platform.tooltip = result.platform and platform_caption(result.platform) or nil
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
    body.empty.caption = available and Loc("transfers-no-space-platforms-on-this-force") or Loc("transfers-transfers-are-available-with-space-age-enabled")
    return result.covered_seconds
  end
  state.platform = result.platform.id
  if body.empty then body.empty.destroy() end
  local note = result.truncated and Loc("transfers-some-deliveries-are-outside-the-retained-history") or nil
  if state.view == "history" then
    state.bucket, state.page = result.bucket, result.page
    state.exchange=result.exchange
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
  return false
end

function UI.on_checked(event, state)
  local el = event.element
  if not (state and el and el.valid and el.tags.transfer_show_all_production) then return false end
  state.show_all_production = el.state
  return true
end

function UI.on_switch(event,state)
  local axis=Axis.selection(event.element)
  if not (state and axis) then return false end
  if state.axis~=axis then state.axis=axis;reset_log(state);state.event_page=nil end
  return true
end

function UI.on_click(event, state, close_all)
  local el = event.element
  if not (state and el and el.valid) then return false end
  local tags = el.tags
  if tags.transfer_jump then
    local player = game.get_player(event.player_index)
    local hub = state.platform == tags.transfer_jump and platform_hub(player.force, tags.transfer_jump)
    if hub then
      close_all(player)
      player.centered_on = hub
    end
  elseif tags.transfer_platform then
    if state.platform ~= tags.transfer_platform then
      state.platform = tags.transfer_platform
      reset_log(state)
      state.event_page=nil
    end
  elseif tags.transfer_favourite then
    local id = tags.transfer_favourite
    state.favourites = state.favourites or {}
    state.favourites[id] = not state.favourites[id] or nil
  elseif tags.transfer_reset_bucket then
    reset_log(state)
  elseif tags.transfer_exchange_page then
    state.event_page=math.max(1,math.min((state.event_page or state._event_pages or 1)+tags.transfer_exchange_page,state._event_pages or 1))
  elseif tags.transfer_exchange then
    local selected=state.exchange==tags.transfer_exchange;reset_log(state)
    if not selected then state.exchange=tags.transfer_exchange end
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
