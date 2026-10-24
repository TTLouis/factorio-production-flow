local player = game.players[1]
local UI = TREQ("scripts.ui")
storage.ui[1].tab_id = "sankey"; storage.ui[1].period = 0; storage.ui[1].view = "detail";
UI.open(player)
local function find(el, pred, out)
  out = out or {}
  if pred(el) then out[#out+1] = el end
  for _, c in ipairs(el.children or {}) do find(c, pred, out) end
  return out
end
local function canvas() return find(player.gui.screen, function(e) return e.name == "ssk_canvas" end)[1] end
local function info() return find(player.gui.screen, function(e) return e.name == "ssk_info" end)[1].caption end
local function dumpc(path)
  local cv = canvas(); local f = io.open(path, "w")
  f:write(string.format("canvas %d %d 0\n", cv.style.width, cv.style.height))
  for _, e in ipairs(cv.children) do local s = e.style
    local c = e
    if e.type == "flow" and e.children[1] then c = e.children[1] end
    f:write(string.format("%s|%s|%d|%d|%d|%d|%s\n", c.type, c.sprite or "", s.left_margin, s.top_margin, s.width, s.height, type(c.caption)=="string" and c.caption or "")) end
  f:close()
end
print("SANKEY:", info())
dumpc(TESTDIR .. "/out/sk_all.txt")
local function click(tags, shift) handlers_click({ element = { valid = true, name = "x", tags = tags, parent = find(player.gui.screen, function(e) return e.name == "ssk_newgroup" end)[1] and find(player.gui.screen, function(e) return e.name == "ssk_newgroup" end)[1].parent }, player_index = 1, shift = shift }) end
local function sel(tag, idx) UI.on_selection({ element = { valid = true, tags = { ssk_sk = tag }, selected_index = idx }, player_index = 1 }) end
handlers_click = function(e) assert(UI.on_click(e), "click not handled " .. tostring(e.element.tags.ssk_sk)) end
-- select a node, move it, hide it, collapse its group, new group
click({ ssk_sk = "node", key = "item/iron-gear-wheel" })
assert(storage.ui[1].sel == "item/iron-gear-wheel")
click({ ssk_sk = "up" }); click({ ssk_sk = "down" }, true)
click({ ssk_sk = "collapse", gid = "mechanical" }); print("after collapse:", info())
click({ ssk_sk = "expand", gid = "mechanical" })
click({ ssk_sk = "node", key = "item/copper-cable" })
local tf = find(player.gui.screen, function(e) return e.name == "ssk_newgroup" end)[1]; tf.text = "My wires"
click({ ssk_sk = "new_group" }); print("group of cable:", TREQ("scripts.groups").of(1, "item/copper-cable"))
sel("move_group", 3)
click({ ssk_sk = "hide" }); print("after hide:", info())
click({ ssk_sk = "unhide_all" })
click({ ssk_sk = "zoom_in" }); click({ ssk_sk = "zoom_fit" })
-- presets
for i, id in ipairs(storage.ui[1].preset_ids) do sel("preset", i); print("preset", id, info():match("^%[color=[^%]]+%](.-) ·")) end
sel("preset", 2); dumpc(TESTDIR .. "/out/sk_sci.txt")
sel("preset", 1); sel("tier_lo", 2); sel("tier_hi", 3); print("tier range:", info())
sel("tier_lo", 1); sel("tier_hi", 99)
sel("tier_mode", 2); print("depth mode:", info()); dumpc(TESTDIR .. "/out/sk_depth.txt")
sel("tier_mode", 1); print("tech mode:", info())
for _, c in ipairs({ "up", "up", "up", "down", "down" }) do click({ ssk_sk = "node", key = "item/iron-gear-wheel" }); click({ ssk_sk = c }) end
print("pos/gpos/lpos sizes", #(storage.ui[1].last_lanes or {}))
sel("tier_lo", 1); sel("tier_hi", 99)
UI.on_selection({ element = { valid = true, tags = { ssk_ui = "surface" }, selected_index = 1 }, player_index = 1 })
UI.on_hover({ element = { valid = true, tags = { ssk_sk = "node", key = "item/iron-plate" } }, player_index = 1 }, true)
UI.on_hover({ element = { valid = true, tags = { ssk_sk = "node", key = "item/iron-plate" } }, player_index = 1 }, false)
UI.on_checked({ element = { valid = true, tags = { ssk_sk = "live" }, state = false }, player_index = 1 })
UI.auto_refresh()
click({ ssk_sk = "reset_layout" })
sel("preset", 1); dumpc(TESTDIR .. "/out/sk_all.txt")
UI.on_checked({ element = { valid = true, tags = { ssk_sk = "split_raw" }, state = false }, player_index = 1 }); print("unsplit:", info())
dumpc(TESTDIR .. "/out/sk_unsplit.txt")
UI.on_checked({ element = { valid = true, tags = { ssk_sk = "split_raw" }, state = true }, player_index = 1 }); print("split:", info())
click({ ssk_sk = "node", key = "item/iron-ore" }); click({ ssk_sk = "hide" }); print("hide ore:", info()); click({ ssk_sk = "unhide_all" })
dumpc(TESTDIR .. "/out/sk_split.txt")
print("SK TESTS OK")
