local Geometry = require("scripts.ribbon_geometry")
local Tooltip = {}

-- Each Factorio LocalisedString can concatenate at most 20 parameters.
function Tooltip.lines(parts)
  while #parts > 20 do
    local groups = {}
    for first = 1, #parts, 20 do
      local group = { "" }
      for i = first, math.min(first + 19, #parts) do group[#group + 1] = parts[i] end
      groups[#groups + 1] = group
    end
    parts = groups
  end
  return { "", table.unpack(parts) }
end

function Tooltip.ribbon(canvas, pieces, caption, tags, prefix, add_hit)
  local index = 0
  Geometry.hover_regions(pieces, function(x, y, width, height)
    index = index + 1
    local name = prefix and (prefix .. index)
    local hit = name and canvas[name]
    if hit then
      hit.tooltip = caption
      return
    end
    local spec = { type = "sprite", name = name, sprite = "ssk-node-hit", resize_to_sprite = false,
      tooltip = caption, tags = tags, raise_hover_events = true }
    if add_hit then
      add_hit(spec, x, y, width, height)
      return
    end
    hit = canvas.add(spec)
    local style = hit.style
    style.width, style.height = width, height
    -- Cancel each scaled length separately. Combining Y + height in one
    -- negative margin shifts subsequent Transfer hover targets at 125/150%.
    style.left_margin, style.top_margin, style.bottom_margin = x, y, -height
    local reset = canvas.add { type = "empty-widget", ignored_by_interaction = true,
      tags = { ssk_position_reset = true } }
    reset.style.width, reset.style.height = 0, 0
    reset.style.left_margin, reset.style.bottom_margin = 0, 0
    reset.style.top_margin = -y
  end)
end

return Tooltip
