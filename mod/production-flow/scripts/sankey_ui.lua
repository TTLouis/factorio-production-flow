-- M4–M7 Sankey tab: toolbar (presets, scope, tiers, zoom, live), selection toolbar
-- (▲/▼, hide, group/collapse), and the canvas drawn with stretched ribbon sprites.

local S = require("shared.sprites")
local palette = require("shared.palette")
local View = require("scripts.view")
local Gr = require("scripts.groups")
local Canvas = require("scripts.canvas")
local Geometry = require("scripts.ribbon_geometry")

local SK = {}
local hovered_nodes = {}
local ZOOM_STEP = 1.25

local function round(v) return math.floor(v + 0.5) end

function SK.defaults(us)
  us.view = us.view or "overview"
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

local function fmt(x)
  if x >= 10000 then return string.format("%.1fk", x / 1000) end
  if x >= 1000 then return string.format("%.2fk", x / 1000) end
  if x >= 100 then return string.format("%.0f", x) end
  if x >= 10 then return string.format("%.1f", x) end
  if x >= 1 then return string.format("%.2f", x) end
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
  return (n.kind == "fluid" or n.flow_kind == "fluid") and "fluid units/s"
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
local function button(parent, caption, action, tooltip, extra)
  local t = { ssk_sk = action }
  if extra then for k, v in pairs(extra) do t[k] = v end end
  local b = parent.add { type = "button", caption = caption, tooltip = tooltip, tags = t }
  if action == "zoom_fit" then b.style.minimal_width = 56
  elseif #caption <= 3 then b.style.width = 32 end
  return b
end

local function small(parent, caption)
  local l = parent.add { type = "label", caption = caption }
  l.style.left_margin = 8
  return l
end

local function focus_toolbar(bar, us, player)
  bar.clear()
  if us.neighborhood then
    local title = bar.add { type = "flow", direction = "horizontal" }
    title.style.vertical_align = "center"
    local hint = title.add { type = "label", caption = "Item flow", style = "caption_label" }
    hint.style.width = 65
    button(title, "Fit graph", "zoom_fit", "Fit the graph while keeping icons and text readable; dense chains retain scrolling")
    button(title, "Center", "center_selection", "Center the selected item in the viewport")
    local expand = button(title, "Expand inputs", "inputs_more", "Reveal another upstream production step without changing the selected item (up to 6 steps)")
    expand.enabled = (us.input_depth or 1) < View.MAX_INPUT_DEPTH
    if (us.input_depth or 1) > 1 then button(title, "− inputs", "inputs_less", "Hide the furthest upstream step") end
    if #(us.focus_hist or {}) > 0 then button(title, "◀", "f_back", "Previous selected item") end
    local row = bar.add { type = "flow", direction = "horizontal" }
    row.style.horizontal_spacing = 4
    row.add { type = "choose-elem-button", elem_type = "item", item = us.focus and us.focus:match("^item/(.+)$"), tags = { ssk_sk = "f_item" } }
    row.add { type = "choose-elem-button", elem_type = "fluid", fluid = us.focus and us.focus:match("^fluid/(.+)$"), tags = { ssk_sk = "f_fluid" } }
    local renderer = row.add { type = "drop-down", items = { "GUI sprites", "Polygons" }, selected_index = us.renderer == "poly" and 2 or 1, tags = { ssk_sk = "f_renderer" } }
    renderer.style.width = 130
    row.add { type = "checkbox", caption = "Live", state = us.live, tags = { ssk_sk = "live" } }
    label_toggle(row, us)
    local options = bar.add {type="flow", direction="horizontal"}
    local heights=options.add {type="drop-down", items={"Proportional", "Compressed"},
      selected_index=us.heights=="linear" and 1 or 2, tags={ssk_sk="f_heights"},
      tooltip="Proportional: linear rate widths (fluids use the configured scale). Compressed: square-root widths; small flows are enlarged. Exact rates remain in tooltips."}
    heights.style.width=150
    local colors=options.add {type="drop-down", items={"Destination colors", "Source colors"},
      selected_index=us.color_mode=="source" and 2 or 1, tags={ssk_sk="balance_colors"},
      tooltip="Destination: inputs share the receiving node's color. Color does not change the ribbon's source-material units."}
    colors.style.width=175
    button(options, "Unpin", "unpin", "Shift-click a node to pin its flow highlight; click normally to inspect it")
    return
  end
  local r1 = bar.add { type = "flow", direction = "horizontal" }
  r1.style.vertical_align = "center"
  r1.style.horizontal_spacing = 6
  if #(us.focus_hist or {}) > 0 then button(r1, "◀", "f_back", "Back to the previous item") end
  small(r1, "Item:")
  local t, n = nil, nil
  if us.focus then t, n = string.match(us.focus, "^(%a+)/(.+)$") end
  r1.add { type = "choose-elem-button", elem_type = "item", item = (t == "item") and n or nil,
           tags = { ssk_sk = "f_item" }, tooltip = "Item to focus on" }
  r1.add { type = "choose-elem-button", elem_type = "fluid", fluid = (t == "fluid") and n or nil,
           tags = { ssk_sk = "f_fluid" }, tooltip = "…or a fluid" }
  small(r1, "Steps:")
  r1.add { type = "drop-down", items = { "1", "2", "3" }, selected_index = us.focus_steps or 2,
           tags = { ssk_sk = "f_steps" }, tooltip = "How many items up- and downstream to show (multi-output recipes don't count as a step)" }
  r1 = bar.add { type = "flow", direction = "horizontal" }
  r1.style.vertical_align = "center"
  r1.style.horizontal_spacing = 6
  small(r1, "Heights:")
  r1.add { type = "drop-down", items = { "Linear", "Square root" }, selected_index = (us.heights == "sqrt") and 2 or 1,
           tags = { ssk_sk = "f_heights" }, tooltip = "Square root keeps small flows visible next to big ones (tooltips keep real numbers)" }
  small(r1, "Lines:")
  r1.add { type = "drop-down", items = { "Curves", "Right angles" }, selected_index = (us.lines == "metro") and 2 or 1,
           tags = { ssk_sk = "f_lines" }, tooltip = "Right angles: steep ribbons run vertically and cross others at 90°" }
  small(r1, "Renderer:")
  r1.add { type = "drop-down", items = { "GUI sprites", "Polygons (beta)" }, selected_index = (us.renderer == "poly") and 2 or 1,
           tags = { ssk_sk = "f_renderer" }, tooltip = "Polygons: smooth shapes drawn on a hidden surface and shown through a camera (experimental)" }
  small(r1, "Zoom:")
  button(r1, "−", "zoom_out", "Zoom out")
  button(r1, string.format("Fit (%.0f%%)", (us.zoom or 1) * 100), "zoom_fit", "Busiest column fits the window")
  button(r1, "+", "zoom_in", "Zoom in")
  local live = r1.add { type = "checkbox", caption = "Live", state = us.live, tags = { ssk_sk = "live" },
                        tooltip = "Refresh every 5 s" }
  live.style.left_margin = 12
  local r2 = bar.add { type = "flow", direction = "horizontal" }
  button(r2, "Reflow", "reflow", "Recalculate node order, spacing and scale. Live updates otherwise keep the current layout.")
  label_toggle(r2, us)
  local hint = small(r2, "[color=0.65,0.65,0.65]Click a node to re-centre. Grey ends show flow outside this view.[/color]")
  hint.style.single_line = false
  hint.style.maximal_width = math.max(160, (us.canvas_w or 1000) - 160)
end

local function build_toolbar(bar, us, L, player)
  if us.view == "focus" then return focus_toolbar(bar, us, player) end
  bar.clear()
  local r1 = bar.add { type = "flow", direction = "horizontal" }
  r1.style.vertical_align = "center"
  r1.style.horizontal_spacing = 6

  small(r1, "View:")
  local view_picker = r1.add { type = "drop-down", items = { "Grouped overview", "Individual items" },
    selected_index = us.view == "overview" and 1 or 2, tags = { ssk_sk = "view" },
    tooltip = "Overview groups production chains; expand a group to inspect its members. Items and fluids stay separate." }
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

  button(r1, "−", "zoom_out", "Zoom out")
  button(r1, "Fit graph", "zoom_fit", "Fit readable node headers and ribbon widths; dense graphs keep scrolling")
  button(r1, "+", "zoom_in", "Zoom in")
  button(r1, "Center", "center_selection", "Center the selected node, or the whole graph when nothing is selected")
  button(r1, us.advanced and "Less" or "Advanced", "advanced", "Layout, rendering and diagnostic controls")
  local controls = bar.add { type = "flow", direction = "vertical", name = "ssk_advanced" }
  controls.visible = us.advanced == true
  r1 = controls.add { type = "flow", direction = "horizontal" }
  r1.style.vertical_align = "center"
  r1.style.horizontal_spacing = 6
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

  r1 = controls.add { type = "flow", direction = "horizontal" }
  r1.style.vertical_align = "center"
  r1.style.horizontal_spacing = 6
  r1.add { type = "checkbox", caption = "Split raw inputs", state = us.split_raw ~= false, tags = { ssk_sk = "split_raw" },
           tooltip = "Ores, oil, water… get one copy per lane that uses them, placed next to their consumers" }
  r1 = controls.add { type = "flow", direction = "horizontal" }
  r1.style.vertical_align = "center"
  r1.style.horizontal_spacing = 6
  small(r1, "Layout:")
  r1.add { type = "drop-down", items = { "Routed columns", "Swimlanes" }, selected_index = (us.layout == "lanes") and 2 or 1,
           tags = { ssk_sk = "layout" },
           tooltip = "Routed columns reserve item headers and long-link tracks; crossings can remain. Scroll sideways for larger graphs.\nSwimlanes group related items and allow manual ordering; ribbons can overlap." }
  small(r1, "Lines:")
  r1.add { type = "drop-down", items = { "Curves", "Right angles" }, selected_index = (us.lines == "metro") and 2 or 1,
           tags = { ssk_sk = "f_lines" } }
  button(r1, "Reset layout", "reset_layout", "Forget manual ordering, hidden items and collapsed groups")

  local renderer_row = controls.add { type = "flow", direction = "horizontal" }
  small(renderer_row, "Renderer:")
  renderer_row.add { type = "drop-down", items = { "GUI sprites", "Polygon mesh (beta)" },
    selected_index = us.renderer == "poly" and 2 or 1, tags = { ssk_sk = "f_renderer" },
    tooltip = "Compare the same routes: atlas sprites or a single polygon mesh per complete ribbon." }
  local r2 = bar.add { type = "flow", direction = "horizontal" }
  local widths=r2.add{type="drop-down",items={"Proportional","Compressed"},
    selected_index=us.heights=="linear" and 1 or 2,tags={ssk_sk="f_heights"},
    tooltip="Proportional uses linear rate widths; compressed uses square roots. Fluids use a separate scale and thin ribbons retain a visible minimum. Hover for exact rates."}
  widths.style.width=150
  local colors=r2.add{type="drop-down",items={"Destination colors","Source colors"},
    selected_index=us.color_mode=="source" and 2 or 1,tags={ssk_sk="balance_colors"},
    tooltip="Destination: ribbons feeding the same node share its color, including across intermediate columns. Ribbons still carry source-material units."}
  colors.style.width=175
  label_toggle(r2,us)
  r2.add{type="checkbox",caption="Live",state=us.live,tags={ssk_sk="live"}}
  button(r2,"Reflow","reflow","Recalculate node order and spacing; Live otherwise keeps the layout stable")
  button(r2,"Unpin","unpin","Clear the selected flow highlight. Click or Shift-click a node to pin it.")
  if us.view == "overview" then button(r2, "Collapse overview", "overview_reset", "Return expanded groups to the overview") end
  r2 = bar.add { type = "flow", direction = "horizontal" }
  r2.style.vertical_align = "center"
  r2.style.horizontal_spacing = 6
  local n = us.sel and L.nodes[us.sel]
  local clean = us.layout ~= "lanes"
  if clean and not n then
    local hint = small(r2, "[color=0.65,0.65,0.65]Hover to trace a chain; click to pin. Select a group to expand it. Scroll for larger graphs.[/color]")
    hint.style.maximal_width = (us.canvas_w or 1000) - 24
    hint.style.single_line = false
  elseif not n then
    local hint = small(r2, "[color=0.65,0.65,0.65]Click a node to select it. ▲/▼ reorders its group; Shift moves to the end.[/color]")
    hint.style.maximal_width = (us.canvas_w or 1000) - 24
    hint.style.single_line = false
  else
    local selected = small(r2, "Selected: " .. rt(sprite_for(n)) .. " " .. display_name(n) .. "  ·  group: " .. n.ginfo.super_name .. " › " .. n.ginfo.name)
    selected.style.width = (us.canvas_w or 1000) - 24
    selected.style.single_line = true
    r2 = bar.add { type = "flow", direction = "horizontal" }
    r2.style.horizontal_spacing = 6
    if not clean then
      button(r2, "▲", "up", "Move up (Shift: to top). At the top it moves the sub-lane, then the lane.")
      button(r2, "▼", "down", "Move down (Shift: to bottom). At the bottom it moves the sub-lane, then the lane.")
    end
    button(r2, "Hide", "hide", "Hide this node (its flow becomes stubs on neighbours)")
    if n.kind == "group" then
      button(r2, "Expand group", "expand", "Show this group's members and their immediate production inputs", { gid = n.group })
    elseif n.base then
      small(r2, "[color=0.65,0.65,0.65](raw input, split per lane — untick 'Split raw inputs' to regroup it)[/color]")
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
            { type = "label", caption = rate:gsub("fluid units/s", "fluid/s"),
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
      heading = ci == center and "Selected item" or ci > center and "Uses · consumption"
        or ci == center - 1 and "Materials" or "Inputs " .. (center - ci)
    end
    late[#late + 1] = { cx[ci], 6, us.neighborhood and math.min(148, L.label_w[ci]) or 60, 18, { type = "label", caption = heading, ignored_by_interaction = true },
                        font = "default-small-bold", color = { 0.6, 0.6, 0.6 } }
  end

  -- 5. deferred labels / buttons, each in a fixed-size wrapper
  for _, d in ipairs(late) do
    local e = wrapped(canvas, d[1], d[2], d[3], d[4], d[5])
    if d.font then e.style.font = d.font end
    if d.color then e.style.font_color = d.color end
    if d.fill or d[5].type == "label" then e.style.width, e.style.height = d[3], d[4] end
    if d[5].type == "label" then e.style.single_line = true end
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
  if us.neighborhood then return 108 end
  if us.view == "focus" then return 112 end
  return (us.advanced and 272 or 96) + (us.sel and 32 or 0)
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
    c.add { type = "label", name = "ssk_info" }
    local sp = c.add { type = "scroll-pane", name = "ssk_sp", horizontal_scroll_policy = "never",
                       vertical_scroll_policy = "auto-and-reserve-space" }
    sp.style.horizontally_stretchable = true
    sp.style.height = viewH
    local canvas = sp.add { type = "flow", name = "ssk_canvas", direction = "vertical" }
    canvas.style.vertical_spacing = 0
  end
  c.ssk_bar.style.width = W
  c.ssk_sp.style.height = viewH
  c.ssk_bar.style.height = SK.toolbar_height(us)
  c.ssk_bar.style.padding = 0
  local canvas = c.ssk_sp.ssk_canvas
  if us.view == "focus" and not us.focus then
    if not only_auto or #c.ssk_bar.children==0 then focus_toolbar(c.ssk_bar, us, player) end
    canvas.clear()
    Canvas.clear(player.index)
    local l = canvas.add { type = "label", caption = us.neighborhood and "Select a table row with its magnifier to inspect materials and uses." or "Pick an item above, or press the search button on a row in the Balance tab." }
    l.style.single_line = false
    place(l, 24, 40, math.max(100, W - 48), 60)
    c.ssk_info.caption = ""
    return
  end
  local L = View.build(player, us, W, viewH)
  if not only_auto or #c.ssk_bar.children==0 then build_toolbar(c.ssk_bar, us, L, player) end
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
    local l = canvas.add { type = "label", caption = (L.seconds < 2)
      and "Collecting data… rates appear after the first few seconds."
      or "Nothing to show for this preset / scope / tier range." }
    place(l, 40, 40, 600, 24)
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
    "[color=0.65,0.65,0.65]%d nodes · %d ribbons · %d lanes · %d columns (%s–%s of %d tiers) · window %.0f s · %.4f px per item/s · fluids drawn ×%g · %d thin flows at %d px min · crossing cost %.0f · %d elements · ribbons carry the source item's units[/color]",
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
    c.ssk_info.caption = string.format("%d input step(s) · %s · %.0f s · shift-click to pin", (L.center_ci or 2)-1, us.heights=="linear" and "proportional" or "compressed widths", L.seconds)
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
    us.focus_hist = us.focus_hist or {}
    if us.focus then table.insert(us.focus_hist, us.focus) end
    if #us.focus_hist > 20 then table.remove(us.focus_hist, 1) end
    us.focus = k
  elseif a == "f_back" then
    local h = us.focus_hist or {}
    if #h > 0 then us.focus = table.remove(h) end
  elseif a == "node" then
    us.sel = (us.sel ~= tags.key) and tags.key or nil
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
      player.print("[Sankey] Type a group name first.")
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
  if k ~= us.focus then
    us.focus_hist = us.focus_hist or {}
    if us.focus then table.insert(us.focus_hist, us.focus) end
    us.focus = k
  end
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
