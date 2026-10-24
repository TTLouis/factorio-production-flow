local S = require("shared.sprites")
local palette = require("shared.palette")

local steps = S.steps
local ATLAS = "__production-flow__/graphics/ribbons.png"

local protos = {}
-- Invisible GUI hit area over polygon node bars; keeps native tooltips and clicks.
protos[#protos + 1] = { type = "sprite", name = "ssk-node-hit",
  filename = "__core__/graphics/empty.png", width = 1, height = 1, flags = { "gui" } }
for d, dir in ipairs(S.DIRS) do
  for k = 1, steps.count do
    local idx = (d - 1) * steps.count + (k - 1)
    local x = (idx % steps.grid_cols) * steps.cell_w
    local y = math.floor(idx / steps.grid_cols) * steps.cell_h
    for c = 1, palette.count do
      protos[#protos + 1] = {
        type = "sprite",
        name = S.name(dir, k, c),
        filename = ATLAS,
        priority = "extra-high-no-scale",
        x = x,
        y = y,
        width = steps.cell_w,
        height = steps.cell_h,
        tint = palette.tint(c),
        flags = { "gui" },
      }
    end
  end
end
-- elbows (quarter annulus) for orthogonal routing of steep ribbons
local ELB = "__production-flow__/graphics/elbows.png"
for ci, corner in ipairs(steps.elbow_corners) do
  for k = 1, steps.elbow_steps do
    local idx = (ci - 1) * steps.elbow_steps + (k - 1)
    local x = (idx % steps.elbow_grid) * steps.elbow
    local y = math.floor(idx / steps.elbow_grid) * steps.elbow
    for c = 1, palette.count do
      protos[#protos + 1] = {
        type = "sprite", name = S.elbow_name(corner, k, c), filename = ELB, priority = "extra-high-no-scale",
        x = x, y = y, width = steps.elbow, height = steps.elbow, tint = palette.tint(c), flags = { "gui" },
      }
    end
  end
end

-- translucent lane / sub-lane backgrounds (full-rect cell)
do
  local k = steps.count
  local x = ((k - 1) % steps.grid_cols) * steps.cell_w
  local y = math.floor((k - 1) / steps.grid_cols) * steps.cell_h
  for c = 1, palette.count do
    for _, v in ipairs({ { "bg", 0.10 }, { "line", 0.35 } }) do
      local col = palette.rgb(c)
      local a = v[2]
      protos[#protos + 1] = {
        type = "sprite", name = string.format("ssk-%s-c%02d", v[1], c), filename = ATLAS,
        priority = "extra-high-no-scale", x = x, y = y, width = steps.cell_w, height = steps.cell_h,
        tint = { r = col[1] / 255 * a, g = col[2] / 255 * a, b = col[3] / 255 * a, a = a }, flags = { "gui" },
      }
    end
  end
end

protos[#protos + 1] = {
  type = "sprite",
  name = "ssk-icon",
  filename = "__production-flow__/graphics/icon.png",
  priority = "extra-high-no-scale",
  size = 64,
  scale = 0.5,
  flags = { "gui-icon" },
}
-- Balance favourite toggles (tools/gen_star.py): gold when set, grey outline otherwise.
for _, v in ipairs({ { "ssk-star", "star.png" }, { "ssk-star-off", "star-off.png" } }) do
  protos[#protos + 1] = { type = "sprite", name = v[1], filename = "__production-flow__/graphics/" .. v[2],
    priority = "extra-high-no-scale", size = 32, scale = 0.5, flags = { "gui-icon" } }
end
data:extend(protos)

-- Native table grids separate items while retaining the paired Details lines.
data.raw["gui-style"].default.ssk_balance_grid = {
  type = "table_style", parent = "table",
  horizontal_line_color = {0.16, 0.17, 0.18, 1},
  vertical_line_color = {0.31, 0.33, 0.35, 1},
  top_cell_padding = 5, bottom_cell_padding = 5,
  left_cell_padding = 3, right_cell_padding = 3,
}
data.raw["gui-style"].default.ssk_balance_header = {
  type = "frame_style", parent = "subheader_frame", padding = 0,
  vertical_flow_style = { type = "vertical_flow_style", vertical_spacing = 0 },
}
