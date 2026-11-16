local Tooltip = TREQ("scripts.tooltip")
local Geometry = TREQ("scripts.ribbon_geometry")
local player = game.players[1]
local canvas = player.gui.screen.add { type = "flow", name = "ssk_tooltip_position_test", direction = "vertical" }
canvas.style.vertical_spacing = 0
-- Irregular hover rectangles retained from a private rendering fixture. Their
-- odd Y coordinates and heights expose independent scaled-length truncation.
local pieces = {
  { kind = "bar", x = 364, y = 251, w = 50, h = 209 },
  { kind = "bar", x = 414, y = 251, w = 43, h = 208 },
  { kind = "bar", x = 457, y = 250, w = 35, h = 209 },
  { kind = "bar", x = 492, y = 248, w = 32, h = 210 },
  { kind = "bar", x = 524, y = 247, w = 28, h = 209 },
  { kind = "bar", x = 552, y = 246, w = 28, h = 209 },
  { kind = "bar", x = 580, y = 244, w = 28, h = 210 },
  { kind = "bar", x = 608, y = 243, w = 32, h = 209 },
  { kind = "bar", x = 640, y = 242, w = 35, h = 209 },
  { kind = "bar", x = 675, y = 241, w = 43, h = 209 },
  { kind = "bar", x = 718, y = 241, w = 50, h = 208 },
}
local regions = {}
Geometry.hover_regions(pieces, function(x, y, w, h) regions[#regions + 1] = { x=x, y=y, w=w, h=h } end)
Tooltip.ribbon(canvas, pieces, "before", { transfer_ribbon = "position-test" }, "ssk_tooltip_position_")
local targets = {}
for i = 1, #regions do
  local hit = assert(canvas["ssk_tooltip_position_" .. i])
  assert(hit.raise_hover_events, "standalone ribbon targets must opt in to native hover events")
  targets[i] = hit
end
for _, scale in ipairs({ 1, 1.25, 1.5 }) do
  local function px(value)
    local scaled = (value or 0) * scale
    return scaled < 0 and math.ceil(scaled) or math.floor(scaled)
  end
  local cursor, found = 0, 0
  for _, element in ipairs(canvas.children) do
    local s = element.style
    if element.tags.transfer_ribbon == "position-test" then
      found = found + 1
      local expected = regions[found]
      assert(cursor + px(s.top_margin) == px(expected.y),
        "standalone ribbon hover target accumulated vertical drift at " .. scale .. " scale, region " .. found)
      assert(px(s.left_margin) == px(expected.x) and px(s.width) == px(expected.w) and px(s.height) == px(expected.h),
        "standalone ribbon hover bounds differ from the drawn geometry")
    end
    cursor = cursor + px(s.top_margin) + px(s.height) + px(s.bottom_margin)
  end
  assert(found == #regions and cursor == 0, "ribbon overlays must consume no scaled layout height")
end
local child_count = #canvas.children
for _ = 1, 3 do
  Tooltip.ribbon(canvas, pieces, "after", { transfer_ribbon = "position-test" }, "ssk_tooltip_position_")
  assert(#canvas.children == child_count, "refresh duplicated ribbon targets or position-reset siblings")
  for i, hit in ipairs(targets) do
    assert(canvas["ssk_tooltip_position_" .. i] == hit and hit.valid and hit.tooltip == "after" and hit.raise_hover_events,
      "named ribbon refresh must retain native target identity and event flags")
  end
end
canvas.destroy()
print("TOOLTIP POSITION OK: standalone ribbon geometry at 100/125/150%, stable refresh identities and native hover flags")
