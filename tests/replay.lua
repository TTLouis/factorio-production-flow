-- Offline replay of an export through the mod's own view + renderer.
-- run from the mod folder:
--   cd mod/production-flow
--   DATA=../../tests/data/rd_nauvis.lua lua5.2 ../../tests/replay.lua ../../tests/out/x.txt
--   (env: VIEW=focus FOCUS=item/<name> STEPS=1..3 HEIGHT=sqrt|linear LINES=metro|curves
--         LAYOUT=clean|lanes RENDER=poly JOG=1 for geometry checks)
us_overview_raw = os.getenv("RAWGROUP") == "1"
-- Replay a real-base export through the mod's own view + renderer.
-- usage: lua5.2 replay.lua <out.txt> [preset] [scope_all:0/1]
package.path = "./?.lua;" .. package.path
local R = dofile(os.getenv("DATA") or "replay_data.lua")
local OUT, PRESET = arg[1], arg[2] or "all"

-- mock GUI (same as mock2)
local Elem = {}
Elem.__index = function(t, k)
  for _, c in ipairs(rawget(t, "children")) do if c.name == k and c.valid then return c end end
end
local function new_elem(spec, parent)
  local e = { children = {}, style = {}, valid = true, tags = spec.tags or {}, name = spec.name, type = spec.type, parent = parent }
  for k, v in pairs(spec) do if e[k] == nil then e[k] = v end end
  setmetatable(e, Elem)
  e.add = function(sp) local c = new_elem(sp, e); table.insert(e.children, c); return c end
  e.clear = function() e.children = {} end
  e.scroll_to_element = function(target) assert(target.valid); e.last_scroll_target=target end
  e.destroy = function() e.valid = false end
  return e
end

storage = {}
settings = { global = {} }
helpers = { is_valid_sprite_path = function() return true end }
prototypes = { get_entity_filtered = function() return { lab = { lab_inputs = {
  "automation-science-pack","logistic-science-pack","military-science-pack","chemical-science-pack","production-science-pack",
  "utility-science-pack","space-science-pack","metallurgic-science-pack","electromagnetic-science-pack","agricultural-science-pack",
  "cryogenic-science-pack","promethium-science-pack" } } } end }
local player = { index = 1, surface = { index = 1, name = "nauvis" }, mod_settings = { ["ssk-min-ribbon-px"] = { value = 6 }, ["ssk-fluid-scale"] = { value = 0.001 } } }
game = { tick = 0, players = { player }, connected_players = { player } }

-- stubs for data modules
local graph = { nodes = {}, recipes = {} }
for k, e in pairs(R.era) do graph.nodes[k] = { era = e } end
for r, e in pairs(R.recipe_era) do graph.recipes[r] = { era = e } end
package.loaded["scripts.graph"] = { get = function() return graph end, key = function(t, n) return t .. "/" .. n end }
package.loaded["scripts.sampler"] = { PF_INCLUDES_BONUS = true }
local ginfo = {}
for k, g in pairs(R.groups) do
  ginfo[g[1]] = { id = g[1], name = g[2], super = g[3], super_name = g[4], color = g[5], order = g[6], super_order = g[7] }
end
package.loaded["scripts.groups"] = {
  of = function(pi, key) if key:sub(1, 7) == "recipe/" then return "recipes" end return R.groups[key] and R.groups[key][1] or "sub:other" end,
  info = function(pi, id) return ginfo[id] or { id = id, name = id, super = "other", super_name = "Other", color = 12, order = 900, super_order = 99 } end,
  list = function() return {} end, assign = function() end, unassign = function() end, create = function() return "x" end,
}
local Model = dofile("scripts/model.lua")
local used = {}
for r in pairs(R.recipe_era) do used[#used + 1] = r end
Model.build = function()
  local edges = {}
  for _, e in ipairs(R.edges) do edges[#edges + 1] = { from = e[1], to = e[2], rate = e[3], reversing = e[4] == 1 } end
  local res = {}
  for k, v in pairs(R.residuals) do res[k] = { prod = v[1], cons = v[2] } end
  return { edges = edges, residuals = res, seconds = R.seconds, used = used }
end
package.loaded["scripts.model"] = Model

-- mock LuaRendering (polygon renderer) -> dumped to <out>.poly
POLYS = {}
local function obj(t) t.valid = true; t.destroy = function() t.valid = false end; POLYS[#POLYS + 1] = t; return t end
rendering = {
  draw_rectangle = function(a) return obj({ k = "rect", a = a.left_top, b = a.right_bottom, c = a.color }) end,
  draw_polygon = function(a) return obj({ k = "poly", v = a.vertices, c = a.color }) end,
}
local surf = { index = 99, name = "ssk-canvas", request_to_generate_chunks = function() end, force_generate_chunk_requests = function() end, set_tiles = function() end }
player.force = { chart = function() end }
game.get_surface = function(n) return game._s end
game.create_surface = function() game._s = surf; return surf end
game.forces = {}
player.display_scale = 1
local SK = dofile("scripts/sankey_ui.lua")
local us = { preset = PRESET, all_surfaces = true, zoom = 1, live = true, tier_mode = os.getenv("MODE") or "tech",
             show_labels = os.getenv("LABELS") == "1", sel = os.getenv("SELECTED"),
             input_depth = tonumber(os.getenv("INPUT_DEPTH") or "1"),
             view = os.getenv("VIEW") or "detail", focus = os.getenv("FOCUS"), focus_steps = tonumber(os.getenv("STEPS") or "2"),
             neighborhood = os.getenv("NEIGHBORHOOD") == "1", canvas_w = tonumber(os.getenv("W") or "3296"),
             top_n = tonumber(os.getenv("TOPN") or "0"), heights = os.getenv("HEIGHT"), lines = os.getenv("LINES"), renderer = os.getenv("RENDER"), layout = os.getenv("LAYOUT") or "clean", heights = os.getenv("HEIGHT") or "sqrt", lines = os.getenv("LINES") or "metro" }
local root = new_elem({ type = "flow" })
local W, H = tonumber(os.getenv("W") or "3296"), tonumber(os.getenv("H") or "1060")
SK.fill(player, root, us, W, H, true)
local function find(el, name) if el.name == name then return el end for _, c in ipairs(el.children) do local r = find(c, name) if r then return r end end end
print("Replay canvas rendered")
local cv = find(root, "ssk_canvas")
local f = io.open(OUT, "w")
f:write(string.format("canvas %d %d 0\n", cv.style.width, cv.style.height))
local function caption_text(value)
  if type(value) == "string" then return value end
  if type(value) ~= "table" or value[1] ~= "" then return "" end
  local parts = {}
  for i = 2, #value do parts[#parts + 1] = caption_text(value[i]) end
  return table.concat(parts)
end
for _, e in ipairs(cv.children) do
  local s, c = e.style, e
  if e.type == "flow" and e.children[1] then c = e.children[1] end
  local cap = caption_text(c.caption)
  if c.type == "sprite-button" and type(c.tooltip) == "string" then
    cap = string.match(c.tooltip, "^%[[^%]]*%] (.-)  %[") or cap
  end
  if e.visible ~= false and c.visible ~= false then
    f:write(string.format("%s|%s|%d|%d|%d|%d|%s\n", c.type, c.sprite or "", s.left_margin, s.top_margin, s.width, s.height, cap))
  end
end
f:close()
local colors = require("shared.palette")
local cf = assert(io.open(OUT .. ".palette", "w"))
for i = 1, colors.count do
  local rgb, tint = colors.rgb(i), colors.tint(i)
  cf:write(string.format("%d,%d,%d,%.4f\n", rgb[1], rgb[2], rgb[3], tint.a))
end
cf:close()
local pf = io.open(OUT .. ".poly", "w")
for _, o in ipairs(POLYS) do
  if o.valid then
    local c = o.c
    local cs = string.format("%.3f,%.3f,%.3f,%.3f", c.r, c.g, c.b, c.a)
    if o.k == "rect" then pf:write(string.format("R|%s|%.4f,%.4f,%.4f,%.4f\n", cs, o.a[1], o.a[2], o.b[1], o.b[2]))
    else
      local pts = {}
      for _, v in ipairs(o.v) do pts[#pts + 1] = string.format("%.4f,%.4f", v[1], v[2]) end
      pf:write("P|" .. cs .. "|" .. table.concat(pts, ";") .. "\n")
    end
  end
end
pf:close()
-- Backend-independent route trace, used to compare real exports in fresh runtimes.
local gf = assert(io.open(OUT .. ".geometry", "w"))
local state = storage.sk_render[us.view == "focus" and "1:focus" or 1]
for _, path in ipairs(state and state.paths or {}) do
  gf:write("PATH|" .. path.from .. "|" .. path.to .. "\n")
  for _, p in ipairs(path.pieces) do
    gf:write(string.format("%s|%s|%s|%d|%d|%d|%d|%d|%.6f|%.6f|%.6f|%.6f\n",
      p.kind, p.corner or "", p.dir or "", p.k or 0, p.x, p.y, p.w, p.h,
      p.ya or 0, p.yb or 0, p.t0 or 0, p.t1 or 0))
  end
end
gf:close()

-- metrics
if os.getenv("JOG") then
  local View = package.loaded["scripts.view"] or dofile("scripts/view.lua")
local L = View.build(player, us, W, H)
local jogs, vt, vsum = 0, 0, 0
for _, sg in ipairs(L.segments or {}) do
  local d = math.abs((sg.y1 or 0) - (sg.y2 or 0))
  if d > 2 then jogs = jogs + 1 end
  vt = vt + d * sg.t; vsum = vsum + d
end
local bad = 0
for _, sg in ipairs(L.segments or {}) do
  local a, b = sg.a, sg.b
  if a.kind ~= "via" and (sg.y1 < a.y - 0.5 or sg.y1 + sg.t > a.y + a.h + 0.5) then bad = bad + 1 end
  if b.kind ~= "via" and (sg.y2 < b.y - 0.5 or sg.y2 + sg.t > b.y + b.h + 0.5) then bad = bad + 1 end
end
print("MISALIGNED ports", bad)
print(string.format("JOGS %d of %d segments, vertical travel %.0f px (thickness-weighted %.0f), height %d, width %d",
  jogs, #(L.segments or {}), vsum, vt, L.content_h, L.content_w or 0))

end
local View = package.loaded["scripts.view"] or dofile("scripts/view.lua")
local L = View.build(player, us, W, H)
local Geometry = require("scripts.ribbon_geometry")
local header_overlaps, header_count = 0, 0
for i, wrapper in ipairs(cv.children) do
  local icon = wrapper.children[1]
  if icon and icon.type == "sprite-button" and icon.tags.ssk_sk == "node" then
    header_count = header_count + 1
    for _, box in ipairs({ wrapper, cv.children[i + 1] }) do
      local p = box.style
      for _, node in pairs(L.nodes) do
        local dx = math.min(p.left_margin + p.width, Geometry.round(node.x + View.NODE_W))
          - math.max(p.left_margin, Geometry.round(node.x))
        local dy = math.min(p.top_margin + p.height, Geometry.round(node.y + node.h))
          - math.max(p.top_margin, Geometry.round(node.y))
        if dx > 0 and dy > 0 then header_overlaps = header_overlaps + 1 end
      end
    end
  end
end
assert(header_count > 0)
print("HEADER overlaps", header_overlaps)
if us.layout == "clean" and not us.neighborhood then
  local overlaps = 0
  for _, path in ipairs(state.paths) do
    for _, piece in ipairs(path.pieces) do
      for _, node in pairs(L.nodes) do
        local dx = math.min(piece.x + piece.w, Geometry.round(node.x) + L.label_w[node.ci]) - math.max(piece.x, Geometry.round(node.x))
        local dy = math.min(piece.y + piece.h, Geometry.round(node.y)) - math.max(piece.y, Geometry.round(node.top))
        if dx > 0.6 and dy > 0.6 then overlaps = overlaps + 1 end
      end
    end
  end
  print("ROUTE HEADER overlaps", overlaps)
end
local ov = 0
local ls = L.lane_list
for i = 1, #ls do for j = i + 1, #ls do
  local a, b = ls[i], ls[j]
  local x = math.min(a.px1 or 0, b.px1 or 0) - math.max(a.px0 or 0, b.px0 or 0)
  local y = math.min(a.y1, b.y1) - math.max(a.y0, b.y0)
  if x > 0 and y > 0 then ov = ov + x * y end
end end
local vlen = 0
for _, l in ipairs(L.links) do if l.a.lane ~= l.b.lane then vlen = vlen + l.t * math.abs((l.y1 or 0) - (l.y2 or 0)) end end
local raw = 0
for _, ln in ipairs(ls) do if ln.id == "raw" or ln.id == "other" then raw = raw + 1 end end
print(string.format("METRICS lanes=%d overlap_px2=%.0f crosslane_vlen=%.0f crossing=%.0f height=%d raw/other lanes=%d",
  #ls, ov, vlen, L.crossing_cost or 0, L.content_h, raw))
for _, ln in ipairs(ls) do io.write(ln.id, " ") end print()
for _, ln in ipairs(ls) do if ln.id == "raw" or ln.id == "other" then
  for _, sb in ipairs(ln.sub_list) do for ci, list in pairs(sb.cols) do for _, n in ipairs(list) do
    print("  ", ln.id, sb.id, n.key, n.kind, "ins", #n.ins, "outs", #n.outs, n.base or "")
  end end end
end end
