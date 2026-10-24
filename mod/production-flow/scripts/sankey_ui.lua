-- M4–M7 Sankey tab: toolbar (presets, scope, tiers, zoom, live), selection toolbar
-- (▲/▼, hide, group/collapse), and the canvas drawn with stretched ribbon sprites.

local S = require("shared.sprites")
local palette = require("shared.palette")
local View = require("scripts.view")
local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local Gr = require("scripts.groups")
local Canvas = require("scripts.canvas")
local Geometry = require("scripts.ribbon_geometry")
local MaterialPicker = require("scripts.material_picker")

local SK = {}
local hovered_nodes = {}
local ZOOM_STEP = 1.25

local function round(v) return math.floor(v + 0.5) end

function SK.defaults(us)
  us.view = us.view or "detail"
  us.tier_mode = us.tier_mode or "depth"
  us.input_depth = math.max(1, math.min(View.MAX_INPUT_DEPTH, us.input_depth or 1))
  us.preset = us.preset or "all"
  if us.view ~= "focus" then
    us.layout = us.layout or "clean"
    us.heights = us.heights or "sqrt"
    us.lines = us.lines or "curves"
  end
  us.zoom = us.zoom or 1
  if us.live == nil then us.live = true end
  if us.show_labels == nil then us.show_labels = false end
  us.hidden = us.hidden or {}
  us.collapsed = us.collapsed or {}
  us.pos = us.pos or {}
  us.last_order = us.last_order or {}
end

-- Same rate formatting as the Balance table, so a value reads identically in both.
local function fmt(x)
  local a = math.abs(x)
  if a >= 1000000 then return string.format("%.2fM", x / 1000000) end
  if a >= 10000 then return string.format("%.1fk", x / 1000) end
  if a >= 100 then return string.format("%.0f", x) end
  if a >= 10 then return string.format("%.1f", x) end
  if a >= 1 then return string.format("%.2f", x) end
  if a > 0 and a < 0.001 then return "<0.001" end
  return string.format("%.3f", x)
end

local function rt(key)
  local t, n = string.match(key, "^(%a+)/(.+)$")
  if t == "group" then return "▣" end
  return "[" .. t .. "=" .. n .. "]"
end

local function base_key(key) return (string.gsub(key, "#.*$", "")) end

local function display_name(n)
  if n.kind == "group" then return n.ginfo.name .. " (" .. #n.members .. (n.flow_kind == "fluid" and " fluids)" or " items)") end
  return string.match(base_key(n.key), "/(.+)$")
end

local function units(n)
  return (n.kind == "fluid" or n.flow_kind == "fluid") and "fluid/s"
    or n.kind == "recipe" and "crafts/s" or "items/s"
end

local function sprite_for(n)
  if n.kind == "group" then
    local t, name = string.match(n.members[1], "^(%a+)/(.+)$")
    return t .. "/" .. name
  end
  return base_key(n.key)
end

local function localised_name(n)
  if n.kind == "group" then return n.ginfo.localised_name or n.ginfo.name end
  local kind, name = base_key(n.key):match("^(%a+)/(.+)$")
  local proto = prototypes[kind] and prototypes[kind][name]
  return proto and proto.localised_name or (name or n.key):gsub("%-", " ")
end

local function label_toggle(row, us)
  row.add { type = "checkbox", caption = "Show labels", state = us.show_labels == true,
    tags = { ssk_sk = "show_labels" },
    tooltip = "Keep all names and rates visible. Otherwise hover an icon or bar; selected items keep their label. Hover a visible label for detailed flow information." }
end

local function live_toggle(row, us)
  return row.add { type = "checkbox", caption = "Auto-update chart", state = us.live, tags = { ssk_sk = "live" },
    tooltip = "Redraw this chart every 5 seconds. Sampling and Balance values continue when this is off." }
end

---------------------------------------------------------------------------
-- placement (negative-margin absolute positioning, verified in M0)
---------------------------------------------------------------------------
-- Every absolutely placed element sits in its own fixed-size wrapper flow: whatever size
-- the engine really gives the element, the wrapper keeps exactly w × h, so nothing placed
-- after it can drift (ribbons and node bars stay aligned with their icons).
local function place_raw(e, x, y, w, h)
  local s = e.style
  s.width, s.height = w, h
  s.left_margin, s.right_margin = x, 0
  s.top_margin, s.bottom_margin = y, -(y + h)
end

-- round the EDGES, not the size: pieces that meet (flat → curve, stacked ribbons) then
-- share the exact same pixel boundary, with no 1 px overlap or gap between them
local function place(e, x, y, w, h)
  local x2, y2 = round(x + w), round(y + h)
  x, y = round(x), round(y)
  w, h = math.max(1, x2 - x), math.max(1, y2 - y)
  local p = e.parent
  if p and p.tags and p.tags.ssk_wrap then
    place_raw(p, x, y, w, h)
    e.style.width, e.style.height = w, h
  else
    place_raw(e, x, y, w, h)
  end
end

local function add_sprite(parent, sprite, tooltip)
  local f = parent.add { type = "flow", direction = "horizontal", tags = { ssk_wrap = true } }
  f.style.padding = 0
  f.style.horizontal_spacing = 0
  local e = f.add { type = "sprite", sprite = sprite, tooltip = tooltip, resize_to_sprite = false }
  e.style.stretch_image_to_widget_size = true
  return e
end

---------------------------------------------------------------------------
-- toolbar
---------------------------------------------------------------------------
local ACTION_SPRITES = {
  f_back = "left_arrow", f_forward = "right_arrow", zoom_fit = "expand", center_selection = "center",
  reflow = "refresh", f_options = "list_view", advanced = "list_view", reset_layout = "reset",
  unpin = "pin_arrow", inputs_more = "add", inputs_less = "collapse", overview_reset = "collapse",
  up = "indication_arrow", down = "down_arrow", hide = "filter_blacklist", expand = "expand", collapse = "collapse",
  new_group = "add", ungroup = "reset", deselect = "close", unhide_all = "grid_view",
}
local function button(parent, caption, action, tooltip, extra)
  local tags = { ssk_sk = action }
  if extra then for k, v in pairs(extra) do tags[k] = v end end
  local sprite = ACTION_SPRITES[action]
  if sprite then
    return parent.add { type = "sprite-button", style = action == "reset_layout" and "tool_button_red" or "tool_button",
      sprite = "utility/" .. sprite, tooltip = tooltip or caption, tags = tags }
  end
  -- Vanilla has no zoom-in/out utility sprite. Its square tool button keeps
  -- the game graphics, hover state, dimensions and click sound for these glyphs.
  assert(action == "zoom_in" or action == "zoom_out", "Missing toolbar sprite: " .. action)
  local b = parent.add { type = "button", style = "tool_button", caption = caption, tooltip = tooltip or caption, tags = tags }
  b.style.width = 28
  return b
end

local function small(parent, caption)
  return parent.add { type = "label", caption = caption }
end

-- secondary guidance text: small and grey in every toolbar
local function hint(parent, caption, width)
  local l = parent.add { type = "label", caption = caption }
  l.style.font = "default-small"
  l.style.font_color = { 0.65, 0.65, 0.65 }
  l.style.single_line = false
  l.style.maximal_width = width
  return l
end

local function developer_controls(player)
  return player.mod_settings["ssk-debug-tabs"] and player.mod_settings["ssk-debug-tabs"].value
end

-- Controls shared by the Balance chart, Focus and Full Sankey toolbars. Each one
-- has the same caption, order, width and tooltip wherever it appears.
local function option_row(bar)
  local row = bar.add { type = "flow", direction = "horizontal" }
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  return row
end

local function right_group(row, us)
  row.style.width = math.max(240, (us.toolbar_width or us.canvas_w or 900) - 12)
  local spacer = row.add { type = "empty-widget", tags = { ssk_toolbar_spacer = true } }
  spacer.style.horizontally_stretchable = true
  spacer.style.minimal_width = 16
  spacer.style.height = 1
  local right = option_row(row)
  right.tags = { ssk_toolbar_side = "right" }
  return right
end

local function dropdown(row, caption, items, index, action, tooltip)
  small(row, caption)
  local d = row.add { type = "drop-down", items = items, selected_index = index, tags = { ssk_sk = action }, tooltip = tooltip }
  d.style.width = 150
  return d
end

local function widths_picker(row, us)
  return dropdown(row, "Widths:", { "Proportional", "Compressed" }, us.heights == "linear" and 1 or 2, "f_heights",
    "Proportional: linear rate widths. Compressed: square-root widths, so small flows stay visible. Fluids use a separate scale and thin ribbons keep a visible minimum. Hover for exact rates.")
end

local function colors_picker(row, us)
  return dropdown(row, "Colors:", { "Destination", "Source" }, us.color_mode == "source" and 2 or 1, "balance_colors",
    "Destination: ribbons feeding the same node share its color. Source: ribbons take the color of the material they come from. Ribbons always carry source-material units.")
end

local function lines_picker(row, us)
  return dropdown(row, "Lines:", { "Curves", "Right angles" }, us.lines == "metro" and 2 or 1, "f_lines",
    "Right angles: steep ribbons run vertically and cross others at 90°.")
end

local function renderer_picker(row, us)
  return dropdown(row, "Renderer:", { "GUI sprites", "Polygons (beta)" }, us.renderer == "poly" and 2 or 1, "f_renderer",
    "Compare the same routes: atlas sprites, or one polygon mesh per ribbon drawn on a hidden surface and shown through a camera.")
end

local function zoom_buttons(row, compact)
  button(row, "−", "zoom_out", "Zoom out")
  button(row, "Fit graph", "zoom_fit", "Fit the chart to the window while keeping icons and text readable; dense charts keep scrolling.")
  button(row, "+", "zoom_in", "Zoom in")
  if not compact then button(row, "Center", "center_selection", "Center the selected item, or the whole chart when nothing is selected.") end
end

local function reflow_button(row)
  button(row, "Reflow", "reflow", "Recalculate node order and spacing. Auto-update otherwise keeps the current layout.")
end

local function item_pickers(row, us)
  small(row, "Item / fluid:")
  MaterialPicker.button(row, us.focus, us.neighborhood and "balance" or "focus")
end

local function material_caption(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  local proto = prototypes[kind] and prototypes[kind][name]
  return { "", "[" .. kind .. "=" .. name .. "] ", proto and proto.localised_name or name:gsub("%-", " ") }
end

local function navigation_controls(row, us)
  local back, forward = us.focus_hist or {}, us.focus_forward or {}
  local caption = material_caption
  local previous = button(row, "◀", "f_back", #back > 0 and { "", "Back to ", caption(back[#back]) } or "No previous material")
  previous.enabled = #back > 0
  local next_ = button(row, "▶", "f_forward", #forward > 0 and { "", "Forward to ", caption(forward[#forward]) } or "No next material")
  next_.enabled = #forward > 0
  local items, steps = { "View history" }, {}
  for i = #(us.focus_hist or {}), 1, -1 do
    steps[#steps + 1] = -(#back - i + 1)
    items[#items + 1] = { "", "◀ ", caption(back[i]) }
  end
  for i = #forward, 1, -1 do
    steps[#steps + 1] = #forward - i + 1
    items[#items + 1] = { "", "▶ ", caption(forward[i]) }
  end
  local recent = row.add { type = "drop-down", items = items, selected_index = 1,
    tags = { ssk_sk = "f_history", steps = steps }, tooltip = "Jump backward or forward along your viewed-material path" }
  recent.style.width = 160
  recent.enabled = #items > 1
  local clear = row.add { type = "sprite-button", style = "tool_button_red", sprite = "utility/trash",
    tags = { ssk_sk = "f_clear_history" },
    tooltip = "Clear viewed-material history. Keep the current material and collected production data." }
  clear.enabled = #back + #forward > 0
end

local function trail_controls(bar, us)
  local back, caption = us.focus_hist or {}, material_caption
  local trail = option_row(bar)
  small(trail, "Path:")
  local slots = math.max(2, math.min(5, math.floor(((us.canvas_w or 900) - 210) / 60)))
  local first = math.max(1, #back - slots + 2)
  if first > 1 then small(trail, "…") end
  for i = first, #back do
    trail.add { type = "sprite-button", style = "slot_button", sprite = back[i],
      tooltip = { "", "Return to ", caption(back[i]) }, tags = { ssk_sk = "f_trail", steps = -(#back - i + 1) } }
    local arrow = trail.add { type = "sprite", sprite = "utility/right_arrow", resize_to_sprite = false }
    arrow.style.width, arrow.style.height = 12, 12
    arrow.style.stretch_image_to_widget_size = true
  end
  if us.focus then
    local current = small(trail, caption(us.focus))
    current.style.width = 140
    current.style.font = "default-bold"
    current.style.single_line = true
    current.tooltip = { "", "Current material: ", caption(us.focus) }
  end
end

local function focus_toolbar(bar, us, player)
  bar.clear()
  local strip = bar.add { type = "frame", style = "subheader_frame", direction = "horizontal", tags = { ssk_primary_controls = true } }
  strip.style.height = 48
  local main = option_row(strip)
  item_pickers(main, us)
  navigation_controls(main, us)
  local actions = right_group(main, us)
  zoom_buttons(actions, true)
  label_toggle(actions, us)
  button(actions, "Options", "f_options", "Show or hide less-used chart and layout controls").toggled = us.options_open == true
  trail_controls(bar, us)
  if us.neighborhood then
    local making = bar.add { type = "label", name = "ssk_producers" }
    making.style.width = math.max(100, (us.toolbar_width or us.canvas_w or 900) - 12)
    making.style.font = "default-small"
    making.style.single_line = true
  end
  local options = bar.add { type = "frame", style = "inside_shallow_frame", name = "ssk_options", direction = "vertical", visible = us.options_open == true }
  options.style.padding = 4
  local row = option_row(options)
  widths_picker(row, us)
  colors_picker(row, us)
  lines_picker(right_group(row, us), us)
  row = option_row(options)
  if us.neighborhood then
    local expand = button(row, "Expand inputs", "inputs_more", "Reveal another upstream production step (up to 6)")
    expand.enabled = (us.input_depth or 1) < View.MAX_INPUT_DEPTH
    if (us.input_depth or 1) > 1 then button(row, "Fewer inputs", "inputs_less", "Hide the furthest upstream step") end
  else
    small(row, "Steps:")
    row.add { type = "drop-down", items = { "1", "2", "3" }, selected_index = us.focus_steps or 2,
      tags = { ssk_sk = "f_steps" }, tooltip = "Item steps to include upstream and downstream" }
  end
  local drawing = right_group(row, us)
  button(drawing, "Center", "center_selection", "Center the selected material")
  reflow_button(drawing)
  button(drawing, "Unpin", "unpin", "Clear the pinned chain highlight")
  row = option_row(options)
  live_toggle(row, us)
  if developer_controls(player) then renderer_picker(right_group(row, us), us) end
end

local function build_toolbar(bar, us, L, player)
  if us.view == "focus" then return focus_toolbar(bar, us, player) end
  bar.clear()
  local r1 = option_row(bar)

  small(r1, "View:")
  local view_picker = r1.add { type = "drop-down", items = { "Grouped (unfinished)", "Item / fluid names" },
    selected_index = us.view == "overview" and 1 or 2, tags = { ssk_sk = "view" },
    tooltip = "Individual item and fluid names are the default. Grouping is unfinished: broad category names can hide material details. Expand a group to inspect its members." }
  view_picker.style.width = 160
  local presets = View.presets()
  local items, sel = {}, 1
  for i, p in ipairs(presets) do
    items[i] = p.name
    if p.id == us.preset then sel = i end
  end
  us.preset_ids = {}
  for i, p in ipairs(presets) do us.preset_ids[i] = p.id end
  small(r1, "Preset:")
  local preset_picker = r1.add { type = "drop-down", items = items, selected_index = sel, tags = { ssk_sk = "preset" } }
  preset_picker.style.width = 190

  local actions = right_group(r1, us)
  zoom_buttons(actions)
  button(actions, "Advanced", "advanced", "Show or hide layout, tier range and line controls").toggled = us.advanced == true
  local controls = bar.add { type = "flow", direction = "vertical", name = "ssk_advanced" }
  controls.visible = us.advanced == true
  r1 = option_row(controls)
  small(r1, "Tiers by:")
  r1.add { type = "drop-down", items = { "Tech era + depth", "Production depth" },
           selected_index = (us.view == "overview" or us.tier_mode == "depth") and 2 or 1, tags = { ssk_sk = "tier_mode" },
           enabled = us.view ~= "overview",
           tooltip = "Overview uses production depth because groups span tech eras. Individual items can use tech era + depth or production depth." }
  small(r1, "Range:")
  local titems, lo_i, hi_i = {}, 1, 1
  us.tier_vals = {}
  for i, t in ipairs(L.all_tiers) do
    titems[i] = View.tier_label(t)
    us.tier_vals[i] = t
    if us.tier_lo and t <= us.tier_lo + 1e-9 then lo_i = i end
    if not us.tier_hi or t <= us.tier_hi + 1e-9 then hi_i = i end
  end
  if #titems == 0 then titems = { "T0" } end
  r1.add { type = "drop-down", items = titems, selected_index = lo_i, tags = { ssk_sk = "tier_lo" } }
  small(r1, "to")
  r1.add { type = "drop-down", items = titems, selected_index = math.max(lo_i, hi_i), tags = { ssk_sk = "tier_hi" } }

  r1 = option_row(controls)
  r1.add { type = "checkbox", caption = "Split raw inputs", state = us.split_raw ~= false, tags = { ssk_sk = "split_raw" },
           tooltip = "Ores, oil, water… get one copy per lane that uses them, placed next to their consumers" }
  r1 = option_row(controls)
  small(r1, "Layout:")
  r1.add { type = "drop-down", items = { "Routed columns", "Swimlanes" }, selected_index = (us.layout == "lanes") and 2 or 1,
           tags = { ssk_sk = "layout" },
           tooltip = "Routed columns reserve item headers and long-link tracks; crossings can remain. Scroll sideways for larger graphs.\nSwimlanes group related items and allow manual ordering; ribbons can overlap." }
  lines_picker(r1, us)
  button(right_group(r1, us), "Reset layout", "reset_layout", "Forget manual ordering, hidden items and collapsed groups")

  if developer_controls(player) then renderer_picker(option_row(controls), us) end
  local r2 = option_row(bar)
  widths_picker(r2, us)
  colors_picker(r2, us)
  local actions = right_group(r2, us)
  live_toggle(actions, us)
  label_toggle(actions, us)
  reflow_button(actions)
  button(actions, "Unpin", "unpin", "Clear the pinned highlight. Click a node to pin one.")
  if us.view == "overview" then button(actions, "Collapse overview", "overview_reset", "Unfinished grouping: return expanded groups to the overview") end
  r2 = option_row(bar)
  local n = us.sel and L.nodes[us.sel]
  local clean = us.layout ~= "lanes"
  if clean and not n then
    hint(r2, "Hover to trace a chain; click to pin. Select a group to expand it. Scroll for larger graphs.", (us.canvas_w or 1000) - 24)
  elseif not n then
    hint(r2, "Click a node to select it. ▲/▼ reorders its group; Shift moves to the end.", (us.canvas_w or 1000) - 24)
  else
    local selected = small(r2, "Selected: " .. rt(sprite_for(n)) .. " " .. display_name(n) .. " · group: " .. n.ginfo.super_name .. " › " .. n.ginfo.name)
    selected.style.width = (us.canvas_w or 1000) - 24
    selected.style.single_line = true
    r2 = option_row(bar)
    if not clean then
      button(r2, "▲", "up", "Move up (Shift: to top). At the top it moves the sub-lane, then the lane.")
      button(r2, "▼", "down", "Move down (Shift: to bottom). At the bottom it moves the sub-lane, then the lane.")
    end
    button(r2, "Hide", "hide", "Hide this node (its flow becomes stubs on neighbours)")
    if n.kind == "group" then
      button(r2, "Expand group", "expand", "Show this group's members and their immediate production inputs", { gid = n.group })
    elseif n.base then
      hint(r2, "Raw input, split per lane. Untick Split raw inputs under Advanced to regroup it.", 400)
    else
      button(r2, "Collapse group", "collapse", "Merge all visible members of this group into one node", { gid = n.group })
      small(r2, "Move to:")
      local glist = Gr.list(player.index)
      local gitems, gsel = {}, 1
      us.group_ids = {}
      for i, g in ipairs(glist) do
        gitems[i] = g.super_name .. " › " .. g.name
        us.group_ids[i] = g.id
        if g.id == n.group then gsel = i end
      end
      local group_picker = r2.add { type = "drop-down", items = gitems, selected_index = gsel, tags = { ssk_sk = "move_group" } }
      group_picker.style.width = 180
      local tf = r2.add { type = "textfield", name = "ssk_newgroup", tooltip = "New group name" }
      tf.style.width = 140
      button(r2, "New group", "new_group", "Create a group with this name and move the node into it")
      button(r2, "Default group", "ungroup", "Remove your override for this item")
    end
    button(r2, "Deselect", "deselect")
  end
  local nh = 0
  for _ in pairs(us.hidden) do nh = nh + 1 end
  if nh > 0 then button(r2, "Show hidden (" .. nh .. ")", "unhide_all") end
end

---------------------------------------------------------------------------
-- canvas
---------------------------------------------------------------------------
local POLY -- polygon painter while drawing with the camera renderer (nil = sprites)

local function bg(canvas, color, x, y, w, h, kind_, tooltip)
  if POLY then return POLY.rect(x, y, w, h, Canvas.col(color, kind_ == "bg" and 0.10 or 0.35)) end
  local e = add_sprite(canvas, string.format("ssk-%s-c%02d", kind_, color), tooltip)
  place(e, x, y, w, h)
  return e
end

-- Labels and buttons can end up a few px taller/shorter than asked, which would shift every
-- element placed after them. So they are drawn LAST, each inside a fixed-size wrapper flow.
local function wrapped(canvas, x, y, w, h, spec)
  local f = canvas.add { type = "flow", direction = "horizontal" }
  place(f, x, y, w, h)
  f.style.padding = 0
  local e = f.add(spec)
  e.style.maximal_width = w
  return e
end

local function ribbon_sprite(r, color)
  if r.kind == "bar" then return S.bar(color) end
  if r.kind == "elbow" then return S.elbow_name(r.corner, r.k, color) end
  return S.pick(r.dir, r.k, color, r.box_h)
end

local function highlight(st, key)
  local upstream, downstream = {}, {}
  local function walk(set, reverse)
    if not key then return end
    set[key] = true
    local changed = true
    while changed do
      changed = false
      for _, path in ipairs(st.paths or {}) do
        local a, b = reverse and path.to or path.from, reverse and path.from or path.to
        if set[a] and not set[b] then set[b] = true; changed = true end
      end
    end
  end
  walk(upstream, true); walk(downstream, false)
  for _, r in ipairs(st.ribbons) do
    local related = upstream[r.from] and upstream[r.to] or downstream[r.from] and downstream[r.to]
    local c = key and not related and palette.DIM or (not key and st.quiet and palette.muted(r.color) or r.color)
    if r.ro then
      if r.ro.valid then r.ro.color = Canvas.col(c) end
    elseif r.elem and r.elem.valid then r.elem.sprite = ribbon_sprite(r, c) end
  end
end

local function draw(canvas, L, us, st, player, W, H)
  st.ribbons = {}
  st.quiet = true
  st.selected = us.view == "focus" and us.focus or us.sel
  if us.neighborhood then st.selected=us.pinned end
  local count = 0
  local cx = L.col_x
  local late = {} -- deferred labels / buttons
  POLY = nil
  if player then Canvas.clear(player.index) end
  if us.renderer == "poly" and player then
    POLY = Canvas.begin(player, W, H)
    local cam = canvas.add(Canvas.camera_spec(player, POLY))
    place(cam, 0, 0, W, H)
    cam.ignored_by_interaction = true
  end

  -- 1. lanes and sub-lanes (behind everything)
  for _, ln in ipairs(L.lane_list) do
    local x0 = cx[ln.c0] - View.LANE_LEFT
    local x1 = cx[ln.c1] + View.NODE_W + View.LANE_RIGHT
    bg(canvas, ln.color, x0, ln.y0, x1 - x0, ln.h, "bg", ln.name)
    bg(canvas, ln.color, x0, ln.y0, 4, ln.h, "line", ln.name)
    late[#late + 1] = { x0 + 10, ln.y0 + 2, 220, 20, { type = "label", caption = ln.name, ignored_by_interaction = true },
                        font = "default-bold", color = { 0.85, 0.85, 0.85 } }
    count = count + 2
    if ln.titled then
      for _, sb in ipairs(ln.sub_list) do
        local sx0 = cx[sb.c0] - View.LANE_LEFT + 10
        local sx1 = cx[sb.c1] + View.NODE_W + View.LANE_RIGHT - 10
        bg(canvas, ln.color, sx0, sb.y0, sx1 - sx0, sb.h, "bg", ln.name .. " › " .. sb.name)
        bg(canvas, ln.color, sx0, sb.y0, sx1 - sx0, 1, "line")
        late[#late + 1] = { sx0 + 4, sb.y0 + 1, 200, 14, { type = "label", caption = sb.name, ignored_by_interaction = true },
                            font = "default-small", color = { 0.75, 0.75, 0.75 } }
        count = count + 2
      end
    end
  end

  -- 2. Shared route primitives; backend selection cannot change the route.
  st.paths = {}
  local meshes, mesh_order = {}, {}
  local function ribbon(l, xa, xb, color, tip)
    local pieces = Geometry.route(l, xa, xb, l.y1, l.y2)
    st.paths[#st.paths + 1] = { from = l.from, to = l.to, pieces = pieces }
    if POLY then
      local key = l.from .. ">" .. l.to
      if not meshes[key] then
        meshes[key] = { from = l.from, to = l.to, color = color, pieces = {} }
        mesh_order[#mesh_order + 1] = key
      end
      for _, p in ipairs(pieces) do table.insert(meshes[key].pieces, p) end
      return
    end
    for _, p in ipairs(pieces) do
      local r = { kind = p.kind, corner = p.corner, dir = p.dir, k = p.k, box_h = p.box_h,
        color = color, from = l.from, to = l.to }
      r.elem = add_sprite(canvas, ribbon_sprite(r, color), tip)
      place(r.elem, p.x, p.y, p.w, p.h)
      if r.ro or r.elem then st.ribbons[#st.ribbons + 1] = r end
    end
  end
  for _, sg in ipairs(L.segments or {}) do
    local x1 = sg.a.kind == "via" and sg.a.x or sg.a.x + View.NODE_W
    if sg.b.x > x1 then
      local src, dst = sg.link.a, sg.link.b
      local endpoint = us.color_mode ~= "source" and dst or src
      local color = endpoint.color or endpoint.ginfo.color
      local tip = string.format("%s → %s\n%s %s of %s", rt(sprite_for(src)), rt(sprite_for(dst)), fmt(sg.rate), units(src.kind == "recipe" and dst or src), display_name(src.kind == "recipe" and dst or src))
      ribbon(sg, x1, sg.b.x, color, tip)
      count = count + 1
    end
  end
  for _, l in ipairs(L.segments and {} or L.links) do
    local x1, x2 = l.a.x + View.NODE_W, l.b.x
    if x2 > x1 then
      local endpoint = us.color_mode ~= "source" and l.b or l.a
      local color = endpoint.color or endpoint.ginfo.color
      local source = l.a.kind == "recipe" and l.b or l.a
      local tip = string.format("%s → %s\n%s %s of %s", rt(sprite_for(l.a)), rt(sprite_for(l.b)), fmt(l.rate), units(source), display_name(source))
      if l.note then tip = tip .. "\n" .. l.note end
      ribbon(l, x1, x2, color, tip)
      count = count + 1
    end
  end
  for _, key in ipairs(mesh_order) do
    local r = meshes[key]
    r.ro = POLY.ribbon(r.pieces, Canvas.col(r.color))
    st.ribbons[#st.ribbons + 1] = r
  end
  -- 3. stubs + node bars (sprites); buttons and labels deferred
  for _, col in ipairs(L.cols) do
    for _, n in ipairs(col) do
      local function stub(x, y, h, tip)
        if POLY then
          -- fades out away from the node: three steps of decreasing alpha
          local w3 = View.STUB / 3
          local right = x > n.x
          for i = 0, 2 do
            local a = 0.25 - 0.08 * i
            local xx = right and (x + i * w3) or (x + View.STUB - (i + 1) * w3)
            POLY.rect(xx, y, w3, h, Canvas.col(palette.GREY, a))
          end
          return
        end
        local e = add_sprite(canvas, S.bar(palette.GREY), tip)
        place(e, x, y, View.STUB, h)
      end
      if n.stub_out > 0 then
        stub(n.x + View.NODE_W, n.stub_out_y, n.t_stub_out, string.format("Other uses of %s: %s/s\n(not shown: outside this view, labs, fuel, building, launches…)", display_name(n), fmt(n.stub_out)))
        count = count + 1
      end
      if n.stub_in > 0 then
        stub(n.x - View.STUB, n.stub_in_y, n.t_stub_in, string.format("Other sources of %s: %s/s\n(outside this view: mining, pumping, handcraft, recycling, filtered producers…)", display_name(n), fmt(n.stub_in)))
        count = count + 1
      end
      local tip = {}
      tip[#tip + 1] = rt(sprite_for(n)) .. " " .. display_name(n) .. "  [" .. n.ginfo.super_name .. " › " .. n.ginfo.name .. "]  " .. View.tier_label(n.tier)
        .. (n.era and string.format(" (tech era %d)", n.era) or " (production depth)")
      if n.context then tip[#tip + 1] = n.context end
      if n.kind == "item" or n.kind == "fluid" or n.kind == "group" then
        tip[#tip + 1] = string.format("Produced %s %s · consumed %s %s", fmt(n.prod), units(n), fmt(n.cons), units(n))
        if n.kind == "group" then tip[#tip + 1] = "Totals across these members; expand the group for each material's rate." end
      end
      if n.copies and n.copies > 1 then
        tip[#tip + 1] = string.format("Split input: this copy feeds %s with %s/s (%.0f%% of %s/s total, %d copies)",
          n.ginfo.super_name, fmt(n.sout), (n.share or 0) * 100, fmt(n.total_prod or n.prod), n.copies)
      end
      if n.stub_in > 0 then tip[#tip + 1] = "Other sources: " .. fmt(n.stub_in) .. "/s" end
      if n.stub_out > 0 then tip[#tip + 1] = "Other uses: " .. fmt(n.stub_out) .. "/s" end
      if (n.catalyst or 0) > 0 then tip[#tip + 1] = "Catalyst (consumed and returned, netted out): " .. fmt(n.catalyst) .. "/s" end
      for _, lp in ipairs(n.loops) do
        local what = rt(base_key(lp.what))
        if lp.back and lp.out then
          tip[#tip + 1] = "↺ feeds back " .. fmt(lp.rate) .. "/s into " .. what .. " (loop, not drawn)"
        elseif lp.back then
          tip[#tip + 1] = "↺ gets " .. fmt(lp.rate) .. "/s back from " .. what .. " (loop, not drawn)"
        elseif lp.late then
          tip[#tip + 1] = "↺ " .. what .. " " .. fmt(lp.rate) .. "/s (later-tech producer, not drawn)"
        else
          tip[#tip + 1] = "↺ " .. what .. " " .. fmt(lp.rate) .. "/s (recycling / reversing recipe, not drawn)"
        end
      end
      if n.members then
        local parts = {}
        for _, mk in ipairs(n.members) do parts[#parts + 1] = rt(mk) end
        tip[#tip + 1] = "Members: " .. table.concat(parts, " ")
      end
      local details = table.concat(tip, "\n")
      local shown = (n.prod > 0) and n.prod or n.cons
      local rate = n.kind == "recipe" and "Recipe" or (fmt(shown) .. " " .. units(n))
      local usage = us.neighborhood and n.selected_usage
      if usage then
        local material=L.nodes[us.focus]
        rate=fmt(usage).." "..units(material)
        details="Consumes selected "..display_name(material)..": "..rate.."\n"..details
      end
      local tooltip = { "", rt(sprite_for(n)), " ", localised_name(n), "\n", rate }
      if usage then
        tooltip[#tooltip+1]=" of "
        tooltip[#tooltip+1]=localised_name(L.nodes[us.focus])
        tooltip[#tooltip+1]=" consumed"
        if n.kind~="recipe" then tooltip[#tooltip+1]="\nConsumer production: "..fmt(n.prod).." "..units(n) end
      end
      local bar
      if POLY then
        POLY.rect(n.x, n.y, View.NODE_W, n.h, Canvas.col(n.color or n.ginfo.color, 1))
        bar = add_sprite(canvas, "ssk-node-hit", tooltip)
      else
        bar = add_sprite(canvas, S.bar(n.color or n.ginfo.color), tooltip)
      end
      place(bar, n.x, n.y, View.NODE_W, n.h)
      bar.raise_hover_events = true
      bar.tags = { ssk_sk = "node", key = n.key, fx = (us.view == "focus"), part = "bar" }
      count = count + 1
      local iy = n.y - View.NODE_W - View.ICON_GAP
      local stem = add_sprite(canvas, S.bar(n.color or n.ginfo.color))
      place(stem, n.x + View.NODE_W / 2 - 1, iy + View.NODE_W, 2, View.ICON_GAP)
      stem.ignored_by_interaction = true
      late[#late + 1] = { n.x, iy, View.NODE_W, View.NODE_W,
        { type = "sprite-button", sprite = sprite_for(n), tooltip = tooltip, style = "slot_button",
          raise_hover_events = true, tags = { ssk_sk = "node", key = n.key, fx = (us.view == "focus") } }, toggled = (us.sel == n.key), fill = true }
      local show_label = us.show_labels or n.key == us.sel or n.key == us.pinned
        or n.kind == "group"
        or (us.view == "focus" and base_key(n.key) == us.focus)
      if L.label_above then
        late[#late + 1] = { n.x, n.top or (iy - 18), math.min(260, (L.label_w and L.label_w[n.ci]) or 260), 16,
          { type = "label", caption = localised_name(n), tooltip = details,
            visible = show_label == true, tags = { ssk_label = n.key } },
          font = "default-small-bold" }
        if usage or (n.kind ~= "recipe" and n.kind ~= "group") then
          local rate_w = math.max(1, math.min(260, (L.label_w and L.label_w[n.ci]) or 260) - View.NODE_W - 6)
          late[#late + 1] = { n.x + View.NODE_W + 6, iy + 8, rate_w, 16,
            { type = "label", caption = rate,
              visible = show_label == true, ignored_by_interaction = true, tags = { ssk_rate = n.key } },
            font = "default-small", color = { 0.75, 0.75, 0.75 } }
        end
      else
        late[#late + 1] = { n.x + View.NODE_W + 3, iy + 6, 80, 16,
          { type = "label", caption = rate, tooltip = details, visible = show_label == true,
            tags = { ssk_label = n.key } }, font = "default-small-bold" }
      end
      if #n.loops > 0 then
        late[#late + 1] = { n.x - 18, iy + 4, 18, 20, { type = "label", caption = "↺", ignored_by_interaction = true }, font = "default-bold" }
      end
    end
  end

  -- 4. column headers
  for ci, t in ipairs(L.col_tiers) do
    local heading = View.tier_label(t)
    if us.neighborhood then
      local center = L.center_ci or 2
      local material=us.focus and localised_name({key=us.focus,kind=us.focus:match("^(%a+)/")}) or "selected material"
      heading = ci == center and "Selected material" or ci > center and {"","Uses · consumed /s\n",material}
        or ci == center - 1 and "Materials" or "Inputs " .. (center - ci)
    end
    late[#late + 1] = { cx[ci], 6, us.neighborhood and L.label_w[ci] or 60, us.neighborhood and 40 or 18,
      { type = "label", caption = heading, tooltip=heading, tags={ssk_column=us.neighborhood and ci>(L.center_ci or 2) and "uses" or "other"} },
      single_line=not us.neighborhood, font = "default-small-bold", color = { 0.6, 0.6, 0.6 } }
  end

  -- 5. deferred labels / buttons, each in a fixed-size wrapper
  for _, d in ipairs(late) do
    local e = wrapped(canvas, d[1], d[2], d[3], d[4], d[5])
    if d.font then e.style.font = d.font end
    if d.color then e.style.font_color = d.color end
    if d.fill or d[5].type == "label" then e.style.width, e.style.height = d[3], d[4] end
    if d[5].type == "label" then e.style.single_line = d.single_line~=false end
    if d.toggled then e.toggled = true end
    count = count + 1
  end
  highlight(st, st.selected)
  return count
end

-- st: runtime per-player render state (ribbon element refs for hover)
local function rstate(pi, view)
  storage.sk_render = storage.sk_render or {}
  local k = (view == "focus") and (pi .. ":focus") or pi
  storage.sk_render[k] = storage.sk_render[k] or { ribbons = {} }
  return storage.sk_render[k]
end

function SK.toolbar_height(us)
  if us.neighborhood then return 120 + (us.options_open and 112 or 0) end
  if us.view == "focus" then return 96 + (us.options_open and 112 or 0) end
  return (us.advanced and 272 or 96) + (us.sel and 32 or 0)
end

local function update_producers(bar,us,L)
  local label=bar.ssk_producers
  if not label then return end
  local names,contribution={},{}
  local graph=Graph.get()
  local node=graph.nodes[us.focus]
  for _,name in ipairs(node and node.producers or {}) do
    local rate=L.recipe_rates[name]
    if rate and rate.cps>0 then
      names[#names+1]=name
      local prod=rate.prod or 0
      local normal=Sampler.PF_INCLUDES_BONUS and rate.cps/(1+prod) or rate.cps
      local total=0
      for _,product in ipairs(graph.recipes[name].products) do
        if product.key==us.focus then total=total+normal*(product.amount+product.prod*prod) end
      end
      contribution[name]=total
    end
  end
  table.sort(names,function(a,b)
    if contribution[a]~=contribution[b] then return contribution[a]>contribution[b] end
    return a<b
  end)
  local caption,tooltip={"","Making: "},{"","Recorded recipes producing this material:"}
  for i,name in ipairs(names) do
    local proto=prototypes.recipe[name]
    local text=proto and proto.localised_name or name:gsub("%-"," ")
    if i<=3 then
      if i>1 then caption[#caption+1]=" · " end
      caption[#caption+1]={"","[recipe="..name.."] ",text}
    end
    tooltip[#tooltip+1]={"","\n[recipe="..name.."] ",text}
  end
  if #names==0 then caption[#caption+1]="No recorded crafting recipe (may be mining, pumping or outside tracked machines)." end
  if #names>3 then caption[#caption+1]=" +"..(#names-3).." more" end
  label.caption=caption;label.tooltip=tooltip;label.tags={ssk_recipes=names}
end

-- c: tab content (vertical flow). full=false keeps the scroll-pane (and its scroll position).
function SK.fill(player, c, us, W, viewH, full, only_auto)
  local hovered=hovered_nodes[player.index]
  if hovered and hovered.valid then
    local ancestor=hovered
    while ancestor and ancestor~=c do ancestor=ancestor.parent end
    if ancestor==c and only_auto and not full then return end
  end
  hovered_nodes[player.index]=nil
  SK.defaults(us)
  if full or not c.ssk_sp then
    c.clear()
    c.add { type = "scroll-pane", name = "ssk_bar", horizontal_scroll_policy = "auto", vertical_scroll_policy = "auto" }
    local info = c.add { type = "label", name = "ssk_info" }
    info.style.font = "default-small"
    info.style.font_color = { 0.65, 0.65, 0.65 }
    local sp = c.add { type = "scroll-pane", name = "ssk_sp", horizontal_scroll_policy = "never",
                       vertical_scroll_policy = "auto-and-reserve-space" }
    sp.style.horizontally_stretchable = true
    sp.style.height = viewH
    local canvas = sp.add { type = "flow", name = "ssk_canvas", direction = "vertical" }
    canvas.style.vertical_spacing = 0
  end
  c.ssk_bar.style.width = W
  us.toolbar_width = W
  c.ssk_sp.style.height = viewH
  c.ssk_bar.style.height = SK.toolbar_height(us)
  c.ssk_bar.style.padding = 0
  local canvas = c.ssk_sp.ssk_canvas
  if us.view == "focus" and not us.focus then
    if not only_auto or #c.ssk_bar.children==0 then focus_toolbar(c.ssk_bar, us, player) end
    canvas.clear()
    Canvas.clear(player.index)
    local l = canvas.add { type = "label", caption = us.neighborhood and "Pick an item or fluid above, or use a row's magnifier to inspect its materials and uses." or "Pick an item or fluid above, or use a row's magnifier in the Balance tab." }
    l.style.single_line = false
    place(l, 24, 40, math.max(100, W - 48), 60)
    c.ssk_info.caption = ""
    return
  end
  local L = View.build(player, us, W, viewH)
  if not only_auto or #c.ssk_bar.children==0 then build_toolbar(c.ssk_bar, us, L, player) end
  update_producers(c.ssk_bar,us,L)
  us.last_order = L.order
  us.last_lanes = L.lane_order
  us.last_subs = L.sub_order

  canvas.clear()
  local CW = math.max(W, math.floor(L.content_w or W))
  canvas.style.width = CW
  canvas.style.height = math.max(viewH - 4, L.content_h)
  c.ssk_sp.horizontal_scroll_policy = (CW > W) and "auto" or "never"
  local nn = 0
  for _ in pairs(L.nodes) do nn = nn + 1 end
  local count = 0
  if nn == 0 then
    Canvas.clear(player.index)
    local caption = (L.seconds < 2)
      and "Collecting data… rates appear after the first few seconds."
      or "Nothing to show for this preset / scope / tier range."
    if us.view == "focus" and L.seconds >= 2 then
      caption = { "", "No recorded recipe flow for ", localised_name({key=us.focus}),
        " on this surface in the selected period. Try another material, surface or period." }
    end
    local l = canvas.add { type = "label", caption = caption }
    l.style.single_line = false
    place(l, 24, 40, math.max(100, W - 48), 80)
  else
    count = draw(canvas, L, us, rstate(player.index, us.view), player, CW, math.max(viewH - 4, L.content_h))
    if us.center_pending or (us.neighborhood and (us.centered_focus ~= us.focus or full)) then
      local n=L.nodes[us.view=="focus" and us.focus or us.sel]
      do
        local aw, ah=math.min(W-24,CW), math.min(viewH-24,L.content_h)
        local mx=n and n.x+View.NODE_W/2 or (us.fit_pending and aw/2 or CW/2)
        local my=n and n.y+n.h/2 or (us.fit_pending and ah/2 or L.content_h/2)
        local x=math.max(0,math.min(CW-aw,mx-aw/2))
        local y=math.max(0,math.min(L.content_h-ah,my-ah/2))
        local anchor=canvas.add{type="empty-widget", ignored_by_interaction=true}
        place(anchor,x,y,aw,ah)
        c.ssk_sp.scroll_to_element(anchor)
      end
      us.center_pending,us.centered_focus=false,us.focus
      us.fit_pending=nil
    end
  end
  c.ssk_info.caption = string.format(
    "%d items/groups · %d flows · %d lanes · %d columns (%s–%s of %d tiers) · %.0f s recorded · %.4f px per item/s · fluids drawn ×%g · %d thin flows at %d px min · crossing cost %.0f · %d elements · ribbons carry the source item's units",
    nn, #L.links, L.lane_list and #L.lane_list or 0, #L.cols,
    L.col_tiers[1] and View.tier_label(L.col_tiers[1]) or "-", L.col_tiers[#L.col_tiers] and View.tier_label(L.col_tiers[#L.col_tiers]) or "-",
    #L.all_tiers, L.seconds, L.scale or 0, L.fluid_factor or 1, L.clamped or 0, L.min_t or 0, L.crossing_cost or 0, count)
  c.ssk_info.style.width = W
  c.ssk_info.style.single_line = true
  c.ssk_info.tooltip = c.ssk_info.caption
  if not us.advanced then
    c.ssk_info.caption = string.format("%d items/groups · %d flows · %.0f s recorded · %s widths · %s colors · hover for details", nn, #L.links, L.seconds, us.heights=="linear" and "proportional" or "compressed", us.color_mode=="source" and "source" or "destination")
  end
  if us.neighborhood then
    c.ssk_info.caption = string.format("%d input step(s) · %.0f s recorded · %s widths · %s colors · Shift-click to pin", (L.center_ci or 2)-1, L.seconds, us.heights=="linear" and "proportional" or "compressed", us.color_mode=="source" and "source" or "destination")
    c.ssk_info.tooltip = "Colors follow the "..(us.color_mode=="source" and "source" or "destination")..". Ribbons carry source-material units. Fluids drawn ×"..tostring(L.fluid_factor)..". Thin flows are enlarged to "..L.min_t.." px. Hover for exact rates."
  end
end

---------------------------------------------------------------------------
-- interaction
---------------------------------------------------------------------------
-- ▲/▼ cascade: inside the node's (sub-lane, column) bucket; at the bucket edge the
-- sub-lane moves inside its lane; at the lane edge the whole lane moves.
local function reorder(list, i, dir, to_end)
  local j
  if to_end then j = (dir < 0) and 1 or #list else j = i + dir end
  if j < 1 or j > #list or j == i then return false end
  local v = table.remove(list, i)
  table.insert(list, j, v)
  return true
end

local function move(player, us, dir, to_end)
  local key = us.sel
  if not key then return end
  local bucket, idx
  for bid, list in pairs(us.last_order or {}) do
    for i, k in ipairs(list) do if k == key then bucket, idx = bid, i end end
  end
  if not bucket then return end
  local list = us.last_order[bucket]
  if reorder(list, idx, dir, to_end) then
    for i, k in ipairs(list) do us.pos[k] = i end
    return
  end
  -- sub-lane level
  us.gpos = us.gpos or {}
  us.lpos = us.lpos or {}
  local gid = string.match(bucket, "^(.-)@%d+$")
  for li, lane in ipairs(us.last_lanes or {}) do
    local subs = (us.last_subs or {})[lane] or {}
    for si, sid in ipairs(subs) do
      if sid == gid then
        if reorder(subs, si, dir, false) then
          for i, g in ipairs(subs) do us.gpos[g] = i end
        else
          local lanes = us.last_lanes
          if reorder(lanes, li, dir, false) then
            for i, l in ipairs(lanes) do us.lpos[l] = i end
          end
        end
        return
      end
    end
  end
end

-- returns: nil (not ours) | "redraw" | "rebuild"
function SK.select_focus(us, key)
  if not key or key == us.focus then return false end
  us.focus_hist = us.focus_hist or {}
  if us.focus then table.insert(us.focus_hist, us.focus) end
  while #us.focus_hist > 20 do table.remove(us.focus_hist, 1) end
  us.focus = key
  us.focus_forward = {}
  return true
end

function SK.step_history(us, steps)
  if not steps or steps == 0 then return false end
  us.focus_hist, us.focus_forward = us.focus_hist or {}, us.focus_forward or {}
  local from = steps < 0 and us.focus_hist or us.focus_forward
  local to = steps < 0 and us.focus_forward or us.focus_hist
  if math.abs(steps) > #from then return false end
  for _ = 1, math.abs(steps) do
    if us.focus then to[#to + 1] = us.focus end
    us.focus = table.remove(from)
  end
  return true
end

function SK.on_click(e, us)
  local tags = e.element.tags
  local a = tags and tags.ssk_sk
  if not a then return nil end
  SK.defaults(us)
  local player = game.get_player(e.player_index)
  local pi = player.index
  if a == "node" and us.neighborhood and e.shift then
    us.pinned = us.pinned ~= tags.key and tags.key or nil
  elseif a == "unpin" then us.pinned=nil; if us.view~="focus" then us.sel=nil end
  elseif a == "center_selection" then us.center_pending=true
  elseif a == "node" and us.view == "focus" then
    local k = base_key(tags.key)
    if string.sub(k, 1, 6) == "group/" or string.sub(k, 1, 7) == "recipe/" or k == us.focus then return "none" end
    SK.select_focus(us, k)
  elseif a == "f_clear_history" then
    us.focus_hist, us.focus_forward = {}, {}
  elseif a == "f_back" or a == "f_forward" or a == "f_trail" then
    if not SK.step_history(us, a == "f_back" and -1 or a == "f_forward" and 1 or tags.steps) then return "none" end
  elseif a == "node" then
    us.sel = (us.sel ~= tags.key) and tags.key or nil
  elseif a == "f_options" then us.options_open = not us.options_open
  elseif a == "advanced" then us.advanced = not us.advanced
  elseif a == "inputs_more" then us.input_depth = math.min(View.MAX_INPUT_DEPTH, (us.input_depth or 1) + 1)
  elseif a == "inputs_less" then us.input_depth = math.max(1, (us.input_depth or 1) - 1)
  elseif a == "deselect" then us.sel = nil
  elseif a == "zoom_in" then us.zoom = math.min(8, us.zoom * ZOOM_STEP)
  elseif a == "zoom_out" then us.zoom = math.max(0.25, us.zoom / ZOOM_STEP)
  elseif a == "zoom_fit" then us.zoom = 1; us.layout_snapshot=nil; us.center_pending=true; us.fit_pending=true
  elseif a == "reflow" then us.reflow = (us.reflow or 0) + 1; us.auto_rank = {}
  elseif a == "overview_reset" then us.overview_open = {}; us.sel = nil
  elseif a == "reset_layout" then
    us.pos, us.gpos, us.lpos, us.hidden, us.collapsed = {}, {}, {}, {}, {}
    us.layout_snapshot, us.auto_rank, us.overview_open = nil, {}, {}
  elseif a == "up" or a == "down" then move(player, us, a == "up" and -1 or 1, e.shift)
  elseif a == "hide" then
    if us.sel then us.hidden[base_key(us.sel)] = true; us.sel = nil end
  elseif a == "unhide_all" then us.hidden = {}
  elseif a == "collapse" then us.collapsed[tags.gid] = true; us.sel = "group/" .. tags.gid
  elseif a == "expand" then
    if us.view == "overview" and string.sub(tags.gid, 1, 1) == "@" then
      us.overview_open = us.overview_open or {}; us.overview_open[string.sub(tags.gid, 2)] = true
    else us.collapsed[tags.gid] = nil end
    us.sel = nil
  elseif a == "ungroup" then if us.sel then Gr.unassign(pi, base_key(us.sel)) end
  elseif a == "new_group" then
    local tf = e.element.parent.ssk_newgroup
    local name = tf and tf.text or ""
    if us.sel and name ~= "" then
      local cur = Gr.info(pi, Gr.of(pi, base_key(us.sel)))
      local id = Gr.create(pi, name, cur.super)
      Gr.assign(pi, base_key(us.sel), id)
    else
      player.print("[Production Flow] Type a group name first.")
      return "redraw"
    end
  else
    return nil
  end
  return "rebuild"
end

function SK.on_selection(e, us)
  local tags = e.element.tags
  local a = tags and tags.ssk_sk
  if not a then return nil end
  SK.defaults(us)
  local i = e.element.selected_index
  if a == "view" then
    us.view = i == 1 and "overview" or "detail"
    us.sel, us.tier_lo, us.tier_hi = nil, nil, nil
  elseif a == "f_history" then
    if not SK.step_history(us, tags.steps and tags.steps[i - 1]) then return "none" end
  elseif a == "layout" then us.layout = (i == 2) and "lanes" or "clean"
  elseif a == "f_steps" then us.focus_steps = i
  elseif a == "f_heights" then us.heights = (i == 2) and "sqrt" or "linear"
  elseif a == "balance_colors" then us.color_mode = i==2 and "source" or "destination"
  elseif a == "f_lines" then us.lines = (i == 2) and "metro" or "curves"
  elseif a == "f_renderer" then us.renderer = (i == 2) and "poly" or "sprites"
  elseif a == "preset" then us.preset = us.preset_ids and us.preset_ids[i] or "all"; us.tier_lo, us.tier_hi = nil, nil
  elseif a == "tier_mode" then
    us.tier_mode = (i == 2) and "depth" or "tech"
    us.tier_lo, us.tier_hi = nil, nil
  elseif a == "tier_lo" then
    local v = us.tier_vals or {}
    us.tier_lo = (i > 1) and v[i] or nil
  elseif a == "tier_hi" then
    local v = us.tier_vals or {}
    us.tier_hi = (i < #v) and v[i] or nil
  elseif a == "move_group" then
    local id = us.group_ids and us.group_ids[i]
    if id and us.sel then Gr.assign(e.player_index, base_key(us.sel), id) end
  else
    return nil
  end
  return "rebuild"
end

function SK.on_checked(e, us)
  local tags = e.element.tags
  if not tags then return nil end
  if tags.ssk_sk == "live" then
    us.live = e.element.state
    return "none"
  elseif tags.ssk_sk == "split_raw" then
    us.split_raw = e.element.state
    return "rebuild"
  elseif tags.ssk_sk == "show_labels" then
    us.show_labels = e.element.state
    return "rebuild"
  end
  return nil
end

-- focus item pickers
function SK.on_elem_changed(e, us)
  local tags = e.element.tags
  local a = tags and tags.ssk_sk
  if a ~= "f_item" and a ~= "f_fluid" then return nil end
  local v = e.element.elem_value
  if type(v) == "table" then v = v.name end
  if not v then return "none" end
  local k = ((a == "f_item") and "item/" or "fluid/") .. v
  SK.select_focus(us, k)
  return "rebuild"
end

-- state for the focus tab (kept inside the player's UI state)
function SK.focus_state(us)
  local fx = us.fx
  if not fx then
    fx = { view = "focus", focus_steps = 2, heights = "sqrt", lines = "curves", renderer = "poly" }
    us.fx = fx
  end
  fx.period, fx.sidx = us.period, us.sidx
  fx.canvas_w, fx.canvas_h = us.canvas_w, us.canvas_h
  return fx
end

function SK.balance_state(us)
  if not us.bal_fx then us.bal_fx = { view = "focus", neighborhood = true, focus_steps = 1,
    heights = "sqrt", lines = "curves", renderer = "poly", live = true } end
  local fx = us.bal_fx
  fx.period, fx.sidx = us.period, us.sidx
  return fx
end

function SK.on_hover(e, entering)
  local tags = e.element.valid and e.element.tags
  if not (tags and tags.ssk_sk == "node") then return false end
  if entering then hovered_nodes[e.player_index]=e.element
  elseif hovered_nodes[e.player_index]==e.element then hovered_nodes[e.player_index]=nil end
  local st = rstate(e.player_index, tags.fx and "focus" or nil)
  local key = entering and tags.key or st.selected
  highlight(st, key)
  return true
end

return SK
