local SK, V, G = TREQ("scripts.sankey_ui"), TREQ("scripts.view"), TREQ("scripts.ribbon_geometry")
local player = game.players[1]
local c = player.gui.screen.add { type = "flow", name = "ssk_readability_test", direction = "vertical" }
local function find(el, predicate)
  if predicate(el) then return el end
  for _, child in ipairs(el.children) do local hit = find(child, predicate); if hit then return hit end end
end
local us = { view = "overview", renderer = "poly", period = 600, canvas_w = 1200 }
SK.fill(player, c, us, 1200, 800, true)
assert(us.tier_mode == "depth" and SK.toolbar_height(us) < 120, "compact production-depth defaults")
assert(not c.ssk_bar.ssk_advanced.visible, "Advanced starts closed")
assert(not c.ssk_info.caption:find("crossing cost", 1, true) and c.ssk_info.tooltip:find("crossing cost", 1, true), "diagnostics hidden in compact mode")
local group = find(c, function(e) return e.tags.ssk_label and e.tags.ssk_label:sub(1, 6) == "group/" end)
assert(group and group.visible, "overview groups need visible names")
local expanded_us = { view = "overview", period = 600, overview_open = { components = true } }
SK.defaults(expanded_us)
local expanded_group = V.build(player, expanded_us, 1200, 800)
assert(expanded_group.nodes["item/iron-plate"] and expanded_group.nodes["group/@smelting"], "expanded group must expose its input while retaining unrelated grouped materials")
SK.on_click({ player_index = 1, element = { tags = { ssk_sk = "advanced" } } }, us)
SK.fill(player, c, us, 1200, 800, false)
assert(c.ssk_bar.ssk_advanced.visible and c.ssk_info.caption:find("crossing cost", 1, true), "Advanced reveals diagnostics")
for _, lines in ipairs({ "curves", "metro" }) do
  local cfg = { view = "detail", layout = "clean", lines = lines, renderer = "poly", period = 600, canvas_w = 1200 }
  SK.fill(player, c, cfg, 1200, 800, true)
  local L = V.build(player, cfg, 1200, 800)
  local st, paths = storage.sk_render[1], {}
  for _, path in ipairs(st.paths) do
    paths[path.from .. ">" .. path.to] = true
    for _, p in ipairs(path.pieces) do
      for _, n in pairs(L.nodes) do
        local dx = math.min(p.x + p.w, G.round(n.x) + L.label_w[n.ci]) - math.max(p.x, G.round(n.x))
        local dy = math.min(p.y + p.h, G.round(n.y)) - math.max(p.y, G.round(n.top))
        assert(dx < 0.6 or dy < 0.6, "ribbon enters reserved header band: " .. n.key)
      end
    end
  end
  local count = 0; for _ in pairs(paths) do count = count + 1 end
  assert(#st.ribbons == count, "polygon renderer must draw one mesh per complete link")
  for _, r in ipairs(st.ribbons) do assert(r.ro and r.ro.valid and #r.ro.a.vertices >= 4) end
end
-- Expansion keeps selection and reveals real ores beyond immediate ingredients.
local fx = { view = "focus", neighborhood = true, focus = "item/electronic-circuit", period = 600,
  renderer = "poly", canvas_w = 520, input_depth = 1, heights = "sqrt", lines = "curves" }
SK.defaults(fx)
local first = V.build(player, fx, 520, 600)
assert(first.nodes["item/iron-plate#input"] and not first.nodes["item/iron-ore#input2"])
SK.on_click({ player_index = 1, element = { tags = { ssk_sk = "inputs_more" } } }, fx)
local second = V.build(player, fx, 520, 600)
assert(second.nodes["item/iron-ore#input2"] and second.nodes[fx.focus], "expanded inputs must reveal ore and retain focus")
assert(second.center_ci == 3 and #second.cols == 4 and second.content_w > 520, "expanded chain needs readable scrollable columns")
SK.on_click({ player_index = 1, element = { tags = { ssk_sk = "inputs_more" } } }, fx)
SK.fill(player, c, fx, 520, 600, true)
local third = V.build(player, fx, 520, 600)
assert(third.nodes["item/copper-ore#input3"] and fx.focus == "item/electronic-circuit", "third step should reveal copper smelting")
SK.on_click({ player_index = 1, element = { tags = { ssk_sk = "inputs_less" } } }, fx)
assert(fx.input_depth == 2 and fx.focus == "item/electronic-circuit")
for _ = 1, 8 do SK.on_click({ player_index = 1, element = { tags = { ssk_sk = "inputs_more" } } }, fx) end
SK.fill(player, c, fx, 520, 600, false)
local expand = find(c, function(e) return e.tags.ssk_sk == "inputs_more" end)
assert(fx.input_depth == 6 and expand and not expand.enabled, "modded chain expansion is bounded")
local short = {view="focus", neighborhood=true, focus="item/iron-plate", period=600,
  input_depth=6, heights="sqrt", lines="curves"}
SK.defaults(short)
local compact = V.build(player, short, 520, 600)
assert(compact.nodes["item/iron-ore#input"], "short chain lost its ore")
assert(#compact.cols == 3 and compact.center_ci == 2 and compact.content_w == 520,
  "expanding past a raw input must not add empty columns or scroll the selection away")
-- A shared upstream recipe is expanded once, even when two branches visit it.
local N = TREQ("scripts.neighborhood")
local nodes, links = {}, {}
for _, name in ipairs({ "ore", "raw", "a", "b", "target" }) do
  nodes["item/" .. name] = { kind = "item", prod = 7, cons = 7 }
end
for _, edge in ipairs({ { "ore", "raw", 7 }, { "raw", "a", 2 }, { "raw", "b", 3 }, { "a", "target", 1 }, { "b", "target", 1 } }) do
  links[#links + 1] = { from = "item/" .. edge[1], to = "item/" .. edge[2], rate = edge[3] }
end
local _, expanded = N.build(nodes, links, { residuals = {} }, "item/target", 3)
assert(expanded["item/ore#input3>item/raw#input2"].rate == 7, "shared upstream input counted twice")
local cycle_nodes = { ["item/a"] = nodes["item/a"], ["item/b"] = nodes["item/b"] }
local cycle, cycle_links = N.build(cycle_nodes, {
  { from = "item/a", to = "item/b", rate = 1 }, { from = "item/b", to = "item/a", rate = 1 }
}, { residuals = {} }, "item/b", 3)
local cycle_count = 0; for _ in pairs(cycle) do cycle_count = cycle_count + 1 end
assert(cycle_count == 5 and cycle_links["item/a#input3>item/b#input2"], "cycle expansion must terminate at requested depth")
-- Primitive strips are joined with zero-area triangles, never diagonal fills.
local mesh = G.mesh({ { kind = "bar", x = 0, y = 0, w = 20, h = 5 }, { kind = "bar", x = 20, y = 0, w = 10, h = 5 } })
local area = 0
for i = 1, #mesh - 2 do
  local a, b, d = mesh[i], mesh[i + 1], mesh[i + 2]
  area = area + math.abs((b[1] - a[1]) * (d[2] - a[2]) - (b[2] - a[2]) * (d[1] - a[1])) / 2
end
assert(area == 150, "mesh connector paints outside the ribbon")
c.destroy(); TREQ("scripts.canvas").clear(player.index)
print("READABILITY TESTS OK: compact toolbar, group labels, protected headers, whole-link meshes and upstream ore expansion")
