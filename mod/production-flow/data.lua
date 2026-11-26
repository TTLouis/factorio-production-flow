local S = require("shared.sprites")
local palette = require("shared.palette")

local steps = S.steps
local ATLAS = "__production-flow__/graphics/ribbons.png"

local protos = {}
-- Plot rectangles tint the base game's white square; no new graphics.
for name,color in pairs(require("shared.plot_colors")) do
  protos[#protos+1]={type="sprite",name="ssk-plot-"..name,filename="__core__/graphics/white-square.png",
    width=10,height=10,tint=color,flags={"gui"}}
end
-- Centre strips from the vanilla horizontal and vertical scrollbar thumbs.
for _, thumb in ipairs({{"x",232,48,8,20},{"y",0,55,20,8}}) do
  protos[#protos+1] = {type="sprite", name="ssk-scroll-thumb-"..thumb[1], filename="__core__/graphics/gui-new.png",
    x=thumb[2],y=thumb[3],width=thumb[4],height=thumb[5],flags={"gui"}}
end
for _, wheel in ipairs({{"up","mouse-wheel-up"},{"down","mouse-wheel-down"},
    {"left","SHIFT + mouse-wheel-up","mouse-wheel-left"},
    {"right","SHIFT + mouse-wheel-down","mouse-wheel-right"}}) do
  protos[#protos+1] = {type="custom-input", name="ssk-sankey-scroll-"..wheel[1], key_sequence=wheel[2],
    alternative_key_sequence=wheel[3],
    localised_name={"", {"production-flow.ui-full-sankey"}, " · ", {"production-flow.sankey-pan-"..wheel[1]}},
    consuming="none"}
end
for _, page in ipairs({{"left","PAGEUP"},{"right","PAGEDOWN"}}) do
  protos[#protos+1] = {type="custom-input", name="ssk-sankey-page-"..page[1], key_sequence=page[2],
    localised_name={"", {"production-flow.ui-full-sankey"}, " · ", {"production-flow.sankey-page-"..page[1]}},
    block_modifiers=true, consuming="none"}
end
-- Thin returns need a lighter version of the source hue against the chart.
for color = 1, palette.count do
  local rgb = palette.rgb(color)
  protos[#protos + 1] = { type = "sprite", name = S.return_line(color),
    filename = "__core__/graphics/white-square.png", width = 10, height = 10, flags = { "gui" },
    tint = { r = (rgb[1] / 255 + 1) / 2, g = (rgb[2] / 255 + 1) / 2, b = (rgb[3] / 255 + 1) / 2, a = 1 } }
end
for step, alpha in ipairs(palette.stub_alpha) do
  for _, dim in ipairs{false, true} do
    protos[#protos+1] = {type="sprite", name=S.stub(step, dim), filename="__core__/graphics/white-square.png",
      width=10, height=10, tint=palette.tint(dim and palette.DIM or palette.GREY, dim and alpha * palette.dim.alpha or alpha),
      flags={"gui"}}
  end
end
-- Invisible GUI hit area over polygon node bars; keeps native tooltips and clicks.
protos[#protos + 1] = { type = "sprite", name = "ssk-node-hit",
  filename = "__core__/graphics/empty.png", width = 1, height = 1, flags = { "gui" } }
for d, dir in ipairs(S.DIRS) do
  for k = 1, steps.count do
    local idx = (d - 1) * steps.count + (k - 1)
    local x = (idx % steps.grid_cols) * steps.cell_w
    local y = math.floor(idx / steps.grid_cols) * steps.cell_h
    local solid = k == steps.count
    for c = 1, palette.count do
      protos[#protos + 1] = {
        type = "sprite",
        name = S.name(dir, k, c),
        -- A separate white square keeps atlas filtering out of straight joins.
        filename = solid and "__core__/graphics/white-square.png" or ATLAS,
        priority = "extra-high-no-scale",
        x = solid and 0 or x,
        y = solid and 0 or y,
        width = solid and 10 or steps.cell_w,
        height = solid and 10 or steps.cell_h,
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
-- Balance favourite toggles use the base game's Browse Games star: gold when set,
-- grey outline otherwise.
for _, v in ipairs({ { "ssk-star", { 32, 600 } }, { "ssk-star-off", { 0, 600 } } }) do
  protos[#protos + 1] = { type = "sprite", name = v[1], filename = "__core__/graphics/gui-new.png",
    position = v[2], size = 32, scale = 0.5, priority = "extra-high-no-scale", flags = { "gui-icon" } }
end
-- Chart settings use the base game's side-menu gear, darkened like the other
-- tool button icons (the original is drawn light for dark side-menu buttons).
-- The 32 px crop is the gear itself, so it matches 16 px utility icons.
protos[#protos + 1] = { type = "sprite", name = "ssk-gear", filename = "__core__/graphics/side-menu-buttons.png",
  x = 16, y = 6 * 64 + 16, size = 32, scale = 0.5, tint = { 0.22, 0.22, 0.22 },
  priority = "extra-high-no-scale", flags = { "gui-icon" } }
data:extend(protos)

-- Native table grids separate items while retaining the paired Details lines.
-- Leave room for the independent drill label without changing the list row's background.
data.raw["gui-style"].default.ssk_layered_cell_list = {
  type = "list_box_style", parent = "list_box",
  item_style = { type = "button_style", parent = "list_box_item", right_padding = 32 },
}

data.raw["gui-style"].default.ssk_balance_grid = {
  type = "table_style", parent = "table",
  horizontal_line_color = {0.16, 0.17, 0.18, 1},
  vertical_line_color = {0.31, 0.33, 0.35, 1},
  top_cell_padding = 5, bottom_cell_padding = 5,
  left_cell_padding = 3, right_cell_padding = 3,
}
data.raw["gui-style"].default.ssk_striped_rows = {
  type = "table_style", parent = "ssk_balance_grid",
  -- Use the vanilla removed-content table's alternating row background.
  odd_row_graphical_set = { filename = "__core__/graphics/gui-new.png", position = {472, 25}, size = 1 },
}
data.raw["gui-style"].default.ssk_balance_header = {
  type = "frame_style", parent = "subheader_frame", padding = 0,
  vertical_flow_style = { type = "vertical_flow_style", vertical_spacing = 0 },
}

-- Keep the default scroll pane's border and padding in both scrollbar states.
data.raw["gui-style"].default.ssk_rate_card_scroll = {
  type = "scroll_pane_style", parent = "scroll_pane",
  always_draw_borders = true, padding = 4, extra_padding_when_activated = 0,
}

local cell_selection = require("shared.cell_selection")
data:extend {{
  type = "selection-tool",
  name = cell_selection.tool,
  icon = "__production-flow__/graphics/icon.png",
  icon_size = 64,
  localised_name = {"production-flow.cells-title"},
  flags = {"only-in-cursor", "not-stackable", "spawnable"},
  hidden = true,
  stack_size = 1,
  select = {
    border_color = {0.3, 0.8, 1},
    mode = {"any-entity"},
    cursor_box_type = "copy",
    entity_type_filters = cell_selection.initial_types,
  },
  alt_select = {border_color = {0.3, 0.8, 1}, mode = {"nothing"}, cursor_box_type = "copy"},
}, {
  type = "shortcut",
  name = cell_selection.tool,
  localised_name = {"production-flow.cells-new"},
  order = "d[wires]-z[production-cell]",
  action = "spawn-item",
  item_to_spawn = cell_selection.tool,
  icon = "__production-flow__/graphics/icon.png",
  icon_size = 64,
  small_icon = "__production-flow__/graphics/icon.png",
  small_icon_size = 64,
}, {
  -- Clicking outside the saved-cells list closes it. Never consumes the click.
  type = "custom-input",
  name = cell_selection.click,
  key_sequence = "mouse-button-1",
  alternative_key_sequence = "mouse-button-2",
  consuming = "none",
  action = "lua",
}}

for _, selection in ipairs({
  { cell_selection.stop_tool, cell_selection.stop_types, "rail-pick-stops", "train-stop" },
  { cell_selection.buffer_tool, cell_selection.buffer_types, "rail-pick-buffers", "steel-chest" },
}) do
  local color = {0.95, 0.74, 0.34}
  data:extend {{
    type = "selection-tool", name = selection[1],
    icon = "__base__/graphics/icons/" .. selection[4] .. ".png",
    localised_name = {"production-flow." .. selection[3]},
    flags = {"only-in-cursor", "not-stackable", "spawnable"}, hidden = true, stack_size = 1,
    select = { border_color = color, mode = {"any-entity"}, cursor_box_type = "copy", entity_type_filters = selection[2] },
    alt_select = { border_color = color, mode = {"nothing"}, cursor_box_type = "copy" },
  }}
end
