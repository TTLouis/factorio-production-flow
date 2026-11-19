local Loc = require("scripts.locale")
local Manifest = {}

function Manifest.item_name(item)
  local name = item.name or item.material
  local prototype = prototypes.item[name]
  local title = prototype and prototype.localised_name or name
  local quality = item.quality or "normal"
  if quality ~= "normal" then
    local q = prototypes.quality and prototypes.quality[quality]
    title = Loc("shipment-quality-item", title, q and { "?", q.localised_name, quality } or quality)
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
      caption = Loc(items and "shipment-empty-manifest" or "shipment-unknown-manifest") }
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
    local cell = grid.add { type = "flow", direction = "horizontal", tooltip = Loc("shipment-manifest-entry", caption, count),
      tags = { transfer_item = item.name, count = item.count } }
    cell.style.width, cell.style.horizontal_spacing, cell.style.vertical_align = cell_width, gap, "center"
    local material = cell.add { type = "label", caption = caption, tooltip = caption }
    material.style.width, material.style.single_line = math.max(1, cell_width - quantity_width - gap), true
    local quantity = cell.add { type = "label", caption = count, style = "bold_label" }
    quantity.style.width, quantity.style.horizontal_align = quantity_width, "right"
  end
end

return Manifest
