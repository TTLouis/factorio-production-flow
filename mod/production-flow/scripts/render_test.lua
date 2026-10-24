-- M0 render test (fake graph). Opened from the main window or /sankey-test [margin|screen]
--   margin : ribbons placed inside a scroll-pane canvas with negative margins (primary approach)
--   screen : ribbons as screen-level elements with absolute `location` (fallback approach)
-- Hover a node icon to highlight its ribbons.

local S = require("shared.sprites")
local palette = require("shared.palette")

local FRAME = "ssk_test_frame"
local NODE_W = 16
local ICON = 28
local NODE_PAD = 48  -- vertical padding between nodes in a column (icon + rate label live here)
local PAD_X = 40
local PAD_TOP = 40
local PAD_BOTTOM = 16
local ZOOM_STEP = 1.25
local FILL = 0.55     -- at zoom 100%, flow bands use at most this share of the height; the rest is air
local MIN_T = 2     -- min ribbon / node thickness in px (linear scale + clamp, D14)

local ITEMS = {
  "iron-ore", "copper-ore", "coal", "stone", "iron-plate", "copper-plate", "steel-plate",
  "iron-gear-wheel", "copper-cable", "electronic-circuit", "plastic-bar", "sulfur",
  "advanced-circuit", "engine-unit", "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "pipe", "stone-brick", "battery",
}

local function round(v) return math.floor(v + 0.5) end

local function pstate(pi)
  storage.test = storage.test or {}
  local s = storage.test[pi]
  if not s then
    s = { mode = "margin", seed = 1, ribbons = {}, screen = {}, zoom = 1, order = true }
    storage.test[pi] = s
  end
  if s.zoom == nil then s.zoom = 1 end
  if s.order == nil then s.order = true end
  return s
end

---------------------------------------------------------------------------
-- fake graph: columns of nodes with conserved flows between adjacent columns
---------------------------------------------------------------------------
local function make_graph(seed)
  local rng = game.create_random_generator(seed)
  local g = { cols = {}, nodes = {}, links = {} }
  local ncol = rng(4, 6)
  local item_i = rng(0, #ITEMS - 1)

  for c = 1, ncol do
    g.cols[c] = {}
    for _ = 1, rng(2, 5) do
      item_i = item_i + 1
      local item = ITEMS[(item_i - 1) % #ITEMS + 1]
      if not prototypes.item[item] then item = "iron-plate" end
      local n = { id = #g.nodes + 1, col = c, value = 0, color = rng(1, #palette.colors),
                  item = item, ins = {}, outs = {} }
      g.nodes[#g.nodes + 1] = n
      g.cols[c][#g.cols[c] + 1] = n
    end
  end
  for _, n in ipairs(g.cols[1]) do n.value = rng(10, 120) end

  for c = 1, ncol - 1 do
    local src, dst = g.cols[c], g.cols[c + 1]
    local w = {} -- w[s.id][t.id] = weight
    local function bump(s, t)
      w[s.id] = w[s.id] or {}
      local x = rng() + 0.15
      if rng() < 0.2 then x = x * 0.02 end -- some tiny flows to exercise the clamp
      w[s.id][t.id] = (w[s.id][t.id] or 0) + x
    end
    for _, t in ipairs(dst) do bump(src[rng(1, #src)], t) end
    for _, s in ipairs(src) do bump(s, dst[rng(1, #dst)]) end
    for _ = 1, rng(0, 3) do bump(src[rng(1, #src)], dst[rng(1, #dst)]) end

    for _, s in ipairs(src) do
      local sum = 0
      for _, x in pairs(w[s.id] or {}) do sum = sum + x end
      for _, t in ipairs(dst) do
        local x = w[s.id] and w[s.id][t.id]
        if x then
          local l = { from = s, to = t, value = s.value * x / sum }
          g.links[#g.links + 1] = l
          s.outs[#s.outs + 1] = l
          t.ins[#t.ins + 1] = l
          t.value = t.value + l.value
        end
      end
    end
  end
  return g
end

---------------------------------------------------------------------------
-- layout: system-owned x (fit to width), player-owned y
--   scale : "fit" = the busiest column (flow + padding) exactly fills the viewport
--           (d3-sankey rule), then multiplied by the player's zoom (D14 slider)
--   order : barycenter sweeps to reduce ribbon crossings (default order for D11)
--   columns shorter than the tallest are vertically centred
---------------------------------------------------------------------------
-- spread nodes over the full height H (d3 "justify"); a single node is centred
local function place_col(col, H)
  local flowH = 0
  for _, n in ipairs(col) do flowH = flowH + n.h end
  local gap, y = 0, PAD_TOP
  if #col > 1 then
    gap = math.max(NODE_PAD, (H - flowH) / (#col - 1))
  else
    y = PAD_TOP + (H - flowH) / 2
  end
  for _, n in ipairs(col) do
    n.y = y
    y = y + n.h + gap
  end
end

local function center(n) return n.y + n.h / 2 end

local function sweep(g, Hmax, forward)
  local ncol = #g.cols
  local first, last, step = 2, ncol, 1
  if not forward then first, last, step = ncol - 1, 1, -1 end
  for c = first, last, step do
    local col = g.cols[c]
    for _, n in ipairs(col) do
      local links = forward and n.ins or n.outs
      local sw, sy = 0, 0
      for _, l in ipairs(links) do
        local other = forward and l.from or l.to
        sw = sw + l.value
        sy = sy + l.value * center(other)
      end
      n.bc = (sw > 0) and (sy / sw) or center(n)
    end
    table.sort(col, function(a, b)
      if a.bc ~= b.bc then return a.bc < b.bc end
      return a.id < b.id
    end)
    place_col(col, Hmax)
  end
end

local function layout(g, W, viewH, st)
  local ncol = #g.cols
  local span = W - 2 * PAD_X - NODE_W
  local usable = viewH - PAD_TOP - PAD_BOTTOM

  local fit = math.huge
  for _, col in ipairs(g.cols) do
    local sum = 0
    for _, n in ipairs(col) do sum = sum + n.value end
    local k = math.min(usable * FILL, usable - (#col - 1) * NODE_PAD) / sum
    if k < fit then fit = k end
  end
  if fit <= 0 or fit == math.huge then fit = 0.05 end
  local scale = fit * st.zoom

  local Hmax = usable
  for c, col in ipairs(g.cols) do
    local x = PAD_X + round(span * (c - 1) / (ncol - 1))
    local colH = -NODE_PAD
    for _, n in ipairs(col) do
      n.x, n.h = x, math.max(MIN_T, n.value * scale)
      colH = colH + n.h + NODE_PAD
    end
    if colH > Hmax then Hmax = colH end
  end
  for _, col in ipairs(g.cols) do place_col(col, Hmax) end
  if st.order then
    for _ = 1, 4 do
      sweep(g, Hmax, true)
      sweep(g, Hmax, false)
    end
  end

  local clamped = 0
  for _, n in ipairs(g.nodes) do
    table.sort(n.outs, function(a, b) return a.to.y < b.to.y end)
    table.sort(n.ins, function(a, b) return a.from.y < b.from.y end)
  end
  for _, l in ipairs(g.links) do
    l.t = l.value * scale
    if l.t < MIN_T then l.t = MIN_T; clamped = clamped + 1 end
  end
  for _, n in ipairs(g.nodes) do
    local off = 0
    for _, l in ipairs(n.outs) do l.y1 = n.y + off; off = off + l.t end
    off = 0
    for _, l in ipairs(n.ins) do l.y2 = n.y + off; off = off + l.t end
  end
  return round(PAD_TOP + Hmax + PAD_BOTTOM), scale, clamped
end

---------------------------------------------------------------------------
-- placement strategies
---------------------------------------------------------------------------
local function margin_placer()
  -- Each child consumes zero net height in the vertical flow:
  -- top_margin = y, bottom_margin = -(y + h). So every child is positioned absolutely.
  return function(e, x, y, w, h)
    x, y, w, h = round(x), round(y), math.max(1, round(w)), math.max(1, round(h))
    local s = e.style
    s.width, s.height = w, h
    s.left_margin, s.right_margin = x, 0
    s.top_margin, s.bottom_margin = y, -(y + h)
  end
end

local function screen_placer(origin, px_scale)
  return function(e, x, y, w, h)
    e.style.width, e.style.height = math.max(1, round(w)), math.max(1, round(h))
    e.location = { origin.x + round(x * px_scale), origin.y + round(y * px_scale) }
  end
end

local function add_sprite(parent, sprite, tooltip)
  local e = parent.add { type = "sprite", sprite = sprite, tooltip = tooltip, resize_to_sprite = false }
  e.style.stretch_image_to_widget_size = true
  return e
end

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------
local function draw(parent, place, g, st, track)
  local count = 0
  -- ribbons first (nodes drawn on top)
  for _, l in ipairs(g.links) do
    local x1, x2 = l.from.x + NODE_W, l.to.x
    local d = l.y2 - l.y1
    local dir, top, H
    if d >= 0 then dir, top, H = "d", l.y1, d + l.t else dir, top, H = "u", l.y2, -d + l.t end
    local k = S.shape_index(l.t / H)
    local tip = string.format("[item=%s] → [item=%s]  %.1f/s", l.from.item, l.to.item, l.value)
    local e = add_sprite(parent, S.name(dir, k, l.from.color), tip)
    place(e, x1, top, x2 - x1, H)
    st.ribbons[#st.ribbons + 1] = { elem = e, dir = dir, k = k, color = l.from.color,
                                    from = l.from.id, to = l.to.id }
    if track then track[#track + 1] = e end
    count = count + 1
  end
  for _, n in ipairs(g.nodes) do
    local tip = string.format("[item=%s] %s  %.1f/s", n.item, n.item, n.value)
    local bar = add_sprite(parent, S.bar(n.color), tip)
    place(bar, n.x, n.y, NODE_W, n.h)
    local btn = parent.add { type = "sprite-button", sprite = "item/" .. n.item, tooltip = tip,
                             style = "slot_button", raise_hover_events = true, tags = { ssk_node = n.id } }
    place(btn, n.x + NODE_W / 2 - ICON / 2, n.y - ICON - 6, ICON, ICON)
    local lbl = parent.add { type = "label", caption = string.format("%.1f/s", n.value), ignored_by_interaction = true }
    lbl.style.font = "default-small"
    local lx = n.x + NODE_W / 2 + ICON / 2 + 4
    if n.col == #g.cols then lx = n.x + NODE_W / 2 - ICON / 2 - 64 end
    place(lbl, lx, n.y - ICON / 2 - 14, 60, 18)
    if n.col == #g.cols then lbl.style.horizontal_align = "right" end
    if track then track[#track + 1] = bar; track[#track + 1] = btn; track[#track + 1] = lbl end
    count = count + 3
  end
  return count
end

local function close(player)
  local st = pstate(player.index)
  local f = player.gui.screen[FRAME]
  if f and f.valid then f.destroy() end
  for _, e in ipairs(st.screen) do if e.valid then e.destroy() end end
  st.screen, st.ribbons = {}, {}
end

local function open(player)
  close(player)
  local st = pstate(player.index)
  local res, sc = player.display_resolution, player.display_scale
  local W = math.floor(res.width / sc) - 70
  local viewH = math.floor(res.height / sc) - 190

  local frame = player.gui.screen.add { type = "frame", name = FRAME, direction = "vertical" }
  -- Same title bar as the main and help windows.
  local header = frame.add { type = "flow", direction = "horizontal" }
  header.drag_target = frame
  header.style.vertical_align = "center"
  header.add { type = "label", caption = "Production Flow render test (" .. st.mode .. " mode)", style = "frame_title",
               ignored_by_interaction = true }
  local drag = header.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  header.add { type = "sprite-button", style = "frame_action_button", sprite = "utility/close", tooltip = "Close",
               tags = { ssk_rt = "close" } }
  local bar = frame.add { type = "flow", direction = "horizontal" }
  bar.style.vertical_align = "center"
  bar.style.horizontal_spacing = 8
  bar.add { type = "button", caption = "Randomize", tags = { ssk_rt = "randomize" } }
  bar.add { type = "button", caption = "Switch to " .. (st.mode == "margin" and "screen" or "margin"),
            tags = { ssk_rt = "mode" } }
  bar.add { type = "button", caption = "Ordering: " .. (st.order and "on" or "off"), tags = { ssk_rt = "order" } }
  bar.add { type = "button", caption = "−", tooltip = "Zoom out", tags = { ssk_rt = "zoom_out" } }.style.width = 32
  bar.add { type = "button", caption = "Fit graph", tooltip = "Fit the busiest column to the window", tags = { ssk_rt = "zoom_fit" } }
  bar.add { type = "button", caption = "+", tooltip = "Zoom in", tags = { ssk_rt = "zoom_in" } }.style.width = 32
  local info = bar.add { type = "label" }

  local g = make_graph(st.seed)
  local content_h, scale, clamped = layout(g, W, viewH, st)
  local count

  if st.mode == "margin" then
    local sp = frame.add { type = "scroll-pane", horizontal_scroll_policy = "never",
                           vertical_scroll_policy = "auto-and-reserve-space" }
    sp.style.width = W + 16
    sp.style.height = viewH
    local canvas = sp.add { type = "flow", direction = "vertical" }
    canvas.style.vertical_spacing = 0
    canvas.style.width = W
    canvas.style.height = content_h
    count = draw(canvas, margin_placer(), g, st, nil)
    frame.auto_center = true
    player.opened = frame
  else
    local bg = frame.add { type = "empty-widget" }
    bg.style.width, bg.style.height = W, viewH
    frame.location = { x = round(20 * sc), y = round(20 * sc) }
    -- approximate content origin under the toolbar; alignment is not the point of this test
    local origin = { x = round(34 * sc), y = round(100 * sc) }
    count = draw(player.gui.screen, screen_placer(origin, sc), g, st, st.screen)
  end

  info.caption = string.format("seed %d · %d cols · %d nodes · %d ribbons · %d elements · %.2f px/unit · %d clamped · canvas %dx%d",
    st.seed, #g.cols, #g.nodes, #g.links, count, scale, clamped, W, content_h)
end

---------------------------------------------------------------------------
-- module API (events are dispatched from control.lua)
---------------------------------------------------------------------------
local T = {}
T.FRAME = FRAME

function T.open(player, mode)
  local st = pstate(player.index)
  if mode == "margin" or mode == "screen" then st.mode = mode end
  open(player)
end

function T.is_open(player) return player.gui.screen[FRAME] ~= nil end

function T.on_click(e)
  local tags = e.element.tags
  local action = tags and tags.ssk_rt
  if not action then return false end
  local player = game.get_player(e.player_index)
  local st = pstate(e.player_index)
  if action == "close" then
    close(player)
  elseif action == "randomize" then
    st.seed = st.seed + 1
    open(player)
  elseif action == "order" then
    st.order = not st.order
    open(player)
  elseif action == "zoom_in" or action == "zoom_out" or action == "zoom_fit" then
    if action == "zoom_fit" then st.zoom = 1
    elseif action == "zoom_in" then st.zoom = math.min(8, st.zoom * ZOOM_STEP)
    else st.zoom = math.max(0.25, st.zoom / ZOOM_STEP) end
    open(player)
  elseif action == "mode" then
    st.mode = (st.mode == "margin") and "screen" or "margin"
    open(player)
  end
  return true
end

local function set_highlight(player, node_id)
  for _, r in ipairs(pstate(player.index).ribbons) do
    if r.elem.valid then
      local c = r.color
      if node_id and r.from ~= node_id and r.to ~= node_id then c = palette.DIM end
      r.elem.sprite = S.name(r.dir, r.k, c)
    end
  end
end

function T.on_hover(e, entering)
  local tags = e.element.valid and e.element.tags
  if not (tags and tags.ssk_node) then return false end
  set_highlight(game.get_player(e.player_index), entering and tags.ssk_node or nil)
  return true
end

function T.on_closed(e)
  if e.element and e.element.valid and e.element.name == FRAME then
    close(game.get_player(e.player_index))
    return true
  end
  return false
end

function T.on_display_changed(player)
  if T.is_open(player) then open(player) end
end

return T
