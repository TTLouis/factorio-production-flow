local UI, SK, View = TREQ("scripts.ui"), TREQ("scripts.sankey_ui"), TREQ("scripts.view")
local Model = TREQ("scripts.model")
local player, us = game.players[1], storage.ui[1]
local resolution, scale = player.display_resolution, player.display_scale
us.tab_id, us.bal_filter, us.bal_details = "balance", "all", false
for _, size in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 } }) do
  for _, gui_scale in ipairs({ 1, 1.25, 1.5 }) do
    player.display_resolution, player.display_scale = { width = size[1], height = size[2] }, gui_scale
    UI.open(player)
    local frame = player.gui.screen.ssk_main
    assert(frame.style.width <= size[1] / gui_scale - 40 and frame.style.height <= size[2] / gui_scale - 64, "window must fit screen at GUI scale")
    assert(math.abs(frame.style.width / frame.style.height - 16 / 9) < 0.01, "16:9 window")
    local split = frame.ssk_inner.ssk_tabs.content_balance.ssk_balance_split
    assert(split.ssk_balance_table.ssk_bal_root.ssk_bal_list.ssk_bal_items.type == "scroll-pane", "items need independent scrolling")
    assert(split.ssk_balance_table.style.width + split.ssk_balance_focus.style.width + 12 == us.canvas_w, "panes exceed content width")
    local table_root = split.ssk_balance_table.ssk_bal_root
    assert(table_root.ssk_bal_list.ssk_bal_items.horizontal_scroll_policy=="never", "item list must not scroll sideways")
    local t=table_root.ssk_bal_list.ssk_bal_items.ssk_bal_section_1.ssk_bal_table
    local used=(t.column_count-1)*t.style.horizontal_spacing+t.column_count*((t.style.left_cell_padding or 0)+(t.style.right_cell_padding or 0))
    for i=1,t.column_count do used=used+t.children[i].style.width end
    assert(used==us.bal_width+4, "rows must fit within the list frame padding and reserved scrollbar")
    UI.on_click({ player_index = 1, element = { name = "x", tags = { ssk_ui = "focus_item", key = "item/electronic-circuit" } } })
    assert(us.tab_id == "balance" and table_root == split.ssk_balance_table.ssk_bal_root, "selection must preserve table and tab")
    for _, focus in ipairs({ "item/electronic-circuit", "item/iron-ore", "fluid/water", "fluid/petroleum-gas", "item/idle-test" }) do
      local fx = SK.balance_state(us)
      fx.focus, fx.sel = focus, focus
      local layout = View.build(player, fx, us.bal_chart_w, us.canvas_h)
      local center = assert(layout.nodes[focus], "selected item must exist even without measured edges")
      assert(#layout.cols == 3 and center.ci == 2, "selected item must keep the middle column")
      assert(math.abs(center.x + View.NODE_W / 2 - us.bal_chart_w / 2) <= 0.5, "selected item must be horizontally centered")
      assert(layout.content_w == us.bal_chart_w, "inspector must fit right pane")
      for _, link in ipairs(layout.links) do
        assert(link.a.ci == 1 and link.b == center or link.a == center and link.b.ci == 3, "inspector includes a non-neighbour edge")
        assert(link.a.x + View.NODE_W < link.b.x, "narrow inspector loses ribbon space")
      end
      if focus == "fluid/petroleum-gas" then
        assert(layout.nodes["fluid/crude-oil#input"] and layout.nodes["fluid/water#input"], "multi-output producer must show materials")
      end
    end
  end
end
-- A reversible production cycle can put the same material on both sides.
local original_build = Model.build
Model.build = function() return { seconds = 60, residuals = {}, edges = {
  { from = "item/test-a", to = "recipe/test-left", rate = 1 },
  { from = "recipe/test-left", to = "item/test-b", rate = 1 },
  { from = "item/test-b", to = "recipe/test-right", rate = 1 },
  { from = "recipe/test-right", to = "item/test-a", rate = 1 },
} } end
local fx = SK.balance_state(us); fx.focus = "item/test-b"
local cyclic = View.build(player, fx, 700, 600)
assert(cyclic.nodes["item/test-a#input"].ci == 1 and cyclic.nodes["item/test-a#use"].ci == 3, "cycle must keep input and use copies separate")
Model.build = original_build
player.display_resolution, player.display_scale = resolution, scale
us.bal_fx.focus = "item/electronic-circuit"
UI.open(player)
-- The paused inspector stays paused while Balance values continue refreshing.
local function find(el, name)
  if el.name == name then return el end
  for _, child in ipairs(el.children) do local hit = find(child, name); if hit then return hit end end
end
UI.on_checked({ player_index = 1, element = { tags = { ssk_sk = "live" }, state = false } })
local canvas = find(player.gui.screen.ssk_main, "ssk_canvas")
local first_child = canvas.children[1]
UI.refresh(player, true)
assert(canvas.children[1] == first_child, "paused inspector must not redraw")
UI.on_checked({ player_index = 1, element = { tags = { ssk_sk = "live" }, state = true } })
print("SPLIT VIEW TESTS OK: 16:9 screens, GUI scales, selection, centered neighbours, shared materials, live pause")
