-- Transfers ribbon colours shared by Space Age and Space Exploration views.
-- Cargo coming in is a blue family, cargo going out an orange family, and
-- production aboard green. Neighbouring ribbons on one side take successive
-- shades (base, light, deep, then a blue-green or amber), so they stay apart
-- while the hue still says the direction. The colours live in plot_colors,
-- which also gives each one a GUI sprite ("ssk-plot-<key>") for card stripes,
-- legend squares and night-vision GUI drawing.
--
-- SE Flow grouped by Items colours by item instead. Each side shows its own
-- eight most transported items; an item keeps one colour on both sides and in
-- every card, and everything else shares a grey "other" band.
local Colors = require("shared.plot_colors")
local Palette = require("shared.palette")
local R = { COUNT = 4, ITEMS = 8 }
-- Sankey colour index behind each item slot (see plot_colors ribbon_item_N).
R.ITEM_SANKEY = { 4, 5, 1, 11, 3, 6, 10, 13 }

function R.key(direction, index)
  if direction == "made" then return "ribbon_made" end
  return "ribbon_" .. direction .. "_" .. ((index or 1) - 1) % R.COUNT + 1
end

-- direction: "in", "out" or "made"; index: 1-based position on that side.
function R.color(direction, index) return Colors[R.key(direction, index)] end
function R.sprite(direction, index) return "ssk-plot-" .. R.key(direction, index) end

-- slot: 1..ITEMS, or nil for the grey "other" band.
function R.item_key(slot) return slot and "ribbon_item_" .. slot or "ribbon_item_other" end
function R.item_color(slot) return Colors[R.item_key(slot)] end
function R.item_sprite(slot) return "ssk-plot-" .. R.item_key(slot) end

-- entries: {key="name/quality", sides={imports=true,...}} in assignment
-- order (items on both sides first). Returns key -> slot. Colours are unique
-- within a side. An item takes its Sankey colour when that is a slot and still
-- unused, so iron stays blue and copper orange where possible; otherwise the
-- first unused slot. Only when both sides together hold more than ITEMS items
-- does a one-sided item reuse a colour from the other side.
function R.assign_items(entries)
  local slot_of_sankey, used, side_used, slots = {}, {}, {}, {}
  for slot, index in ipairs(R.ITEM_SANKEY) do slot_of_sankey[index] = slot end
  local function free_on_sides(entry, slot)
    for side in pairs(entry.sides) do if side_used[side] and side_used[side][slot] then return false end end
    return true
  end
  for _, entry in ipairs(entries) do
    local preferred = slot_of_sankey[Palette.material("item/" .. entry.key:gsub("/.*$", ""))]
    local choice
    local function try(test)
      if choice then return end
      if preferred and test(preferred) then choice = preferred; return end
      for s = 1, R.ITEMS do if test(s) then choice = s; return end end
    end
    try(function(s) return not used[s] end)
    try(function(s) return free_on_sides(entry, s) end)
    if choice then
      used[choice], slots[entry.key] = true, choice
      for side in pairs(entry.sides) do side_used[side] = side_used[side] or {}; side_used[side][choice] = true end
    end
  end
  return slots
end

return R
