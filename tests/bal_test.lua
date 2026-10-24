
local B = TREQ("scripts.balance")
local rows = B.rows(nil)
for _, r in ipairs(rows) do
  print(string.format("BAL %-10s %-34s prod %7.3f cons %7.3f net %+.0f%% pu %s cu %s stock %s trend %s eta %s",
    r.status, r.key, r.prod, r.cons, r.netp * 100, r.pu and string.format("%.2f", r.pu) or "-", r.cu and string.format("%.2f", r.cu) or "-",
    tostring(r.stock), r.trend and string.format("%.0f", r.trend) or "-", r.eta and string.format("%.0f", r.eta) or "-"))
end
local UI = TREQ("scripts.ui")
storage.ui[1].tab_id = "balance"; storage.ui[1].bal_filter = "all"; UI.refresh(game.players[1])
UI.on_selection({ element = { valid = true, tags = { ssk_ui = "bal_filter" }, selected_index = 1 }, player_index = 1 })
local BU = TREQ("scripts.balance_ui")
local player, us = game.players[1], storage.ui[1]
local function content() return player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_balance end
local function root() return content().ssk_balance_split.ssk_balance_table.ssk_bal_root end
local function find(el, pred, out)
  out = out or {}
  if pred(el) then out[#out + 1] = el end
  for _, child in ipairs(el.children) do find(child, pred, out) end
  return out
end
local function select(action, index)
  assert(UI.on_selection({ player_index = 1, element = { tags = { ssk_ui = action }, selected_index = index } }))
end
local function tables() return find(root(), function(e) return e.name == "ssk_bal_table" end) end
local function links() return find(root(), function(e) return e.tags.ssk_ui == "focus_item" end) end
assert(tables()[1].column_count == 8, "compact summary should have 8 columns including focus")
local original = root()
local item_pane = original.ssk_bal_items
assert(content().ssk_balance_split.ssk_balance_table.type == "flow", "outer Balance pane must stay fixed")
assert(item_pane.type == "scroll-pane", "only the item list should scroll")
assert(original.ssk_bal_summary and original.ssk_bal_context and original.ssk_bal_count, "summary and footer must remain outside the item scroller")
assert(item_pane.ssk_bal_section_1, "item tables must live inside the scroller")
UI.refresh(player, true)
assert(root() == original and root().ssk_bal_items == item_pane, "unchanged live refresh must preserve the item scroller")
select("bal_filter", 3)
for _, e in ipairs(links()) do
  local status
  for _, r in ipairs(B.rows(1, us.period)) do if r.key == e.tags.key then status = r.status end end
  assert(status == "deficit" or status == "limited" or status == "starved", "shortage filter leaked another status")
end
assert(#links() > 0, "shortages should be visible")
select("bal_filter", 4)
for _, e in ipairs(links()) do
  local status
  for _, r in ipairs(B.rows(1, us.period)) do if r.key == e.tags.key then status = r.status end end
  assert(status == "surplus", "surplus filter leaked another status")
end
select("bal_filter", 2)
select("bal_sort", 2)
assert(#tables() > 1, "group ordering should show separate group sections")
local grouped = root()
UI.refresh(player, true)
assert(root() == grouped, "grouped live update should reuse every section")
assert(UI.on_checked({ player_index = 1, element = { tags = { ssk_ui = "bal_details" }, state = true } }))
for _, t in ipairs(tables()) do assert(t.column_count == 8, "details must stack without adding width")
  assert(t.children[12].caption:find("\n"), "producer utilisation should appear beneath production") end
local group_index
for i, id in pairs(us.bal_group_ids) do if id == "plates" then group_index = i end end
assert(group_index, "active curated group missing")
select("bal_group", group_index)
for _, e in ipairs(links()) do assert(TREQ("scripts.groups").of(1, e.tags.key) == "plates", "group filter leaked an item") end
assert(#links() > 0)
select("bal_group", 1)

-- Deterministic fixture verifies pagination, real caption updates, zero stock,
-- missing stock, localisation, and status-driven table invalidation.
local saved_rows = B.rows
local fixture = {}
for i = 1, 205 do
  fixture[i] = { key = "item/test-" .. i, prod = 2, cons = 1, net = 1, netp = 0.5,
    status = "surplus", stock = i == 1 and 0 or nil }
end
local old_proto = rawget(prototypes.item, "test-1")
prototypes.item["test-1"] = { name = "test-1", subgroup = { name = "x" }, localised_name = { "item-name.test-1" } }
B.rows = function() return fixture, 60 end
us.bal_group, us.bal_sort, us.bal_details, us.bal_limit = nil, "priority", false, nil
UI.refresh(player)
assert(#links() == 200 and root().ssk_bal_count.caption == "Showing 200 of 205 matching items", "truncation must be visible")
UI.on_click({ player_index = 1, element = { name = "x", tags = { ssk_ui = "bal_more" } } })
assert(#links() == 205, "show more must expose all remaining rows")
local t = tables()[1]
assert(t.children[15].caption == "0.000", "known zero stock must not become missing stock")
assert(t.children[23].caption == "—", "missing stock must stay unavailable")
assert(t.children[10].caption[4] == prototypes.item["test-1"].localised_name, "use prototype display name")
local reuse = root()
fixture[1].prod = 3
UI.refresh(player, true)
assert(root() == reuse and t.children[12].caption == "3.00", "live numbers must update in place")
fixture[1].status = "deficit"
UI.refresh(player, true)
assert(root()==reuse and t.children[11].caption:find("Deficit"), "live status changes must update cells without destroying controls")
local original_first=t.children[9]
table.remove(fixture,1)
UI.refresh(player,true)
assert(root()==reuse and t.children[9]==original_first and t.children[11].caption:find("Inactive"), "expired rows must not interrupt selection")
UI.refresh(player)
assert(root()~=reuse, "manual Refresh must reapply list membership")
fixture = {}
UI.refresh(player)
assert(root().ssk_bal_count.caption == "Showing 0 of 0 matching items", "empty data state")
B.rows = saved_rows
prototypes.item["test-1"] = old_proto
us.bal_details, us.bal_filter, us.bal_limit = false, "problems", nil
UI.refresh(player)
print("BAL UI OK")
