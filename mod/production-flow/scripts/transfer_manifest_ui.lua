local Loc = require("scripts.locale")
local Manifest = {}

function Manifest.item_name(item)
  local name = item.name or item.material
  local prototype = prototypes.item[name]
  local title = prototype and prototype.localised_name or name
  local quality = item.quality or "normal"
  if quality ~= "normal" then
    local q = prototypes.quality and prototypes.quality[quality]
    title = Loc("se-ui-quality-item", title, q and { "?", q.localised_name, quality } or quality)
  end
  if not prototype then return title end
  return Loc.join("[item=" .. name .. "] ", title)
end

function Manifest.preview(parent, items, width)
  local icon_size, gap, overflow = 18, 2, 28
  parent.style.horizontal_spacing = gap
  local shown = math.min(#items, 5, math.floor((width + gap) / (icon_size + gap)))
  if shown < #items then
    shown = math.min(shown, math.max(0, math.floor((width - overflow) / (icon_size + gap))))
  end
  for i = 1, shown do
    local path = "item/" .. items[i].name
    local icon = parent.add { type = "sprite", resize_to_sprite = false, ignored_by_interaction = true }
    if helpers.is_valid_sprite_path(path) then icon.sprite = path end
    icon.style.width, icon.style.height = icon_size, icon_size
  end
  if shown < #items then
    parent.add { type = "label", caption = "+" .. (#items - shown), style = "grey_label", ignored_by_interaction = true }
  end
end

function Manifest.section(parent, name, heading, items, width, format_count, grid_name)
  local section = parent.add { type = "flow", name = name, direction = "vertical" }
  section.style.width, section.style.vertical_spacing = width, 4
  section.add { type = "label", caption = heading, style = "caption_label" }
  if not items or #items == 0 then
    local note = section.add { type = "label", style = "grey_label",
      caption = Loc(items and "se-ui-empty-manifest" or "se-ui-unknown-manifest") }
    note.style.width, note.style.single_line = width, false
    return
  end

  local columns = math.min(4, math.max(1, math.floor(width / 185)))
  local grid = section.add { type = "table", name = grid_name or "manifest", column_count = columns,
    style = "ssk_striped_rows", draw_vertical_lines = #items >= columns }
  grid.style.horizontal_spacing, grid.style.vertical_spacing = 0, 0
  grid.style.top_cell_padding, grid.style.bottom_cell_padding = 3, 3
  local cell_width = math.floor(width / columns) - 6
  local quantity_width, gap = 76, 8
  for _, item in ipairs(items) do
    local caption, count = Manifest.item_name(item), format_count(item.count)
    local cell = grid.add { type = "flow", direction = "horizontal", tooltip = Loc("se-ui-manifest-entry", caption, count),
      tags = { transfer_item = item.name, count = item.count } }
    cell.style.width, cell.style.horizontal_spacing, cell.style.vertical_align = cell_width, gap, "center"
    local material = cell.add { type = "label", caption = caption, tooltip = caption }
    material.style.width, material.style.single_line = math.max(1, cell_width - quantity_width - gap), true
    local quantity = cell.add { type = "label", caption = count, style = "bold_label" }
    quantity.style.width, quantity.style.horizontal_align = quantity_width, "right"
  end
end

local function item_key(item) return (item.name or item.material or "?") .. "/" .. (item.quality or "normal") end

-- Pair a known sent manifest with a measured receipt, item by item and quality
-- by quality. lost is sent minus received, never negative; an item received
-- but absent from the sent manifest keeps sent=nil. Without a measured receipt
-- (received=nil) both received and lost stay nil: unknown, never zero.
function Manifest.receipt_rows(sent, received)
  local rows, by_key = {}, {}
  local function row_for(item)
    local key = item_key(item)
    local row = by_key[key]
    if not row then
      row = { name = item.name or item.material, quality = item.quality, received = 0 }
      by_key[key] = row
      rows[#rows + 1] = row
    end
    return row
  end
  for _, item in ipairs(sent or {}) do
    local row = row_for(item)
    row.sent = (row.sent or 0) + (item.count or 0)
  end
  for _, item in ipairs(received or {}) do
    local row = row_for(item)
    row.received = row.received + (item.count or 0)
  end
  for _, row in ipairs(rows) do
    if received == nil then
      row.received = nil
    else
      row.lost = row.sent and math.max(0, row.sent - row.received) or 0
    end
  end
  return rows
end

-- One grid like Manifest.section, but each cell reads: item, lost, received.
-- No subtitle: the grid's first row names the three parts of every column.
-- unknown_tip explains an unmeasured receipt on its "—" cells.
function Manifest.receipt(parent, name, sent, received, width, format_count, grid_name, unknown_tip)
  local rows = Manifest.receipt_rows(sent, received)
  local section = parent.add { type = "flow", name = name, direction = "vertical" }
  section.style.width = width
  if #rows == 0 then
    local unknown = sent == nil and received == nil
    local note = section.add { type = "label", style = "grey_label",
      caption = Loc(unknown and "se-ui-unknown-manifest" or "se-ui-empty-manifest"), tooltip = unknown and unknown_tip or nil }
    note.style.width, note.style.single_line = width, false
    return
  end

  local fit = math.min(4, math.max(1, math.floor(width / 185)))
  local columns = math.min(fit, #rows)
  local grid = section.add { type = "table", name = grid_name or "manifest", column_count = columns,
    style = "ssk_striped_rows", draw_vertical_lines = columns > 1 }
  grid.style.horizontal_spacing, grid.style.vertical_spacing = 0, 0
  grid.style.top_cell_padding, grid.style.bottom_cell_padding = 3, 3
  local cell_width = math.floor(width / fit) - 6
  local quantity_width, lost_width, gap = 64, 56, 6
  local item_width = math.max(1, cell_width - quantity_width - lost_width - 2 * gap)
  for i = 1, columns do
    local header = grid.add { type = "flow", name = "header_" .. i, direction = "horizontal" }
    header.style.width, header.style.horizontal_spacing = cell_width, gap
    for _, part in ipairs({ { "item", Loc("se-ui-manifest-item"), item_width, "left" },
        { "lost", Loc("se-ui-manifest-lost"), lost_width, "right" },
        { "received", Loc("se-ui-received"), quantity_width, "right" } }) do
      local heading = header.add { type = "label", name = part[1], caption = part[2], style = "bold_label" }
      heading.style.width, heading.style.horizontal_align = part[3], part[4]
    end
  end
  for _, row in ipairs(rows) do
    local caption = Manifest.item_name(row)
    local known = row.received ~= nil
    local got = known and format_count(row.received) or "—"
    local lost = not known and "—" or row.lost > 0 and "−" .. format_count(row.lost) or "0"
    local sent_text = row.sent and format_count(row.sent) or "—"
    local cell = grid.add { type = "flow", direction = "horizontal",
      tooltip = known and Loc("se-ui-manifest-receipt-entry", caption, got, sent_text, format_count(row.lost))
        or Loc.join(Loc("se-ui-manifest-entry", caption, sent_text), unknown_tip and "\n" or "", unknown_tip or ""),
      tags = { transfer_item = row.name, count = row.received, sent = row.sent, lost = row.lost } }
    cell.style.width, cell.style.horizontal_spacing, cell.style.vertical_align = cell_width, gap, "center"
    local material = cell.add { type = "label", caption = caption, tooltip = caption }
    material.style.width, material.style.single_line = item_width, true
    local loss = cell.add { type = "label", name = "lost", caption = lost,
      style = known and row.lost > 0 and "red_label" or "grey_label" }
    loss.style.width, loss.style.horizontal_align = lost_width, "right"
    local quantity = cell.add { type = "label", name = "received", caption = got, style = known and "bold_label" or "grey_label" }
    quantity.style.width, quantity.style.horizontal_align = quantity_width, "right"
  end
end

return Manifest
