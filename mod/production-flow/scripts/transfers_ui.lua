local Graph = require("scripts.graph")
local Transfers = require("scripts.transfers")

local UI = {}
local ROWS_PER_PAGE = 150
local TITLES = { "From", "To", "Material", "Delivered", "Last arrival" }
local FILTERS = { { "from", "From" }, { "to", "To" }, { "material", "Material" } }
local FOOTNOTE = "Transfers are recorded when cargo arrives. Each platform leg has its own route."
local BODY_PADDING = 12
local CELL_PADDING = 8
local COLUMN_BORDER = 4
local SCROLLBAR_GUTTER = 20

local function label(parent, name, caption, style)
  return parent.add { type = "label", name = name, caption = caption, style = style }
end

local function row(parent, name)
  local flow = parent.add { type = "flow", name = name, direction = "horizontal" }
  flow.style.vertical_align = "center"
  return flow
end

local function spacer(parent)
  parent.add { type = "empty-widget" }.style.horizontally_stretchable = true
end

local function number(n)
  return (string.format("%.0f", n):reverse():gsub("(%d%d%d)", "%1,"):gsub(",$", ""):reverse())
end

local function quantity(n, noun)
  return number(n) .. " " .. noun .. (n == 1 and "" or "s")
end

local function age(tick, last)
  local seconds = math.floor((tick - last) / 60)
  if seconds == 0 then return "Just now" end
  if seconds < 60 then return seconds .. " s ago" end
  if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
  return math.floor(seconds / 3600) .. " h ago"
end

local function item_name(name)
  local prototype = prototypes.item[name]
  if not prototype then return (name:gsub("-", " ")) end
  return { "", Graph.rt("item/" .. name), " ", prototype.localised_name }
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
    if a.name ~= b.name then return a.name:lower() < b.name:lower() or
      (a.name:lower() == b.name:lower() and a.name < b.name) end
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
  for i, name in ipairs(names) do list[i] = { key = name, name = name, caption = item_name(name) } end
  return list
end

local function update_filter(element, field, choices, state)
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
    items[#items + 1] = field == "material" and item_name(value) or name
    selected = #keys
  end
  local tags = element.tags
  local changed = not tags.keys or #tags.keys ~= #keys
  if not changed then
    for i, key in ipairs(keys) do
      if key ~= tags.keys[i] or names[i] ~= tags.names[i] then changed = true; break end
    end
  end
  if changed then
    element.items = items
    element.tags = { transfer_filter = field, keys = keys, names = names }
  end
  if element.selected_index ~= selected then element.selected_index = selected end
end

local function columns(width)
  local usable = width - 2 * BODY_PADDING - SCROLLBAR_GUTTER - #TITLES * (CELL_PADDING + COLUMN_BORDER)
  local delivered = math.max(72, math.floor(usable * 0.12))
  local last = math.max(84, math.floor(usable * 0.15))
  local remaining = usable - delivered - last
  local route = math.floor(remaining * 0.34)
  return { route, route, remaining - 2 * route, delivered, last }
end

local function cargo_table(parent, name, row_padding)
  local list = parent.add { type = "table", name = name, style = "finished_game_table", column_count = #TITLES }
  list.style.horizontal_spacing, list.style.vertical_spacing = 0, 0
  list.style.left_cell_padding, list.style.right_cell_padding = CELL_PADDING, 0
  list.style.top_cell_padding, list.style.bottom_cell_padding = row_padding, row_padding
  return list
end

local function cell_label(parent, name, caption, style, width, right)
  local cell = label(parent, name, caption, style)
  cell.style.width, cell.style.single_line = width, true
  if right then cell.style.horizontal_align = "right" end
  return cell
end

local function add_row(list, index, widths)
  for i = 1, 2 do
    local surface = row(list, index .. "_" .. i)
    surface.style.width, surface.style.horizontal_spacing = widths[i], 4
    local icon = surface.add { type = "sprite", name = "icon" }
    icon.style.width, icon.style.height = 20, 20
    local caption = cell_label(surface, "surface_name", "", nil, widths[i] - 24)
    caption.style.rich_text_setting = defines.rich_text_setting.disabled
  end
  cell_label(list, index .. "_3", "", nil, widths[3])
  cell_label(list, index .. "_4", "", "caption_label", widths[4], true)
  cell_label(list, index .. "_5", "", "grey_label", widths[5], true)
end

local function show_endpoint(cell, endpoint)
  local name, icon = endpoint_name(endpoint)
  local visible = icon and helpers.is_valid_sprite_path(icon) or false
  cell.icon.visible = visible
  if visible and cell.icon.sprite ~= icon then cell.icon.sprite = icon end
  if cell.surface_name.caption ~= name then
    cell.surface_name.caption, cell.surface_name.tooltip = name, name
  end
end

local function render_rows(list, rows, page, widths, tick)
  local first = (page - 1) * ROWS_PER_PAGE
  local count = math.min(ROWS_PER_PAGE, #rows - first)
  local existing = #list.children / 5
  for i = 1, count do
    if i > existing then add_row(list, i, widths) end
    local item = rows[first + i]
    show_endpoint(list[i .. "_1"], item.from)
    show_endpoint(list[i .. "_2"], item.to)
    local material = list[i .. "_3"]
    if material.tags.material ~= item.material then
      local name = item_name(item.material)
      material.caption, material.tooltip = name, name
      material.tags = { material = item.material }
    end
    list[i .. "_4"].caption = number(item.count)
    list[i .. "_5"].caption = age(tick, item.last)
  end
  for i = existing, count + 1, -1 do
    for j = 1, 5 do list[i .. "_" .. j].destroy() end
  end
end

local function build(content, width, height, widths)
  local panel = content.add { type = "frame", name = "ssk_transfers", style = "inside_deep_frame", direction = "vertical" }
  panel.style.width, panel.style.height = width, height
  local layout = panel.add { type = "flow", name = "layout", direction = "vertical" }
  layout.style.horizontally_stretchable, layout.style.vertically_stretchable = true, true
  layout.style.vertical_spacing = 0
  local compact = width < 590
  local filters = layout.add { type = "frame", name = "filters", style = "subheader_frame", direction = compact and "vertical" or "horizontal" }
  filters.style.padding = 8
  filters.style.left_padding, filters.style.right_padding = 12, 12
  filters.style.horizontally_stretchable = true
  for _, filter in ipairs(FILTERS) do
    local field, title = filter[1], filter[2]
    local cell = row(filters, field)
    if not compact then cell.style.right_margin = 12 end
    local caption = label(cell, nil, title, "subheader_semibold_label")
    if compact then caption.style.width = 76 end
    local dropdown = cell.add { type = "drop-down", name = "ssk_transfer_" .. field, items = { "" },
      selected_index = 1, tooltip = "Filter delivered cargo by " .. title:lower() .. "." }
    dropdown.style.width = math.min(205, math.floor((width - 212) / 3))
    if compact then dropdown.style.width = math.min(205, width - 115) end
  end

  local body = layout.add { type = "flow", name = "body", direction = "vertical" }
  body.style.padding, body.style.vertical_spacing = BODY_PADDING, 6
  body.style.horizontally_stretchable, body.style.vertically_stretchable = true, true
  local heading = row(body, "heading")
  heading.style.horizontally_stretchable = true
  label(heading, nil, "Delivered cargo", "heading_2_label")
  spacer(heading)
  label(heading, "summary", "", "bold_label")
  label(body, nil, "Totals by route and material over the selected period.", "grey_label")
  local header = body.add { type = "frame", style = "inside_shallow_frame", direction = "horizontal" }
  header.style.horizontally_stretchable = true
  header.style.padding = 0
  local titles = cargo_table(header, nil, 4)
  for i, title in ipairs(TITLES) do cell_label(titles, nil, title, "caption_label", widths[i], i >= 4) end

  local scroll = body.add { type = "scroll-pane", name = "scroll", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
  scroll.style.horizontally_stretchable, scroll.style.vertically_stretchable = true, true
  cargo_table(scroll, "list", 8)
  local empty = label(scroll, "empty", "", "grey_label")
  empty.style.maximal_width, empty.style.single_line = width - 48, false
  empty.style.padding = 8

  local footer = row(body, "footer")
  footer.style.horizontally_stretchable = true
  local note = label(footer, "note", FOOTNOTE, "grey_label")
  note.style.maximal_width, note.style.single_line = width - 32, false
  spacer(footer)
  local pager = row(footer, "pager")
  pager.add { type = "sprite-button", name = "previous", style = "tool_button",
    sprite = "utility/left_arrow", tooltip = "Previous page", tags = { transfer_page = -1 } }
  label(pager, "page", "", "grey_label")
  pager.add { type = "sprite-button", name = "next", style = "tool_button",
    sprite = "utility/right_arrow", tooltip = "Next page", tags = { transfer_page = 1 } }
  return panel
end

function UI.render(content, player, period, state, width, height)
  local force = player.force
  if state.force ~= force then
    state.force = force
    for _, filter in ipairs(FILTERS) do
      state[filter[1]], state[filter[1] .. "_label"] = nil, nil
    end
    state.page = nil
  end
  if state.period ~= period then state.period, state.page = period, nil end
  local now = game.tick
  local seconds = period > 0 and period or settings.global["ssk-window-seconds"].value
  local available = Transfers.available()
  local result = Transfers.query(force, now, seconds, state)
  local widths = columns(width)
  local panel = content.ssk_transfers or build(content, width, height, widths)
  local filters, body = panel.layout.filters, panel.layout.body
  update_filter(filters.from.ssk_transfer_from, "from", choices_for(result.sources), state)
  update_filter(filters.to.ssk_transfer_to, "to", choices_for(result.destinations), state)
  update_filter(filters.material.ssk_transfer_material, "material", material_choices(result.materials), state)
  body.heading.summary.caption = table.concat({
    quantity(result.routes, "route"), quantity(result.arrivals, "arrival"), quantity(result.items, "item") }, "  ·  ")

  local scroll, pager = body.scroll, body.footer.pager
  scroll.empty.visible = #result.rows == 0
  if scroll.empty.visible then
    if not available then
      scroll.empty.caption = "Transfers are available with Space Age enabled."
    elseif next(result.materials) then
      scroll.empty.caption = "No delivered cargo matches these filters."
    else
      scroll.empty.caption = "No cargo deliveries have been recorded in this period."
    end
  end
  local pages = math.max(1, math.ceil(#result.rows / ROWS_PER_PAGE))
  state.page = math.max(1, math.min(state.page or 1, pages))
  pager.visible = pages > 1
  if pager.visible then
    pager.previous.enabled, pager.next.enabled = state.page > 1, state.page < pages
    pager.page.caption = state.page .. " / " .. pages
  end
  body.footer.note.style.maximal_width = width - (pager.visible and 156 or 32)
  body.footer.note.caption = result.truncated and "Some deliveries in this period are outside the retained history." or FOOTNOTE
  render_rows(scroll.list, result.rows, state.page, widths, now)
end

function UI.on_selection(event, state)
  local element = event.element
  if not (element and element.valid) then return false end
  local tags = element.tags
  local field = tags.transfer_filter
  if not field then return false end
  local key = tags.keys[element.selected_index]
  state[field] = key ~= 0 and key or nil
  state[field .. "_label"] = key ~= 0 and tags.names[element.selected_index] or nil
  state.page = nil
  return true
end

function UI.on_click(event, state)
  local element = event.element
  if not (element and element.valid) then return false end
  local page = element.tags.transfer_page
  if not page then return false end
  state.page = (state.page or 1) + page
  return true
end

return UI
