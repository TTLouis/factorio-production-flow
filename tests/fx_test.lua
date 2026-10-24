-- Focus tab: pick, steps, renderers, re-centre, back, Balance link
local UI = TREQ("scripts.ui")
local player = game.players[1]
local RO = dofile(TESTDIR .. "/render_mock.lua")
local us = storage.ui[1]
us.tab_id = "focus"; UI.open(player)
local fx = us.fx
assert(fx and fx.view == "focus", "focus state")
UI.on_elem_changed({ element = { valid = true, tags = { ssk_sk = "f_item" }, elem_value = "electronic-circuit" }, player_index = 1 })
assert(fx.focus == "item/electronic-circuit", "picked")
local function find(el, name) if el.name == name then return el end for _, c in ipairs(el.children) do local r = find(c, name) if r then return r end end end
local function info() local L=TREQ("scripts.view").build(player,fx,1000,600);return string.format("%d flows · %.0f s recorded",#L.links,L.seconds) end
print("focus 2:", info())
for i = 1, 3 do
  UI.on_selection({ element = { valid = true, tags = { ssk_sk = "f_steps" }, selected_index = i }, player_index = 1 })
  print("steps", i, info():match("%](.-) ·"))
end
fx.renderer="poly";UI.refresh(player)
local live = 0
for _, o in ipairs(RO) do if o.valid then live = live + 1 end end
print("poly objects:", live)
assert(live > 10, "polygon renderer drew nothing")
-- A picker can select a material outside the recorded recipe graph. It must
-- not turn Focus into an unfiltered factory chart or retain old polygons.
local View = TREQ("scripts.view")
for _, pick in ipairs({ {"f_item", "wood"}, {"f_fluid", "unrecorded-fluid"} }) do
  UI.on_elem_changed({ element = { valid = true, tags = { ssk_sk = pick[1] }, elem_value = pick[2] }, player_index = 1 })
  local L = View.build(player, fx, 1000, 600)
  assert(not next(L.nodes) and #L.links == 0, "unrecorded focus leaked unrelated factory flows")
  local canvas = find(player.gui.screen.ssk_main, "ssk_canvas")
  assert(#canvas.children == 1 and type(canvas.children[1].caption) == "table"
    and canvas.children[1].caption[2]:find("No recorded recipe flow", 1, true), "missing focus empty-state message")
  for _, o in ipairs(RO) do assert(not o.valid, "empty focus retained old polygons") end
  UI.refresh(player, true)
  assert(not next(View.build(player, fx, 1000, 600).nodes), "live refresh restored unrelated flows")
  UI.on_click({ element = { valid = true, name = "x", tags = { ssk_sk = "f_back" } }, player_index = 1 })
  assert(fx.focus == "item/electronic-circuit", "back from unrecorded material")
  assert(View.build(player, fx, 1000, 600).nodes[fx.focus], "back failed to restore focused chart")
end
UI.on_hover({ element = { valid = true, tags = { ssk_sk = "node", key = "item/electronic-circuit", fx = true } }, player_index = 1 }, true)
UI.on_hover({ element = { valid = true, tags = { ssk_sk = "node", key = "item/electronic-circuit", fx = true } }, player_index = 1 }, false)
fx.renderer="sprites";UI.refresh(player)
live = 0
for _, o in ipairs(RO) do if o.valid then live = live + 1 end end
assert(live == 0, "sprite renderer should clear polygons, left " .. live)
UI.on_click({ element = { valid = true, name = "x", tags = { ssk_sk = "node", key = "item/copper-cable", fx = true } }, player_index = 1 })
assert(fx.focus == "item/copper-cable", "re-centre")
UI.on_click({ element = { valid = true, name = "x", tags = { ssk_sk = "f_back" } }, player_index = 1 })
assert(fx.focus == "item/electronic-circuit", "back")
for _, L in ipairs({ 1, 2 }) do
  UI.on_selection({ element = { valid = true, tags = { ssk_sk = "f_lines" }, selected_index = L }, player_index = 1 })
  UI.on_selection({ element = { valid = true, tags = { ssk_sk = "f_heights" }, selected_index = L }, player_index = 1 })
end
us.tab_id = "balance"; UI.refresh(player)
UI.on_click({ element = { valid = true, name = "x", tags = { ssk_ui = "focus_item", key = "item/iron-gear-wheel" } }, player_index = 1 })
assert(us.tab_id == "balance" and us.bal_fx.focus == "item/iron-gear-wheel", "balance must inspect alongside its table")
print("FOCUS TESTS OK")
