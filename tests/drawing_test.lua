local G = TREQ("scripts.ribbon_geometry")
local View = TREQ("scripts.view")
local SK = TREQ("scripts.sankey_ui")
local Canvas = TREQ("scripts.canvas")
local Model = TREQ("scripts.model")
local Groups = TREQ("scripts.groups")
local player = game.players[1]
local function near(a, b) assert(math.abs(a - b) < 1e-6, tostring(a) .. " differs from " .. tostring(b)) end
local bx, by = G.bezier(0.25)
near(bx, 0.296875); near(by, 0.15625)
for _, t in ipairs({ 1, 6, 17.4, 120.7 }) do
  for _, d in ipairs({ -400, -0.3, 0, 0.3, 400 }) do
    local pieces = G.route({ t = t }, 28.3, 1400.8, 100.4, 100.4 + d)
    assert(#pieces > 0)
    for _, p in ipairs(pieces) do
      assert(p.w > 0 and p.h > 0 and p.x == math.floor(p.x) and p.y == math.floor(p.y), "pixel edges")
      if p.kind == "curve" then
        assert(p.w <= TREQ("shared.sprites").CURVE_MAX, "wide curve cap")
        near(p.ya, G.round(100.4)); near(p.yb, G.round(100.4 + d))
        near(p.ya + p.t0, G.round(100.4 + t))
        near(p.yb + p.t1, G.round(100.4 + d + t))
      end
    end
  end
end
local k, q = TREQ("shared.sprites").elbow_index(0.4)
local radius = 10 * (1 - q) / q
for _, dy in ipairs({ -150, 150 }) do
  local p = G.route({ t = 10, route = "late", curve_x0 = 80, cx0 = 80,
    ortho = { k = k, R = radius, xv = 125 } }, 28, 260, 200, 200 + dy)
  local corners = 0
  for _, piece in ipairs(p) do
    if piece.kind == "elbow" then
      corners = corners + 1
      for _, pt in ipairs(G.arc_points(piece, 16)) do
        assert(pt[1] >= piece.x - 1e-6 and pt[1] <= piece.x + piece.w + 1e-6)
        assert(pt[2] >= piece.y - 1e-6 and pt[2] <= piece.y + piece.h + 1e-6)
      end
    end
  end
  assert(corners == 2, "long routed link must retain both rounded corners")
end

-- Check real polygon vertices, not just a route signature shared by construction.
local painter = Canvas.begin(player, 300, 300)
local object = painter.curve(20, 116, 40, 104, 6, Canvas.col(1))
local v = object.a.vertices
near((v[9][1] - 512) * 32, 20 + 96 * bx)
near(v[9][2] * 32, 40 + 64 * by)
near((v[10][2] - v[9][2]) * 32, 6)
near((v[#v - 1][1] - 512) * 32, 116)
near(v[#v][2] * 32, 110)
Canvas.clear(player.index)

local function trace(st)
  local out = {}
  for _, path in ipairs(st.paths) do
    out[#out + 1] = path.from .. ">" .. path.to
    for _, p in ipairs(path.pieces) do
      out[#out + 1] = table.concat({ p.kind, p.corner or "", p.dir or "", p.k or 0,
        p.x, p.y, p.w, p.h, p.ya or 0, p.yb or 0, p.t0 or 0, p.t1 or 0 }, ",")
    end
  end
  return table.concat(out, "|")
end
local function configuration(view, layout, lines)
  return { view = view, layout = layout, lines = lines, focus = "item/electronic-circuit",
    focus_steps = 2, heights = "sqrt", period = 0, preset = "all", hidden = {}, collapsed = {} }
end
local c = player.gui.screen.add { type = "flow", name = "ssk_drawing_test", direction = "vertical" }
local thick_header_checked = false
local function headers(us, width)
  local layout = View.build(player, us, width, 900)
  local function find(el, name)
    if el.name == name then return el end
    for _, child in ipairs(el.children) do local hit = find(child, name); if hit then return hit end end
  end
  local canvas = assert(find(c, "ssk_canvas"))
  local checked = 0
  for i, wrapper in ipairs(canvas.children) do
    local icon = wrapper.children[1]
    if icon and icon.type == "sprite-button" and icon.tags.ssk_sk == "node" then
      local n = assert(layout.nodes[icon.tags.key])
      local pos = wrapper.style
      local label_wrapper = assert(canvas.children[i + 1])
      local label = assert(label_wrapper.children[1])
      assert(label.type == "label" and label.style.single_line, "name must stay on one line")
      assert(label.style.width == label_wrapper.style.width, "name must be clipped to its reserved width")
      assert(pos.top_margin + pos.height <= G.round(n.y) - View.ICON_GAP, "icon blocks its flow bar")
      assert(label_wrapper.style.top_margin + label_wrapper.style.height <= pos.top_margin, "name blocks icon")
      assert(label_wrapper.style.width <= math.min(260, layout.label_w[n.ci]) + 1, "long name spills into next column")
      for _, other in pairs(layout.nodes) do
        local function disjoint(x, y, w, h)
          return x + w <= G.round(other.x) or x >= G.round(other.x + View.NODE_W)
            or y + h <= G.round(other.y) or y >= G.round(other.y + other.h)
        end
        assert(disjoint(pos.left_margin, pos.top_margin, pos.width, pos.height), "icon overlaps another bar")
        local lp = label_wrapper.style
        assert(disjoint(lp.left_margin, lp.top_margin, lp.width, lp.height), "name overlaps another bar")
      end
      if n.h >= 2 * View.NODE_W then thick_header_checked = true end
      checked = checked + 1
    end
  end
  assert(checked > 0, "header fixture is empty")
end
for _, setting in ipairs({ { "detail", "clean" }, { "detail", "lanes" }, { "focus", "clean" }, { "overview", "clean" } }) do
  for _, lines in ipairs({ "curves", "metro" }) do
    local us = configuration(setting[1], setting[2], lines)
    us.renderer = "sprites"
    SK.fill(player, c, us, 1800, 900, true)
    headers(us, 1800)
    local id = us.view == "focus" and "1:focus" or 1
    local sprite = trace(storage.sk_render[id])
    assert(#sprite > 0)
    if us.view == "detail" then
      us.sel = "item/electronic-circuit"
      SK.fill(player, c, us, 1800, 900, false)
      local state = storage.sk_render[id]
      local distant = false
      for _, r in ipairs(state.ribbons) do
        if r.from == "item/copper-ore" then
          assert(tonumber(r.elem.sprite:match("c(%d+)$")) ~= TREQ("shared.palette").DIM, "distant upstream edge dimmed")
          distant = true
        end
      end
      assert(distant, "chain fixture missing distant ancestor")
      SK.on_hover({ player_index = 1, element = { valid = true, tags = { ssk_sk = "node", key = "item/plastic-bar" } } }, true)
      SK.on_hover({ player_index = 1, element = { valid = true, tags = { ssk_sk = "node", key = "item/plastic-bar" } } }, false)
      assert(state.selected == us.sel, "hover exit must retain selection")
    end
    us.renderer = "poly"
    SK.fill(player, c, us, 1800, 900, false)
    headers(us, 1800)
    local poly = trace(storage.sk_render[id])
    if poly ~= sprite then
      local at = 1
      while at <= math.min(#poly, #sprite) and poly:sub(at, at) == sprite:sub(at, at) do at = at + 1 end
      error("renderer route parity: " .. setting[1] .. "/" .. setting[2] .. "/" .. lines .. " stable=" .. tostring(us.keep_layout)
        .. "\nsprite: " .. sprite:sub(math.max(1, at - 60), at + 100) .. "\npoly: " .. poly:sub(math.max(1, at - 60), at + 100))
    end
  end
end
assert(thick_header_checked, "missing thick-bar header regression fixture")
for _, layout in ipairs({ "clean", "lanes" }) do
  local narrow = configuration("detail", layout, "metro")
  SK.fill(player, c, narrow, 1000, 900, true)
  headers(narrow, 1000)
end

-- Live fluctuations must preserve order/scale; increased heights must stay packed.
local original_build = Model.build
local factor = 1
Model.build = function(...)
  local m = original_build(...)
  for _, edge in ipairs(m.edges) do edge.rate = edge.rate * factor end
  for _, r in pairs(m.residuals) do r.prod = r.prod * factor; r.cons = r.cons * factor end
  return m
end
local us = configuration("detail", "clean", "metro")
SK.defaults(us)
local first = View.build(player, us, 1800, 900)
local ranks, xs, tops = {}, {}, {}
for key, rank in pairs(us.auto_rank) do ranks[key] = rank end
for key, n in pairs(first.nodes) do xs[key], tops[key] = n.x, n.top end
local scale = first.scale
for _, f in ipairs({ 0.97, 1.02, 1.5 }) do
  factor = f
  local next = View.build(player, us, 1800, 900)
  assert(us.keep_layout and next.scale == scale, "live scale stability")
  for _, col in ipairs(next.cols) do
    table.sort(col, function(a, b) return a.top < b.top end)
    for i = 2, #col do
      assert(ranks[col[i - 1].key] < ranks[col[i].key], "live update reordered nodes")
      assert(col[i].top >= col[i - 1].top + col[i - 1].slot + View.F_GAP - 1e-6, "live slot collision")
    end
  end
  for key, n in pairs(next.nodes) do assert(n.x >= xs[key], "live update contracted column spacing") end
end
us.reflow = 1
View.build(player, us, 1800, 900)
assert(not us.keep_layout, "Reflow must optimise again")
Model.build = original_build
local empty = configuration("detail", "lanes", "metro"); empty.preset = "all"; SK.defaults(empty)
Model.build = function(...) local m = original_build(...); m.edges, m.residuals = {}, {}; return m end
local empty_view = View.build(player, empty, 1000, 900)
assert(not next(empty_view.nodes) and empty_view.content_w > 0, "empty swimlanes must remain drawable")
Model.build = original_build

-- A player's mixed material group is split into separate item/fluid nodes.
local custom = Groups.create(1, "Mixed materials", "oil")
local state = Groups.state(1)
local old_item, old_fluid = state.assign["item/plastic-bar"], state.assign["fluid/petroleum-gas"]
Groups.assign(1, "item/plastic-bar", custom); Groups.assign(1, "fluid/petroleum-gas", custom)
us = configuration("detail", "clean", "metro"); us.collapsed[custom] = true; SK.defaults(us)
local mixed = View.build(player, us, 1800, 900)
assert(mixed.nodes["group/" .. custom].flow_kind == "item")
assert(mixed.nodes["group/" .. custom .. "#fluid"].flow_kind == "fluid", "mixed group must keep units separate")
for _, n in pairs(mixed.nodes) do
  if n.kind == "group" then
    for _, key in ipairs(n.members) do assert(key:match("^(%a+)/") == n.flow_kind, "mixed unit total") end
  end
end
state.assign["item/plastic-bar"], state.assign["fluid/petroleum-gas"] = old_item, old_fluid
state.custom[custom] = nil

-- The overview can be expanded without changing the player's assignments.
us = configuration("overview", "clean", "metro"); SK.defaults(us)
local overview = View.build(player, us, 1800, 900)
assert(overview.nodes["group/@oil"] and overview.nodes["group/@oil#fluid"], "overview splits oil items and fluids")
local raw, smelting = overview.nodes["item/iron-ore"], overview.nodes["group/@smelting"]
assert(raw and smelting and raw.tier < smelting.tier, "overview must keep raw inputs before production groups")
us.overview_open = { oil = true }
local expanded = View.build(player, us, 1800, 900)
assert(not expanded.nodes["group/@oil"] and expanded.nodes["item/plastic-bar"], "expanded group exposes members")
us.overview_open = {}; us.sel = "group/@oil#fluid"
SK.on_click({ player_index = 1, element = { tags = { ssk_sk = "hide" } } }, us)
local hidden = View.build(player, us, 1800, 900)
assert(not hidden.nodes["group/@oil"] and not hidden.nodes["group/@oil#fluid"], "hide aggregate after grouping")
us.tier_lo, us.tier_hi = 4, 5
SK.on_selection({ element = { tags = { ssk_sk = "view" }, selected_index = 2 } }, us)
assert(us.view == "detail" and not us.tier_lo and not us.tier_hi, "view switch must clear incompatible tier range")
c.destroy()
Canvas.clear(player.index)
print("DRAWING TESTS OK")
